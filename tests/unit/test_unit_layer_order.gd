extends GutTest

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func _layer(sim: BattleSim) -> UnitLayer:
	var snaps := BattleSnapshotBuffer.new()
	snaps.capture(sim)
	var runner := BattleRunner.new()
	autofree(runner)
	var layer := UnitLayer.new()
	autofree(layer)
	layer.setup(sim, config, IsoProjection.new(14.0, Vector2.ZERO), snaps, runner)
	return layer


func _without_nucleus(order: Array[Vector2i], sim: BattleSim) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for item: Vector2i in order:
		if item == Vector2i(UnitLayer.KIND_STRUCTURE, sim.nucleus_id):
			continue
		out.append(item)
	return out


func test_units_and_tower_sort_by_depth() -> void:
	var sim: BattleSim = SimFixtures.make_sim(
		[{"type": "macrophage", "origin": Vector2i(10, 10)}],
		[
			{"type": "rhinovirus", "cell": Vector2i(30, 30)},
			{"type": "rhinovirus", "cell": Vector2i(3, 3)},
		],
		1, config)
	var layer: UnitLayer = _layer(sim)
	# Pathogen ids are 1-based in unit order: id 1 is the far unit, id 2 the near one.
	var tower_id: int = 0
	for s: StructureState in sim.structures:
		if s.type_id == "macrophage":
			tower_id = s.id
	var order: Array[Vector2i] = _without_nucleus(layer.build_draw_order(), sim)
	assert_eq(order, [
		Vector2i(UnitLayer.KIND_PATHOGEN, 2),
		Vector2i(UnitLayer.KIND_STRUCTURE, tower_id),
		Vector2i(UnitLayer.KIND_PATHOGEN, 1),
	] as Array[Vector2i])


func test_equal_keys_sort_structures_before_units() -> void:
	var sim: BattleSim = SimFixtures.make_sim(
		[{"type": "macrophage", "origin": Vector2i(10, 10)}],
		[{"type": "rhinovirus", "cell": Vector2i(10, 10)}],
		1, config)
	var layer: UnitLayer = _layer(sim)
	var tower: StructureState = null
	for s: StructureState in sim.structures:
		if s.type_id == "macrophage":
			tower = s
	# Put the unit exactly on the tower's footprint centre so both keys match.
	sim.pathogens[0].pos = Vector2i(11500, 11500)
	layer.snapshots.capture(sim)
	layer.runner.alpha = 1.0
	var order: Array[Vector2i] = _without_nucleus(layer.build_draw_order(), sim)
	assert_eq(order, [
		Vector2i(UnitLayer.KIND_STRUCTURE, tower.id),
		Vector2i(UnitLayer.KIND_PATHOGEN, 1),
	] as Array[Vector2i])


func test_dead_units_leave_the_order_after_the_fade() -> void:
	var sim: BattleSim = SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(3, 3)}], 1, config)
	var layer: UnitLayer = _layer(sim)
	var p: PathogenState = sim.pathogens[0]
	p.alive = false
	layer.on_event({"type": SimEvents.PATHOGEN_KILLED, "unit_id": p.id})
	assert_true(layer.build_draw_order().has(Vector2i(UnitLayer.KIND_PATHOGEN, p.id)), "fading copy still drawn")
	sim.tick += AnimDriver.DEATH_TICKS["rhinovirus"]
	assert_false(layer.build_draw_order().has(Vector2i(UnitLayer.KIND_PATHOGEN, p.id)), "dropped after the fade")


func test_destroyed_tower_leaves_scorch_but_wall_does_not() -> void:
	var sim: BattleSim = SimFixtures.make_sim(
		[{"type": "macrophage", "origin": Vector2i(10, 10)}, {"type": "mucous_wall", "origin": Vector2i(5, 5)}],
		[], 1, config)
	var layer: UnitLayer = _layer(sim)
	for s: StructureState in sim.structures:
		if s.type_id == "macrophage" or s.type_id == "mucous_wall":
			s.alive = false
			layer.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "structure_id": s.id})
	assert_eq(layer._scorch.size(), 1)
