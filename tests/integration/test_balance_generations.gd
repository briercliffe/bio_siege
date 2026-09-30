extends GutTest

## Runs the balance sim loop (BalanceSimRunner) without the CLI.

var config: GameConfig


func _load_config(flags: Array[String]) -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load")
	for f: String in flags:
		res.config.feature_flags[f] = true
	return res.config


func _ring(cfg: GameConfig) -> Array[Vector2i]:
	return Scenarios.ring_cells(cfg.grid_width, cfg.grid_height)


func test_single_generation_matches_plain_loop() -> void:
	config = _load_config([])
	var ring: Array[Vector2i] = _ring(config)
	var base: BattleSetup = Scenarios.repeat_swarm(ring, config.default_seed)
	for run_idx in range(3):
		var run_seed: int = config.default_seed + run_idx
		# Today's loop, verbatim.
		var jittered: Array = BalanceSimArgs.apply_jitter(base.units, 2, run_seed, ring)
		var sim := BattleSim.new(config, BattleSetup.create(base.structures, jittered, run_seed))
		while not sim.finished:
			sim.step()

		var res: Array[Dictionary] = BalanceSimRunner.run_run(config, base, run_idx, run_seed, 2, 1, {}, ring)
		assert_eq(res.size(), 1)
		assert_eq(res[0]["seed"], run_seed)
		assert_eq(res[0]["outcome"], sim.outcome)
		assert_eq(res[0]["ticks"], sim.tick)
		assert_eq(res[0]["generation"], 1)
		assert_eq(res[0]["memory_after"], "")
		assert_true((res[0]["analyzed"] as Array).is_empty())


func test_generation_seed_rules() -> void:
	assert_eq(BalanceSimRunner.generation_seed(12345, 1, 1), 12345)
	assert_eq(BalanceSimRunner.generation_seed(12345, 3, 5), 1234503)


func test_repeat_swarm_learning_reaches_max_level() -> void:
	config = _load_config(["bcell_analysis", "immune_memory"])
	var ring: Array[Vector2i] = _ring(config)
	var base: BattleSetup = Scenarios.repeat_swarm(ring, config.default_seed)
	var runs_that_learned: int = 0
	for run_idx in range(5):
		var res: Array[Dictionary] = BalanceSimRunner.run_run(config, base, run_idx, config.default_seed + run_idx, 2, 4, {}, ring)
		assert_eq(res.size(), 4)
		var prev: int = 0
		var reached_at: int = -1
		var analyzed_each_gen: bool = true
		for r: Dictionary in res:
			var level: int = int((r["memory_levels"] as Dictionary).get("rhinovirus/wild", 0))
			assert_gte(level, prev, "memory level must not decrease (run %d gen %d)" % [run_idx, int(r["generation"])])
			prev = level
			if level >= config.memory_max_level and reached_at == -1:
				reached_at = int(r["generation"])
			if not (r["analyzed"] as Array).has("rhinovirus/wild"):
				analyzed_each_gen = false
		if analyzed_each_gen:
			assert_true(reached_at != -1 and reached_at <= 3, "run %d: max level by generation 3 (got %d)" % [run_idx, reached_at])
		if prev > 0:
			runs_that_learned += 1
			assert_true(str(res[3]["memory_after"]).contains("rhinovirus/wild="))
	assert_gt(runs_that_learned, 0, "at least one run must learn rhinovirus/wild")


func test_starting_memory_seeds_generation_one() -> void:
	config = _load_config(["bcell_analysis", "immune_memory"])
	var ring: Array[Vector2i] = _ring(config)
	var base: BattleSetup = Scenarios.repeat_swarm(ring, config.default_seed)
	var res: Array[Dictionary] = BalanceSimRunner.run_run(config, base, 0, config.default_seed, 2, 1, {"rhinovirus/wild": 3}, ring)
	var expected: int = mini(100, mini(3, config.memory_max_level) * config.memory_seed_pct_per_level)
	assert_eq(res[0]["memory_seed"], {"rhinovirus/wild": expected})


func test_repeat_swarm_valid_at_40_and_48_grids() -> void:
	for size: int in [40, 48]:
		var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
		var cfg: GameConfig = res.config
		cfg.grid_width = size
		cfg.grid_height = size
		var setup: BattleSetup = Scenarios.repeat_swarm(Scenarios.ring_cells(size, size), 1)
		var errors: PackedStringArray = setup.validate(cfg)
		assert_eq(errors.size(), 0, "repeat_swarm valid at %dx%d: %s" % [size, size, str(errors)])
