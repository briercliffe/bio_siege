extends GutTest

## Path budget at 40x40: the stress scenario (100 Rhinoviruses spread over the whole
## 2-tile deploy band) must stay inside max_path_recalcs_per_tick on every tick and
## finish before the battle timeout.


func test_stress_path_budget_and_timeout_at_40x40() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load")
	var config: GameConfig = res.config
	assert_eq(config.grid_width, 40)

	var band: Array[Vector2i] = Scenarios.ring_cells(config.grid_width, config.grid_height, config.deploy_ring)
	assert_eq(band.size(), 304, "Band covers both deploy rows")
	var setup: BattleSetup = Scenarios.stress(band)
	assert_eq(setup.validate(config).size(), 0, "Stress setup must validate at 40x40")

	var sim: BattleSim = BattleSim.new(config, setup)
	var max_seen: int = 0
	while not sim.finished:
		sim.step()
		var computed: int = sim.path_service.computations_this_tick
		max_seen = maxi(max_seen, computed)
		assert_lte(computed, config.max_path_recalcs_per_tick,
			"Path computations (%d) exceeded the per-tick budget (%d) at tick %d" % [
				computed, config.max_path_recalcs_per_tick, sim.tick])

	assert_true(sim.finished)
	assert_lt(sim.tick, config.battle_timeout_ticks, "Battle must finish within the timeout")
	assert_gt(sim.path_service.computations_total, 0, "Pathfinding actually ran")
	assert_lte(max_seen, config.max_path_recalcs_per_tick)
