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
	var p2: int = session.grid.place("macrophage", Vector2i(5, 3), session.wallet)
	var p3: int = session.grid.place("macrophage", Vector2i(7, 3), session.wallet)
	var p4: int = session.grid.place("macrophage", Vector2i(9, 3), session.wallet)
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


func test_results_phase_ui_attacker_win() -> void:
	var session := Session.new(_config)
	session.last_result = {
		"outcome": "attacker",
		"end_reason": "nucleus_destroyed",
		"battle_s": 75.0,
		"nucleus_hp": 0,
		"nucleus_max_hp": 2000,
		"structures_destroyed": 4,
		"structures_total": 17,
		"pathogens_killed": 31,
		"pathogens_total": 40,
		"first_contact_s": 8.0,
		"first_destroyed_structure_id": 2,
		"first_destroyed_structure_type": "mucous_wall"
	}
	session.last_launch = {
		"base_atp": 400,
		"army_atp": 300,
		"unspent_atp": 300,
	}

	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	assert_not_null(scene)
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session)

	# Title & Reason
	assert_eq(ui.title_label.text, "INFECTION SUCCESSFUL")
	assert_eq(ui.title_label.get_theme_color("font_color"), Color("#2ecc71"))
	assert_eq(ui.reason_label.text, "The Nucleus was destroyed in 1:15.")

	# Stat rows
	assert_eq(ui.get_stat("Battle time"), "1:15")
	assert_eq(ui.get_stat("Nucleus HP remaining"), "0 / 2000")
	assert_eq(ui.get_stat("Structures destroyed"), "4 / 17")
	assert_eq(ui.get_stat("Pathogens lost"), "31 / 40")
	assert_eq(ui.get_stat("First structure to fall"), "Mucous Wall")
	assert_eq(ui.get_stat("Time to first contact"), "0:08")

	# ATP Split Bar calculations: 400 + 300 + 300 = 1000 total
	# 560 * 400 / 1000 = 224, 560 * 300 / 1000 = 168, 560 - 224 - 168 = 168
	var split: Dictionary = ui.get_atp_split_widths()
	assert_eq(split.get("base"), 224.0)
	assert_eq(split.get("army"), 168.0)
	assert_eq(split.get("unspent"), 168.0)
	assert_eq(ui.bar_base.custom_minimum_size.x, 224.0)
	assert_eq(ui.bar_army.custom_minimum_size.x, 168.0)
	assert_eq(ui.bar_unspent.custom_minimum_size.x, 168.0)
	assert_eq(ui.bar_base.color, Color("#1e5aa8"))
	assert_eq(ui.bar_army.color, Color("#c0392b"))
	assert_eq(ui.bar_unspent.color, Color("#7f8c8d"))
	assert_eq(ui.legend_label.text, "Base 400 · Army 300 · Unspent 300")


func test_results_phase_ui_defender_win_all_pathogens_dead() -> void:
	var session := Session.new(_config)
	session.last_result = {
		"outcome": "defender",
		"end_reason": "all_pathogens_dead",
		"battle_s": 65.0,
		"nucleus_hp": 1800,
		"nucleus_max_hp": 2000,
		"structures_destroyed": 1,
		"structures_total": 10,
		"pathogens_killed": 20,
		"pathogens_total": 20,
		"first_contact_s": -1.0,
		"first_destroyed_structure_id": 0,
		"first_destroyed_structure_type": ""
	}
	session.last_launch = {
		"base_atp": 500,
		"army_atp": 200,
		"unspent_atp": 300,
	}

	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session)

	assert_eq(ui.title_label.text, "IMMUNE RESPONSE WINS")
	assert_eq(ui.title_label.get_theme_color("font_color"), Color("#48dbfb"))
	assert_eq(ui.reason_label.text, "Every pathogen was eliminated after 1:05.")
	assert_eq(ui.get_stat("First structure to fall"), "none")
	assert_eq(ui.get_stat("Time to first contact"), "never")
	assert_eq(ui.legend_label.text, "Base 500 · Army 200 · Unspent 300")


func test_results_phase_ui_defender_win_timeout() -> void:
	var session := Session.new(_config)
	session.last_result = {
		"outcome": "defender",
		"end_reason": "timeout",
		"battle_s": 180.0,
		"timeout_s": 180.0,
		"nucleus_hp": 1500,
		"nucleus_max_hp": 2000,
		"structures_destroyed": 2,
		"structures_total": 10,
		"pathogens_killed": 5,
		"pathogens_total": 20,
		"first_contact_s": 15.0,
		"first_destroyed_structure_id": 1,
		"first_destroyed_structure_type": "mucous_wall"
	}

	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session)

	assert_eq(ui.title_label.text, "IMMUNE RESPONSE WINS")
	assert_eq(ui.title_label.get_theme_color("font_color"), Color("#48dbfb"))
	assert_eq(ui.reason_label.text, "Time ran out (3:00). The immune system held.")


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

	# Button dimensions >= 48 px tall
	assert_true(ui.btn_re_raid.custom_minimum_size.y >= 48.0)
	assert_true(ui.btn_edit_base.custom_minimum_size.y >= 48.0)
	assert_true(ui.btn_new_base.custom_minimum_size.y >= 48.0)

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


func test_telemetry_slots_exist_and_empty() -> void:
	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui._resolve_nodes()

	assert_not_null(ui.survey_slot)
	assert_true(ui.survey_slot is VBoxContainer)
	assert_eq(ui.survey_slot.get_child_count(), 0)

	assert_not_null(ui.export_slot)
	assert_true(ui.export_slot is VBoxContainer)
	assert_eq(ui.export_slot.get_child_count(), 0)


func test_loop_stability_5_cycles() -> void:
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.start()
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


func test_prediction_display_in_results() -> void:
	var session := Session.new(_config)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)

	# 1. No prediction made -> val_prediction should be invisible
	session.prediction_structure_id = 0
	session.last_result = {
		"outcome": "attacker",
		"end_reason": "nucleus_destroyed",
		"battle_s": 45.0,
		"first_destroyed_structure_id": 2,
		"first_destroyed_structure_type": "macrophage"
	}
	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui_none: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui_none)
	ui_none.setup(session, fsm)
	assert_false(ui_none.val_prediction.visible)

	# 2. Correct prediction
	session.prediction_structure_id = 2
	var ui_correct: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui_correct)
	ui_correct.setup(session, fsm)
	assert_true(ui_correct.val_prediction.visible)
	assert_true(ui_correct.val_prediction.text.contains("✓ correct"))
	assert_eq(ui_correct.val_prediction.get_theme_color("font_color"), Color("#2ecc71"))

	# 3. Incorrect prediction
	session.prediction_structure_id = 1 # Predicted 1, but 2 fell first
	var ui_wrong: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui_wrong)
	ui_wrong.setup(session, fsm)
	assert_true(ui_wrong.val_prediction.visible)
	assert_true(ui_wrong.val_prediction.text.contains("✗ it was the Macrophage"))
	assert_eq(ui_wrong.val_prediction.get_theme_color("font_color"), Color("#e74c3c"))


func test_survey_slot_and_submission() -> void:
	var session := Session.new(_config)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)

	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session, fsm)

	assert_not_null(ui.btn_toggle_survey)
	assert_true(ui.btn_toggle_survey.custom_minimum_size.y >= 48.0)
	assert_not_null(ui.survey_body)
	assert_not_null(ui.btn_submit_survey)
	assert_true(ui.btn_submit_survey.custom_minimum_size.y >= 48.0)
	assert_false(ui.btn_submit_survey.disabled)

	# Submit feedback
	ui.btn_submit_survey.pressed.emit()
	assert_true(ui.survey_submitted)
	assert_true(ui.btn_submit_survey.disabled)
	assert_true(ui.btn_submit_survey.text.contains("submitted"))


func test_export_slot_button() -> void:
	var session := Session.new(_config)
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)

	var scene: PackedScene = load("res://src/game/phases/results_phase.tscn")
	var ui: ResultsPhase = scene.instantiate() as ResultsPhase
	add_child_autoqfree(ui)
	ui.setup(session, fsm)

	assert_not_null(ui.btn_export_logs)
	assert_true(ui.btn_export_logs.custom_minimum_size.y >= 48.0)
	assert_eq(ui.btn_export_logs.text, "Export playtest logs")



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
	assert_true(ui.score_label == null or not ui.score_label.visible)


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
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "b_cell", "origin": Vector2i(10, 3)},
		]
		var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 10)}]
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
