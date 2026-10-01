extends GutTest

## Smoke test for the 200-unit Rhinovirus bench (#67). Frame-time numbers are not asserted: headless
## rendering is not representative, see docs/PERF_BASELINE.md.

func test_build_setup_places_200_rhinos_evenly_and_deterministically() -> void:
	var grid: GridModel = GridModel.new(GameConfig.load_from_dir("res://data").config)
	var ring: Array[Vector2i] = grid.ring_cells()
	assert_gt(ring.size(), 0)
	var a: BattleSetup = RhinoBench.build_setup(ring, RhinoBench.UNIT_COUNT, RhinoBench.BENCH_SEED)
	var b: BattleSetup = RhinoBench.build_setup(ring, RhinoBench.UNIT_COUNT, RhinoBench.BENCH_SEED)
	assert_eq(a.units.size(), 200)
	assert_eq(a.units, b.units)
	assert_eq(a.seed, RhinoBench.BENCH_SEED)
	var seen: Dictionary = {}
	for u: Dictionary in a.units:
		assert_eq(u["type"], "rhinovirus")
		seen[u["cell"]] = true
	assert_eq(seen.size(), 200, "200 distinct ring cells")


func test_build_setup_mix_cycles_the_types() -> void:
	var grid: GridModel = GridModel.new(GameConfig.load_from_dir("res://data").config)
	var types: Array[String] = ["rhinovirus", "bacteriophage", "staphylococcus"]
	var setup: BattleSetup = RhinoBench.build_setup(grid.ring_cells(), RhinoBench.UNIT_COUNT, RhinoBench.BENCH_SEED, types)
	var counts: Dictionary = {}
	for u: Dictionary in setup.units:
		counts[u["type"]] = int(counts.get(u["type"], 0)) + 1
	assert_eq(setup.units.size(), 200)
	assert_eq(counts.size(), 3)
	for id: String in types:
		assert_between(int(counts[id]), 66, 67)


func test_mix_types_with_counts_builds_that_exact_army_interleaved() -> void:
	var types: Array[String] = RhinoBench.mix_types("rhinovirus:120,bacteriophage:50,staphylococcus:30")
	assert_eq(types.size(), 200)
	var counts: Dictionary = {}
	for id: String in types:
		counts[id] = int(counts.get(id, 0)) + 1
	assert_eq(counts, {"rhinovirus": 120, "bacteriophage": 50, "staphylococcus": 30})
	# Interleaved: every run of 20 units has each type in proportion, within one unit.
	for start: int in range(0, 200, 20):
		var window: Dictionary = {}
		for i: int in range(start, start + 20):
			window[types[i]] = int(window.get(types[i], 0)) + 1
		assert_between(int(window.get("rhinovirus", 0)), 11, 13)
		assert_between(int(window.get("bacteriophage", 0)), 4, 6)
		assert_between(int(window.get("staphylococcus", 0)), 2, 4)
	assert_eq(RhinoBench.mix_types("rhinovirus:120,bacteriophage:50,staphylococcus:30"), types, "deterministic")

	var grid: GridModel = GridModel.new(GameConfig.load_from_dir("res://data").config)
	var setup: BattleSetup = RhinoBench.build_setup(grid.ring_cells(), types.size(), RhinoBench.BENCH_SEED, types)
	assert_eq(setup.units.size(), 200)
	var seen: Dictionary = {}
	for i: int in range(setup.units.size()):
		assert_eq(setup.units[i]["type"], types[i])
		seen[setup.units[i]["cell"]] = true
	assert_eq(seen.size(), 200, "200 distinct ring cells")


func test_mix_types_without_counts_cycles_and_falls_back() -> void:
	var cycled: Array[String] = RhinoBench.mix_types("rhinovirus,bacteriophage", 4)
	assert_eq(cycled, ["rhinovirus", "bacteriophage", "rhinovirus", "bacteriophage"] as Array[String])
	assert_eq(RhinoBench.mix_types("", 3), ["rhinovirus", "rhinovirus", "rhinovirus"] as Array[String])
	assert_eq(RhinoBench.mix_types("rhinovirus").size(), RhinoBench.UNIT_COUNT)


func test_summarize() -> void:
	var s: Dictionary = RhinoBench.summarize([10.0, 20.0, 30.0, 40.0])
	assert_almost_eq(float(s["avg_ms"]), 25.0, 0.001)
	assert_almost_eq(float(s["p95_ms"]), 40.0, 0.001)
	assert_almost_eq(float(s["min_fps"]), 25.0, 0.001)
	assert_eq(RhinoBench.summarize([])["frames"], 0)


func test_bench_scene_runs_for_three_seconds() -> void:
	var scene: PackedScene = load("res://tests/perf/rhino_bench.tscn")
	assert_not_null(scene)
	var bench: RhinoBench = scene.instantiate() as RhinoBench
	add_child_autofree(bench)
	await wait_seconds(3.0)
	assert_eq(bench.session.battle_setup.units.size(), 200)
	assert_gt(bench.alive_units, 0, "the swarm is alive and fighting")
	assert_not_null(bench.infection_phase.unit_layer)
	assert_false(bench.stats_label.text.is_empty())
	assert_eq(get_logger().get_errors().size(), 0)


func test_the_organelle_bench_adds_four_mitochondria_and_two_dendritic_cells() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["living_base"] = true
	cfg.feature_flags["dendritic_cell"] = true
	var grid := GridModel.new(cfg)
	var plain: BattleSetup = RhinoBench.build_setup(grid.ring_cells(), 20, RhinoBench.BENCH_SEED)
	var with: BattleSetup = RhinoBench.build_setup(grid.ring_cells(), 20, RhinoBench.BENCH_SEED, ["rhinovirus"], true)
	assert_eq(with.structures.size(), plain.structures.size() + 6)
	var counts: Dictionary = {}
	for s: Dictionary in with.structures:
		counts[s["type"]] = int(counts.get(s["type"], 0)) + 1
	assert_eq(counts["mitochondria"], 4)
	assert_eq(counts["dendritic_cell"], 2)
	assert_eq(with.validate(cfg).size(), 0, str(with.validate(cfg)))
	assert_false(plain.structures.any(func(s: Dictionary) -> bool: return s["type"] == "mitochondria"))
