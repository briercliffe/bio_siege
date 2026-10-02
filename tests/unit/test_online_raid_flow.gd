extends GutTest

## The async PvP raid flow end to end on the client, with OfflineBackend canned responses: find a player, raid,
## battle, "Validating...", and server-only numbers on Results.

const DIR: String = "user://test_online_raid_flow"
const T0: int = 1800000000

var _cfg: GameConfig
var _backend: OfflineBackend
var _flow: LivingBaseFlow
var _session: Session
var _fsm: GameStateMachine


func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true, "immune_memory": true, "bcell_analysis": true}).config
	_backend = OfflineBackend.new()
	_backend.set_status_for_tests("online")


func after_each() -> void:
	_clean()


func _clean() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _profile() -> Dictionary:
	return JSON.parse_string(JSON.stringify(LivingBaseProfile.create_new(_cfg, 5, T0).to_dict())) as Dictionary


func _enter() -> void:
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	_flow = LivingBaseFlow.new(store)
	_flow.online_cache_path = DIR + "/online.json"
	_flow.local_base_path = DIR + "/local.json"
	_flow.import_answered_path = DIR + "/answered.txt"
	_session = Session.new(_cfg)
	var api := ProfileApi.new(_backend)
	api.poll_interval_s = 0.0
	api.max_polls = 4
	var res: Dictionary = await _flow.enter_online(_session, api)
	assert_true(res["ok"])
	_fsm = GameStateMachine.new()
	_fsm.session = _session
	add_child_autoqfree(_fsm)
	_fsm.phase = GameStateMachine.Phase.SYNTHESIS


func _find_response() -> Dictionary:
	return {"ok": true, "error": "", "defender_id": "def-1", "trophies": 120, "preview": {
		"layout": [{"type": "nucleus", "origin": [18, 18]}, {"type": "mitochondria", "origin": [10, 10]}],
		"memory": {}, "populations": {}, "stored_atp": 400, "trophies": 120, "updated_unix": T0}}


func _start_response() -> Dictionary:
	var snap: Dictionary = (_find_response()["preview"] as Dictionary).duplicate(true)
	return {"ok": true, "error": "", "raid_id": "raid-1", "seed": 77, "expires_unix": T0 + 600, "defender_snapshot": snap}


func _screen() -> OpponentScreen:
	var screen := OpponentScreen.new()
	add_child_autofree(screen)
	screen.now_ms_override = 10000
	screen.setup(_session, _fsm)
	return screen


func _wait_frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().process_frame


func test_players_tab_shows_one_opponent_with_memory_loot_and_trophies() -> void:
	await _enter()
	_backend.respond("find_opponent", _find_response())
	var screen: OpponentScreen = _screen()
	await _wait_frames(2)
	assert_not_null(screen.tabs)
	assert_eq(screen.tabs.selected_index, OpponentScreen.PLAYERS_TAB)
	assert_true(screen.players_box.visible)
	assert_true(screen.player_card.visible)
	assert_eq(screen.player_trophies_label.text, "Trophies: 120")
	assert_eq(screen.player_loot_label.text, "Loot: up to %d ATP" % (400 * _cfg.loot_atp_pct / 100))
	assert_true(screen.player_memory_box.get_child_count() > 0, "the memory panel is always visible")
	assert_eq(screen.current_defender_id, "def-1")
	assert_false(screen.btn_raid.disabled)
	assert_false(screen.cards_row.get_parent().visible, "AI cards are on the other tab")


func test_no_players_in_range_switches_to_the_ai_tab() -> void:
	await _enter()
	_backend.respond("find_opponent", {"ok": true, "error": "", "ai": true})
	var screen: OpponentScreen = _screen()
	await _wait_frames(2)
	assert_eq(screen.message_label.text, OpponentScreen.NO_PLAYERS_TEXT)
	assert_eq(screen.tabs.selected_index, OpponentScreen.AI_TAB)
	assert_false(screen.players_box.visible)
	assert_true(screen.cards_row.get_parent().visible)


func test_next_is_rate_limited_to_one_find_per_two_seconds() -> void:
	await _enter()
	_backend.respond("find_opponent", _find_response())
	var screen: OpponentScreen = _screen()
	await _wait_frames(2)
	assert_eq(_backend.call_names().count("find_opponent"), 1)
	screen.btn_next.pressed.emit()
	await _wait_frames(2)
	assert_eq(_backend.call_names().count("find_opponent"), 2)
	screen.now_ms_override = 10500
	screen.btn_next.pressed.emit()
	await _wait_frames(2)
	assert_eq(_backend.call_names().count("find_opponent"), 2, "too soon")
	screen.now_ms_override = 12100
	screen.btn_next.pressed.emit()
	await _wait_frames(2)
	assert_eq(_backend.call_names().count("find_opponent"), 3)


func test_every_button_is_at_least_48_by_48() -> void:
	await _enter()
	_backend.respond("find_opponent", _find_response())
	var screen: OpponentScreen = _screen()
	await _wait_frames(2)
	for b: PillButton in [screen.btn_raid, screen.btn_next]:
		assert_gte(b.custom_minimum_size.x, 48.0)
		assert_gte(b.custom_minimum_size.y, 48.0)
	for b: Node in screen.tabs.get_children():
		assert_gte((b as Control).custom_minimum_size.y, 48.0)
		assert_gte((b as Control).custom_minimum_size.x, 48.0)
	assert_gte(screen.btn_back.size.x, 0.0)


func test_raid_starts_the_server_raid_and_goes_to_incubation() -> void:
	await _enter()
	_backend.respond("find_opponent", _find_response())
	_backend.respond("raid_start", _start_response())
	var screen: OpponentScreen = _screen()
	await _wait_frames(2)
	screen.btn_raid.pressed.emit()
	await _wait_frames(3)
	assert_eq(_fsm.phase, GameStateMachine.Phase.INCUBATION)
	assert_eq(_session.pvp_raid_id, "raid-1")
	assert_eq(_session.battle_seed_override, 77)
	assert_eq(_backend.calls[_backend.calls.size() - 1]["payload"], {"defender_id": "def-1"})


func test_each_mapped_error_code_shows_its_text() -> void:
	await _enter()
	_backend.respond("find_opponent", _find_response())
	var screen: OpponentScreen = _screen()
	await _wait_frames(2)
	for code: String in ["shielded", "under_attack", "raid_in_progress", "self_raid", "unknown_player", "rate_limited", "update_required", "busy"]:
		_backend.respond("raid_start", {"ok": false, "error": code})
		screen.btn_raid.pressed.emit()
		await _wait_frames(3)
		assert_eq(screen.message_label.text, NetCopy.error_text(code), code)
		assert_ne(screen.message_label.text, NetCopy.error_text("some_unmapped_code"), code)
		assert_false(screen.btn_raid.disabled, "the player can try again")
	assert_ne(_fsm.phase, GameStateMachine.Phase.INCUBATION)


func test_the_expiry_countdown_returns_to_base_with_the_message() -> void:
	await _enter()
	_backend.respond("raid_start", _start_response())
	_backend.respond("raid_cancel", {"ok": true, "error": ""})
	await _flow.begin_pvp_raid("def-1")
	assert_true(_session.army.buy("rhinovirus", _session.wallet))
	_fsm.phase = GameStateMachine.Phase.INCUBATION
	var phase: IncubationPhase = (load("res://src/game/phases/incubation_phase.tscn") as PackedScene).instantiate() as IncubationPhase
	phase.now_unix_override = T0 + 540
	add_child_autofree(phase)
	phase.setup(_session, _fsm)
	assert_true(phase.expiry_pill.visible)
	assert_eq(phase.expiry_label.text, "Raid expires in 1:00")
	phase.now_unix_override = T0 + 599
	phase.update_expiry()
	assert_eq(phase.expiry_label.text, "Raid expires in 0:01")
	assert_eq(_fsm.phase, GameStateMachine.Phase.INCUBATION)
	phase.now_unix_override = T0 + 600
	phase.update_expiry()
	assert_eq(phase.toast.last_message, "Raid expired. Your army was spent.")
	await _wait_frames(2)
	assert_eq(_fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_true(_backend.call_names().has("raid_cancel"))
	var cancel: Dictionary = {}
	for c: Dictionary in _backend.calls:
		if c["name"] == "raid_cancel":
			cancel = c["payload"] as Dictionary
	assert_false(cancel.has("army"), "nothing was deployed yet, so no army is reported")
	assert_eq(_session.pvp_raid_id, "")


func test_no_expiry_pill_without_an_online_raid() -> void:
	await _enter()
	var phase: IncubationPhase = (load("res://src/game/phases/incubation_phase.tscn") as PackedScene).instantiate() as IncubationPhase
	add_child_autofree(phase)
	phase.setup(_session, _fsm)
	assert_null(phase.expiry_pill)


func _battle() -> BattleSim:
	assert_true(_session.army.buy("rhinovirus", _session.wallet))
	assert_true(_session.army.deploy("rhinovirus", Vector2i(0, 0)))
	var sim := BattleSim.new(_cfg, BattleSetup.create(_session.attack_grid().to_layout(), _session.army.deployments.duplicate(true), 77))
	sim.run_to_end()
	return sim


func _results() -> ResultsPhase:
	var results := ResultsPhase.new()
	add_child_autofree(results)
	results.setup(_session, _fsm)
	return results


func test_find_raid_battle_submit_validating_then_the_server_numbers() -> void:
	await _enter()
	_backend.respond("find_opponent", _find_response())
	_backend.respond("raid_start", _start_response())
	var screen: OpponentScreen = _screen()
	await _wait_frames(2)
	screen.btn_raid.pressed.emit()
	await _wait_frames(3)
	var sim: BattleSim = _battle()
	_session.last_result = {"outcome": sim.outcome, "end_reason": sim.end_reason, "pvp_pending": true, "battle_s": 5.0}
	_backend.respond("raid_submit", {"ok": true, "error": "", "job_id": "job-1"})
	_backend.respond_sequence("job_status", [
		{"ok": true, "status": "queued", "result": null},
		{"ok": true, "status": "done", "result": {
			"res": {"outcome": "attacker", "atp_looted": 42, "amino_attacker": 8, "dna_attacker": 0,
					"memory_changes": [{"strain_key": "rhinovirus/wild", "reason": "learned", "from": 0, "to": 1}], "evolution": []},
			"trophies": {"attacker_delta": 22, "defender_delta": -22}, "hash_match": false}},
	])
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
	_flow.submit_pvp_raid(sim)
	var results: ResultsPhase = _results()
	assert_true(results.is_pvp())
	assert_eq(results.pvp_status_label.text, ResultsPhase.VALIDATING_TEXT)
	assert_true(results.pvp_status_label.visible)
	assert_false(results.loot_label.visible, "no locally computed reward is shown")
	await _wait_frames(6)
	assert_eq(results.pvp_status_label.text, "Loot: +42 ATP · +8 Amino Acids · +22 trophies")
	assert_true(results.memory_label.text.begins_with("Their base learned"))
	assert_eq(results.pvp_note_label.text, ResultsPhase.HASH_DIFFERS_TEXT)
	assert_true(results.pvp_note_label.visible)
	assert_eq(results.title_label.text, ResultsPhase.TITLE_ATTACKER)
	var sent: Dictionary = {}
	for c: Dictionary in _backend.calls:
		if c["name"] == "raid_submit":
			sent = c["payload"] as Dictionary
	assert_eq(sent["client_final_hash"], sim.state_hash())


func test_a_validation_timeout_leaves_results_usable() -> void:
	await _enter()
	_backend.respond("raid_start", _start_response())
	await _flow.begin_pvp_raid("def-1")
	var sim: BattleSim = _battle()
	_session.last_result = {"outcome": sim.outcome, "end_reason": sim.end_reason, "pvp_pending": true, "battle_s": 5.0}
	_backend.respond("raid_submit", {"ok": true, "error": "", "job_id": "job-1"})
	_backend.respond("job_status", {"ok": true, "status": "queued", "result": null})
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
	_flow.submit_pvp_raid(sim)
	var results: ResultsPhase = _results()
	await _wait_frames(LivingBaseFlow.PVP_POLLS + 10)
	assert_eq(results.pvp_status_label.text, ResultsPhase.STILL_VALIDATING_TEXT)
	assert_true(results.btn_edit_base.visible)
	assert_false(results.btn_edit_base.disabled)
	assert_true(results.btn_re_raid.visible)
	assert_gte(results.btn_edit_base.custom_minimum_size.y, 48.0)
	ResultsPhase.apply_choice("back_to_base", _session, _fsm)
	assert_eq(_fsm.phase, GameStateMachine.Phase.SYNTHESIS)


func test_a_flag_off_session_shows_no_pvp_ui() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true}).config
	var session := Session.new(cfg)
	var results := ResultsPhase.new()
	add_child_autofree(results)
	results.setup(session, null)
	assert_false(results.is_pvp())
	assert_false(results.pvp_status_label.visible)
