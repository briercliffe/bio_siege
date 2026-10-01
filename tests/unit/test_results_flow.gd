extends GutTest

var _config: GameConfig = null


func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	_config = res.config


func test_post_battle_choices_and_last_launch() -> void:
	var session := Session.new(_config)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	fsm.phase = GameStateMachine.Phase.INCUBATION

	# 1. Base costing 400: Place 4 macrophages (100 ATP each)
	var p1: int = session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	var p2: int = session.grid.place("macrophage", Vector2i(7, 3), session.wallet)
	var p3: int = session.grid.place("macrophage", Vector2i(11, 3), session.wallet)
	var p4: int = session.grid.place("macrophage", Vector2i(15, 3), session.wallet)
	assert_gt(p1, 0)
	assert_gt(p2, 0)
	assert_gt(p3, 0)
	assert_gt(p4, 0)
	assert_eq(session.grid.total_cost().get("atp", 0), 400)
	assert_eq(session.wallet.get_amount("atp"), 600)

	# 2. Army costing 300: Buy 30 rhinoviruses (10 ATP each)
	for i in range(30):
		var ok: bool = session.army.buy("rhinovirus", session.wallet)
		assert_true(ok)
	assert_eq(session.army.total_cost().get("atp", 0), 300)
	assert_eq(session.wallet.get_amount("atp"), 300)

	# 3. DeployController launch records session.last_launch
	var dc := DeployController.new()
	add_child_autoqfree(dc)
	var gv := GridView.new()
	add_child_autoqfree(gv)
	gv.setup(session.grid, session.config, session.army)
	dc.setup(session, gv, null, null, fsm)
	dc._on_hud_launch_requested()

	# Assert last_launch fields
	assert_eq(session.last_launch.get("base_atp"), 400)
	assert_eq(session.last_launch.get("army_atp"), 300)
	assert_eq(session.last_launch.get("unspent_atp"), 300)
	assert_eq(session.last_launch.get("army_counts", {}).get("rhinovirus"), 30)
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)

	# 4. Test Re-raid choice:
	# wallet becomes 600 (refunds 300), army empty, grid unchanged, transitions to INCUBATION
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("re_raid", session, fsm)
	assert_eq(session.wallet.get_amount("atp"), 600)
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.grid.total_cost().get("atp", 0), 400)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

	# 5. Re-buy army costing 300, test Edit base choice:
	for i in range(30):
		session.army.buy("rhinovirus", session.wallet)
	assert_eq(session.wallet.get_amount("atp"), 300)
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("edit_base", session, fsm)
	assert_eq(session.wallet.get_amount("atp"), 600)
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.grid.total_cost().get("atp", 0), 400)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	# 6. Re-buy army costing 300, test New base choice:
	for i in range(30):
		session.army.buy("rhinovirus", session.wallet)
	assert_eq(session.wallet.get_amount("atp"), 300)
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("new_base", session, fsm)
	assert_eq(session.wallet.get_amount("atp"), 1000)
	assert_eq(session.grid.total_cost().get("atp", 0), 0)
	assert_eq(session.grid.structures().size(), 1, "Only Nucleus should remain on grid")
	assert_eq(session.army.total_count(), 0)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)


const LOG_PATH: String = "user://telemetry/test_results_flow_log.jsonl"
const MISSING_SETTINGS_PATH: String = "user://test_results_flow_no_settings.cfg"


func _new_ui(session: Session, fsm: GameStateMachine = null) -> ResultsPhase:
	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session, fsm)
	return ui


## A ResultsPhase whose survey and choice events go to a throwaway log file, never the real telemetry.
func _logged_ui(session: Session) -> ResultsPhase:
	_logger = load("res://src/telemetry/session_logger.gd").new()
	_logger.settings_path = MISSING_SETTINGS_PATH
	add_child_autoqfree(_logger)
	_logger.set_custom_file_path(LOG_PATH)
	var ui: ResultsPhase = _new_ui(session)
	ui.logger = _logger
	return ui


func _logged_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		return out
	for line: String in f.get_as_text().split("
", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	return out


var _logger: Node = null


func after_each() -> void:
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.remove_absolute(LOG_PATH)


func _fixture_result(end_reason: String) -> Dictionary:
	return {
		"outcome": "attacker" if end_reason == "nucleus_destroyed" else "defender",
		"end_reason": end_reason,
		"battle_s": 108.0,
		"nucleus_hp": 0 if end_reason == "nucleus_destroyed" else 1140,
		"nucleus_max_hp": 2000,
		"structures_destroyed": 10,
		"structures_total": 56,
		"pathogens_killed": 4,
		"pathogens_total": 8,
		"first_contact_s": 8.0,
		"first_destroyed_structure_id": 2,
		"first_destroyed_structure_type": "mucous_wall",
	}


func test_title_kicker_and_badge_per_end_reason() -> void:
	var session := Session.new(_config)
	session.last_result = _fixture_result("nucleus_destroyed")
	var ui: ResultsPhase = _new_ui(session)
	assert_eq(ui.title_label.text, "Nucleus destroyed")
	assert_eq(ui.kicker_label.get_theme_color("font_color"), Color("#2ecc71"))
	assert_false(ui.badge.visible)

	session.last_result = _fixture_result("timeout")
	ui = _new_ui(session)
	assert_eq(ui.title_label.text, "Defense held")
	assert_eq(ui.kicker_label.get_theme_color("font_color"), Color("#8fb8ff"))
	assert_true(ui.badge.visible)
	assert_eq((ui.badge.get_child(0) as Label).text, "Time limit reached")

	session.last_result = _fixture_result("all_pathogens_dead")
	ui = _new_ui(session)
	assert_eq(ui.title_label.text, "Defense held")
	assert_eq(ui.kicker_label.get_theme_color("font_color"), Color("#8fb8ff"))
	assert_false(ui.badge.visible)


func test_subtitle_uses_result_and_config() -> void:
	var session := Session.new(_config)
	session.last_result = _fixture_result("nucleus_destroyed")
	var ui: ResultsPhase = _new_ui(session)
	assert_eq(ui.reason_label.text, "Your army broke through your own defense in 1:48.")

	session.last_result = _fixture_result("timeout")
	ui = _new_ui(session)
	var timeout_s: int = _config.battle_timeout_ticks / _config.tick_rate
	assert_eq(ui.reason_label.text, "The %d:%02d timer ran out with the Nucleus at 1140 HP." % [timeout_s / 60, timeout_s % 60])

	session.last_result = _fixture_result("all_pathogens_dead")
	session.last_result["battle_s"] = 72.0
	ui = _new_ui(session)
	assert_eq(ui.reason_label.text, "Every pathogen was eliminated after 1:12.")


func test_timeout_subtitle_follows_config_timeout() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.battle_timeout_ticks = cfg.tick_rate * 90
	var session := Session.new(cfg)
	session.last_result = _fixture_result("timeout")
	session.last_result["timeout_s"] = 180.0
	var ui: ResultsPhase = _new_ui(session)
	assert_true(ui.reason_label.text.begins_with("The 1:30 timer"))


func test_stat_tiles_show_fixture_values() -> void:
	var session := Session.new(_config)
	session.last_result = _fixture_result("nucleus_destroyed")
	var ui: ResultsPhase = _new_ui(session)
	assert_eq(ui.tile_battle_time.label_text(), "Battle time")
	assert_eq(ui.tile_battle_time.value_text(), "1:48")
	assert_eq(ui.tile_nucleus_hp.label_text(), "Nucleus HP left")
	assert_eq(ui.tile_nucleus_hp.value_text(), "0")
	assert_eq(ui.tile_pathogens_alive.value_text(), "4")
	assert_eq(ui.tile_pathogens_alive.suffix_text(), "of 8")
	assert_eq(ui.tile_structures_lost.value_text(), "10")
	assert_eq(ui.tile_structures_lost.suffix_text(), "of 56")
	assert_eq(ui.get_stat("Battle time"), "1:48")
	assert_eq(ui.get_stat("Nucleus HP remaining"), "0 / 2000")
	assert_eq(ui.get_stat("Structures destroyed"), "10 / 56")
	assert_eq(ui.get_stat("Pathogens lost"), "4 / 8")
	assert_eq(ui.get_stat("First structure to fall"), "Mucous Wall")
	assert_eq(ui.get_stat("Time to first contact"), "0:08")


func test_no_first_structure_stat() -> void:
	var session := Session.new(_config)
	session.last_result = _fixture_result("all_pathogens_dead")
	session.last_result["first_contact_s"] = -1.0
	session.last_result["first_destroyed_structure_id"] = 0
	session.last_result["first_destroyed_structure_type"] = ""
	var ui: ResultsPhase = _new_ui(session)
	assert_eq(ui.get_stat("First structure to fall"), "none")
	assert_eq(ui.get_stat("Time to first contact"), "never")
	assert_eq(ui.final_summary_label.text, "No structure fell.")


func test_atp_split_segments_match_widths() -> void:
	var session := Session.new(_config)
	session.last_result = _fixture_result("nucleus_destroyed")
	session.last_launch = {"base_atp": 400, "army_atp": 300, "unspent_atp": 300}
	var ui: ResultsPhase = _new_ui(session)

	# 560 * 400 / 1000 = 224, 560 * 300 / 1000 = 168, 560 - 224 - 168 = 168
	var split: Dictionary = ui.get_atp_split_widths()
	assert_eq(split.get("base"), 224.0)
	assert_eq(split.get("army"), 168.0)
	assert_eq(split.get("unspent"), 168.0)
	var segs: Array[Dictionary] = ui.atp_track.segments
	assert_eq(segs.size(), 3)
	assert_almost_eq(float(segs[0]["frac"]) * ResultsPhase.SPLIT_BAR_WIDTH, split["base"] as float, 0.001)
	assert_almost_eq(float(segs[1]["frac"]) * ResultsPhase.SPLIT_BAR_WIDTH, split["army"] as float, 0.001)
	assert_almost_eq(float(segs[2]["frac"]) * ResultsPhase.SPLIT_BAR_WIDTH, split["unspent"] as float, 0.001)
	assert_eq(segs[0]["color"], Color("#2e86de"))
	assert_eq(segs[1]["color"], Color("#2ecc71"))
	assert_eq(segs[2]["color"], Color("#8a7a7e"))
	assert_eq(ui.atp_track.track_height, 28.0)
	assert_eq(ui.atp_track.segment_gap, 2.0)
	assert_eq(ui.atp_title_label.text, "Where your 1000 ATP went")
	assert_eq((ui.legend_values["base"] as Label).text, "400")
	assert_eq((ui.legend_values["army"] as Label).text, "300")
	assert_eq((ui.legend_values["unspent"] as Label).text, "300")


func test_button_clicks_emit_choice_made() -> void:
	var session := Session.new(_config)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	fsm.phase = GameStateMachine.Phase.RESULTS

	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session, fsm)
	watch_signals(ui)

	# Every tappable control is at least 48 px, and Re-raid at least 52 px tall.
	for b: Button in [ui.btn_re_raid, ui.btn_edit_base, ui.btn_new_base,
			ui.btn_export_logs, ui.survey_card.skip_button]:
		assert_gte(b.custom_minimum_size.y, 48.0, b.name)
		assert_gte(b.get_combined_minimum_size().x, 48.0, b.name)
	for ab: Button in ui.survey_card.answer_buttons:
		assert_gte(ab.custom_minimum_size.y, 48.0)
		assert_gte(ab.custom_minimum_size.x, 48.0)
	assert_gte(ui.btn_re_raid.custom_minimum_size.y, 52.0)
	assert_eq(ui.btn_re_raid.text, "Re-raid")
	assert_eq(ui.btn_re_raid.subtitle, "Same base, new army")
	assert_eq(ui.btn_edit_base.text, "Edit base")
	assert_eq(ui.btn_edit_base.subtitle, "Back to Synthesis")
	assert_eq(ui.btn_new_base.text, "New base")
	assert_eq(ui.btn_new_base.subtitle, "Reset to %d ATP" % int(_config.start_wallet.get("atp", 0)))

	# Re-raid
	ui.btn_re_raid.pressed.emit()
	assert_signal_emitted_with_parameters(ui, "choice_made", ["re_raid"])
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

	# Edit base
	fsm.phase = GameStateMachine.Phase.RESULTS
	ui.btn_edit_base.pressed.emit()
	assert_signal_emitted_with_parameters(ui, "choice_made", ["edit_base"])
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	# New base
	fsm.phase = GameStateMachine.Phase.RESULTS
	ui.btn_new_base.pressed.emit()
	assert_signal_emitted_with_parameters(ui, "choice_made", ["new_base"])
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)


func test_loop_stability_5_cycles() -> void:
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.start()
	fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	var choices: Array[String] = ["re_raid", "edit_base", "new_base", "re_raid", "edit_base"]

	for cycle in range(5):
		var choice: String = choices[cycle]

		# 1. From current phase (SYNTHESIS or INCUBATION), advance to INFECTION
		if fsm.phase == GameStateMachine.Phase.SYNTHESIS:
			var ok_inc: bool = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
			assert_true(ok_inc, "Cycle %d: transition to INCUBATION failed" % cycle)

		assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

		# Ensure at least 1 pathogen is bought/deployed
		if fsm.session.army.total_count() == 0:
			fsm.session.army.buy("rhinovirus", fsm.session.wallet)

		# Launch
		var ok_inf: bool = fsm.request_transition(GameStateMachine.Phase.INFECTION)
		assert_true(ok_inf, "Cycle %d: transition to INFECTION failed" % cycle)
		assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)

		# 2. In INFECTION, step battle to end and trigger finished
		var inf_scene: InfectionPhase = fsm.current_phase_scene as InfectionPhase
		assert_not_null(inf_scene)
		if inf_scene.runner != null and inf_scene.runner.sim != null:
			inf_scene.runner.sim.run_to_end()
			inf_scene._on_battle_finished(inf_scene.runner.sim)
		else:
			fsm.request_transition(GameStateMachine.Phase.RESULTS)

		# 3. Now in RESULTS
		assert_eq(fsm.phase, GameStateMachine.Phase.RESULTS)
		assert_true(fsm.current_phase_scene is ResultsPhase)
		var res_scene: ResultsPhase = fsm.current_phase_scene as ResultsPhase

		# 4. Make post-battle choice
		res_scene.make_choice(choice)

		# Verify transition succeeded
		match choice:
			"re_raid":
				assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)
			"edit_base", "new_base":
				assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

		assert_true(fsm.session.wallet.get_amount("atp") >= 0)


func test_final_state_summary_names_first_structure_and_prediction() -> void:
	var session := Session.new(_config)
	var wall_id: int = session.grid.place("mucous_wall", Vector2i(3, 3), session.wallet)
	var mac_id: int = session.grid.place("macrophage", Vector2i(7, 3), session.wallet)
	session.last_result = {
		"outcome": "attacker",
		"end_reason": "nucleus_destroyed",
		"battle_s": 45.0,
		"first_destroyed_structure_id": mac_id,
		"first_destroyed_structure_type": "macrophage",
	}

	# No prediction: only what fell first.
	session.prediction_structure_id = 0
	var ui: ResultsPhase = _new_ui(session)
	assert_eq(ui.final_summary_label.text, "The Macrophage fell first.")
	assert_eq(ui.get_stat("Prediction"), "")

	# Correct prediction.
	session.prediction_structure_id = mac_id
	ui = _new_ui(session)
	assert_eq(ui.final_summary_label.text, "The Macrophage fell first. You predicted it ✓")
	assert_eq(ui.get_stat("Prediction"), "Your prediction: ✓ correct")

	# Wrong prediction names the predicted structure.
	session.prediction_structure_id = wall_id
	ui = _new_ui(session)
	assert_eq(ui.final_summary_label.text, "The Macrophage fell first. You predicted the Mucous Wall ✗")
	assert_eq(ui.get_stat("Prediction"), "Your prediction: ✗ it was the Macrophage")


func _session_with_count(count: int) -> Session:
	var session := Session.new(_config)
	session.battle_count = count
	return session


func test_survey_rotation_by_battle_count() -> void:
	var keys: Array[String] = ["pivot", "map_feel", "predictability", "economy", "pivot"]
	for count: int in range(keys.size()):
		var ui: ResultsPhase = _new_ui(_session_with_count(count))
		assert_eq(ui.survey_card.question_key, keys[count], "battle_count %d" % count)
	var pivot_ui: ResultsPhase = _new_ui(_session_with_count(0))
	assert_eq(pivot_ui.survey_card.answer_buttons.size(), 5)
	assert_eq(pivot_ui.survey_card.low_label.text, "Jarring")
	assert_eq(pivot_ui.survey_card.high_label.text, "Smooth")
	assert_eq(pivot_ui.survey_card.answer_buttons[0].custom_minimum_size, Vector2(58.0, 50.0))
	var map_ui: ResultsPhase = _new_ui(_session_with_count(1))
	assert_eq(map_ui.survey_card.answer_buttons.size(), 3)
	assert_eq(map_ui.survey_card.answer_buttons[0].text, "Empty")
	assert_eq(map_ui.survey_card.answer_buttons[1].text, "Just right")
	assert_eq(map_ui.survey_card.answer_buttons[2].text, "Cramped")
	assert_eq(map_ui.survey_card.answer_buttons[0].custom_minimum_size, Vector2(110.0, 52.0))


func test_survey_answer_logs_one_key_and_shows_thanks() -> void:
	var ui: ResultsPhase = _logged_ui(_session_with_count(0))
	var card: ResultsSurveyCard = ui.survey_card
	assert_eq(card.question_label.text, "How did switching from builder to attacker feel?")
	card.answer_button(4).pressed.emit()

	var surveys: Array[Dictionary] = []
	for e: Dictionary in _logged_events():
		if e.get("event") == "survey":
			surveys.append(e)
	assert_eq(surveys.size(), 1)
	assert_eq(int(surveys[0].get("pivot", -1)), 4)
	assert_eq(surveys[0].get("question"), "pivot")
	assert_false(surveys[0].has("map_feel"))
	assert_false(surveys[0].has("predictability"))
	assert_false(surveys[0].has("economy"))

	assert_eq(card.question_label.text, "Thanks!")
	assert_true(card.answer_button(4).chosen)
	assert_false(card.answer_button(2).chosen)
	assert_false(card.skip_button.visible)

	# A second tap does not log a second answer.
	card.answer_button(2).pressed.emit()
	var count: int = 0
	for e: Dictionary in _logged_events():
		if e.get("event") == "survey":
			count += 1
	assert_eq(count, 1)


func test_survey_pill_answer_logs_map_feel_word() -> void:
	var ui: ResultsPhase = _logged_ui(_session_with_count(1))
	ui.survey_card.answer_button("just_right").pressed.emit()
	var found: Dictionary = {}
	for e: Dictionary in _logged_events():
		if e.get("event") == "survey":
			found = e
	assert_eq(found.get("map_feel"), "just_right")
	assert_eq(found.get("question"), "map_feel")


func test_survey_skip_logs_skipped_and_hides_card() -> void:
	var ui: ResultsPhase = _logged_ui(_session_with_count(1))
	ui.survey_card.skip_button.pressed.emit()
	assert_false(ui.survey_card.visible)
	var skipped: Array[Dictionary] = []
	var answered: int = 0
	for e: Dictionary in _logged_events():
		if e.get("event") == "survey_skipped":
			skipped.append(e)
		elif e.get("event") == "survey":
			answered += 1
	assert_eq(skipped.size(), 1)
	assert_eq(skipped[0].get("question"), "map_feel")
	assert_eq(answered, 0)


func test_export_button() -> void:
	var ui: ResultsPhase = _new_ui(Session.new(_config))
	assert_not_null(ui.btn_export_logs)
	assert_gte(ui.btn_export_logs.custom_minimum_size.y, 48.0)
	assert_eq(ui.btn_export_logs.text, "Export playtest logs")


func test_final_island_shows_only_alive_structures() -> void:
	var session := Session.new(_config)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.grid.place("mucous_wall", Vector2i(7, 3), session.wallet)
	var layout: Array[Dictionary] = session.grid.to_layout()
	session.battle_setup = BattleSetup.create(layout, [], session.seed)
	var nucleus_idx: int = -1
	for i: int in range(layout.size()):
		if layout[i]["type"] == "nucleus":
			nucleus_idx = i
	assert_gte(nucleus_idx, 0)

	# Nucleus destroyed: only the surviving non-core structures remain.
	var alive: Array = []
	for i: int in range(layout.size()):
		if layout[i]["type"] == "macrophage":
			alive.append(i + 1)
	var grid: GridModel = ResultsPhase.build_final_grid(_config, layout, alive)
	assert_eq(grid.structures().size(), 1)
	assert_eq(grid.structures()[0].type_id, "macrophage")
	assert_null(grid.find_core())

	# Nucleus alive: it is kept at its raid origin.
	alive.append(nucleus_idx + 1)
	grid = ResultsPhase.build_final_grid(_config, layout, alive)
	assert_eq(grid.structures().size(), 2)
	assert_not_null(grid.find_core())
	assert_eq(grid.find_core().origin, layout[nucleus_idx]["origin"])

	# The phase builds its thumbnail from last_result.alive_structure_ids.
	session.last_result = _fixture_result("timeout")
	session.last_result["alive_structure_ids"] = [nucleus_idx + 1]
	var ui: ResultsPhase = _new_ui(session)
	assert_not_null(ui.island_grid)
	assert_eq(ui.island_grid.structures().size(), 1)
	assert_not_null(ui.island_view)
	assert_eq(ui.island_view.get_parent(), ui.island_holder)


func test_infection_result_records_alive_structure_ids() -> void:
	var session := Session.new(_config)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	var layout: Array[Dictionary] = session.grid.to_layout()
	session.battle_setup = BattleSetup.create(layout, [], session.seed)
	var sim: BattleSim = SimFixtures.make_sim(layout, [], session.seed, _config)
	sim.run_to_end()
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._on_battle_finished(sim)
	var ids: Array = session.last_result["alive_structure_ids"]
	var expected: Array[int] = []
	for st: StructureState in sim.structures:
		if st.alive:
			expected.append(st.id)
	assert_eq(ids, expected)


func _score_result(outcome: String) -> Dictionary:
	return {
		"outcome": outcome,
		"end_reason": "nucleus_destroyed" if outcome == "attacker" else "timeout",
		"battle_s": 45.0,
		"score": 760 if outcome == "attacker" else 0,
		"base_value": 760,
		"best_score": 900,
	}


func test_score_hidden_when_flag_off() -> void:
	var session := Session.new(_config)
	session.last_result = _score_result("attacker")
	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session)
	assert_eq(ui.get_stat("score"), "")
	assert_false(ui.score_label.visible)


func test_score_shown_when_flag_on() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	var cfg: GameConfig = res.config
	cfg.feature_flags["raid_score"] = true
	var session := Session.new(cfg)
	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")

	session.last_result = _score_result("attacker")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session)
	assert_true(ui.score_label.visible)
	assert_true(ui.score_label.text.contains(str(session.last_result["score"])))
	assert_true(ui.score_label.text.contains("you broke"))
	assert_true(ui.score_label.text.contains("Best this session: %d" % int(session.last_result["best_score"])))
	assert_eq(ui.get_stat("score"), str(session.last_result["score"]))
	assert_eq(ui.get_stat("best_score"), str(session.last_result["best_score"]))

	session.last_result = _score_result("defender")
	var ui2: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui2)
	ui2.setup(session)
	assert_true(ui2.score_label.visible)
	assert_true(ui2.score_label.text.contains("held"))
	assert_eq(ui2.get_stat("score"), "0")


func test_best_score_reset_only_on_new_base() -> void:
	var session := Session.new(_config)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	session.best_score = 500
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("re_raid", session, fsm)
	assert_eq(session.best_score, 500)
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("edit_base", session, fsm)
	assert_eq(session.best_score, 500)
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("new_base", session, fsm)
	assert_eq(session.best_score, 0)


func test_infection_phase_writes_score_only_when_flag_on() -> void:
	for flag_on: bool in [false, true]:
		var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
		var cfg: GameConfig = res.config
		cfg.feature_flags["raid_score"] = flag_on
		var session := Session.new(cfg)
		session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
		var layout: Array[Dictionary] = session.grid.to_layout()
		session.battle_setup = BattleSetup.create(layout, [], session.seed)
		var sim: BattleSim = SimFixtures.make_sim(layout, [], session.seed, cfg)
		sim.run_to_end()
		var inf := InfectionPhase.new()
		add_child_autoqfree(inf)
		inf.session = session
		inf._on_battle_finished(sim)
		var result: Dictionary = session.last_result
		assert_eq(result.has("score"), flag_on)
		assert_eq(result.has("base_value"), flag_on)
		assert_eq(result.has("best_score"), flag_on)
		if flag_on:
			var expected: int = RaidScore.compute(cfg, layout, sim.outcome)
			assert_eq(int(result["score"]), expected)
			assert_eq(int(result["base_value"]), int(cfg.structures["macrophage"].cost.get("atp", 0)))
			assert_eq(session.best_score, expected)


func _memory_cfg() -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["immune_memory"] = true
	cfg.feature_flags["bcell_analysis"] = true
	return cfg


func test_memory_cleared_only_on_new_base() -> void:
	var session := Session.new(_memory_cfg())
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	session.memory.entries["rhinovirus/wild"] = {"level": 2, "absent": 0, "since": 1}
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("re_raid", session, fsm)
	assert_false(session.memory.is_empty())
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("edit_base", session, fsm)
	assert_false(session.memory.is_empty())
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("new_base", session, fsm)
	assert_true(session.memory.is_empty())


func test_infection_phase_updates_memory_when_enabled() -> void:
	for enabled: bool in [false, true]:
		var cfg: GameConfig = _memory_cfg()
		cfg.feature_flags["immune_memory"] = enabled
		var session := Session.new(cfg)
		var structs: Array = [
			{"type": "nucleus", "origin": Vector2i(18, 18)},
			{"type": "b_cell", "origin": Vector2i(10, 3)},
		]
		var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 20)}]
		session.battle_setup = BattleSetup.create(structs, units, session.seed)
		var sim: BattleSim = SimFixtures.make_sim(structs, units, session.seed, cfg)
		sim.run_to_end()
		var inf := InfectionPhase.new()
		add_child_autoqfree(inf)
		inf.session = session
		inf._on_battle_finished(sim)
		assert_eq(session.memory.raids, 1 if enabled else 0)
		assert_eq(session.last_result.has("memory_changes"), enabled)
		assert_eq(session.last_result.has("memory"), enabled)


func test_results_memory_line() -> void:
	var cfg: GameConfig = _memory_cfg()
	var session := Session.new(cfg)
	session.last_result = _score_result("attacker")
	session.last_result["memory_changes"] = [
		{"strain_key": "rhinovirus/wild", "from": 1, "to": 2, "reason": "learned"},
		{"strain_key": "staphylococcus/wild", "from": 1, "to": 0, "reason": "forgotten"},
	]
	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session)
	var expected: String = "Immune memory: Rhinovirus (wild) 1→2 · Staphylococcus (wild) forgotten"
	assert_true(ui.memory_label.visible)
	assert_eq(ui.memory_label.text, expected)
	assert_eq(ui.get_stat("memory"), expected)


func _results_ui(session: Session) -> ResultsPhase:
	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session)
	return ui


func _visible_choice_buttons(ui: ResultsPhase) -> Array[String]:
	var names: Array[String] = []
	var row: Node = ui.find_child("ChoiceButtons", true, false)
	for child: Node in row.get_children():
		if child is Button and (child as Button).visible:
			names.append(child.name)
	return names


func test_lab_buttons_with_raid_score_on() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["raid_score"] = true
	var session := Session.new(cfg)
	session.last_result = _score_result("attacker")
	var ui: ResultsPhase = _results_ui(session)
	assert_true(ui.score_label.visible)
	assert_eq(_visible_choice_buttons(ui), ["BtnReRaid", "BtnEditBase", "BtnNewBase"] as Array[String])
	assert_eq(ui.btn_re_raid.text, "Re-raid")
	assert_eq(ui.btn_edit_base.text, "Edit base")
	assert_eq(ui.btn_new_base.text, "New base")
	assert_eq(ui.btn_new_base.subtitle, "Reset to %d ATP" % int(cfg.start_wallet.get("atp", 0)))


func test_stale_outbreak_flag_is_ignored() -> void:
	# Outbreak mode was removed (#149). An old local config that still sets the flag changes nothing.
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["outbreak_mode"] = true
	var session := Session.new(cfg)
	var structs: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "b_cell", "origin": Vector2i(10, 3)},
	]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 20)}]
	session.battle_setup = BattleSetup.create(structs, units, session.seed)
	var sim: BattleSim = SimFixtures.make_sim(structs, units, session.seed, cfg)
	sim.run_to_end()
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._on_battle_finished(sim)
	assert_false(session.last_result.has("outbreak"))
	assert_false(session.last_result.has("outbreak_best"))
	var ui: ResultsPhase = _results_ui(session)
	assert_eq(_visible_choice_buttons(ui), ["BtnReRaid", "BtnEditBase", "BtnNewBase"] as Array[String])


func test_apply_new_base_resets_base_wallet_and_memory() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["immune_memory"] = true
	cfg.feature_flags["bcell_analysis"] = true
	var session := Session.new(cfg)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.memory.entries["rhinovirus/wild"] = {"level": 2, "absent": 0, "since": 1}
	session.best_score = 500
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("new_base", session, fsm)
	assert_eq(session.grid.total_cost().get("atp", 0), 0)
	assert_eq(session.wallet.get_amount("atp"), int(cfg.start_wallet.get("atp", 0)))
	assert_true(session.memory.is_empty())
	assert_eq(session.best_score, 0)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)


func test_removed_outbreak_choices_do_nothing() -> void:
	var session := Session.new(_config)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	var layout: Array = session.grid.to_layout()
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	fsm.phase = GameStateMachine.Phase.RESULTS
	for choice: String in ["new_outbreak", "retry_base"]:
		ResultsPhase.apply_choice(choice, session, fsm)
	assert_eq(session.grid.to_layout(), layout)
	assert_eq(fsm.phase, GameStateMachine.Phase.RESULTS)


# --- coevolution (#144) ---

func _coevo_cfg(on: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["coevolution"] = on
	return cfg


func _finished_battle(session: Session, rhino_fitness_index: int = 1) -> void:
	var structs: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "macrophage", "origin": Vector2i(5, 5)},
	]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 20)}]
	session.battle_setup = BattleSetup.create(structs, units, session.seed)
	var sim: BattleSim = SimFixtures.make_sim(structs, units, session.seed, session.config)
	sim.finished = true
	sim.outcome = "defender"
	sim.end_reason = "timeout"
	# Force the fitness: only rhinovirus index 1 scored, and nothing survives to earn a bonus.
	sim._pools["rhinovirus"].fitness[rhino_fitness_index] = 10
	sim._survival_granted = true
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._on_battle_finished(sim)


func test_new_base_clears_pools_and_re_raid_keeps_them() -> void:
	var cfg: GameConfig = _coevo_cfg()
	var session := Session.new(cfg)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	var pool: BreedPool = BreedPool.wild_pool("rhinovirus", cfg)
	pool.generation = 4
	pool.genomes[0] = Genome.from_slots([], ["binder_a", ""], cfg)
	session.populations["rhinovirus"] = pool
	for choice: String in ["re_raid", "edit_base"]:
		fsm.phase = GameStateMachine.Phase.RESULTS
		ResultsPhase.apply_choice(choice, session, fsm)
		assert_eq((session.populations["rhinovirus"] as BreedPool).generation, 4)
		assert_eq((session.populations["rhinovirus"] as BreedPool).genomes[0].receptors[0], "binder_a")
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("new_base", session, fsm)
	assert_true(session.populations.is_empty())
	assert_true(session.population("rhinovirus").is_wild())


func test_battle_breeds_only_types_that_scored() -> void:
	var session := Session.new(_coevo_cfg())
	_finished_battle(session)
	assert_eq(session.population("rhinovirus").generation, 1)
	assert_eq(session.population("macrophage").generation, 0)
	var evo: Array = session.last_result["evolution"]
	assert_eq(evo.size(), session.config.coevo_types.size())
	var by_type: Dictionary = {}
	for e: Dictionary in evo:
		by_type[e["type_id"]] = e
	assert_true(by_type["rhinovirus"]["bred"])
	assert_false(by_type["macrophage"]["bred"])
	assert_eq(by_type["rhinovirus"]["top_parent"], 1)
	assert_true(session.last_result["populations"].has("rhinovirus"))


func test_flag_off_battle_leaves_no_pools() -> void:
	var session := Session.new(_coevo_cfg(false))
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(18, 18)}]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 20)}]
	session.battle_setup = BattleSetup.create(structs, units, session.seed)
	var sim: BattleSim = SimFixtures.make_sim(structs, units, session.seed, session.config)
	sim.run_to_end()
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._on_battle_finished(sim)
	assert_true(session.populations.is_empty())
	assert_false(session.last_result.has("evolution"))
	assert_false(session.last_result.has("populations"))


func test_breeding_is_deterministic() -> void:
	var children: Array = []
	for i: int in range(2):
		var session := Session.new(_coevo_cfg())
		_finished_battle(session)
		children.append(session.population("rhinovirus").to_dict())
	assert_eq(children[0], children[1])


# --- Living Base results (#161) ---

func test_living_base_results_buttons_and_loot_line() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["living_base"] = true
	var store := LivingBaseStore.new()
	store.path = "user://test_results_lb.json"
	var session := Session.new(cfg)
	LivingBaseFlow.new(store).enter(session)
	session.living_flow.begin_raid(str(session.profile.opponents[0]["id"]))
	session.last_result = {"outcome": "attacker", "end_reason": "nucleus_destroyed", "battle_s": 30.0,
		"living_base": {"atp_looted": 120, "amino_attacker": 30, "dna_attacker": 0, "outcome": "attacker"}}
	var results := ResultsPhase.new()
	add_child_autofree(results)
	results.setup(session)
	assert_eq(results.loot_label.text, "+120 ATP · +30 Amino Acids")
	assert_true(results.loot_label.visible)
	assert_eq(results.btn_re_raid.text, "Raid again")
	assert_eq(results.btn_edit_base.text, "Back to base")
	assert_false(results.btn_new_base.visible)
	assert_eq(ResultsPhase.loot_text({"atp_looted": 5, "amino_attacker": 0, "dna_attacker": 2}), "+5 ATP · +2 DNA")
	DirAccess.remove_absolute(store.path)


func test_living_base_results_choices() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["living_base"] = true
	var store := LivingBaseStore.new()
	store.path = "user://test_results_lb2.json"
	var session := Session.new(cfg)
	LivingBaseFlow.new(store).enter(session)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = session
	var opp_id: String = str(session.profile.opponents[0]["id"])
	session.living_flow.begin_raid(opp_id)
	session.army.buy("rhinovirus", session.wallet)
	var spent_wallet: int = session.wallet.get_amount("atp")
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("raid_again", session, fsm)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)
	assert_eq(session.attack_opponent_id, opp_id)
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.wallet.get_amount("atp"), spent_wallet, "the army is not refunded")
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("back_to_base", session, fsm)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_false(session.has_attack_target())
	# A replaced base cannot be raided again: the choice returns to the base.
	session.living_flow.begin_raid(opp_id)
	session.profile.replace_opponent(opp_id, cfg)
	fsm.phase = GameStateMachine.Phase.RESULTS
	ResultsPhase.apply_choice("raid_again", session, fsm)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	DirAccess.remove_absolute(store.path)


func test_kicker_colour_flips_for_a_live_defense() -> void:
	assert_eq(ResultsPhase.kicker_color(true, false), ResultsPhase.KICKER_ATTACKER)
	assert_eq(ResultsPhase.kicker_color(false, false), ResultsPhase.KICKER_DEFENDER)
	assert_eq(ResultsPhase.kicker_color(true, true), ResultsPhase.KICKER_BASE_INFECTED)
	assert_eq(ResultsPhase.kicker_color(false, true), ResultsPhase.KICKER_ATTACKER)
