class_name BuildController
extends Node

signal tool_changed(tool: String)
signal place_failed(reason: int)
signal sold(type_id: String, refund: Dictionary, cell: Vector2i)

var tool: String = ""
var session: Session = null
var grid_view: GridView = null

var _sell_press_id: int = 0

func setup(p_session: Session, p_grid_view: GridView) -> void:
	if grid_view != null:
		if grid_view.cell_pressed.is_connected(_on_cell_pressed):
			grid_view.cell_pressed.disconnect(_on_cell_pressed)
		if grid_view.cell_dragged.is_connected(_on_cell_dragged):
			grid_view.cell_dragged.disconnect(_on_cell_dragged)
		if grid_view.cell_released.is_connected(_on_cell_released):
			grid_view.cell_released.disconnect(_on_cell_released)

	session = p_session
	grid_view = p_grid_view

	if grid_view != null:
		grid_view.cell_pressed.connect(_on_cell_pressed)
		grid_view.cell_dragged.connect(_on_cell_dragged)
		grid_view.cell_released.connect(_on_cell_released)

func select_tool(t: String) -> void:
	if tool == t:
		tool = ""
	else:
		tool = t
	_sell_press_id = 0
	if grid_view != null:
		grid_view.clear_ghost()
	tool_changed.emit(tool)

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

func _on_cell_pressed(cell: Vector2i) -> void:
	if session == null or session.grid == null:
		return
	if tool.is_empty():
		return

	if _is_tower_tool(tool):
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if grid_view != null:
			grid_view.set_ghost(tool, cell, err == GridModel.PlaceError.OK)
	elif _is_wall_tool(tool):
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if err == GridModel.PlaceError.OK:
			var pid: int = session.grid.place(tool, cell, session.wallet)
			if pid > 0 and SessionLogger != null and SessionLogger.has_method("log_event"):
				var atp_after: int = session.wallet.get_amount("atp") if session.wallet != null else 0
				SessionLogger.log_event("structure_placed", {"type": tool, "cell": cell, "atp_after": atp_after})
		else:
			place_failed.emit(int(err))
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

	if _is_tower_tool(tool):
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if grid_view != null:
			grid_view.set_ghost(tool, cell, err == GridModel.PlaceError.OK)
	elif _is_wall_tool(tool):
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if err == GridModel.PlaceError.OK:
			var pid: int = session.grid.place(tool, cell, session.wallet)
			if pid > 0 and SessionLogger != null and SessionLogger.has_method("log_event"):
				var atp_after: int = session.wallet.get_amount("atp") if session.wallet != null else 0
				SessionLogger.log_event("structure_placed", {"type": tool, "cell": cell, "atp_after": atp_after})

func _on_cell_released(cell: Vector2i) -> void:
	if session == null or session.grid == null:
		return
	if tool.is_empty():
		return

	if _is_tower_tool(tool):
		if grid_view != null:
			grid_view.clear_ghost()
		var err: GridModel.PlaceError = session.grid.check_place(tool, cell, session.wallet)
		if err == GridModel.PlaceError.OK:
			var pid: int = session.grid.place(tool, cell, session.wallet)
			if pid > 0 and SessionLogger != null and SessionLogger.has_method("log_event"):
				var atp_after: int = session.wallet.get_amount("atp") if session.wallet != null else 0
				SessionLogger.log_event("structure_placed", {"type": tool, "cell": cell, "atp_after": atp_after})
		else:
			place_failed.emit(int(err))
	elif _is_wall_tool(tool):
		pass
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
