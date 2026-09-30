extends GutTest

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func test_manual_step_runner_matches_headless_sim() -> void:
	var setup := Scenarios.open_field(42)
	var headless_sim := BattleSim.new(config, setup)
	while not headless_sim.finished:
		headless_sim.step()
	var expected_hash: String = headless_sim.state_hash()

	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.start(config, setup)
	var tick_dt: float = 1.0 / float(config.tick_rate)
	while not runner.sim.finished:
		runner._process(tick_dt)

	assert_true(runner.sim.finished, "Runner sim should finish")
	assert_eq(runner.sim.state_hash(), expected_hash, "State hash must match headless sim")

	var finish_steps: int = 0
	while runner.is_running and finish_steps < 100:
		runner._process(tick_dt)
		finish_steps += 1
	assert_false(runner.is_running, "Runner should stop after finish delay")


func test_infection_phase_last_result_populated() -> void:
	var session := Session.new(config)
	var fsm := GameStateMachine.new()
	fsm.phase = GameStateMachine.Phase.INFECTION
	add_child_autofree(fsm)
	var setup := Scenarios.open_field(42)
	session.battle_setup = setup

	var phase: InfectionPhase = preload("res://src/game/phases/infection_phase.tscn").instantiate()
	add_child_autofree(phase)
	phase.setup(session, fsm)

	var tick_dt: float = 1.0 / float(config.tick_rate)
	var max_steps: int = 3000
	var steps: int = 0
	while session.last_result.is_empty() and steps < max_steps:
		phase.runner._process(tick_dt)
		phase._process(tick_dt)
		steps += 1

	assert_gt(session.last_result.size(), 0, "session.last_result must not be empty")
	assert_eq(session.last_result.get("outcome"), phase.runner.sim.outcome)
	assert_eq(session.last_result.get("end_reason"), phase.runner.sim.end_reason)
	assert_eq(session.last_result.get("ticks"), phase.runner.sim.tick)
	assert_true(session.last_result.has("battle_s"))
	assert_true(session.last_result.has("nucleus_hp"))
	assert_true(session.last_result.has("nucleus_max_hp"))
	assert_true(session.last_result.has("structures_destroyed"))
	assert_true(session.last_result.has("structures_total"))
	assert_true(session.last_result.has("pathogens_killed"))
	assert_true(session.last_result.has("pathogens_total"))
	assert_true(session.last_result.has("first_contact_s"))
	assert_true(session.last_result.has("first_destroyed_structure_id"))
	assert_true(session.last_result.has("first_destroyed_structure_type"))
	assert_true(session.last_result.has("final_state_hash"))
	assert_eq(session.last_result.get("final_state_hash"), phase.runner.sim.state_hash())
	assert_eq(fsm.phase, GameStateMachine.Phase.RESULTS, "FSM should transition to RESULTS phase")


func test_node_pool_created_count_stays_at_100() -> void:
	var session := Session.new(config)
	var fsm := GameStateMachine.new()
	add_child_autofree(fsm)

	var ring: Array[Vector2i] = Scenarios.ring_cells(config.grid_width, config.grid_height, config.deploy_ring)
	var units: Array[Dictionary] = []
	for i in range(100):
		var cell: Vector2i = ring[i % ring.size()]
		units.append({"type": "rhinovirus", "cell": cell})

	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
	]
	var setup := BattleSetup.create(structures, units, 100)
	session.battle_setup = setup

	var phase: InfectionPhase = preload("res://src/game/phases/infection_phase.tscn").instantiate()
	add_child_autofree(phase)
	phase.setup(session, fsm)

	assert_eq(phase.pathogen_pool.created_count, 100, "Initially created_count should be 100")

	var tick_dt: float = 1.0 / float(config.tick_rate)
	for i in range(30):
		phase.runner._process(tick_dt)
		phase._process(tick_dt)
		assert_eq(phase.pathogen_pool.created_count, 100, "created_count should stay at 100 during battle")
