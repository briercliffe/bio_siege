extends GutTest

func test_all_25_transition_pairs() -> void:
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)

	var phases: Array[GameStateMachine.Phase] = [
		GameStateMachine.Phase.NONE,
		GameStateMachine.Phase.SYNTHESIS,
		GameStateMachine.Phase.INCUBATION,
		GameStateMachine.Phase.INFECTION,
		GameStateMachine.Phase.RESULTS,
	]

	var allowed_pairs: Dictionary = {
		[GameStateMachine.Phase.NONE, GameStateMachine.Phase.SYNTHESIS]: true,
		[GameStateMachine.Phase.SYNTHESIS, GameStateMachine.Phase.INCUBATION]: true,
		[GameStateMachine.Phase.INCUBATION, GameStateMachine.Phase.SYNTHESIS]: true,
		[GameStateMachine.Phase.INCUBATION, GameStateMachine.Phase.INFECTION]: true,
		[GameStateMachine.Phase.INFECTION, GameStateMachine.Phase.RESULTS]: true,
		[GameStateMachine.Phase.RESULTS, GameStateMachine.Phase.INCUBATION]: true,
		[GameStateMachine.Phase.RESULTS, GameStateMachine.Phase.SYNTHESIS]: true,
	}

	var allowed_count: int = 0
	var disallowed_count: int = 0

	for from_phase: GameStateMachine.Phase in phases:
		for to_phase: GameStateMachine.Phase in phases:
			var pair_key: Array = [from_phase, to_phase]
			var expected_allowed: bool = allowed_pairs.has(pair_key)
			var actual_allowed: bool = fsm.can_transition(from_phase, to_phase)

			assert_eq(
				actual_allowed,
				expected_allowed,
				"can_transition(%s, %s) expected %s but got %s" % [
					GameStateMachine.get_phase_name(from_phase),
					GameStateMachine.get_phase_name(to_phase),
					expected_allowed,
					actual_allowed
				]
			)

			if actual_allowed:
				allowed_count += 1
			else:
				disallowed_count += 1

	assert_eq(allowed_count, 7, "Exactly 7 transition pairs must be allowed")
	assert_eq(disallowed_count, 18, "Exactly 18 transition pairs must be disallowed")
	assert_eq(allowed_count + disallowed_count, 25, "Total pairs must be 25")

func test_start_transitions_to_synthesis() -> void:
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)
	watch_signals(fsm)

	assert_eq(fsm.phase, GameStateMachine.Phase.NONE)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.NONE)
	assert_null(fsm.current_phase_scene)

	fsm.start()

	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.NONE)
	assert_signal_emitted_with_parameters(fsm, "phase_changed", [GameStateMachine.Phase.NONE, GameStateMachine.Phase.SYNTHESIS])
	assert_not_null(fsm.session)
	assert_not_null(fsm.current_phase_scene)
	assert_true(fsm.current_phase_scene is SynthesisPhase)

	var label: Label = fsm.current_phase_scene.get_node("Label") as Label
	assert_not_null(label)
	assert_eq(label.text, "SYNTHESIS")

	var synth: SynthesisPhase = fsm.current_phase_scene as SynthesisPhase
	assert_eq(synth.session, fsm.session)
	assert_eq(synth.fsm, fsm)

func test_session_init_copies_config_values() -> void:
	# 1. From GameData config
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	var cfg: GameConfig = res.config
	var session: Session = Session.new(cfg)

	assert_eq(session.config, cfg)
	assert_eq(session.seed, cfg.default_seed)
	assert_eq(session.intent_lines_enabled, cfg.feature_flags.get("intent_lines_default", true))
	assert_not_null(session.wallet)
	assert_eq(session.wallet.get_amount("atp"), 1000)
	assert_not_null(session.grid)
	assert_eq(session.grid.structure_id_at(session.grid.default_nucleus_origin()), 1)
	assert_null(session.battle_setup)
	assert_eq(session.army_reserve.size(), 0)
	assert_eq(session.deployments.size(), 0)
	assert_eq(session.last_result.size(), 0)
	assert_eq(session.prediction_structure_id, 0)

	# 2. Custom values
	cfg.default_seed = 98765
	cfg.feature_flags["intent_lines_default"] = false
	var custom_session: Session = Session.new(cfg)
	assert_eq(custom_session.seed, 98765)
	assert_eq(custom_session.intent_lines_enabled, false)
	assert_not_null(custom_session.wallet)
	assert_not_null(custom_session.grid)

	# 3. Null config
	var null_session: Session = Session.new(null)
	assert_null(null_session.config)
	assert_eq(null_session.seed, 0)
	assert_true(null_session.intent_lines_enabled)
	assert_null(null_session.wallet)
	assert_null(null_session.grid)

func test_invalid_transition_rejected() -> void:
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.start()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	var initial_scene: Control = fsm.current_phase_scene
	assert_not_null(initial_scene)

	watch_signals(fsm)

	# SYNTHESIS -> INFECTION is invalid
	var ok: bool = fsm.request_transition(GameStateMachine.Phase.INFECTION)
	assert_false(ok, "request_transition to INFECTION from SYNTHESIS should return false")
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS, "Phase must remain SYNTHESIS")
	assert_eq(fsm.current_phase_scene, initial_scene, "Current scene must not change")
	assert_signal_not_emitted(fsm, "phase_changed")

	# SYNTHESIS -> RESULTS is invalid
	ok = fsm.request_transition(GameStateMachine.Phase.RESULTS)
	assert_false(ok, "request_transition to RESULTS from SYNTHESIS should return false")
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.current_phase_scene, initial_scene)
	assert_signal_not_emitted(fsm, "phase_changed")

	# SYNTHESIS -> NONE is invalid
	ok = fsm.request_transition(GameStateMachine.Phase.NONE)
	assert_false(ok, "request_transition to NONE from SYNTHESIS should return false")
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.current_phase_scene, initial_scene)
	assert_signal_not_emitted(fsm, "phase_changed")

func test_valid_transition_cycle_and_phase_scenes() -> void:
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)
	watch_signals(fsm)

	fsm.start()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_true(fsm.current_phase_scene is SynthesisPhase)

	# SYNTHESIS -> INCUBATION
	var ok: bool = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.SYNTHESIS)
	assert_true(fsm.current_phase_scene is IncubationPhase)
	assert_eq(fsm.current_phase_scene.get_node("Label").text, "INCUBATION")

	# INCUBATION -> INFECTION
	ok = fsm.request_transition(GameStateMachine.Phase.INFECTION)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.INCUBATION)
	assert_true(fsm.current_phase_scene is InfectionPhase)
	assert_eq(fsm.current_phase_scene.get_node("Label").text, "INFECTION")

	# INFECTION -> RESULTS
	ok = fsm.request_transition(GameStateMachine.Phase.RESULTS)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.RESULTS)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.INFECTION)
	assert_true(fsm.current_phase_scene is ResultsPhase)
	assert_eq(fsm.current_phase_scene.get_node("Label").text, "RESULTS")

	# RESULTS -> SYNTHESIS
	ok = fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.RESULTS)
	assert_true(fsm.current_phase_scene is SynthesisPhase)

	# SYNTHESIS -> INCUBATION -> SYNTHESIS
	ok = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_true(ok)
	ok = fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	# SYNTHESIS -> INCUBATION -> INFECTION -> RESULTS -> INCUBATION
	fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	fsm.request_transition(GameStateMachine.Phase.INFECTION)
	fsm.request_transition(GameStateMachine.Phase.RESULTS)
	ok = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

func test_force_transition_bypasses_can_transition() -> void:
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.start()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	# Jump directly from SYNTHESIS to RESULTS (normally not allowed)
	fsm.force_transition(GameStateMachine.Phase.RESULTS)
	assert_eq(fsm.phase, GameStateMachine.Phase.RESULTS)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.SYNTHESIS)
	assert_true(fsm.current_phase_scene is ResultsPhase)

	# Jump directly from RESULTS to INFECTION (normally not allowed)
	fsm.force_transition(GameStateMachine.Phase.INFECTION)
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)
	assert_eq(fsm.previous_phase, GameStateMachine.Phase.RESULTS)
	assert_true(fsm.current_phase_scene is InfectionPhase)

func test_debug_overlay_debug_build_check() -> void:
	var overlay_scene: PackedScene = load("res://src/ui/debug_overlay.tscn")
	assert_not_null(overlay_scene)
	var overlay: DebugOverlay = overlay_scene.instantiate() as DebugOverlay
	add_child_autoqfree(overlay)

	# In debug build (default when running tests)
	assert_true(overlay.check_debug_build(true))
	assert_true(overlay.visible)

	# Non-debug build simulation
	var res: bool = overlay.check_debug_build(false)
	assert_false(res)
	assert_false(overlay.visible)
	assert_true(overlay.is_queued_for_deletion())

func test_debug_overlay_toggling_and_buttons() -> void:
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.start()

	var overlay_scene: PackedScene = load("res://src/ui/debug_overlay.tscn")
	var overlay: DebugOverlay = overlay_scene.instantiate() as DebugOverlay
	add_child_autoqfree(overlay)
	overlay.setup(fsm)

	# Starts closed
	assert_false(overlay.panel.visible)
	assert_false(overlay.is_open)
	assert_eq(overlay.phase_label.text, "SYNTHESIS")

	# Toggle via method
	overlay.toggle()
	assert_true(overlay.panel.visible)
	assert_true(overlay.is_open)
	overlay.toggle()
	assert_false(overlay.panel.visible)

	# Toggle via DBG button press
	assert_eq(overlay.dbg_button.custom_minimum_size, Vector2(48, 48))
	overlay.dbg_button.pressed.emit()
	assert_true(overlay.panel.visible)
	overlay.dbg_button.pressed.emit()
	assert_false(overlay.panel.visible)

	# Toggle via F1 key event
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F1
	overlay._unhandled_input(event)
	assert_true(overlay.panel.visible)
	overlay._unhandled_input(event)
	assert_false(overlay.panel.visible)

	# Test buttons call force_transition
	overlay.btn_results.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.RESULTS)
	assert_eq(overlay.phase_label.text, "RESULTS")

	overlay.btn_incubation.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)
	assert_eq(overlay.phase_label.text, "INCUBATION")

	overlay.btn_infection.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)
	assert_eq(overlay.phase_label.text, "INFECTION")

	overlay.btn_synthesis.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(overlay.phase_label.text, "SYNTHESIS")

func test_main_scene_integration() -> void:
	var main_scene: PackedScene = load("res://src/main.tscn")
	var main_node: Node = main_scene.instantiate()
	add_child_autoqfree(main_node)

	var fsm: GameStateMachine = main_node.get_node_or_null("GameStateMachine") as GameStateMachine
	assert_not_null(fsm, "Main must have GameStateMachine node")
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS, "FSM should start in SYNTHESIS")
	assert_not_null(fsm.current_phase_scene)

	var dbg: DebugOverlay = main_node.get_node_or_null("DebugOverlay") as DebugOverlay
	assert_not_null(dbg, "Main must have DebugOverlay node")
	assert_eq(dbg.fsm, fsm, "DebugOverlay should be connected to FSM")
