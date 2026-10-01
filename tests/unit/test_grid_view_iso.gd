extends GutTest

func _make_view() -> GridView:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	var session := Session.new(res.config)
	var gv := GridView.new()
	add_child_autofree(gv)
	gv.setup(session.grid, session.config)
	gv.fit_to_rect(Rect2(0, 0, 640, 520))
	return gv

func _touch(gv: GridView, local: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = pressed
	ev.position = gv.to_global(local)
	return ev

func test_corner_cells_round_trip() -> void:
	var gv: GridView = _make_view()
	for c: Vector2i in [Vector2i(2, 2), Vector2i(37, 2), Vector2i(2, 37), Vector2i(37, 37), Vector2i(20, 20)]:
		assert_eq(gv.local_to_cell(gv.cell_to_local_center(c)), c)

func test_island_fits_the_rect() -> void:
	var gv: GridView = _make_view()
	var size: Vector2 = gv.projection.island_size(40, 40)
	assert_true(size.x <= 640.01)
	assert_true(gv.projection.tile_px <= float(gv.config.tile_px) * 2.0)
	assert_eq(gv.scale, Vector2.ONE)

func test_touch_press_emits_cell() -> void:
	var gv: GridView = _make_view()
	var got: Array[Vector2i] = []
	gv.cell_pressed.connect(func(c: Vector2i) -> void: got.append(c))
	gv._unhandled_input(_touch(gv, gv.cell_to_local_center(Vector2i(5, 5)), true))
	assert_eq(got, [Vector2i(5, 5)])

func test_press_outside_island_emits_nothing() -> void:
	var gv: GridView = _make_view()
	var got: Array[Vector2i] = []
	gv.cell_pressed.connect(func(c: Vector2i) -> void: got.append(c))
	gv._unhandled_input(_touch(gv, Vector2(1.0, 1.0), true))
	assert_eq(got.size(), 0)

func test_mouse_events_are_ignored() -> void:
	var gv: GridView = _make_view()
	var got: Array[Vector2i] = []
	gv.cell_pressed.connect(func(c: Vector2i) -> void: got.append(c))
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = gv.to_global(gv.cell_to_local_center(Vector2i(5, 5)))
	gv._unhandled_input(mb)
	assert_eq(got.size(), 0)

func test_ghost_geometry_for_ranged_tower() -> void:
	var gv: GridView = _make_view()
	gv.set_ghost("b_cell", Vector2i(10, 10), true)
	gv._rebuild_ghost()
	assert_not_null(gv._g_item)
	assert_false(gv._g_range_fill.is_empty())
	assert_false(gv._g_dots.is_empty())
	gv.set_ghost("mucous_wall", Vector2i(10, 10), false)
	gv._rebuild_ghost()
	assert_true(gv._g_range_fill.is_empty())

func test_structures_are_painted_by_their_model_painters() -> void:
	var gv: GridView = _make_view()
	var wallet := Wallet.new({"atp": 100000})
	assert_gt(gv.grid.place("macrophage", Vector2i(6, 6), wallet), 0)
	assert_gt(gv.grid.place("b_cell", Vector2i(12, 6), wallet), 0)
	gv._rebuild_items()
	var seen: Dictionary = {}
	for item: GridView.StructureItem in gv._items:
		if item.kind == 1:
			assert_null(item.painter, "walls go through the WallRenderer")
			continue
		assert_same(item.painter, ModelRegistry.painter_for(item.type_id))
		assert_eq(item.pose.anim, ModelPose.Anim.IDLE)
		assert_eq(item.pose.seed, item.id)
		seen[item.type_id] = item.painter
	assert_true(seen.get("nucleus") is NucleusPainter)
	assert_true(seen.get("macrophage") is MacrophagePainter)
	assert_true(seen.get("b_cell") is BCellPainter)
	gv.queue_redraw()
	await wait_process_frames(2)
	assert_eq(get_logger().get_errors().size(), 0)

func test_idle_clock_runs_only_while_structures_are_drawn() -> void:
	var gv: GridView = _make_view()
	gv._rebuild_items()
	assert_true(gv._has_models, "the Nucleus is always on the island")
	gv._process(0.25)
	assert_almost_eq(gv.anim_time, 0.25, 0.0001)
	gv.draw_structures = false
	gv._process(0.25)
	assert_almost_eq(gv.anim_time, 0.25, 0.0001, "Infection draws structures in the UnitLayer, so the island stays still")
	gv.draw_structures = true
	gv.visible = false
	gv._process(0.25)
	assert_almost_eq(gv.anim_time, 0.25, 0.0001, "no idle redraws while hidden")

func test_tower_ghost_is_the_real_model_in_the_ghost_group() -> void:
	var gv: GridView = _make_view()
	gv.set_ghost("b_cell", Vector2i(10, 10), true)
	gv._rebuild_ghost()
	assert_true(gv._ghost_group.visible)
	assert_true(gv._ghost_canvas.painter is BCellPainter)
	assert_eq(gv._ghost_canvas.foot, gv.projection.footprint_center(Vector2i(10, 10), Vector2i(3, 3)))
	gv.clear_ghost()
	assert_false(gv._ghost_group.visible)

func test_static_island_is_cached_and_repainted_only_on_change() -> void:
	var gv: GridView = _make_view()
	await wait_process_frames(2)
	assert_eq(gv.ground_renders, 1, "painted once")
	var rect: Rect2 = gv.ground_rect()
	var slab := Vector2(0.0, GridView.SLAB_T * gv.projection.tile_px)
	var rim := Vector2(2.0, 2.0)
	for p: Vector2 in gv._outline:
		assert_true(rect.has_point(p - rim) and rect.has_point(p + rim), "covers the island and its rim")
		assert_true(rect.has_point(p + slab + rim), "and the slab")
	# Idle and pulse redraws of the live layers reuse the texture.
	gv.deploy_mode = true
	gv.set_night(true)
	await wait_process_frames(2)
	var after_phase: int = gv.ground_renders
	assert_eq(after_phase, 2, "one repaint for the theme and phase change together")
	for i: int in range(5):
		gv._process(0.05)
		await wait_process_frames(1)
	assert_eq(gv.ground_renders, after_phase, "the band pulse is a live overlay")
	gv.draw_structures = false
	await wait_process_frames(2)
	assert_eq(gv.ground_renders, after_phase + 1, "plates leave the island in Infection")
	gv.fit_to_rect(Rect2(0, 0, 800, 600))
	await wait_process_frames(2)
	assert_eq(gv.ground_renders, after_phase + 2, "T and origin changes repaint it")
	var wallet := Wallet.new({"atp": 100000})
	gv.draw_structures = true
	await wait_process_frames(2)
	var before_place: int = gv.ground_renders
	assert_gt(gv.grid.place("macrophage", Vector2i(6, 6), wallet), 0)
	await wait_process_frames(2)
	assert_eq(gv.ground_renders, before_place + 1, "a new structure brings its plate")
	assert_eq(get_logger().get_errors().size(), 0)

func test_night_switch_and_structure_cache_is_depth_sorted() -> void:
	var gv: GridView = _make_view()
	gv.set_night(true)
	assert_true(gv.night)
	gv._rebuild_items()
	assert_eq(gv._items.size(), gv.grid.structures().size())
	var last: float = -1.0
	for item: GridView.StructureItem in gv._items:
		assert_true(item.depth >= last)
		last = item.depth

# --- pinch zoom ------------------------------------------------------------

func _finger(gv: GridView, idx: int, local: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.pressed = pressed
	ev.position = gv.to_global(local)
	return ev

func _fdrag(gv: GridView, idx: int, local: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = gv.to_global(local)
	return ev

func test_pinch_out_zooms_in_and_keeps_midpoint_fixed() -> void:
	var gv: GridView = _make_view()
	var fit: float = gv.projection.tile_px
	var mid := Vector2(320.0, 260.0)
	var ground: Vector2 = gv.projection.screen_to_ground(mid)
	gv._unhandled_input(_finger(gv, 0, mid + Vector2(-50, 0), true))
	gv._unhandled_input(_finger(gv, 1, mid + Vector2(50, 0), true))
	gv._unhandled_input(_fdrag(gv, 1, mid + Vector2(100, 0)))
	assert_gt(gv.projection.tile_px, fit)
	assert_almost_eq(gv.projection.ground_to_screen(ground).x, mid.x + 25.0, 0.5)

func test_pinch_zoom_is_clamped() -> void:
	var gv: GridView = _make_view()
	var fit: float = gv.projection.tile_px
	gv._unhandled_input(_finger(gv, 0, Vector2(300, 260), true))
	gv._unhandled_input(_finger(gv, 1, Vector2(340, 260), true))
	gv._unhandled_input(_fdrag(gv, 1, Vector2(2000, 260)))
	assert_almost_eq(gv.projection.tile_px, fit * GridView.MAX_ZOOM, 0.001)
	gv._unhandled_input(_fdrag(gv, 1, Vector2(301, 260)))
	assert_almost_eq(gv.projection.tile_px, fit, 0.001)

func test_second_finger_cancels_press_without_release() -> void:
	var gv: GridView = _make_view()
	var released: Array[Vector2i] = []
	var cancelled: Array[bool] = []
	gv.cell_released.connect(func(c: Vector2i) -> void: released.append(c))
	gv.press_cancelled.connect(func() -> void: cancelled.append(true))
	var p: Vector2 = gv.cell_to_local_center(Vector2i(5, 5))
	gv._unhandled_input(_finger(gv, 0, p, true))
	gv._unhandled_input(_finger(gv, 1, p + Vector2(60, 0), true))
	gv._unhandled_input(_finger(gv, 1, p + Vector2(60, 0), false))
	gv._unhandled_input(_finger(gv, 0, p, false))
	assert_eq(cancelled.size(), 1)
	assert_eq(released.size(), 0)

func test_hit_testing_follows_zoom() -> void:
	var gv: GridView = _make_view()
	gv.apply_zoom(gv.projection.tile_px * 2.0, Vector2(320, 260), Vector2(320, 260))
	for c: Vector2i in [Vector2i(5, 5), Vector2i(20, 20)]:
		assert_eq(gv.local_to_cell(gv.cell_to_local_center(c)), c)
