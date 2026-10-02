extends GutTest

## The online defense log with OfflineBackend canned responses: the list, Watch, Revenge, paging and the
## "While you were away" summary.

const DIR: String = "user://test_online_defense_log"
const T0: int = 1800000000

var _cfg: GameConfig
var _backend: OfflineBackend
var _flow: LivingBaseFlow
var _session: Session
var _fsm: GameStateMachine


func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true, "coevolution": true}).config
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


func _entry(id: String, age_s: int, extra: Dictionary = {}) -> Dictionary:
	var e: Dictionary = {
		"raid_id": id, "attacker_id": "att-" + id, "attacker_name": "Ada", "created_unix": T0 - age_s, "outcome": "attacker",
		"trophies_delta": -20, "atp_lost": 40, "amino_gained": 3, "army": {"rhinovirus": 4},
		"memory_changes": [{"strain_key": "rhinovirus/wild", "reason": "learned", "from": 0, "to": 1}],
		"evolution": [{"type_id": "b_cell", "bred": true, "generation": 4}], "has_battle": true, "seen": false}
	for k: Variant in extra.keys():
		e[k] = extra[k]
	return e


func _enter() -> void:
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
	_backend.respond("defense_log_mark_seen", {"ok": true, "error": "", "marked": 0})
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


func _screen() -> DefenseLogScreen:
	var screen := DefenseLogScreen.new()
	add_child_autofree(screen)
	screen.now_unix_override = T0
	screen.setup(_session, _fsm)
	return screen


func _wait_frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().process_frame


func test_the_list_renders_from_the_backend() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [
		_entry("r2", 100, {"outcome": "defender", "trophies_delta": 10}), _entry("r1", 3600, {"attacker_name": ""})], "cursor": ""})
	await _enter()
	var screen: DefenseLogScreen = _screen()
	await _wait_frames(2)
	assert_eq(screen.rows.size(), 2)
	assert_true(screen.scroll.visible)
	assert_false(screen.empty_label.visible)
	var first: Control = screen.rows[0]["row"] as Control
	assert_eq((first.find_child("OutcomeChip", true, false) as Label).text, "Held")
	assert_eq((first.find_child("RaidLabel", true, false) as Label).text, "vs Ada")
	assert_eq((first.find_child("ResultLabel", true, false) as Label).text, "-40 ATP · +3 Amino Acids · +10 trophies")
	var second: Control = screen.rows[1]["row"] as Control
	assert_eq((second.find_child("RaidLabel", true, false) as Label).text, "vs Player")
	assert_true((second.find_child("EvolutionLabel", true, false) as Label).text.contains("generation 4"))
	assert_true((second.find_child("LearningLabel", true, false) as Label).text.begins_with("Learned"))
	for r: Dictionary in screen.rows:
		assert_gte((r["watch"] as Control).custom_minimum_size.y, 48.0)
		assert_gte((r["watch"] as Control).custom_minimum_size.x, 48.0)


func test_an_empty_log_and_an_error_show_text() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [], "cursor": ""})
	await _enter()
	var screen: DefenseLogScreen = _screen()
	await _wait_frames(2)
	assert_true(screen.empty_label.visible)
	assert_eq(screen.empty_label.text, DefenseLogScreen.EMPTY_TEXT)
	_backend.respond("defense_log_list", {"ok": false, "error": "rate_limited"})
	var bad: DefenseLogScreen = _screen()
	await _wait_frames(2)
	assert_eq(bad.message_label.text, NetCopy.error_text("rate_limited"))


func test_revenge_only_within_24_hours_and_it_raids_the_attacker() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [
		_entry("new", 3600), _entry("old", 25 * 3600)], "cursor": ""})
	await _enter()
	var screen: DefenseLogScreen = _screen()
	await _wait_frames(2)
	assert_not_null(screen.rows[0]["revenge"])
	assert_null(screen.rows[1]["revenge"], "older than 24 hours")
	assert_gte((screen.rows[0]["revenge"] as Control).custom_minimum_size.y, 48.0)
	_backend.respond("raid_start", {"ok": true, "error": "", "raid_id": "rv", "seed": 5, "expires_unix": T0 + 600, "defender_snapshot": {
		"layout": [{"type": "nucleus", "origin": [18, 18]}], "memory": {}, "populations": {}, "stored_atp": 0}})
	(screen.rows[0]["revenge"] as PillButton).pressed.emit()
	await _wait_frames(3)
	assert_eq(_backend.calls[_backend.calls.size() - 1]["payload"], {"defender_id": "att-new"})
	assert_eq(_fsm.phase, GameStateMachine.Phase.INCUBATION)
	assert_eq(_session.pvp_raid_id, "rv")


func test_revenge_still_respects_shields() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [_entry("new", 60)], "cursor": ""})
	await _enter()
	var screen: DefenseLogScreen = _screen()
	await _wait_frames(2)
	_backend.respond("raid_start", {"ok": false, "error": "shielded"})
	(screen.rows[0]["revenge"] as PillButton).pressed.emit()
	await _wait_frames(3)
	assert_eq(screen.message_label.text, NetCopy.error_text("shielded"))
	assert_ne(_fsm.phase, GameStateMachine.Phase.INCUBATION)


func test_watch_fetches_the_full_entry_and_replays_it() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [_entry("r1", 100)], "cursor": ""})
	await _enter()
	var grid := GridModel.new(_cfg)
	grid.reset_with_nucleus()
	var setup := BattleSetup.create(grid.to_layout(), [{"type": "rhinovirus", "cell": Vector2i(0, 0), "strain": "wild"}], 9)
	var sim := BattleSim.new(_cfg, setup)
	sim.run_to_end()
	var battle: Dictionary = JSON.parse_string(JSON.stringify(SnapshotIO.battle_to_dict(_cfg, setup, sim))) as Dictionary
	var full: Dictionary = _entry("r1", 100, {"battle": battle})
	_backend.respond("defense_log_get", {"ok": true, "error": "", "entry": full})
	var screen: DefenseLogScreen = _screen()
	await _wait_frames(2)
	(screen.rows[0]["watch"] as PillButton).pressed.emit()
	await _wait_frames(3)
	assert_eq(_backend.calls[_backend.calls.size() - 1]["payload"], {"raid_id": "r1"})
	assert_true(_session.replay_mode)
	assert_eq(_fsm.phase, GameStateMachine.Phase.INFECTION)
	assert_true(_session.has_attack_target())
	assert_eq(_session.replay_expected_hash, sim.state_hash())


func test_a_watch_without_a_battle_is_refused() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [_entry("r1", 100, {"has_battle": false})], "cursor": ""})
	await _enter()
	var screen: DefenseLogScreen = _screen()
	await _wait_frames(2)
	assert_true((screen.rows[0]["watch"] as PillButton).disabled)


func test_paging_loads_more() -> void:
	var page1: Array = []
	for i: int in range(20):
		page1.append(_entry("a%02d" % i, 100 + i))
	_backend.respond_sequence("defense_log_list", [
		{"ok": true, "error": "", "entries": [], "cursor": ""},
		{"ok": true, "error": "", "entries": page1, "cursor": "20"},
		{"ok": true, "error": "", "entries": [_entry("b00", 5000)], "cursor": ""},
	])
	await _enter()
	var screen: DefenseLogScreen = _screen()
	await _wait_frames(2)
	assert_eq(screen.rows.size(), 20)
	assert_not_null(screen.btn_more)
	assert_gte(screen.btn_more.custom_minimum_size.y, 48.0)
	screen.btn_more.pressed.emit()
	await _wait_frames(2)
	assert_eq(screen.rows.size(), 21)
	var calls: Array = []
	for c: Dictionary in _backend.calls:
		if c["name"] == "defense_log_list":
			calls.append(c["payload"]["cursor"])
	assert_eq(calls, ["", "", "20"])


func test_unseen_entries_become_one_while_you_were_away_summary_once() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [
		_entry("r2", 100, {"outcome": "defender", "trophies_delta": 10, "evolution": []}),
		_entry("r1", 200),
		_entry("seen", 300, {"seen": true})], "cursor": ""})
	await _enter()
	assert_eq(_flow.away_summary["raids"], 2)
	assert_eq(_flow.away_summary["held"], 1)
	assert_eq(_flow.away_summary["atp_lost"], 80)
	var text: String = _flow.away_summary_text()
	assert_true(text.begins_with("While you were away: 2 raids · 1 held · -80 ATP"), text)
	assert_true(text.contains("Your B-Cells are now generation 4"), text)
	assert_false(_session.unseen_away_summary.is_empty())
	var marked: Array = []
	for c: Dictionary in _backend.calls:
		if c["name"] == "defense_log_mark_seen":
			marked = c["payload"]["raid_ids"] as Array
	assert_eq(marked, ["r2", "r1"])
	# The next visit has nothing unseen.
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [_entry("r2", 100, {"seen": true})], "cursor": ""})
	var again := LivingBaseFlow.new(_flow.store)
	again.online_cache_path = DIR + "/online.json"
	again.local_base_path = DIR + "/local.json"
	again.import_answered_path = DIR + "/answered.txt"
	var s2 := Session.new(_cfg)
	var api := ProfileApi.new(_backend)
	api.poll_interval_s = 0.0
	await again.enter_online(s2, api)
	assert_true(s2.unseen_away_summary.is_empty())
	assert_eq(again.away_summary_text(), "")


func test_the_away_card_shows_the_online_numbers() -> void:
	_backend.respond("defense_log_list", {"ok": true, "error": "", "entries": [_entry("r1", 200)], "cursor": ""})
	await _enter()
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(_session, _fsm)
	await _wait_frames(3)
	assert_not_null(phase.away_label)
	assert_true(phase.away_label.text.contains("While you were away: 1 raid"))
	assert_true(phase.away_label.text.contains("generation 4"))
