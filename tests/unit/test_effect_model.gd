extends GutTest

## EffectModel and EffectLayer (issue #71): effect lifetimes, the capacity cap, Reduce flashes and the
## health-bar colours, without rendering.

var config: GameConfig
var sim: BattleSim
var bcell: StructureState
var macrophage: StructureState
var wall: StructureState
var unit: PathogenState


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config
	sim = SimFixtures.make_sim(
		[
			{"type": "b_cell", "origin": Vector2i(10, 10)},
			{"type": "macrophage", "origin": Vector2i(26, 10)},
			{"type": "mucous_wall", "origin": Vector2i(5, 30)},
		],
		[{"type": "rhinovirus", "cell": Vector2i(3, 3)}],
		1, config)
	for s: StructureState in sim.structures:
		match s.type_id:
			"b_cell":
				bcell = s
			"macrophage":
				macrophage = s
			"mucous_wall":
				wall = s
	unit = sim.pathogens[0]


func _spawn(tick: int, projectile_id: int) -> Dictionary:
	return {"type": SimEvents.PROJECTILE_SPAWNED, "tick": tick, "projectile_id": projectile_id,
		"structure_id": bcell.id, "target_unit_id": unit.id}


func _hit(tick: int, projectile_id: int) -> Dictionary:
	return {"type": SimEvents.PROJECTILE_HIT, "tick": tick, "projectile_id": projectile_id,
		"structure_id": bcell.id, "target_unit_id": unit.id}


func _splash(tick: int, radius_mt: int) -> Dictionary:
	return {"type": SimEvents.SPLASH, "tick": tick, "structure_id": macrophage.id,
		"pos": Vector2i(12000, 9000), "radius": radius_mt, "hit_unit_ids": []}


func test_projectile_lifecycle() -> void:
	var model := EffectModel.new()
	model.on_event(_spawn(10, 5), sim)
	assert_eq(model.count_of(EffectModel.Kind.PROJECTILE), 1, "PROJECTILE_SPAWNED adds one")
	assert_eq(model.active_count(), 1)
	model.advance(30)
	assert_eq(model.count_of(EffectModel.Kind.PROJECTILE), 1, "a projectile stays until its hit")

	model.on_event(_hit(30, 5), sim)
	assert_eq(model.count_of(EffectModel.Kind.PROJECTILE), 0, "PROJECTILE_HIT removes it")
	assert_eq(model.count_of(EffectModel.Kind.SPARK), 1, "and adds a spark")
	var start: int = model.start[model.find(EffectModel.Kind.SPARK, unit.id)]
	assert_eq(start, 31, "effects start on the tick the view first sees the event")
	model.advance(start + EffectModel.SPARK_TICKS - 1)
	assert_eq(model.count_of(EffectModel.Kind.SPARK), 1)
	model.advance(start + EffectModel.SPARK_TICKS)
	assert_eq(model.count_of(EffectModel.Kind.SPARK), 0, "the spark expires after 4 ticks")
	assert_eq(EffectModel.SPARK_TICKS, 4)


func test_fizzled_projectile_is_removed_without_a_spark() -> void:
	var model := EffectModel.new()
	model.on_event(_spawn(10, 7), sim)
	model.on_event({"type": SimEvents.PROJECTILE_FIZZLED, "tick": 12, "projectile_id": 7}, sim)
	assert_eq(model.active_count(), 0)


func test_splash_ring_radius_and_lifetime() -> void:
	var model := EffectModel.new()
	model.on_event(_splash(20, 4000), sim)
	var s: int = model.find(EffectModel.Kind.SPLASH, macrophage.id)
	assert_ne(s, -1)
	assert_eq(model.radius[s], 4.0)
	assert_eq(model.pos_a[s], Vector2(12.0, 9.0))
	var start: int = model.start[s]
	model.advance(start + 5)
	assert_eq(model.count_of(EffectModel.Kind.SPLASH), 1)
	model.advance(start + 6)
	assert_eq(model.count_of(EffectModel.Kind.SPLASH), 0, "the ring expires after 6 ticks")


func test_splash_tower_shot_launches_a_vesicle_and_delays_the_ring() -> void:
	var model := EffectModel.new()
	model.on_event(_splash(20, 1000), sim)
	model.on_event({"type": SimEvents.TOWER_FIRED, "tick": 20, "structure_id": macrophage.id, "target_unit_id": unit.id}, sim)
	var v: int = model.find(EffectModel.Kind.VESICLE, macrophage.id)
	assert_ne(v, -1, "a Macrophage shot launches a vesicle")
	assert_eq(model.pos_a[v], UnitLayer.structure_anchor(macrophage))
	assert_eq(model.pos_b[v], Vector2(12.0, 9.0), "it lands where the splash is")
	var ring: int = model.find(EffectModel.Kind.SPLASH, macrophage.id)
	assert_eq(model.start[ring], model.start[v] + EffectModel.VESICLE_TICKS, "the ring opens when it lands")
	model.advance(model.start[v] + EffectModel.VESICLE_TICKS)
	assert_eq(model.count_of(EffectModel.Kind.VESICLE), 0)
	assert_eq(model.count_of(EffectModel.Kind.SPLASH), 1)


func test_projectile_tower_shot_has_no_vesicle() -> void:
	var model := EffectModel.new()
	model.on_event({"type": SimEvents.TOWER_FIRED, "tick": 3, "structure_id": bcell.id, "target_unit_id": unit.id}, sim)
	assert_eq(model.active_count(), 0)


func test_scorch_stays_for_towers_and_never_for_walls() -> void:
	var model := EffectModel.new()
	model.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "tick": 40, "structure_id": macrophage.id, "structure_type": "macrophage"}, sim)
	assert_eq(model.scorch_count(), 1)
	assert_eq(model.scorch_pos[model.scorch_slot(0)], UnitLayer.structure_anchor(macrophage))
	for t: int in range(40, 5000, 97):
		model.advance(t)
	assert_eq(model.scorch_count(), 1, "scorch never expires during advance()")
	model.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "tick": 41, "structure_id": macrophage.id}, sim)
	assert_eq(model.scorch_count(), 1, "one scorch per structure")

	model.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "tick": 50, "structure_id": wall.id, "structure_type": "mucous_wall"}, sim)
	assert_eq(model.scorch_count(), 1, "a wall leaves no scorch")
	assert_eq(model.active_count(), 1, "nor a puff: walls have their own break effect")


func test_bar_colors() -> void:
	assert_eq(EffectLayer.bar_color(0.6), EffectLayer.BAR_GREEN)
	assert_eq(EffectLayer.bar_color(0.5), EffectLayer.BAR_AMBER)
	assert_eq(EffectLayer.bar_color(0.3), EffectLayer.BAR_AMBER)
	assert_eq(EffectLayer.bar_color(0.25), EffectLayer.BAR_AMBER)
	assert_eq(EffectLayer.bar_color(0.2), EffectLayer.BAR_RED)
	assert_eq(EffectLayer.BAR_GREEN, Color("#2ecc71"))
	assert_eq(EffectLayer.BAR_AMBER, Color("#f5b041"))
	assert_eq(EffectLayer.BAR_RED, Color("#e74c3c"))


func test_capacity_drops_the_oldest() -> void:
	var model := EffectModel.new()
	model.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "tick": 1, "structure_id": bcell.id}, sim)
	for i: int in range(300):
		model.on_event({"type": SimEvents.PATHOGEN_KILLED, "tick": 100 + i, "unit_id": unit.id, "unit_type": "test_blob"}, sim)
	assert_lte(model.active_count(), EffectModel.CAPACITY)
	assert_eq(EffectModel.CAPACITY, 256)
	assert_eq(model.count_of(EffectModel.Kind.PUFF), EffectModel.TRANSIENT_CAPACITY)
	assert_eq(model.start[model.slot(0)], 100 + 300 - EffectModel.TRANSIENT_CAPACITY + 1, "the oldest puffs were dropped")
	assert_eq(model.scorch_count(), 1, "a burst of puffs never drops a scorch")
	model.advance(100 + 300 + EffectModel.PUFF_TICKS)
	assert_eq(model.count_of(EffectModel.Kind.PUFF), 0)


func test_puffs_only_for_painters_without_a_custom_death() -> void:
	var model := EffectModel.new()
	model.on_event({"type": SimEvents.PATHOGEN_KILLED, "tick": 5, "unit_id": unit.id, "unit_type": "rhinovirus"}, sim)
	assert_eq(model.active_count(), 0, "the Rhinovirus painter draws its own pop")
	model.on_event({"type": SimEvents.PATHOGEN_KILLED, "tick": 5, "unit_id": unit.id, "unit_type": "test_blob"}, sim)
	assert_eq(model.count_of(EffectModel.Kind.PUFF), 1)
	assert_false(ModelRegistry.painter_for("test_blob").has_custom_death())
	for id: String in ["rhinovirus", "bacteriophage", "staphylococcus", "macrophage", "b_cell", "nucleus", "mucous_wall"]:
		assert_true(ModelRegistry.painter_for(id).has_custom_death(), id)


func test_reduce_flashes_creates_no_sparks() -> void:
	var model := EffectModel.new(true)
	model.on_event(_spawn(10, 5), sim)
	model.on_event(_hit(12, 5), sim)
	assert_eq(model.count_of(EffectModel.Kind.SPARK), 0)
	assert_eq(model.active_count(), 0)


func test_layer_passes_reduce_flashes_to_the_model_live() -> void:
	var layer := EffectLayer.new()
	add_child_autofree(layer)
	var model := EffectModel.new()
	layer.setup(model, sim, IsoProjection.new(14.0, Vector2.ZERO), null, null, true)
	assert_true(model.reduce_flashes)
	layer.reduce_flashes = false
	assert_false(model.reduce_flashes)
	model.on_event(_spawn(10, 5), sim)
	model.on_event(_hit(12, 5), sim)
	assert_eq(model.count_of(EffectModel.Kind.SPARK), 1)


func test_layer_builds_shots_bars_and_ground_decals() -> void:
	var snaps := BattleSnapshotBuffer.new()
	var proj := ProjectileState.create(5, bcell.id, unit.id, bcell.center, 500, 0)
	sim.projectiles.append(proj)
	snaps.capture(sim)
	proj.pos += Vector2i(500, 0)
	snaps.capture(sim)
	var runner := BattleRunner.new()
	autofree(runner)
	runner.alpha = 0.5
	var layer := EffectLayer.new()
	add_child_autofree(layer)
	var model := EffectModel.new()
	layer.setup(model, sim, IsoProjection.new(14.0, Vector2.ZERO), snaps, runner, false)

	layer.build_frame()
	assert_eq(layer.fx_triangles(), 0)
	assert_eq(layer.last_bar_count, 0, "no bars while nothing is damaged")

	model.on_event(_spawn(sim.tick - 1, 5), sim)
	unit.hp = unit.max_hp / 2
	bcell.hp = bcell.max_hp - 1
	layer.build_frame()
	assert_gt(layer.fx_triangles(), 0, "the shot is drawn")
	assert_eq(layer.last_bar_count, 2, "one bar per damaged entity")

	assert_true(layer.build_ground())
	assert_eq(layer.ground_triangles(), Vector2i.ZERO)
	model.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "tick": sim.tick - 1, "structure_id": macrophage.id}, sim)
	model.on_event(_splash(sim.tick - 1, 1000), sim)
	layer.build_ground()
	var tris: Vector2i = layer.ground_triangles()
	assert_gt(tris.x, 0, "scorch decal")
	assert_gt(tris.y, 0, "splash ring")

	layer.reduce_flashes = true
	layer.build_ground()
	assert_lt(layer.ground_triangles().y, tris.y, "no splash fill with Reduce flashes on")
