extends GutTest

## AI raids on the player's base (#163): resolved on return, and played live on demand.

const DIR: String = "user://test_lb_defense"
const HOUR: int = 3600

var _cfg: GameConfig = null
var _store: LivingBaseStore = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_store = LivingBaseStore.new()
	_store.path = DIR + "/living_base.json"


func after_each() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


## A saved profile whose last AI raid was `hours_ago` hours ago, with a Mitochondria and some stored ATP.
func _write_profile(hours_ago: int) -> void:
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	session.grid.place("mitochondria", Vector2i(10, 10), session.wallet)
	session.living_flow.sync_profile_from_session()
	session.profile.stored_atp = 200
	session.profile.last_ai_raid_unix = LivingBaseStore.now_unix() - hours_ago * HOUR
	_store.save_profile(session.profile)


func test_two_due_raids_resolve_on_entry_newest_first() -> void:
	_write_profile(17)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	var before: int = LivingBaseStore.now_unix()
	flow.enter(session)
	var profile: LivingBaseProfile = session.profile
	assert_eq(profile.defense_log.size(), 2)
	assert_eq(int(profile.defense_log[0]["raid_index"]), 1, "newest first")
	assert_eq(int(profile.defense_log[1]["raid_index"]), 0)
	assert_eq(profile.ai_raid_counter, 2)
	assert_false(flow.has_pending_raids())
	assert_gte(profile.last_ai_raid_unix, before - 17 * HOUR + 16 * HOUR - 5)
	assert_lte(profile.last_ai_raid_unix, before - 17 * HOUR + 16 * HOUR + 5, "advanced by two intervals")
	assert_eq(int(flow.away_summary["raids"]), 2)
	assert_true(flow.away_summary_text().begins_with("While you were away: 2 raids · "))
	# Everything persisted.
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(_store.path))
	var saved: LivingBaseProfile = LivingBaseProfile.from_dict(json, _cfg)["profile"]
	assert_eq(saved.defense_log.size(), 2)
	assert_eq(saved.ai_raid_counter, 2)
	assert_eq(saved.last_ai_raid_unix, profile.last_ai_raid_unix)


func test_nothing_is_due_right_after_creation() -> void:
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_eq(session.profile.defense_log.size(), 0)
	assert_eq(flow.away_summary_text(), "")


func test_a_long_absence_is_capped_and_jumps_the_clock() -> void:
	_write_profile(200)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_eq(session.profile.defense_log.size(), 3, "capped at max_pending")
	assert_lte(LivingBaseStore.now_unix() - session.profile.last_ai_raid_unix, 5, "jumped to now")


func test_deferred_raids_resolve_one_at_a_time() -> void:
	_write_profile(17)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session, true)
	assert_eq(flow.pending_raids, 2)
	assert_eq(session.profile.defense_log.size(), 0)
	assert_true(flow.resolve_next_raid())
	assert_eq(session.profile.defense_log.size(), 1)
	assert_eq(flow.pending_raids, 1)
	assert_true(flow.resolve_next_raid())
	assert_false(flow.resolve_next_raid())
	assert_eq(session.profile.defense_log.size(), 2)


func test_amino_acids_from_away_raids_reach_the_wallet() -> void:
	_write_profile(17)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_eq(session.wallet.get_amount("amino_acids"), int(session.profile.wallet.get("amino_acids", 0)))
	assert_eq(session.wallet.get_amount("amino_acids"), int(flow.away_summary["amino_gained"]))


func test_the_away_card_resolves_raids_then_shows_the_summary() -> void:
	_write_profile(17)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session, true)
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	fsm.screen_stack = stack
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	phase.setup(session, fsm)
	add_child_autofree(phase)
	assert_not_null(phase.away_card)
	assert_true(phase.away_label.text.begins_with("Resolving raids... 0 of 2"))
	phase._process(0.016)
	assert_true(phase.away_label.text.begins_with("Resolving raids... 1 of 2"))
	phase._process(0.016)
	phase._process(0.016)
	assert_true(phase.away_label.text.begins_with("While you were away: 2 raids"))
	assert_true(phase.away_buttons.visible)
	assert_gte(phase.btn_away_ok.custom_minimum_size.y, 48.0)
	assert_true(phase.btn_away_log.visible, "View log shows once the Defense log screen exists")
	assert_gte(phase.btn_away_log.custom_minimum_size.y, 48.0)
	phase.btn_away_ok.pressed.emit()
	assert_null(phase.away_card)


func test_the_incoming_infection_button_starts_a_live_raid() -> void:
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	fsm.phase = GameStateMachine.Phase.SYNTHESIS
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	phase.setup(session, fsm)
	add_child_autofree(phase)
	assert_true(phase.hud_build.btn_incoming.visible)
	assert_gte(phase.hud_build.btn_incoming.custom_minimum_size.y, 48.0)
	var last_raid: int = session.profile.last_ai_raid_unix
	phase.hud_build.btn_incoming.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)
	assert_true(session.live_defense)
	assert_gt(session.battle_setup.units.size(), 0, "the AI deployed")
	assert_eq(session.battle_setup.structures.size(), session.profile.layout.size())
	assert_eq(session.profile.last_ai_raid_unix, last_raid, "it does not use up a scheduled raid")


func test_a_finished_live_raid_is_applied_and_logged_as_live() -> void:
	_write_profile(0)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_true(flow.begin_live_defense())
	var last_raid: int = session.profile.last_ai_raid_unix
	var sim := BattleSim.new(_cfg, session.battle_setup)
	sim.run_to_end()
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._on_battle_finished(sim)
	var profile: LivingBaseProfile = session.profile
	assert_eq(profile.defense_log.size(), 1)
	assert_true(bool(profile.defense_log[0]["live"]))
	assert_eq(profile.ai_raid_counter, 1)
	assert_eq(profile.last_ai_raid_unix, last_raid)
	assert_true(session.last_result.has("living_base"))
	assert_false((session.last_result["living_base"] as Dictionary).has("battle"), "the replay stays out of last_result")
	var verdict: Dictionary = Replay.verify(SnapshotIO.to_json(profile.defense_log[0]["battle"]), _cfg)
	assert_true(bool(verdict.get("ok", false)), str(verdict))
	assert_eq(int(profile.stored_atp), 200 - int(profile.defense_log[0]["atp_lost"]))
	assert_eq(session.wallet.get_amount("amino_acids"), int(profile.defense_log[0]["amino_gained"]))


func test_live_results_show_the_defense_and_one_button() -> void:
	_write_profile(0)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	flow.begin_live_defense()
	session.last_result = {"outcome": "attacker", "end_reason": "nucleus_destroyed", "battle_s": 40.0,
		"living_base": {"atp_lost": 80, "amino_gained": 12, "outcome": "attacker", "live": true}}
	var results := ResultsPhase.new()
	add_child_autofree(results)
	results.setup(session)
	assert_eq(results.title_label.text, "Base infected")
	assert_eq(results.loot_label.text, "Lost 80 ATP · +12 Amino Acids")
	assert_false(results.btn_re_raid.visible)
	assert_false(results.btn_new_base.visible)
	assert_false(results.atp_card.visible)
	assert_eq(results.btn_edit_base.text, "Back to base")
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	fsm.phase = GameStateMachine.Phase.RESULTS
	results.fsm = fsm
	results.make_choice("edit_base")
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_false(session.live_defense)
	assert_false(session.has_attack_target())
	session.last_result["outcome"] = "defender"
	session.last_result["end_reason"] = "timeout"
	session.live_defense = true
	var again := ResultsPhase.new()
	add_child_autofree(again)
	again.setup(session)
	assert_eq(again.title_label.text, "Defense held")


func test_abandoning_a_live_raid_applies_nothing() -> void:
	_write_profile(0)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	flow.begin_live_defense()
	var counter: int = session.profile.ai_raid_counter
	var stored: int = session.profile.stored_atp
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._abandon("quit", GameStateMachine.Phase.TITLE)
	assert_false(session.live_defense)
	assert_eq(session.profile.ai_raid_counter, counter)
	assert_eq(session.profile.stored_atp, stored)
	assert_eq(session.profile.defense_log.size(), 0)


func test_the_defender_intro_text() -> void:
	var overlay: SideSwitchOverlay = (load("res://src/ui/side_switch_overlay.tscn") as PackedScene).instantiate() as SideSwitchOverlay
	add_child_autofree(overlay)
	overlay.play_defender()
	assert_eq(overlay.subtitle_label.text, "You are the Immune System")
	assert_eq(overlay.kicker_label.text, "INCOMING INFECTION")


# --- replays (#170) ---

func _log_one_offline_raid() -> Session:
	_write_profile(9)
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	assert_eq(session.profile.defense_log.size(), 1)
	return session


func _read_profile_bytes() -> String:
	return FileAccess.get_file_as_string(_store.path)


func test_watching_an_entry_plays_it_with_the_recorded_hash_and_no_side_effects() -> void:
	var session: Session = _log_one_offline_raid()
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	fsm.phase = GameStateMachine.Phase.SYNTHESIS
	var before: String = _read_profile_bytes()
	var profile_before: Dictionary = session.profile.to_dict()
	var screen := DefenseLogScreen.new()
	add_child_autofree(screen)
	screen.setup(session, fsm)
	screen.rows[0]["watch"].pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)
	assert_true(session.replay_mode)
	var recorded: String = str(session.profile.defense_log[0]["battle"]["result"]["final_state_hash"])
	assert_eq(session.replay_expected_hash, recorded)
	# Play it to the end like the Infection phase would.
	var sim := BattleSim.new(_cfg, session.battle_setup)
	sim.run_to_end()
	assert_eq(sim.state_hash(), recorded, "the replay reaches the recorded final hash")
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf.fsm = fsm
	inf._on_battle_finished(sim)
	assert_false(session.replay_mode, "replay_mode is reset")
	assert_eq(session.replay_expected_hash, "")
	assert_false(session.has_attack_target())
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS, "it ends back at the base, not Results")
	assert_true(session.last_result.is_empty(), "no result was written")
	assert_eq(session.profile.to_dict(), profile_before)
	assert_eq(_read_profile_bytes(), before, "the profile file is byte-identical")
	assert_eq(session.living_flow.notices, [] as Array[String], "a matching hash raises no notice")


func test_a_changed_game_is_noticed_after_a_replay() -> void:
	var session: Session = _log_one_offline_raid()
	assert_true(session.living_flow.begin_replay(0))
	session.replay_expected_hash = "0000"
	var sim := BattleSim.new(_cfg, session.battle_setup)
	sim.run_to_end()
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._on_battle_finished(sim)
	assert_eq(session.living_flow.notices, ["Replay differs from the recorded raid (data changed since)."] as Array[String])
	assert_false(session.replay_mode)


func test_leaving_a_replay_early_changes_nothing() -> void:
	var session: Session = _log_one_offline_raid()
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	var before: String = _read_profile_bytes()
	session.living_flow.begin_replay(0)
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf.fsm = fsm
	inf._abandon("quit", GameStateMachine.Phase.TITLE)
	assert_false(session.replay_mode)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(_read_profile_bytes(), before)


func test_begin_replay_rejects_missing_entries() -> void:
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_false(flow.begin_replay(0))
	assert_false(flow.begin_replay(-1))
	assert_false(session.replay_mode)


func test_the_replay_pill_is_shown_instead_of_the_siege_title() -> void:
	var session: Session = _log_one_offline_raid()
	session.living_flow.begin_replay(0)
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	var inf: InfectionPhase = (load("res://src/game/phases/infection_phase.tscn") as PackedScene).instantiate() as InfectionPhase
	inf.setup(session, fsm)
	add_child_autofree(inf)
	assert_eq(inf.hud_combat.phase_pill._title.text, "REPLAY")
	assert_eq(inf.hud_combat.phase_pill._subtitle.text, "Recorded raid")


func test_every_logged_raid_can_be_replayed_including_upgraded_defenses() -> void:
	_cfg.feature_flags["amino_upgrades"] = true
	_write_profile(17)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	session.profile.upgrades = {"analysis_speed": 2}
	var entry: Dictionary = DefenseRunner.resolve_offline(_cfg, session.profile, session.profile.ai_raid_counter)
	session.profile.push_defense_log(entry, _cfg)
	assert_eq(session.profile.defense_log.size(), 3)
	for i: int in range(session.profile.defense_log.size()):
		assert_true(flow.begin_replay(i))
		var sim := BattleSim.new(_cfg, session.battle_setup)
		sim.run_to_end()
		assert_eq(sim.state_hash(), session.replay_expected_hash, "entry %d replays" % i)
		flow.end_replay()
	assert_eq((session.profile.defense_log[0]["battle"] as Dictionary)["defender_mods"], {"analysis_threshold_pct": 81})


func test_an_unseen_away_summary_survives_leaving_and_shows_on_the_next_visit() -> void:
	_write_profile(17)
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session, true)
	var first: LivingBaseFlow = session.living_flow
	assert_true(first.resolve_next_raid())
	# The player quits to the Title and picks Living Base again before the card is closed.
	var second := LivingBaseFlow.new(_store)
	second.enter(session, true)
	second.resolve_all_pending()
	assert_eq(int(second.away_summary["raids"]), 2, "the first raid is carried into the summary")
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	phase.setup(session, fsm)
	add_child_autofree(phase)
	assert_not_null(phase.away_card, "the card shows although nothing is pending")
	phase._process(0.016)
	assert_true(phase.away_label.text.begins_with("While you were away: 2 raids"))
	phase.btn_away_ok.pressed.emit()
	assert_true(session.unseen_away_summary.is_empty())


func test_starting_a_live_raid_again_without_finishing_changes_the_raid() -> void:
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_true(flow.begin_live_defense())
	var first_seed: int = session.battle_setup.seed
	assert_true(flow.begin_live_defense())
	assert_ne(session.battle_setup.seed, first_seed)
	assert_eq(session.profile.ai_raid_counter, 0, "an unfinished raid uses up nothing")
