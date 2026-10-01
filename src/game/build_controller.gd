class_name BuildController
extends Node

signal tool_changed(tool: String)
signal place_failed(reason: int)
signal placed(type_id: String, cell: Vector2i)
signal sold(type_id: String, refund: Dictionary, cell: Vector2i)
signal nucleus_moved(from: Vector2i, to: Vector2i)

const TOOL_MOVE_NUCLEUS: String = "move_nucleus"

var tool: String = ""
var session: Session = null
var grid_view: GridView = null

var _sell_press_id: int = 0
var _move_id: int = 0
var _move_grab_offset: Vector2i = Vector2i.ZERO
var _wall_anchor: Vector2i = Vector2i.ZERO
var _wall_dragging: bool = false

func setup(p_session: Session, p_grid_view: GridView) -> void:
	if grid_view != null:
		if grid_view.cell_pressed.is_connected(_on_cell_pressed):
			grid_view.cell_pressed.disconnect(_on_cell_pressed)
		if grid_view.cell_dragged.is_connected(_on_cell_dragged):
			grid_view.cell_dragged.disconnect(_on_cell_dragged)
		if grid_view.cell_released.is_connected(_on_cell_released):
			grid_view.cell_released.disconnect(_on_cell_released)
		if grid_view.touch_cancelled.is_connected(_on_touch_cancelled):
			grid_view.touch_cancelled.disconnect(_on_touch_cancelled)

	session = p_session
	grid_view = p_grid_view

	if grid_view != null:
		grid_view.cell_pressed.connect(_on_cell_pressed)
		grid_view.cell_dragged.connect(_on_cell_dragged)
		grid_view.cell_released.connect(_on_cell_released)
		grid_view.touch_cancelled.connect(_on_touch_cancelled)

func select_tool(t: String) -> void:
	if t == TOOL_MOVE_NUCLEUS and tool != t and not _move_tool_allowed():
		return
	if tool == t:
		tool = ""
	else:
		tool = t
	_sell_press_id = 0
	_move_id = 0
	_wall_dragging = false
	if grid_view != null:
		grid_view.clear_ghost()
	tool_changed.emit(tool)

func _move_tool_allowed() -> bool:
	return session != null and session.config != null and session.config.move_nucleus_enabled()

func _is_wall_tool(tool_id: String) -> bool:
	if session == null or session.config == null:
		return false
	var sdef: StructureDef = session.config.structures.get(tool_id)
	return sdef != null and sdef.has_tag("wall")

func _is_tower_tool(tool_id: String) -> bool:
	if session == null or session.config == null:
		return false
	var sdef: StructureDef = session.config.structures.get(tool_id)
	return sdef != null and sdef.buildable and not sdef.has_tag("wall")

func _place_current_tool(cell: Vector2i) -> void:
	var pid: int = session.grid.place(tool, cell, session.wallet)
	if pid <= 0:
		return
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		var atp_after: int = session.wallet.get_amount("atp") if session.wallet != null else 0
		SessionLogger.log_event("structure_placed", {"type": tool, "cell": cell, "atp_after": atp_after})
	placed.emit(tool, cell)

## The cells of the straight run from `start` to `end`, along whichever axis the finger has moved furthest.
static func wall_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var delta: Vector2i = end - start
	var horizontal: bool = absi(delta.x) >= absi(delta.y)
	var step: Vector2i = Vector2i(signi(delta.x), 0) if horizontal else Vector2i(0, signi(delta.y))
	var count: int = (absi(delta.x) if horizontal else absi(delta.y)) + 1
	for i: int in range(count):
		cells.append(start + step * i)
	return cells

## Which cells of `cells` would be built: free, in bounds, and paid for by the wallet after the cells before.
func _plan_wall_line(cells: Array[Vector2i]) -> Array[bool]:
	var plan: Array[bool] = []
	var sdef: StructureDef = session.config.structures.get(tool)
	var built: int = 0
	for cell: Vector2i in cells:
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		# Funds are judged below, for the whole run, so a poor wallet only rejects the cells it cannot pay for.
		var free: bool = err == GridModel.PlaceError.OK or err == GridModel.PlaceError.INSUFFICIENT_FUNDS
		var scaled: Dictionary = {}
		for cur: Variant in sdef.cost.keys():
			scaled[cur] = int(sdef.cost[cur]) * (built + 1)
		var ok: bool = free and session.wallet.can_afford(scaled)
		if ok:
			built += 1
		plan.append(ok)
	return plan

func _preview_wall_line(end: Vector2i) -> void:
	if grid_view == null:
		return
	var cells: Array[Vector2i] = wall_line(_wall_anchor, end)
	grid_view.set_ghost_line(tool, cells, _plan_wall_line(cells))

func _commit_wall_line(end: Vector2i) -> void:
	_wall_dragging = false
	if grid_view != null:
		grid_view.clear_ghost()
	var cells: Array[Vector2i] = wall_line(_wall_anchor, end)
	var plan: Array[bool] = _plan_wall_line(cells)
	var any_placed: bool = false
	for i: int in range(cells.size()):
		if plan[i]:
			_place_current_tool(cells[i])
			any_placed = true
	if not any_placed:
		place_failed.emit(int(session.grid.check_place(tool, cells[0], session.wallet)))

func _begin_move(cell: Vector2i) -> void:
	_move_id = 0
	var sid: int = session.grid.structure_id_at(cell)
	var core: GridModel.PlacedStructure = session.grid.find_core()
	if core == null or core.id != sid:
		return
	_move_id = core.id
	_move_grab_offset = cell - core.origin
	_update_move_ghost(cell)

func _update_move_ghost(cell: Vector2i) -> void:
	var s: GridModel.PlacedStructure = session.grid.get_structure(_move_id)
	if s == null or grid_view == null:
		return
	var origin: Vector2i = cell - _move_grab_offset
	var err: GridModel.PlaceError = session.grid.check_move(_move_id, origin)
	grid_view.set_ghost(s.type_id, origin, err == GridModel.PlaceError.OK)

func _finish_move(cell: Vector2i) -> void:
	var move_id: int = _move_id
	_move_id = 0
	if move_id <= 0:
		return
	if grid_view != null:
		grid_view.clear_ghost()
	var s: GridModel.PlacedStructure = session.grid.get_structure(move_id)
	if s == null:
		return
	var from: Vector2i = s.origin
	var to: Vector2i = cell - _move_grab_offset
	var err: GridModel.PlaceError = session.grid.move_structure(move_id, to)
	if err != GridModel.PlaceError.OK:
		place_failed.emit(int(err))
		return
	if to != from:
		if SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("nucleus_moved", {"from": from, "to": to})
		nucleus_moved.emit(from, to)
	# select_tool toggles, so selecting the active move tool deselects it.
	select_tool(TOOL_MOVE_NUCLEUS)

func _on_cell_pressed(cell: Vector2i) -> void:
	if session == null or session.grid == null:
		return
	if tool.is_empty():
		return

	if tool == TOOL_MOVE_NUCLEUS:
		_begin_move(cell)
	elif _is_tower_tool(tool):
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if grid_view != null:
			grid_view.set_ghost(tool, cell, err == GridModel.PlaceError.OK)
	elif _is_wall_tool(tool):
		_wall_anchor = cell
		_wall_dragging = true
		_preview_wall_line(cell)
	elif tool == "sell":
		var sid: int = session.grid.structure_id_at(cell)
		if sid > 0:
			var s: GridModel.PlacedStructure = session.grid.get_structure(sid)
			if s != null:
				var sdef: StructureDef = session.config.structures.get(s.type_id) if session.config != null else null
				var is_core: bool = (sdef != null and sdef.has_tag("core")) or (s.type_id == "nucleus")
				if is_core:
					_sell_press_id = 0
				else:
					_sell_press_id = sid
			else:
				_sell_press_id = 0
		else:
			_sell_press_id = 0

func _on_cell_dragged(cell: Vector2i) -> void:
	if session == null or session.grid == null:
		return
	if tool.is_empty():
		return

	if tool == TOOL_MOVE_NUCLEUS:
		if _move_id > 0:
			_update_move_ghost(cell)
	elif _is_tower_tool(tool):
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if grid_view != null:
			grid_view.set_ghost(tool, cell, err == GridModel.PlaceError.OK)
	elif _is_wall_tool(tool):
		if _wall_dragging:
			_preview_wall_line(cell)

func _on_cell_released(cell: Vector2i) -> void:
	if session == null or session.grid == null:
		return
	if tool.is_empty():
		return

	if tool == TOOL_MOVE_NUCLEUS:
		_finish_move(cell)
	elif _is_tower_tool(tool):
		if grid_view != null:
			grid_view.clear_ghost()
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if err == GridModel.PlaceError.OK:
			_place_current_tool(cell)
		else:
			place_failed.emit(int(err))
	elif _is_wall_tool(tool):
		if _wall_dragging:
			_commit_wall_line(cell)
	elif tool == "sell":
		var sid: int = session.grid.structure_id_at(cell)
		if _sell_press_id > 0 and sid == _sell_press_id:
			var s: GridModel.PlacedStructure = session.grid.get_structure(_sell_press_id)
			if s != null:
				var type_id: String = s.type_id
				var sdef: StructureDef = session.config.structures.get(type_id) if session.config != null else null
				var refund: Dictionary = sdef.cost.duplicate(true) if sdef != null else {}
				var ok: bool = session.grid.sell(_sell_press_id, session.wallet)
				if ok:
					sold.emit(type_id, refund, cell)
					if SessionLogger != null and SessionLogger.has_method("log_event"):
						var atp_after: int = session.wallet.get_amount("atp") if session.wallet != null else 0
						SessionLogger.log_event("structure_sold", {"type": type_id, "cell": cell, "atp_after": atp_after})
		_sell_press_id = 0

## A touch ended off the grid: drop the wall line or tower ghost without building.
func _on_touch_cancelled() -> void:
	if tool.is_empty() or tool == TOOL_MOVE_NUCLEUS:
		return
	_wall_dragging = false
	if grid_view != null:
		grid_view.clear_ghost()

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_1, KEY_KP_1:
				select_tool("mucous_wall")
			KEY_2, KEY_KP_2:
				select_tool("macrophage")
			KEY_3, KEY_KP_3:
				select_tool("b_cell")
			KEY_4, KEY_KP_4:
				select_tool("sell")
