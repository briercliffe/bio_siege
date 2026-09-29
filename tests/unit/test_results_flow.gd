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
