extends GutTest

## Read-only guard (docs/MODEL_PIPELINE_PLAN.md section 7.3): attaching the isometric view must not
## change the simulation.

const SEED: int = 7

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func test_state_hash_identical_with_and_without_view() -> void:
	var headless: BattleSim = BattleSim.new(config, Scenarios.mixed([], SEED))
	while not headless.finished:
		headless.step()
	var expected: String = headless.state_hash()

	var session := Session.new(config)
	session.battle_setup = Scenarios.mixed([], SEED)
	var phase: InfectionPhase = preload("res://src/game/phases/infection_phase.tscn").instantiate()
	add_child_autofree(phase)
	phase.setup(session, null)
	phase.runner.is_running = false  # stepped manually below
	var sim: BattleSim = phase.runner.sim
	var steps: int = 0
	while not sim.finished and steps < config.battle_timeout_ticks + 10:
		sim.step()
		phase._on_runner_ticked()
		phase._dispatch_events()
		phase.runner.alpha = 0.5
		phase.unit_layer.build_draw_order()
		if steps % 50 == 0:
			await wait_process_frames(1)
		steps += 1

	assert_true(sim.finished)
	assert_eq(sim.state_hash(), expected, "view must not change the simulation")
	assert_gt(phase.unit_layer.last_item_count, 0)
