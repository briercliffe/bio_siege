class_name GridView
extends Node2D

signal cell_pressed(cell: Vector2i)
signal cell_dragged(cell: Vector2i)
signal cell_released(cell: Vector2i)

enum Device { NONE, TOUCH, MOUSE }

var grid: GridModel = null
var config: GameConfig = null
var tile_px: int = 32
var deploy_mode: bool = false: set = set_deploy_mode
var draw_structures: bool = true: set = set_draw_structures
var army: Army = null: set = set_army
var predicted_structure_id: int = 0: set = set_predicted_structure_id

var _has_ghost: bool = false
var _ghost_type_id: String = ""
var _ghost_origin: Vector2i = Vector2i.ZERO
var _ghost_valid: bool = false

var _active_device: Device = Device.NONE
var _last_cell: Vector2i = Vector2i(-99999, -99999)

func set_draw_structures(val: bool) -> void:
	draw_structures = val
	queue_redraw()

func set_deploy_mode(val: bool) -> void:
	if deploy_mode != val:
		deploy_mode = val
		queue_redraw()

func set_predicted_structure_id(val: int) -> void:
	if predicted_structure_id != val:
		predicted_structure_id = val
		queue_redraw()

func set_army(val: Army) -> void:
	if army == val:
		return
	if army != null and army.changed.is_connected(_on_army_changed):
		army.changed.disconnect(_on_army_changed)
	army = val
	if army != null:
		army.changed.connect(_on_army_changed)
	queue_redraw()

func _on_army_changed() -> void:
	queue_redraw()

func _exit_tree() -> void:
	if army != null and army.changed.is_connected(_on_army_changed):
		army.changed.disconnect(_on_army_changed)

func _process(_delta: float) -> void:
	if deploy_mode:
		queue_redraw()

func setup(p_grid: GridModel, p_config: GameConfig, p_army: Army = null) -> void:
	if grid != null:
		if grid.structure_placed.is_connected(_on_structure_changed):
			grid.structure_placed.disconnect(_on_structure_changed)
		if grid.structure_removed.is_connected(_on_structure_changed):
			grid.structure_removed.disconnect(_on_structure_changed)

	grid = p_grid
	config = p_config
	if p_army != null:
		set_army(p_army)
	if config != null and config.tile_px > 0:
		tile_px = config.tile_px

	if grid != null:
		grid.structure_placed.connect(_on_structure_changed)
		grid.structure_removed.connect(_on_structure_changed)

	queue_redraw()

func _on_structure_changed(_s: GridModel.PlacedStructure) -> void:
	queue_redraw()

func fit_to_rect(r: Rect2) -> void:
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return
	var gw_px: float = float(grid.width * tile_px)
	var gh_px: float = float(grid.height * tile_px)
	if gw_px <= 0.0 or gh_px <= 0.0:
		return
	var s: float = minf(r.size.x / gw_px, r.size.y / gh_px)
	scale = Vector2(s, s)
	var scaled_size: Vector2 = Vector2(gw_px, gh_px) * s
	position = r.position + (r.size - scaled_size) * 0.5

func set_ghost(type_id: String, origin: Vector2i, valid: bool) -> void:
	_has_ghost = true
	_ghost_type_id = type_id
	_ghost_origin = origin
	_ghost_valid = valid
	queue_redraw()

func clear_ghost() -> void:
	if _has_ghost:
		_has_ghost = false
		_ghost_type_id = ""
		queue_redraw()

func cell_to_local_center(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * float(tile_px)

func local_to_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(local_pos.x / float(tile_px))), int(floor(local_pos.y / float(tile_px))))

func _unhandled_input(event: InputEvent) -> void:
	if grid == null:
		return

	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		if event.pressed:
			if _active_device != Device.NONE:
				return
			_active_device = Device.TOUCH
			_handle_press(event.position)
		else:
			if _active_device != Device.TOUCH:
				return
			_active_device = Device.NONE
			_handle_release(event.position)
	elif event is InputEventScreenDrag:
		if event.index != 0 or _active_device != Device.TOUCH:
			return
		_handle_drag(event.position)
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			if _active_device != Device.NONE:
				return
			_active_device = Device.MOUSE
			_handle_press(event.position)
		else:
			if _active_device != Device.MOUSE:
				return
			_active_device = Device.NONE
			_handle_release(event.position)
	elif event is InputEventMouseMotion:
		if _active_device != Device.MOUSE:
			return
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_drag(event.position)

func _handle_press(screen_pos: Vector2) -> void:
	var cell: Vector2i = local_to_cell(to_local(screen_pos))
	if grid == null or not grid.in_bounds(cell):
		_last_cell = Vector2i(-99999, -99999)
		return
	_last_cell = cell
	cell_pressed.emit(cell)

func _handle_drag(screen_pos: Vector2) -> void:
	var cell: Vector2i = local_to_cell(to_local(screen_pos))
	if grid == null or not grid.in_bounds(cell):
		return
	if cell != _last_cell:
		_last_cell = cell
		cell_dragged.emit(cell)

func _handle_release(screen_pos: Vector2) -> void:
	var cell: Vector2i = local_to_cell(to_local(screen_pos))
	_last_cell = Vector2i(-99999, -99999)
	if grid == null or not grid.in_bounds(cell):
		return
	cell_released.emit(cell)

func _draw() -> void:
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return

	# Ring color in deploy mode: pulses green fill #2ecc71 with alpha 0.25 to 0.45 on 1.2s cycle
	var ring_color := Color("#2ecc71")
	if deploy_mode:
		var pulse_time: float = fmod(float(Time.get_ticks_msec()) / 1000.0, 1.2)
		var pulse_norm: float = 0.5 + 0.5 * sin((pulse_time / 1.2) * TAU)
		ring_color.a = lerpf(0.25, 0.45, pulse_norm)

	# Draw cells (interior and deploy ring)
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var cell_rect := Rect2(float(x * tile_px), float(y * tile_px), float(tile_px), float(tile_px))
			if grid.is_deploy_zone(cell):
				if deploy_mode:
					draw_rect(cell_rect, ring_color, true)
				else:
					draw_rect(cell_rect, Color("#d9dee4"), true)
					_draw_deploy_cell_hatch(cell_rect)
			else:
				draw_rect(cell_rect, Color("#f4f8fc"), true)

	# Grid lines: 1 px, #c3ccd6
	var grid_line_color := Color("#c3ccd6")
	var total_w: float = float(grid.width * tile_px)
	var total_h: float = float(grid.height * tile_px)
	for x in range(grid.width + 1):
		var px: float = float(x * tile_px)
		draw_line(Vector2(px, 0.0), Vector2(px, total_h), grid_line_color, 1.0)
	for y in range(grid.height + 1):
		var py: float = float(y * tile_px)
		draw_line(Vector2(0.0, py), Vector2(total_w, py), grid_line_color, 1.0)

	# Structures from grid.structures()
	if draw_structures:
		for s: GridModel.PlacedStructure in grid.structures():
			var sdef: StructureDef = config.structures.get(s.type_id) if config != null else null
			var shape: String = sdef.placeholder_shape if sdef != null else "square"
			var color: Color = sdef.placeholder_color if sdef != null else Color.WHITE
			var s_rect := Rect2(Vector2(s.origin) * float(tile_px), Vector2(s.footprint) * float(tile_px))
			PlaceholderShapes.draw_shape(self, shape, s_rect, color)

	# Placement ghost
	if _has_ghost and not _ghost_type_id.is_empty():
		var sdef: StructureDef = config.structures.get(_ghost_type_id) if config != null else null
		var footprint: Vector2i = sdef.footprint if sdef != null else Vector2i.ONE
		var g_rect := Rect2(Vector2(_ghost_origin) * float(tile_px), Vector2(footprint) * float(tile_px))

		var tint: Color = Color("#2ecc71") if _ghost_valid else Color("#e74c3c")
		tint.a = 0.35
		draw_rect(g_rect, tint, true)

		var shape: String = sdef.placeholder_shape if sdef != null else "square"
		var g_color: Color = sdef.placeholder_color if sdef != null else Color.WHITE
		g_color.a = 0.5
		PlaceholderShapes.draw_shape(self, shape, g_rect, g_color)

	# Unit markers in deploy mode
	if army != null and deploy_mode:
		for cell: Vector2i in grid.ring_cells():
			var deployed: Array[String] = army.deployed_at(cell)
			if deployed.is_empty():
				continue
			var count: int = deployed.size()
			var last_type: String = deployed[-1]
			var pdef: PathogenDef = config.pathogens.get(last_type) if config != null else null
			var shape: String = pdef.placeholder_shape if pdef != null else "circle"
			var color: Color = pdef.placeholder_color if pdef != null else Color.WHITE

			var tile_size := float(tile_px)
			var marker_size: float = tile_size * 0.60
			var offset: float = (tile_size - marker_size) * 0.5
			var marker_rect := Rect2(
				float(cell.x * tile_px) + offset,
				float(cell.y * tile_px) + offset,
				marker_size,
				marker_size
			)
			PlaceholderShapes.draw_shape(self, shape, marker_rect, color)

			if count > 1:
				var badge_radius: float = maxf(tile_size * 0.22, 6.0)
				var badge_center := Vector2(
					float((cell.x + 1) * tile_px) - badge_radius - 1.0,
					float(cell.y * tile_px) + badge_radius + 1.0
				)
				draw_circle(badge_center, badge_radius, Color.WHITE)
				draw_arc(badge_center, badge_radius, 0.0, TAU, 16, Color(0.2, 0.2, 0.2, 0.6), 1.0, true)

				var font: Font = ThemeDB.fallback_font
				if font != null:
					var font_size: int = max(int(badge_radius * 1.5), 9)
					var count_text: String = str(count)
					var str_size: Vector2 = font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
					var text_pos := Vector2(
						badge_center.x - str_size.x * 0.5,
						badge_center.y + str_size.y * 0.35
					)
					draw_string(font, text_pos, count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

	# Predicted structure marker
	if predicted_structure_id > 0 and grid != null:
		var s: GridModel.PlacedStructure = grid.get_structure(predicted_structure_id)
		if s != null:
			var s_center: Vector2 = (Vector2(s.origin) + Vector2(s.footprint) * 0.5) * float(tile_px)
			var badge_radius: float = float(tile_px) * 0.35
			draw_circle(s_center, badge_radius, Color("#f1c40f"))
			draw_arc(s_center, badge_radius, 0.0, TAU, 16, Color(0.1, 0.1, 0.1, 0.8), 1.5, true)
			var font: Font = ThemeDB.fallback_font
			if font != null:
				var font_size: int = max(int(badge_radius * 1.4), 10)
				var q_text: String = "?"
				var str_size: Vector2 = font.get_string_size(q_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
				var text_pos := Vector2(
					s_center.x - str_size.x * 0.5,
					s_center.y + str_size.y * 0.35
				)
				draw_string(font, text_pos, q_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

func _draw_deploy_cell_hatch(cell_rect: Rect2) -> void:
	var hatch_color := Color("#b0b8c0")
	var step: float = 6.0
	var w: float = cell_rect.size.x
	var h: float = cell_rect.size.y
	var d: float = step
	while d < w + h:
		var p1: Vector2
		var p2: Vector2
		if d <= w:
			p1 = Vector2(d, 0.0)
		else:
			p1 = Vector2(w, d - w)
		if d <= h:
			p2 = Vector2(0.0, d)
		else:
			p2 = Vector2(d - h, h)
		draw_line(cell_rect.position + p1, cell_rect.position + p2, hatch_color, 1.0)
		d += step
