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
