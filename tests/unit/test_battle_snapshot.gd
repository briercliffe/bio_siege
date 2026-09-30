extends GutTest

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func _sim_with_unit() -> BattleSim:
	return SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(3, 3)}], 1, config)


func test_interpolates_between_two_captures() -> void:
	var sim: BattleSim = _sim_with_unit()
	var buf := BattleSnapshotBuffer.new()
	var p: PathogenState = sim.pathogens[0]
	p.pos = Vector2i(3000, 3000)
	buf.capture(sim)
	p.pos = Vector2i(5000, 7000)
	buf.capture(sim)
	assert_eq(buf.unit_ground(p.id, 0.0), Vector2(3.0, 3.0))
	assert_eq(buf.unit_ground(p.id, 1.0), Vector2(5.0, 7.0))
	assert_eq(buf.unit_ground(p.id, 0.5), Vector2(4.0, 5.0))
	assert_almost_eq(buf.moved_tiles(p.id), sqrt(20.0), 0.0001)


func test_unit_without_previous_capture_returns_current() -> void:
	var sim: BattleSim = _sim_with_unit()
	var buf := BattleSnapshotBuffer.new()
	var p: PathogenState = sim.pathogens[0]
	p.pos = Vector2i(2500, 4500)
	buf.capture(sim)
	assert_eq(buf.unit_ground(p.id, 0.0), Vector2(2.5, 4.5))
	assert_eq(buf.unit_ground(p.id, 0.5), Vector2(2.5, 4.5))
	assert_eq(buf.moved_tiles(p.id), 0.0)


func test_dead_units_are_dropped() -> void:
	var sim: BattleSim = _sim_with_unit()
	var buf := BattleSnapshotBuffer.new()
	var p: PathogenState = sim.pathogens[0]
	buf.capture(sim)
	assert_true(buf.has_unit(p.id))
	p.alive = false
	buf.capture(sim)
	assert_false(buf.has_unit(p.id))
	assert_false(buf.curr.has(p.id))


func test_capture_swaps_instead_of_allocating() -> void:
	var sim: BattleSim = _sim_with_unit()
	var buf := BattleSnapshotBuffer.new()
	var first: Dictionary = buf.prev
	var second: Dictionary = buf.curr
	buf.capture(sim)
	buf.capture(sim)
	# Two captures swap twice, so each dictionary is back in its original slot. Marker keys prove identity.
	first["marker"] = 1
	assert_true(buf.prev.has("marker"))
	assert_false(buf.curr.has("marker"))
	second["marker"] = 2
	assert_eq(buf.curr["marker"], 2)


func test_projectiles_are_tracked_separately() -> void:
	var sim: BattleSim = _sim_with_unit()
	var buf := BattleSnapshotBuffer.new()
	var proj := ProjectileState.create(1, 1, 1, Vector2i(1000, 2000), 100, 5)
	sim.projectiles.append(proj)
	buf.capture(sim)
	proj.pos = Vector2i(3000, 2000)
	buf.capture(sim)
	assert_true(buf.has_projectile(1))
	assert_eq(buf.projectile_ground(1, 0.5), Vector2(2.0, 2.0))
	assert_eq(buf.unit_ground(1, 0.0), Vector2(3.5, 3.5), "pathogen id 1 is unaffected by projectile id 1")
