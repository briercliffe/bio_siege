extends GutTest

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func test_stress_setup_validates() -> void:
	var setup: BattleSetup = Scenarios.stress()
	assert_not_null(setup, "Stress setup should not be null")
	var errors: PackedStringArray = setup.validate(config)
	assert_eq(errors.size(), 0, "Stress setup should validate with 0 errors: %s" % [", ".join(errors)])


func test_stress_sim_run_to_completion() -> void:
	var setup: BattleSetup = Scenarios.stress()
	var sim: BattleSim = BattleSim.new(config, setup)
	assert_not_null(sim, "BattleSim should initialize")
	assert_false(sim.finished, "BattleSim should not start finished")

	while not sim.finished:
		sim.step()
		assert_lte(
			sim.path_service.computations_this_tick,
			config.max_path_recalcs_per_tick,
			"Path computations this tick (%d) exceeded max (%d) at tick %d" % [
				sim.path_service.computations_this_tick,
				config.max_path_recalcs_per_tick,
				sim.tick
			]
		)

	assert_true(sim.finished, "Simulation must finish")
	assert_ne(sim.outcome, "", "Outcome must not be empty")
	assert_ne(sim.end_reason, "", "End reason must not be empty")
	assert_lt(sim.tick, config.battle_timeout_ticks, "Simulation must finish before timeout")


const StressBattleScript: GDScript = preload("res://tests/perf/stress_battle.gd")


func test_stress_battle_scene_instantiation() -> void:
	var scene_res: PackedScene = load("res://tests/perf/stress_battle.tscn")
	assert_not_null(scene_res, "Stress battle scene should load")
	var scene: Control = scene_res.instantiate() as Control
	assert_not_null(scene, "Stress battle should instantiate")
	add_child_autoqfree(scene)

	var infection_phase: InfectionPhase = scene.get("infection_phase") as InfectionPhase
	assert_not_null(infection_phase, "InfectionPhase child must exist")
	assert_not_null(scene.get("session"), "Session must be initialized")
	var fps_label: Label = scene.get("fps_label") as Label
	var pool_label: Label = scene.get("pool_label") as Label
	assert_not_null(fps_label, "FpsLabel must exist")
	assert_not_null(pool_label, "PoolLabel must exist")

	scene._process(0.016)
	assert_true(fps_label.text.contains("FPS:"), "FpsLabel must show FPS")
	assert_true(pool_label.text.contains("Pools Created:"), "PoolLabel must show pool counts")


func test_debug_overlay_stress_button() -> void:
	var overlay_scene: PackedScene = load("res://src/ui/debug_overlay.tscn")
	assert_not_null(overlay_scene)
	var overlay: DebugOverlay = overlay_scene.instantiate() as DebugOverlay
	add_child_autoqfree(overlay)

	assert_not_null(overlay.btn_stress, "Debug overlay must have btn_stress")
	assert_eq(overlay.btn_stress.text, "Stress test")
