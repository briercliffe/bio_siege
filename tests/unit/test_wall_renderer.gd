extends GutTest

## WallRenderer (#69): segment topology, post rules, damage tiers, and the battle and island wiring.

var config: GameConfig


class DrawHost extends Node2D:
	var draw_cb: Callable = Callable()
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		if draw_cb.is_valid():
			draw_cb.call(self)


func before_each() -> void:
	config = GameConfig.load_from_dir("res://data").config


func _cells_set(cells: Array[Vector2i]) -> Dictionary:
	var d: Dictionary = {}
	for c: Vector2i in cells:
		d[c] = true
	return d


func _run(from: Vector2i, to: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = []
	for x: int in range(from.x, to.x + 1):
		for y: int in range(from.y, to.y + 1):
			cells.append(Vector2i(x, y))
	return _cells_set(cells)


# --- topology ---------------------------------------------------------------

func test_lone_cell_has_one_rect_and_a_post() -> void:
	var walls: Dictionary = _cells_set([Vector2i(5, 5)])
	var rects: Array[Rect2] = WallRenderer.segment_rects(Vector2i(5, 5), walls)
	assert_eq(rects.size(), 1)
	assert_almost_eq(rects[0].size.x, 0.72, 0.0001)
	assert_almost_eq(rects[0].position.x, 5.14, 0.0001)
	assert_true(WallRenderer.needs_post(Vector2i(5, 5), walls, false), "a lone cell is an end")


func test_horizontal_run_bridges_left_and_posts_ends_and_every_fourth() -> void:
	var walls: Dictionary = _run(Vector2i(0, 0), Vector2i(4, 0))
	var rects: Array[Rect2] = WallRenderer.segment_rects(Vector2i(2, 0), walls)
	assert_eq(rects.size(), 2, "core plus the left bridge")
	assert_eq(rects[1], Rect2(1.5, 0.14, 1.0, 0.72))
	assert_eq(WallRenderer.needs_post(Vector2i(2, 0), walls, false), (2 + 0) % 4 == 0)
	assert_false(WallRenderer.needs_post(Vector2i(2, 0), walls, false))
	assert_false(WallRenderer.needs_post(Vector2i(1, 0), walls, false))
	assert_false(WallRenderer.needs_post(Vector2i(3, 0), walls, false))
	assert_true(WallRenderer.needs_post(Vector2i(0, 0), walls, false), "left end")
	assert_true(WallRenderer.needs_post(Vector2i(4, 0), walls, false), "right end")
	var long: Dictionary = _run(Vector2i(0, 0), Vector2i(9, 0))
	assert_true(WallRenderer.needs_post(Vector2i(4, 0), long, false), "(4 + 0) % 4 == 0 mid-run")
	assert_true(WallRenderer.needs_post(Vector2i(8, 0), long, false), "(8 + 0) % 4 == 0 mid-run")
	assert_eq(WallRenderer.segment_rects(Vector2i(0, 0), walls).size(), 1, "the right join belongs to the neighbour")


func test_vertical_run_bridges_up() -> void:
	var walls: Dictionary = _run(Vector2i(3, 0), Vector2i(3, 4))
	var rects: Array[Rect2] = WallRenderer.segment_rects(Vector2i(3, 2), walls)
	assert_eq(rects.size(), 2)
	assert_eq(rects[1], Rect2(3.14, 1.5, 0.72, 1.0))
	assert_false(WallRenderer.needs_post(Vector2i(3, 2), walls, false))
	assert_true(WallRenderer.needs_post(Vector2i(3, 1), walls, false), "(3 + 1) % 4 == 0")


func test_corner_needs_a_post() -> void:
	var walls: Dictionary = _cells_set([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	assert_true(WallRenderer.needs_post(Vector2i(0, 0), walls, false), "right and down is not straight")
	assert_eq(WallRenderer.segment_rects(Vector2i(0, 0), walls).size(), 1)
	assert_eq(WallRenderer.segment_rects(Vector2i(1, 0), walls).size(), 2)
	assert_eq(WallRenderer.segment_rects(Vector2i(0, 1), walls).size(), 2)


func test_t_junction_centre_needs_a_post() -> void:
	var walls: Dictionary = _cells_set([Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)])
	assert_true(WallRenderer.needs_post(Vector2i(5, 5), walls, false), "3 neighbours")
	var cross: Dictionary = _cells_set([Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(5, 4)])
	assert_true(WallRenderer.needs_post(Vector2i(5, 5), cross, false), "4 neighbours")
	assert_eq(WallRenderer.segment_rects(Vector2i(5, 5), cross).size(), 3)


func test_hurt_never_has_a_post() -> void:
	var lone: Dictionary = _cells_set([Vector2i(5, 5)])
	assert_false(WallRenderer.needs_post(Vector2i(5, 5), lone, true))
	var corner: Dictionary = _cells_set([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	assert_false(WallRenderer.needs_post(Vector2i(0, 0), corner, true))


func test_height_tiers() -> void:
	assert_eq(WallRenderer.height_tiles(149, 300), 0.55)
	assert_eq(WallRenderer.height_tiles(150, 300), 0.8)
	assert_eq(WallRenderer.height_tiles(300, 300), 0.8)
	assert_eq(WallRenderer.height_tiles(0, 300), 0.55)


func test_removing_a_cell_drops_the_neighbours_bridge() -> void:
	var walls: Dictionary = _run(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(WallRenderer.segment_rects(Vector2i(3, 0), walls).size(), 2)
	walls.erase(Vector2i(2, 0))
	assert_eq(WallRenderer.segment_rects(Vector2i(3, 0), walls).size(), 1, "no left bridge into the gap")
	assert_true(WallRenderer.needs_post(Vector2i(3, 0), walls, false), "(3, 0) is now an end")
	assert_true(WallRenderer.needs_post(Vector2i(1, 0), walls, false), "(1, 0) is now an end")


# --- cache and painting -----------------------------------------------------

func test_rebuild_caches_cells_and_posts() -> void:
	var r := WallRenderer.new()
	var walls: Dictionary = _run(Vector2i(12, 16), Vector2i(22, 16))
	walls.erase(Vector2i(15, 16))
	r.rebuild(walls, IsoProjection.new(40.0, Vector2(600.0, 100.0)))
	assert_eq(r.cell_count(), 10)
	assert_false(r.has_cell(Vector2i(15, 16)))
	assert_true(r.has_post(Vector2i(12, 16)))
	assert_true(r.has_post(Vector2i(14, 16)), "end beside the gap")
	assert_true(r.has_post(Vector2i(16, 16)), "end beside the gap")
	assert_true(r.has_post(Vector2i(20, 16)), "(20 + 16) % 4 == 0")
	assert_false(r.has_post(Vector2i(18, 16)))
	assert_eq(r.tile_px(), 40.0)


func test_paint_every_part_at_every_size_draws_cleanly() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var walls: Dictionary = _run(Vector2i(2, 2), Vector2i(6, 2))
	walls[Vector2i(4, 3)] = true
	var renderers: Array[WallRenderer] = []
	for t: float in [8.0, 14.0, 40.0]:
		var r := WallRenderer.new()
		r.rebuild(walls, IsoProjection.new(t, Vector2(200.0, 50.0)))
		renderers.append(r)
	var pose := ModelPose.new()
	pose.shake = 1.0
	pose.time = 0.3
	host.draw_cb = func(ci: CanvasItem) -> void:
		for r: WallRenderer in renderers:
			r.paint_shadows(ci)
			for cell_var: Variant in walls:
				var cell: Vector2i = cell_var
				r.paint_cell(ci, cell, 1.0, pose)
				r.paint_cell(ci, cell, 0.3, pose)
				r.paint_cracks(ci, cell, false, 0.8, pose)
			r.paint_break(ci, Vector2i(9, 9), 0.5)
			r.paint_goo(ci, Vector2i(9, 9))
			r.paint_body(ci, Vector2i(30, 30), false, pose)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0)
	assert_no_new_orphans()


func test_wall_painter_is_registered_for_the_viewer() -> void:
	var p: ModelPainter = ModelRegistry.painter_for("mucous_wall")
	assert_true(p is WallPainter)
	assert_eq(p.height_tiles(), 0.8)


# --- AnimDriver shake -------------------------------------------------------

func test_wall_hit_shakes_for_three_ticks() -> void:
	var sim: BattleSim = SimFixtures.make_sim([{"type": "mucous_wall", "origin": Vector2i(5, 5)}], [], 1, config)
	var wall: StructureState = null
	for s: StructureState in sim.structures:
		if s.type_id == "mucous_wall":
			wall = s
	var driver := AnimDriver.new()
	driver.on_event({"type": SimEvents.STRUCTURE_DAMAGED, "structure_id": wall.id, "tick": sim.tick})
	var seen: Array[float] = []
	for i: int in range(5):
		seen.append(driver.pose_for_structure(wall, sim.tick + 1 + i, Vector2.ZERO, 0.0).shake)
	assert_eq(seen[0], 1.0)
	assert_gt(seen[2], 0.0)
	assert_eq(seen[3], 0.0, "over after 3 ticks")
	assert_eq(seen[4], 0.0)


# --- UnitLayer wiring -------------------------------------------------------

func _layer(sim: BattleSim) -> UnitLayer:
	var snaps := BattleSnapshotBuffer.new()
	snaps.capture(sim)
	var runner := BattleRunner.new()
	autofree(runner)
	var layer := UnitLayer.new()
	autofree(layer)
	layer.setup(sim, config, IsoProjection.new(14.0, Vector2.ZERO), snaps, runner)
	return layer


func _wall_sim(cells: Array[Vector2i], units: Array) -> BattleSim:
	var defs: Array = []
	for c: Vector2i in cells:
		defs.append({"type": "mucous_wall", "origin": c})
	return SimFixtures.make_sim(defs, units, 1, config)


func _wall_at(sim: BattleSim, cell: Vector2i) -> StructureState:
	for s: StructureState in sim.structures:
		if s.type_id == "mucous_wall" and s.origin == cell:
			return s
	return null


func test_wall_items_use_cell_keys_with_post_and_crack_offsets() -> void:
	var sim: BattleSim = _wall_sim([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)], [])
	var layer: UnitLayer = _layer(sim)
	var end: StructureState = _wall_at(sim, Vector2i(5, 5))
	var mid: StructureState = _wall_at(sim, Vector2i(6, 5))
	mid.hp = mid.max_hp / 2 - 1
	layer._collect()
	var keys: Dictionary = {}
	for item: UnitLayer.UnitDrawItem in layer._sorted:
		keys[Vector2i(item.kind, item.id)] = item.key
	assert_almost_eq(float(keys[Vector2i(UnitLayer.KIND_STRUCTURE, end.id)]), 11.0, 0.00001, "key c + r + 1")
	assert_almost_eq(float(keys[Vector2i(UnitLayer.KIND_WALL_POST, end.id)]), 11.001, 0.00001)
	assert_false(keys.has(Vector2i(UnitLayer.KIND_WALL_CRACKS, end.id)), "no cracks at full HP when not attacked")
	assert_false(keys.has(Vector2i(UnitLayer.KIND_WALL_POST, mid.id)), "a straight middle cell has no post")
	assert_almost_eq(float(keys[Vector2i(UnitLayer.KIND_WALL_CRACKS, mid.id)]), 12.002, 0.00001, "hurt cells crack")


func test_blocked_wall_shows_cracks_above_half_hp() -> void:
	var sim: BattleSim = _wall_sim([Vector2i(5, 5)], [{"type": "rhinovirus", "cell": Vector2i(3, 5)}])
	var layer: UnitLayer = _layer(sim)
	var wall: StructureState = _wall_at(sim, Vector2i(5, 5))
	sim.pathogens[0].blocker_id = wall.id
	assert_true(layer.build_draw_order().has(Vector2i(UnitLayer.KIND_WALL_CRACKS, wall.id)))
	sim.pathogens[0].blocker_id = 0
	assert_false(layer.build_draw_order().has(Vector2i(UnitLayer.KIND_WALL_CRACKS, wall.id)))


func test_unit_behind_a_wall_draws_before_it_and_in_front_after() -> void:
	var sim: BattleSim = _wall_sim([Vector2i(10, 10)], [
		{"type": "rhinovirus", "cell": Vector2i(9, 10)},
		{"type": "rhinovirus", "cell": Vector2i(11, 10)},
	])
	var layer: UnitLayer = _layer(sim)
	var wall: StructureState = _wall_at(sim, Vector2i(10, 10))
	var order: Array[Vector2i] = layer.build_draw_order()
	var behind: int = order.find(Vector2i(UnitLayer.KIND_PATHOGEN, 1))
	var front: int = order.find(Vector2i(UnitLayer.KIND_PATHOGEN, 2))
	var seg: int = order.find(Vector2i(UnitLayer.KIND_STRUCTURE, wall.id))
	var post: int = order.find(Vector2i(UnitLayer.KIND_WALL_POST, wall.id))
	assert_true(behind < seg, "the far unit is painted first, so the wall hides it")
	assert_true(seg < post and post < front, "the near unit overlaps the wall and its post")


func test_destroyed_wall_leaves_a_gap_goo_and_a_short_break() -> void:
	var sim: BattleSim = _wall_sim([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)], [])
	var layer: UnitLayer = _layer(sim)
	layer._collect()
	assert_eq(layer.walls.cell_count(), 3)
	assert_false(layer.walls.has_post(Vector2i(6, 5)))
	var mid: StructureState = _wall_at(sim, Vector2i(6, 5))
	mid.alive = false
	layer.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "structure_id": mid.id})
	layer._collect()
	assert_eq(layer.walls.cell_count(), 2)
	assert_false(layer.walls.has_cell(Vector2i(6, 5)))
	assert_eq(WallRenderer.segment_rects(Vector2i(7, 5), layer._wall_cells).size(), 1, "the bridge into the gap is gone")
	assert_true(layer.walls.has_post(Vector2i(7, 5)), "the new end gets a post")
	assert_eq(layer._goo, [mid.id] as Array[int])
	assert_eq(layer._scorch.size(), 0)
	assert_true(layer.build_draw_order().has(Vector2i(UnitLayer.KIND_STRUCTURE, mid.id)), "chunks play")
	sim.tick += AnimDriver.DEATH_TICKS["mucous_wall"]
	assert_false(layer.build_draw_order().has(Vector2i(UnitLayer.KIND_STRUCTURE, mid.id)), "break effect over")
	assert_eq(layer._goo.size(), 1, "goo stays")


func test_unit_layer_draws_walls_without_errors() -> void:
	var sim: BattleSim = _wall_sim([Vector2i(5, 5), Vector2i(6, 5), Vector2i(6, 6)], [{"type": "rhinovirus", "cell": Vector2i(3, 5)}])
	var layer: UnitLayer = _layer(sim)
	var wall: StructureState = _wall_at(sim, Vector2i(6, 5))
	wall.hp = 1
	sim.pathogens[0].blocker_id = wall.id
	var gone: StructureState = _wall_at(sim, Vector2i(5, 5))
	gone.alive = false
	layer.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "structure_id": gone.id})
	add_child(layer)
	layer.queue_redraw()
	await wait_process_frames(2)
	assert_gt(layer.last_item_count, 0)
	remove_child(layer)


# --- GridView wiring --------------------------------------------------------

func test_grid_view_rebuilds_walls_on_place_and_remove() -> void:
	var session := Session.new(config)
	var gv := GridView.new()
	add_child_autofree(gv)
	gv.setup(session.grid, session.config)
	gv.fit_to_rect(Rect2(0, 0, 640, 520))
	gv._rebuild_items()
	var before: int = gv._walls.cell_count()
	var sid: int = session.grid.place("mucous_wall", Vector2i(8, 8), Wallet.new({"atp": 1000}))
	assert_gt(sid, 0)
	assert_true(gv._walls_dirty)
	gv._rebuild_items()
	assert_eq(gv._walls.cell_count(), before + 1)
	assert_true(gv._walls.has_cell(Vector2i(8, 8)))
	assert_true(session.grid.sell(sid))
	gv._rebuild_items()
	assert_false(gv._walls.has_cell(Vector2i(8, 8)))
	gv.set_ghost("mucous_wall", Vector2i(10, 10), true)
	gv.queue_redraw()
	await wait_process_frames(2)
	assert_true(gv._ghost_walls.has_cell(Vector2i(10, 10)))
