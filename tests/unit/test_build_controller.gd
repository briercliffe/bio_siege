extends GutTest

func _load_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	return res.config

func _create_session() -> Session:
	var cfg: GameConfig = _load_config()
	return Session.new(cfg)

func test_select_same_tool_twice_deselects() -> void:
	var session: Session = _create_session()
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	var emitted_tools: Array[String] = []
	bc.tool_changed.connect(func(t: String) -> void: emitted_tools.append(t))

	assert_eq(bc.tool, "")
	bc.select_tool("mucous_wall")
	assert_eq(bc.tool, "mucous_wall")
	assert_eq(emitted_tools, ["mucous_wall"])

	bc.select_tool("mucous_wall")
	assert_eq(bc.tool, "")
	assert_eq(emitted_tools, ["mucous_wall", ""])

	bc.select_tool("macrophage")
	assert_eq(bc.tool, "macrophage")
	assert_eq(emitted_tools, ["mucous_wall", "", "macrophage"])

func test_wall_drag_places_walls_and_spends_atp() -> void:
	var session: Session = _create_session()
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	bc.select_tool("mucous_wall")
	var initial_atp: int = session.wallet.get_amount("atp")

	# Drag (2,2) -> (3,2) -> (4,2)
	grid_view.cell_pressed.emit(Vector2i(2, 2))
	grid_view.cell_dragged.emit(Vector2i(3, 2))
	grid_view.cell_dragged.emit(Vector2i(4, 2))
	grid_view.cell_released.emit(Vector2i(4, 2))

	assert_eq(session.grid.tile_state(Vector2i(2, 2)), GridModel.TileState.WALL)
	assert_eq(session.grid.tile_state(Vector2i(3, 2)), GridModel.TileState.WALL)
	assert_eq(session.grid.tile_state(Vector2i(4, 2)), GridModel.TileState.WALL)

	var spent_atp: int = initial_atp - session.wallet.get_amount("atp")
	assert_eq(spent_atp, 15, "Wall drag across 3 tiles should spend 15 ATP")
	assert_eq(bc.tool, "mucous_wall", "Tool remains selected after action")

func test_wall_drag_reentering_cell_does_not_double_place() -> void:
	var session: Session = _create_session()
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	bc.select_tool("mucous_wall")
	var initial_atp: int = session.wallet.get_amount("atp")

	# Press (2,2), drag to (3,2), then drag back to (2,2)
	grid_view.cell_pressed.emit(Vector2i(2, 2))
	grid_view.cell_dragged.emit(Vector2i(3, 2))
	grid_view.cell_dragged.emit(Vector2i(2, 2))
	grid_view.cell_released.emit(Vector2i(2, 2))

	var spent_atp: int = initial_atp - session.wallet.get_amount("atp")
	assert_eq(spent_atp, 10, "Re-entering (2,2) should not place a second wall or deduct extra ATP")

func test_tower_press_and_drag_places_at_release_only() -> void:
	var session: Session = _create_session()
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	bc.select_tool("macrophage")
	var initial_atp: int = session.wallet.get_amount("atp")

	# Press at (2,2)
	grid_view.cell_pressed.emit(Vector2i(2, 2))
	assert_true(grid_view._has_ghost)
	assert_eq(grid_view._ghost_origin, Vector2i(2, 2))
	assert_true(grid_view._ghost_valid)
	assert_eq(session.grid.tile_state(Vector2i(2, 2)), GridModel.TileState.EMPTY)
	assert_eq(session.wallet.get_amount("atp"), initial_atp)

	# Drag to (5,5)
	grid_view.cell_dragged.emit(Vector2i(5, 5))
	assert_true(grid_view._has_ghost)
	assert_eq(grid_view._ghost_origin, Vector2i(5, 5))
	assert_true(grid_view._ghost_valid)
	assert_eq(session.grid.tile_state(Vector2i(5, 5)), GridModel.TileState.EMPTY)
	assert_eq(session.wallet.get_amount("atp"), initial_atp)

	# Release at (5,5)
	grid_view.cell_released.emit(Vector2i(5, 5))
	assert_false(grid_view._has_ghost)
	assert_eq(session.grid.tile_state(Vector2i(5, 5)), GridModel.TileState.TOWER)
	assert_eq(session.grid.tile_state(Vector2i(2, 2)), GridModel.TileState.EMPTY)
	assert_eq(session.wallet.get_amount("atp"), initial_atp - 100)

func test_sell_press_structure_a_release_structure_b_does_nothing() -> void:
	var session: Session = _create_session()
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	var id_a: int = session.grid.place("mucous_wall", Vector2i(2, 2), session.wallet)
	var id_b: int = session.grid.place("macrophage", Vector2i(4, 4), session.wallet)
	assert_gt(id_a, 0)
	assert_gt(id_b, 0)

	var atp_before_sell_attempt: int = session.wallet.get_amount("atp")

	bc.select_tool("sell")
	var sold_events: Array = []
	bc.sold.connect(func(type_id: String, refund: Dictionary, cell: Vector2i) -> void:
		sold_events.append({"type": type_id, "refund": refund, "cell": cell})
	)

	# Press on structure A (2,2) then release on structure B (4,4)
	grid_view.cell_pressed.emit(Vector2i(2, 2))
	grid_view.cell_released.emit(Vector2i(4, 4))

	assert_eq(sold_events.size(), 0, "No sold signal should be emitted")
	assert_not_null(session.grid.get_structure(id_a), "Structure A should not be removed")
	assert_not_null(session.grid.get_structure(id_b), "Structure B should not be removed")
	assert_eq(session.wallet.get_amount("atp"), atp_before_sell_attempt)

	# Now press on A and release on A
	grid_view.cell_pressed.emit(Vector2i(2, 2))
	grid_view.cell_released.emit(Vector2i(2, 2))

	assert_eq(sold_events.size(), 1)
	assert_eq(sold_events[0]["type"], "mucous_wall")
	assert_eq(sold_events[0]["refund"], {"atp": 5})
	assert_eq(sold_events[0]["cell"], Vector2i(2, 2))
	assert_null(session.grid.get_structure(id_a))
	assert_eq(session.wallet.get_amount("atp"), atp_before_sell_attempt + 5)

func test_cannot_sell_nucleus() -> void:
	var session: Session = _create_session()
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	bc.select_tool("sell")
	var sold_events: Array = []
	bc.sold.connect(func(type_id: String, refund: Dictionary, cell: Vector2i) -> void:
		sold_events.append(type_id)
	)

	# Nucleus is at (18,18)
	grid_view.cell_pressed.emit(Vector2i(18, 18))
	grid_view.cell_released.emit(Vector2i(18, 18))

	assert_eq(sold_events.size(), 0)
	assert_not_null(session.grid.get_structure(1))
	assert_eq(session.grid.get_structure(1).type_id, "nucleus")

func test_toast_messages_and_failure_handling() -> void:
	var session: Session = _create_session()
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	var toast: Toast = Toast.new()
	add_child_autofree(toast)
	bc.place_failed.connect(func(reason: int) -> void:
		var msg: String = Toast.message_for_place_error(reason)
		toast.show_message(msg)
	)

	bc.select_tool("macrophage")
	var failed_signals: Array[int] = []
	bc.place_failed.connect(func(reason: int) -> void: failed_signals.append(reason))

	# 1. OUT_OF_BOUNDS -> "Outside the map"
	assert_eq(Toast.message_for_place_error(GridModel.PlaceError.OUT_OF_BOUNDS), "Outside the map")

	# 2. DEPLOY_ZONE -> "The outer ring is reserved for pathogen deployment"
	assert_eq(Toast.message_for_place_error(GridModel.PlaceError.DEPLOY_ZONE), "The outer ring is reserved for pathogen deployment")
	grid_view.cell_pressed.emit(Vector2i(0, 5))
	grid_view.cell_released.emit(Vector2i(0, 5))
	assert_eq(failed_signals.back(), int(GridModel.PlaceError.DEPLOY_ZONE))
	assert_eq(toast.last_message, "The outer ring is reserved for pathogen deployment")

	# 3. OCCUPIED -> "That tile is taken"
	assert_eq(Toast.message_for_place_error(GridModel.PlaceError.OCCUPIED), "That tile is taken")
	grid_view.cell_pressed.emit(Vector2i(18, 18)) # Nucleus tile
	grid_view.cell_released.emit(Vector2i(18, 18))
	assert_eq(failed_signals.back(), int(GridModel.PlaceError.OCCUPIED))
	assert_eq(toast.last_message, "That tile is taken")

	# 4. INSUFFICIENT_FUNDS -> "Not enough ATP"
	assert_eq(Toast.message_for_place_error(GridModel.PlaceError.INSUFFICIENT_FUNDS), "Not enough ATP")
	session.wallet.spend({"atp": session.wallet.get_amount("atp")}) # drain ATP
	grid_view.cell_pressed.emit(Vector2i(2, 2))
	grid_view.cell_released.emit(Vector2i(2, 2))
	assert_eq(failed_signals.back(), int(GridModel.PlaceError.INSUFFICIENT_FUNDS))
	assert_eq(toast.last_message, "Not enough ATP")

	# Floating text
	toast.show_floating_text("+10 ATP", Vector2(100, 100))
	assert_eq(toast.last_floating_text, "+10 ATP")

func test_grid_view_fit_to_rect_and_center() -> void:
	var session: Session = _create_session()
	var gv: GridView = GridView.new()
	add_child_autofree(gv)
	gv.setup(session.grid, session.config)

	var container_rect := Rect2(100.0, 50.0, 1280.0, 720.0)
	gv.fit_to_rect(container_rect)

	# 40 * 14 = 560
	assert_almost_eq(gv.scale.x, 720.0 / 560.0, 0.001)
	assert_almost_eq(gv.scale.y, 720.0 / 560.0, 0.001)

	assert_eq(gv.cell_to_local_center(Vector2i(0, 0)), Vector2(7.0, 7.0))
	assert_eq(gv.cell_to_local_center(Vector2i(1, 2)), Vector2(21.0, 35.0))

func test_placeholder_shapes_guards() -> void:
	# Safe no-op on null canvas item or invalid rects
	PlaceholderShapes.draw_shape(null, "square", Rect2(0, 0, 10, 10), Color.RED)
	var node := Node2D.new()
	add_child_autofree(node)
	PlaceholderShapes.draw_shape(node, "square", Rect2(0, 0, 0, 0), Color.RED)
	PlaceholderShapes.draw_shape(node, "square", Rect2(0, 0, -5, -5), Color.RED)
	pass_test("PlaceholderShapes safely handled null CanvasItem and invalid rects without errors")

func test_grid_view_input_touch_events() -> void:
	var session: Session = _create_session()
	var gv: GridView = GridView.new()
	add_child_autofree(gv)
	gv.setup(session.grid, session.config)

	var pressed_cells: Array[Vector2i] = []
	var dragged_cells: Array[Vector2i] = []
	var released_cells: Array[Vector2i] = []
	gv.cell_pressed.connect(func(c: Vector2i) -> void: pressed_cells.append(c))
	gv.cell_dragged.connect(func(c: Vector2i) -> void: dragged_cells.append(c))
	gv.cell_released.connect(func(c: Vector2i) -> void: released_cells.append(c))

	# 1. Touch press at cell (3, 4) -> 3 * 14 + 5 = 106, 4 * 14 + 5 = 138
	var touch_press := InputEventScreenTouch.new()
	touch_press.index = 0
	touch_press.pressed = true
	touch_press.position = Vector2(47, 61)
	gv._unhandled_input(touch_press)
	assert_eq(pressed_cells, [Vector2i(3, 4)])

	# Touch with index 1 should be ignored
	var touch_idx1 := InputEventScreenTouch.new()
	touch_idx1.index = 1
	touch_idx1.pressed = true
	touch_idx1.position = Vector2(47, 61)
	gv._unhandled_input(touch_idx1)
	assert_eq(pressed_cells.size(), 1)

	# 2. Drag to (4, 4)
	var touch_drag := InputEventScreenDrag.new()
	touch_drag.index = 0
	touch_drag.position = Vector2(4 * 14 + 5, 4 * 14 + 5)
	gv._unhandled_input(touch_drag)
	assert_eq(dragged_cells, [Vector2i(4, 4)])

	# Drag within same cell shouldn't fire signal again
	var touch_drag_same := InputEventScreenDrag.new()
	touch_drag_same.index = 0
	touch_drag_same.position = Vector2(4 * 14 + 10, 4 * 14 + 10)
	gv._unhandled_input(touch_drag_same)
	assert_eq(dragged_cells.size(), 1)

	# 3. Release at (4, 4)
	var touch_release := InputEventScreenTouch.new()
	touch_release.index = 0
	touch_release.pressed = false
	touch_release.position = Vector2(4 * 14 + 5, 4 * 14 + 5)
	gv._unhandled_input(touch_release)
	assert_eq(released_cells, [Vector2i(4, 4)])

func test_grid_view_input_mouse_events() -> void:
	var session: Session = _create_session()
	var gv: GridView = GridView.new()
	add_child_autofree(gv)
	gv.setup(session.grid, session.config)

	var pressed_cells: Array[Vector2i] = []
	var dragged_cells: Array[Vector2i] = []
	var released_cells: Array[Vector2i] = []
	gv.cell_pressed.connect(func(c: Vector2i) -> void: pressed_cells.append(c))
	gv.cell_dragged.connect(func(c: Vector2i) -> void: dragged_cells.append(c))
	gv.cell_released.connect(func(c: Vector2i) -> void: released_cells.append(c))

	# Mouse click at cell (2, 2) -> 2 * 14 + 5 = 74
	var mb_press := InputEventMouseButton.new()
	mb_press.button_index = MOUSE_BUTTON_LEFT
	mb_press.pressed = true
	mb_press.position = Vector2(33, 33)
	gv._unhandled_input(mb_press)
	assert_eq(pressed_cells, [Vector2i(2, 2)])

	# Motion to cell (3, 2)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.position = Vector2(3 * 14 + 5, 33)
	gv._unhandled_input(mm)
	assert_eq(dragged_cells, [Vector2i(3, 2)])

	# Mouse release
	var mb_release := InputEventMouseButton.new()
	mb_release.button_index = MOUSE_BUTTON_LEFT
	mb_release.pressed = false
	mb_release.position = Vector2(3 * 14 + 5, 33)
	gv._unhandled_input(mb_release)
	assert_eq(released_cells, [Vector2i(3, 2)])

func test_grid_view_ignores_out_of_bounds_input() -> void:
	var session: Session = _create_session()
	var gv: GridView = GridView.new()
	add_child_autofree(gv)
	gv.setup(session.grid, session.config)

	var pressed_cells: Array[Vector2i] = []
	gv.cell_pressed.connect(func(c: Vector2i) -> void: pressed_cells.append(c))

	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(-50, -50) # Negative / out of bounds
	gv._unhandled_input(touch)
	assert_eq(pressed_cells.size(), 0)

func test_grid_view_deploy_mode_property() -> void:
	var gv := GridView.new()
	add_child_autofree(gv)
	assert_false(gv.deploy_mode)
	gv.deploy_mode = true
	assert_true(gv.deploy_mode)


func test_debug_keyboard_shortcuts() -> void:
	if not OS.is_debug_build():
		return
	var session: Session = _create_session()
	var gv: GridView = GridView.new()
	add_child_autofree(gv)
	gv.setup(session.grid, session.config)

	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, gv)

	var ev1 := InputEventKey.new()
	ev1.pressed = true
	ev1.keycode = KEY_1
	bc._unhandled_input(ev1)
	assert_eq(bc.tool, "mucous_wall")

	var ev2 := InputEventKey.new()
	ev2.pressed = true
	ev2.keycode = KEY_2
	bc._unhandled_input(ev2)
	assert_eq(bc.tool, "macrophage")

	var ev3 := InputEventKey.new()
	ev3.pressed = true
	ev3.keycode = KEY_3
	bc._unhandled_input(ev3)
	assert_eq(bc.tool, "b_cell")

	var ev4 := InputEventKey.new()
	ev4.pressed = true
	ev4.keycode = KEY_4
	bc._unhandled_input(ev4)
	assert_eq(bc.tool, "sell")

func test_synthesis_phase_integration() -> void:
	var session: Session = _create_session()
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autofree(fsm)

	var phase_scene: PackedScene = load("res://src/game/phases/synthesis_phase.tscn")
	assert_not_null(phase_scene)
	var phase: SynthesisPhase = phase_scene.instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)

	assert_not_null(phase.grid_view)
	assert_not_null(phase.build_controller)
	assert_not_null(phase.toast)

	phase.build_controller.select_tool("macrophage")
	phase.grid_view.cell_pressed.emit(Vector2i(0, 0))
	phase.grid_view.cell_released.emit(Vector2i(0, 0))
	assert_eq(phase.toast.last_message, "The outer ring is reserved for pathogen deployment")
