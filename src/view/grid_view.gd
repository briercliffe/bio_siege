class_name GridView
extends Node2D

## The isometric island for Synthesis, Incubation and Infection (docs/MVP_UI_SPEC.md section 3).
## Reads the flat integer grid and draws it through an IsoProjection. Never modifies core state.

signal cell_pressed(cell: Vector2i)
signal cell_dragged(cell: Vector2i)
signal cell_released(cell: Vector2i)

const CORNER_RADIUS_TILES: float = 3.2
const HEADROOM_T: float = 4.5
const SLAB_T: float = 1.6
const SLAB_LAYERS: int = 6
const ARC_STEPS: int = 8
const CIRCLE_POINTS: int = 24
const PULSE_PERIOD_S: float = 1.2
const PULSE_REDRAW_INTERVAL_S: float = 1.0 / 30.0
## The idle animation of the towers and the Nucleus redraws the island at this rate.
const ANIM_REDRAW_INTERVAL_S: float = 1.0 / 30.0
const DASH_PX: float = 8.0
const GAP_PX: float = 6.0
const DOT_RADIUS_TILES: float = 5.5
const BLOB_RINGS: int = 6
const BLOB_RING_ALPHA: float = 0.22
const DECOR_SEED: int = 11
const NO_CELL: Vector2i = Vector2i(-99999, -99999)

const MODEL_HEIGHT_T: Dictionary = {"nucleus": 4.1, "macrophage": 3.0, "b_cell": 4.3}
const DEFAULT_MODEL_HEIGHT_T: float = 3.0

# Day and night theme colours, from the canvas mockup (Field.dc.html).
const SHADOW_DAY: Color = Color("#7f9fbd")
const SHADOW_NIGHT: Color = Color("#2c0e15")
const SLAB_HI_DAY: Color = Color("#86a8c6")
const SLAB_LO_DAY: Color = Color("#93b3cf")
const SLAB_HI_NIGHT: Color = Color("#3a131c")
const SLAB_LO_NIGHT: Color = Color("#4a1a24")
const TOP_DAY: Color = Color("#d8e9f7")
const TOP_NIGHT: Color = Color("#34111a")
const BLOB_HI_DAY: Color = Color("#f0f8fd")
const BLOB_HI_NIGHT: Color = Color("#4d1c24")
const RIM_DAY: Color = Color("#a9c8e4")
const RIM_NIGHT: Color = Color("#6b2632")
const SOFT_A_DAY: Color = Color(140.0 / 255.0, 185.0 / 255.0, 225.0 / 255.0, 0.28)
const SOFT_A_NIGHT: Color = Color(0.0, 0.0, 0.0, 0.22)
const SOFT_B_DAY: Color = Color(1.0, 1.0, 1.0, 0.55)
const SOFT_B_NIGHT: Color = Color(130.0 / 255.0, 45.0 / 255.0, 60.0 / 255.0, 0.30)
const CELL_FILL_DAY: Color = Color(1.0, 1.0, 1.0, 0.38)
const CELL_FILL_NIGHT: Color = Color(0.0, 0.0, 0.0, 0.18)
const CELL_RIM_DAY: Color = Color(130.0 / 255.0, 175.0 / 255.0, 215.0 / 255.0, 0.55)
const CELL_RIM_NIGHT: Color = Color(1.0, 1.0, 1.0, 0.07)
const BAND_DAY: Color = Color(30.0 / 255.0, 90.0 / 255.0, 168.0 / 255.0, 0.09)
const BAND_LINE_DAY: Color = Color(30.0 / 255.0, 90.0 / 255.0, 168.0 / 255.0, 0.45)
const GREEN: Color = Color("#2ecc71")
const RED: Color = Color("#e74c3c")
const BAND_NIGHT_IDLE: Color = Color(46.0 / 255.0, 204.0 / 255.0, 113.0 / 255.0, 0.09)
const BAND_LINE_NIGHT_IDLE: Color = Color(46.0 / 255.0, 204.0 / 255.0, 113.0 / 255.0, 0.25)
const BAND_ACTIVE_ALPHA_LO: float = 0.24
const BAND_ACTIVE_ALPHA_HI: float = 0.36
const PLATE_DAY: Color = Color(30.0 / 255.0, 70.0 / 255.0, 120.0 / 255.0, 0.13)
const PLATE_NIGHT: Color = Color(0.0, 0.0, 0.0, 0.3)
const PLATE_RIM_DAY: Color = Color(1.0, 1.0, 1.0, 0.6)
const PLATE_RIM_NIGHT: Color = Color(1.0, 1.0, 1.0, 0.07)
const NUCLEUS_GLOW: Color = Color(195.0 / 255.0, 155.0 / 255.0, 211.0 / 255.0, 0.6)
const NUCLEUS_PLATE: Color = Color(74.0 / 255.0, 28.0 / 255.0, 102.0 / 255.0, 0.38)
const NUCLEUS_PLATE_RIM: Color = Color(236.0 / 255.0, 208.0 / 255.0, 248.0 / 255.0, 0.35)
const GHOST_OK_FILL: Color = Color(46.0 / 255.0, 204.0 / 255.0, 113.0 / 255.0, 0.3)
const GHOST_BAD_FILL: Color = Color(231.0 / 255.0, 76.0 / 255.0, 60.0 / 255.0, 0.3)
const GHOST_DOT: Color = Color(30.0 / 255.0, 90.0 / 255.0, 168.0 / 255.0, 0.65)
const RANGE_FILL: Color = Color(30.0 / 255.0, 90.0 / 255.0, 168.0 / 255.0, 0.07)
const RANGE_LINE: Color = Color(30.0 / 255.0, 90.0 / 255.0, 168.0 / 255.0, 0.55)

## A placed structure with its projected geometry cached. Towers and the core are painted by their
## ModelPainter with an idle pose; walls by the WallRenderer.
class StructureItem extends RefCounted:
	var id: int = 0
	var type_id: String = ""
	var kind: int = 0 # 0 tower, 1 wall, 2 core
	var depth: float = 0.0
	var foot: Vector2 = Vector2.ZERO
	var painter: ModelPainter = null
	var pose: ModelPose = null
	var plate: PackedVector2Array = PackedVector2Array()
	var plate_rim: PackedVector2Array = PackedVector2Array()
	var glow_rings: Array[PackedVector2Array] = []
	var cell: Vector2i = Vector2i.ZERO

## A deployed-unit marker with its screen position cached.
class UnitMarker extends RefCounted:
	var center: Vector2 = Vector2.ZERO
	var shape: String = "circle"
	var color: Color = Color.WHITE
	var count: int = 1

var grid: GridModel = null
var config: GameConfig = null
var tile_px: int = 32
var projection: IsoProjection = IsoProjection.new()
var night: bool = false
var deploy_mode: bool = false: set = set_deploy_mode
var draw_structures: bool = true: set = set_draw_structures
var army: Army = null: set = set_army
var predicted_structure_id: int = 0: set = set_predicted_structure_id

var _has_ghost: bool = false
var _ghost_type_id: String = ""
var _ghost_origin: Vector2i = Vector2i.ZERO
var _ghost_valid: bool = false

var _last_cell: Vector2i = NO_CELL
var _touching: bool = false

var _pulse_time: float = 0.0
var _redraw_accum: float = 0.0
## View clock in seconds for the idle loops of the painted structures. Advances while they are shown.
var anim_time: float = 0.0
var _has_models: bool = false

# Cached geometry. Layout caches rebuild when T or origin change; item caches when structures change.
var _geometry_dirty: bool = true
var _items_dirty: bool = true
var _markers_dirty: bool = true
var _ghost_dirty: bool = true
var _fitted: bool = false

var _island_ground: PackedVector2Array = PackedVector2Array()
var _outline: PackedVector2Array = PackedVector2Array()
var _outline_closed: PackedVector2Array = PackedVector2Array()
var _decor_polys: Array[PackedVector2Array] = []
var _decor_kinds: PackedInt32Array = PackedInt32Array()  # 0 soft A, 1 soft B, 2 cell ring, 3 highlight
var _decor_alpha: PackedFloat32Array = PackedFloat32Array()
var _decor_rims: Array[PackedVector2Array] = []
var _decor_ground: Array[PackedVector2Array] = []
var _decor_ground_kinds: PackedInt32Array = PackedInt32Array()
var _decor_ground_alpha: PackedFloat32Array = PackedFloat32Array()
var _decor_ground_rim: PackedByteArray = PackedByteArray()
var _decor_dims: Vector2i = Vector2i.ZERO
var _band_quads: Array[PackedVector2Array] = []
var _band_line: PackedVector2Array = PackedVector2Array()
var _band_line_dashes: PackedVector2Array = PackedVector2Array()

var _items: Array[StructureItem] = []
var _markers: Array[UnitMarker] = []

var _g_fill: PackedVector2Array = PackedVector2Array()
var _g_border: PackedVector2Array = PackedVector2Array()
var _g_dots: PackedVector2Array = PackedVector2Array()
var _g_dot_alpha: PackedFloat32Array = PackedFloat32Array()
var _g_range_fill: Array[PackedVector2Array] = []
var _g_range_dashes: PackedVector2Array = PackedVector2Array()
var _g_item: StructureItem = null

# Walls are connected segments, cached by WallRenderer and rebuilt only when a wall is placed or removed or
# the projection changes. The ghost preview has its own lone-cell renderer.
var _walls: WallRenderer = WallRenderer.new()
var _walls_dirty: bool = true
var _walls_key: Vector4 = Vector4(-1.0, 0.0, 0.0, 0.0)
var _still_pose: ModelPose = ModelPose.new()
## The ghost (a wall or a model) is painted opaque inside a CanvasGroup whose self_modulate fades the
## composited result once. Per-vertex alpha would let hidden parts (the wall outline under the top, a
## tower's arms behind its body) show through. Children paint after _draw(), so the ghost sits above the
## markers and the prediction.
var _ghost_group: CanvasGroup = null
var _ghost_canvas: GhostCanvas = null


class GhostCanvas extends Node2D:
	var walls: WallRenderer = WallRenderer.new()
	var cell: Vector2i = Vector2i.ZERO
	var pose: ModelPose = ModelPose.new()
	## Set for a tower or core ghost, which is painted at `foot` instead of the wall cell.
	var painter: ModelPainter = null
	var foot: Vector2 = Vector2.ZERO
	var tile_px: float = 14.0

	func _draw() -> void:
		if painter != null:
			painter.paint(self, foot, pose, tile_px)
			return
		walls.paint_shadows(self)
		walls.paint_cell(self, cell, 1.0, pose)


func _init() -> void:
	_ghost_group = CanvasGroup.new()
	_ghost_group.name = "Ghost"
	_ghost_group.visible = false
	_ghost_group.self_modulate = Color(1.0, 1.0, 1.0, PlaceholderBillboard.GHOST_OPACITY)
	_ghost_canvas = GhostCanvas.new()
	_ghost_group.add_child(_ghost_canvas)
	add_child(_ghost_group, false, Node.INTERNAL_MODE_BACK)

func set_draw_structures(val: bool) -> void:
	draw_structures = val
	queue_redraw()

func set_deploy_mode(val: bool) -> void:
	if deploy_mode != val:
		deploy_mode = val
		_markers_dirty = true
		_redraw_accum = 0.0
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
	_markers_dirty = true
	queue_redraw()

func set_night(val: bool) -> void:
	if night != val:
		night = val
		queue_redraw()

func _on_army_changed() -> void:
	_markers_dirty = true
	queue_redraw()

func _exit_tree() -> void:
	if army != null and army.changed.is_connected(_on_army_changed):
		army.changed.disconnect(_on_army_changed)

func _process(delta: float) -> void:
	var animate: bool = draw_structures and _has_models and is_visible_in_tree()
	if not deploy_mode and not animate:
		return
	if deploy_mode:
		_pulse_time = fmod(_pulse_time + delta, PULSE_PERIOD_S)
	if animate:
		anim_time += delta
	_redraw_accum += delta
	if _redraw_accum >= minf(PULSE_REDRAW_INTERVAL_S, ANIM_REDRAW_INTERVAL_S):
		_redraw_accum = 0.0
		queue_redraw()
		if _ghost_group.visible and _ghost_canvas.painter != null:
			_ghost_canvas.pose.time = anim_time
			_ghost_canvas.queue_redraw()

func setup(p_grid: GridModel, p_config: GameConfig, p_army: Army = null) -> void:
	if grid != null:
		if grid.structure_placed.is_connected(_on_structure_changed):
			grid.structure_placed.disconnect(_on_structure_changed)
		if grid.structure_removed.is_connected(_on_structure_changed):
			grid.structure_removed.disconnect(_on_structure_changed)

	grid = p_grid
	config = p_config
	ModelRegistry.configure(config, projection.scale)
	if p_army != null:
		set_army(p_army)
	if config != null and config.tile_px > 0:
		tile_px = config.tile_px

	if grid != null:
		grid.structure_placed.connect(_on_structure_changed)
		grid.structure_removed.connect(_on_structure_changed)

	if not _fitted and grid != null:
		_apply_default_layout()
	_geometry_dirty = true
	_items_dirty = true
	_walls_dirty = true
	_markers_dirty = true
	_ghost_dirty = true
	queue_redraw()

func _on_structure_changed(s: GridModel.PlacedStructure) -> void:
	if s != null and _is_wall(s.type_id):
		_walls_dirty = true
	_items_dirty = true
	_ghost_dirty = true
	queue_redraw()

# --- layout ----------------------------------------------------------------

func _apply_default_layout() -> void:
	var t: float = float(tile_px)
	projection.tile_px = t
	projection.origin = Vector2(float(grid.height) * t * projection.scale, HEADROOM_T * t)

func fit_to_rect(r: Rect2) -> void:
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return
	var s: float = projection.scale
	var span_tiles: float = float(grid.width + grid.height) * s
	var t_fit: float = minf(r.size.x / span_tiles, r.size.y / (span_tiles * 0.5 + HEADROOM_T + SLAB_T))
	var t_max: float = float(tile_px) * 2.0
	var t: float = clampf(t_fit, 1.0, t_max)
	var diamond_h: float = span_tiles * 0.5 * t
	var total_h: float = (HEADROOM_T + SLAB_T) * t + diamond_h
	var left_extent: float = float(grid.height) * t * s
	var right_extent: float = float(grid.width) * t * s
	var origin_x: float = r.position.x + (r.size.x - (left_extent + right_extent)) * 0.5 + left_extent
	var origin_y: float = r.position.y + (r.size.y - total_h) * 0.5 + HEADROOM_T * t
	projection.tile_px = t
	projection.origin = Vector2(origin_x, origin_y)
	_fitted = true
	_geometry_dirty = true
	_items_dirty = true
	_markers_dirty = true
	_ghost_dirty = true
	queue_redraw()

func set_ghost(type_id: String, origin: Vector2i, valid: bool) -> void:
	_has_ghost = true
	_ghost_type_id = type_id
	_ghost_origin = origin
	_ghost_valid = valid
	_ghost_dirty = true
	queue_redraw()

func clear_ghost() -> void:
	if _has_ghost:
		_has_ghost = false
		_ghost_type_id = ""
		_g_item = null
		_hide_ghost()
		queue_redraw()

func cell_to_local_center(cell: Vector2i) -> Vector2:
	return projection.cell_center(cell)

func local_to_cell(local_pos: Vector2) -> Vector2i:
	return projection.screen_to_cell(local_pos)

# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if grid == null:
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.index != 0:
			return
		if touch.pressed:
			if _touching:
				return
			_touching = true
			_handle_press(touch.position)
		else:
			if not _touching:
				return
			_touching = false
			_handle_release(touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index != 0 or not _touching:
			return
		_handle_drag(drag.position)

func _handle_press(screen_pos: Vector2) -> void:
	var cell: Vector2i = projection.screen_to_cell(to_local(screen_pos))
	if grid == null or not grid.in_bounds(cell):
		_last_cell = NO_CELL
		return
	_last_cell = cell
	cell_pressed.emit(cell)

func _handle_drag(screen_pos: Vector2) -> void:
	var cell: Vector2i = projection.screen_to_cell(to_local(screen_pos))
	if grid == null or not grid.in_bounds(cell):
		return
	if cell != _last_cell:
		_last_cell = cell
		cell_dragged.emit(cell)

func _handle_release(screen_pos: Vector2) -> void:
	var cell: Vector2i = projection.screen_to_cell(to_local(screen_pos))
	_last_cell = NO_CELL
	if grid == null or not grid.in_bounds(cell):
		return
	cell_released.emit(cell)

# --- geometry caches -------------------------------------------------------

func _project(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i: int in range(poly.size()):
		out[i] = projection.ground_to_screen(poly[i])
	return out

func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = poly.duplicate()
	if poly.size() > 0:
		out.append(poly[0])
	return out

func _circle_ground(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(CIRCLE_POINTS):
		var a: float = TAU * float(i) / float(CIRCLE_POINTS)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

func _rect_ground(center: Vector2, size: float, radius: float) -> PackedVector2Array:
	var half: float = size * 0.5
	return KitDraw.rounded_rect_points(Rect2(center - Vector2(half, half), Vector2(size, size)), radius, ARC_STEPS)

## Dash segments (point pairs) along a closed screen polyline. When `clip_to_island` is set, dashes
## whose midpoint falls off the island are dropped.
func _dash_segments(line: PackedVector2Array, clip_to_island: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var on: bool = true
	var remaining: float = DASH_PX
	for i: int in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0:
			continue
		var dir: Vector2 = (b - a) / seg_len
		var pos: float = 0.0
		while pos < seg_len:
			var step: float = minf(remaining, seg_len - pos)
			if on:
				var p0: Vector2 = a + dir * pos
				var p1: Vector2 = a + dir * (pos + step)
				if not clip_to_island or _on_island((p0 + p1) * 0.5):
					out.append(p0)
					out.append(p1)
			pos += step
			remaining -= step
			if remaining <= 0.0:
				on = not on
				remaining = DASH_PX if on else GAP_PX
	return out

func _on_island(screen: Vector2) -> bool:
	var g: Vector2 = projection.screen_to_ground(screen)
	return g.x >= 0.0 and g.y >= 0.0 and g.x <= float(grid.width) and g.y <= float(grid.height)

func _rebuild_decor_ground() -> void:
	_decor_ground.clear()
	_decor_ground_kinds.clear()
	_decor_ground_alpha.clear()
	_decor_ground_rim.clear()
	var w: float = float(grid.width)
	var h: float = float(grid.height)
	_island_ground = KitDraw.rounded_rect_points(Rect2(0.0, 0.0, w, h), CORNER_RADIUS_TILES, ARC_STEPS)

	# Highlight blob, about 12 tiles across near ground (12, 10) on the 40x40 island.
	var hl_center := Vector2(w * 0.3, h * 0.25)
	for i: int in range(BLOB_RINGS):
		var r: float = 6.0 * (1.0 - float(i) / float(BLOB_RINGS))
		_add_clipped(_circle_ground(hl_center, r), 3, BLOB_RING_ALPHA, false)

	# Port of the canvas decor loop. Its own LCG, never the sim's Rng.
	var seed_v: int = DECOR_SEED
	for i: int in range(12):
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var cx: float = float(seed_v) / 2147483648.0 * w
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var cy: float = float(seed_v) / 2147483648.0 * h
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var sz: float = 5.0 + float(seed_v) / 2147483648.0 * 8.0
		var kind: int = 1 if (i % 2) == 1 else 0
		for ring: int in range(BLOB_RINGS):
			var r: float = sz * 0.5 * (1.0 - float(ring) / float(BLOB_RINGS))
			_add_clipped(_circle_ground(Vector2(cx, cy), r), kind, BLOB_RING_ALPHA, false)

	var placed: int = 0
	var tries: int = 0
	while placed < 24 and tries < 200:
		tries += 1
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var cx: float = float(seed_v) / 2147483648.0 * w
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var cy: float = float(seed_v) / 2147483648.0 * h
		if cx > w * 0.225 and cx < w * 0.775 and cy > h * 0.225 and cy < h * 0.775:
			continue
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var sz: float = 1.0 + float(seed_v) / 2147483648.0 * 1.6
		_add_clipped(_circle_ground(Vector2(cx, cy), sz * 0.5), 2, 1.0, true)
		placed += 1
	_decor_dims = Vector2i(grid.width, grid.height)

func _add_clipped(poly: PackedVector2Array, kind: int, alpha: float, rim: bool) -> void:
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, _island_ground):
		if piece.size() < 3 or Geometry2D.is_polygon_clockwise(piece):
			continue
		_decor_ground.append(piece)
		_decor_ground_kinds.append(kind)
		_decor_ground_alpha.append(alpha)
		_decor_ground_rim.append(1 if rim else 0)

func _ensure_island() -> void:
	if _decor_dims != Vector2i(grid.width, grid.height) or _island_ground.is_empty():
		_rebuild_decor_ground()

func _rebuild_geometry() -> void:
	_geometry_dirty = false
	_ensure_island()
	var w: float = float(grid.width)
	var h: float = float(grid.height)

	_outline = _project(_island_ground)
	_outline_closed = _closed(_outline)

	_decor_polys.clear()
	_decor_kinds = PackedInt32Array()
	_decor_alpha = PackedFloat32Array()
	_decor_rims.clear()
	for i: int in range(_decor_ground.size()):
		var p: PackedVector2Array = _project(_decor_ground[i])
		_decor_polys.append(p)
		_decor_kinds.append(_decor_ground_kinds[i])
		_decor_alpha.append(_decor_ground_alpha[i])
		if _decor_ground_rim[i] == 1:
			_decor_rims.append(_closed(p))

	# Deploy band: concentric rounded rects share their corner centres, so quads pair up point for point.
	var ring: float = float(grid.deploy_ring)
	_band_quads.clear()
	_band_line = PackedVector2Array()
	_band_line_dashes = PackedVector2Array()
	if ring > 0.0 and w > ring * 2.0 and h > ring * 2.0:
		var outer: PackedVector2Array = _project(KitDraw.rounded_rect_points(Rect2(0.0, 0.0, w, h), CORNER_RADIUS_TILES, ARC_STEPS))
		var inner_ground: PackedVector2Array = KitDraw.rounded_rect_points(
				Rect2(ring, ring, w - ring * 2.0, h - ring * 2.0), maxf(CORNER_RADIUS_TILES - ring, 0.05), ARC_STEPS)
		var inner: PackedVector2Array = _project(inner_ground)
		var n: int = mini(outer.size(), inner.size())
		for i: int in range(n):
			var j: int = (i + 1) % n
			_band_quads.append(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]))
		_band_line = _closed(inner)
		_band_line_dashes = _dash_segments(_band_line, false)

func _rebuild_items() -> void:
	_items_dirty = false
	_items.clear()
	if grid == null:
		return
	_has_models = false
	for s: GridModel.PlacedStructure in grid.structures():
		var item: StructureItem = _make_item(s.id, s.type_id, s.origin, s.footprint)
		_has_models = _has_models or item.painter != null
		_items.append(item)
	_items.sort_custom(_sort_items)
	var key := Vector4(projection.tile_px, projection.origin.x, projection.origin.y, projection.scale)
	if _walls_dirty or key != _walls_key:
		_walls_dirty = false
		_walls_key = key
		var cells: Dictionary = {}
		for s: GridModel.PlacedStructure in grid.structures():
			if _is_wall(s.type_id):
				cells[s.origin] = true
		_walls.rebuild(cells, projection)

func _is_wall(type_id: String) -> bool:
	var sdef: StructureDef = config.structures.get(type_id) if config != null else null
	return sdef != null and sdef.has_tag("wall")

func _sort_items(a: StructureItem, b: StructureItem) -> bool:
	if a.depth != b.depth:
		return a.depth < b.depth
	return a.id < b.id

func _make_item(id: int, type_id: String, origin: Vector2i, footprint: Vector2i) -> StructureItem:
	var t: float = projection.tile_px
	var sdef: StructureDef = config.structures.get(type_id) if config != null else null
	var item := StructureItem.new()
	item.id = id
	item.type_id = type_id
	var center_g: Vector2 = Vector2(origin) + Vector2(footprint) * 0.5
	item.depth = IsoProjection.depth_key(center_g)
	item.foot = projection.ground_to_screen(center_g)
	if sdef != null and sdef.has_tag("wall"):
		item.kind = 1
		item.cell = origin
		return item
	item.kind = 2 if (sdef != null and sdef.has_tag("core")) else 0
	item.painter = ModelRegistry.painter_for(type_id)
	item.pose = ModelPose.new()
	item.pose.seed = id
	if item.kind == 2:
		for i: int in range(BLOB_RINGS):
			var r: float = 7.4 * 0.5 * (1.0 - float(i) / float(BLOB_RINGS))
			item.glow_rings.append(_project(_circle_ground(center_g, r)))
		item.plate = _project(_rect_ground(center_g, 5.6, 5.6 * 0.34))
	else:
		item.plate = _project(_rect_ground(center_g, 3.8, 3.8 * 0.36))
	item.plate_rim = _closed(item.plate)
	return item

func _rebuild_markers() -> void:
	_markers_dirty = false
	_markers.clear()
	if army == null or grid == null or not deploy_mode:
		return
	for cell: Vector2i in grid.ring_cells():
		var deployed: Array[String] = army.deployed_at(cell)
		if deployed.is_empty():
			continue
		var last_type: String = deployed[-1]
		var pdef: PathogenDef = config.pathogens.get(last_type) if config != null else null
		var m := UnitMarker.new()
		m.center = projection.cell_center(cell)
		m.shape = pdef.placeholder_shape if pdef != null else "circle"
		m.color = pdef.placeholder_color if pdef != null else Color.WHITE
		m.count = deployed.size()
		_markers.append(m)

func _rebuild_ghost() -> void:
	_ghost_dirty = false
	_g_item = null
	_g_dots = PackedVector2Array()
	_g_dot_alpha = PackedFloat32Array()
	_g_range_fill.clear()
	_g_range_dashes = PackedVector2Array()
	if not _has_ghost or _ghost_type_id.is_empty() or grid == null:
		_hide_ghost()
		return
	_ensure_island()
	var sdef: StructureDef = config.structures.get(_ghost_type_id) if config != null else null
	var footprint: Vector2i = sdef.footprint if sdef != null else Vector2i.ONE
	var center_g: Vector2 = Vector2(_ghost_origin) + Vector2(footprint) * 0.5
	var radius: float = minf(0.7, minf(float(footprint.x), float(footprint.y)) * 0.5)
	var fill_g: PackedVector2Array = KitDraw.rounded_rect_points(Rect2(Vector2(_ghost_origin), Vector2(footprint)), radius, ARC_STEPS)
	_g_fill = _project(fill_g)
	_g_border = _closed(_g_fill)
	_g_item = _make_item(0, _ghost_type_id, _ghost_origin, footprint)
	if _g_item.kind == 1:
		_show_ghost_wall(_ghost_origin)
	else:
		_show_ghost_model(_g_item)

	var reach: int = int(ceilf(DOT_RADIUS_TILES))
	var cx: int = int(floorf(center_g.x))
	var cy: int = int(floorf(center_g.y))
	for y: int in range(cy - reach, cy + reach + 1):
		for x: int in range(cx - reach, cx + reach + 1):
			if not grid.in_bounds(Vector2i(x, y)):
				continue
			var tile_c: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = tile_c.distance_to(center_g)
			if d >= DOT_RADIUS_TILES:
				continue
			_g_dots.append(projection.ground_to_screen(tile_c))
			_g_dot_alpha.append(1.0 - d / DOT_RADIUS_TILES)

	if sdef != null and sdef.has_attack and sdef.attack_range_mt > 0:
		var ring_g: PackedVector2Array = _circle_ground(center_g, float(sdef.attack_range_mt) / 1000.0)
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(ring_g, _island_ground):
			if piece.size() >= 3 and not Geometry2D.is_polygon_clockwise(piece):
				_g_range_fill.append(_project(piece))
		_g_range_dashes = _dash_segments(_closed(_project(ring_g)), true)

# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return
	if _geometry_dirty:
		_rebuild_geometry()
	if _items_dirty:
		_rebuild_items()
	if _markers_dirty:
		_rebuild_markers()
	if _ghost_dirty:
		_rebuild_ghost()

	var k: float = projection.tile_px / 14.0
	_draw_slab()
	_draw_top(k)
	_draw_decor(k)
	_draw_band(k)
	if draw_structures:
		_draw_plates(k)
		_walls.paint_shadows(self)
		_draw_structure_items()
	if _has_ghost:
		_draw_ghost(k)
	if deploy_mode:
		_draw_markers()
	_draw_prediction()

func _draw_slab() -> void:
	var th: float = SLAB_T * projection.tile_px
	draw_set_transform(Vector2(0.0, th), 0.0, Vector2.ONE)
	draw_colored_polygon(_outline, SHADOW_NIGHT if night else SHADOW_DAY)
	for i: int in range(SLAB_LAYERS, 0, -1):
		var col: Color
		if night:
			col = SLAB_HI_NIGHT if i > 3 else SLAB_LO_NIGHT
		else:
			col = SLAB_HI_DAY if i > 3 else SLAB_LO_DAY
		draw_set_transform(Vector2(0.0, th * float(i) / float(SLAB_LAYERS)), 0.0, Vector2.ONE)
		draw_colored_polygon(_outline, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_top(k: float) -> void:
	draw_colored_polygon(_outline, TOP_NIGHT if night else TOP_DAY)
	draw_polyline(_outline_closed, RIM_NIGHT if night else RIM_DAY, 3.0 * k, true)

func _decor_color(kind: int) -> Color:
	match kind:
		0:
			return SOFT_A_NIGHT if night else SOFT_A_DAY
		1:
			return SOFT_B_NIGHT if night else SOFT_B_DAY
		2:
			return CELL_FILL_NIGHT if night else CELL_FILL_DAY
		_:
			return BLOB_HI_NIGHT if night else BLOB_HI_DAY

func _draw_decor(k: float) -> void:
	for i: int in range(_decor_polys.size()):
		var col: Color = _decor_color(_decor_kinds[i])
		col.a *= _decor_alpha[i]
		if col.a > 0.0:
			draw_colored_polygon(_decor_polys[i], col)
	var rim: Color = CELL_RIM_NIGHT if night else CELL_RIM_DAY
	for line: PackedVector2Array in _decor_rims:
		draw_polyline(line, rim, 1.5 * k, true)

func _draw_band(k: float) -> void:
	var fill: Color
	var line: Color
	var active: bool = night and deploy_mode
	if night:
		if active:
			var pulse: float = 0.5 + 0.5 * sin(_pulse_time / PULSE_PERIOD_S * TAU)
			fill = Color(GREEN, lerpf(BAND_ACTIVE_ALPHA_LO, BAND_ACTIVE_ALPHA_HI, pulse))
			line = Color(GREEN, 0.9)
		else:
			fill = BAND_NIGHT_IDLE
			line = BAND_LINE_NIGHT_IDLE
	else:
		fill = BAND_DAY
		line = BAND_LINE_DAY
	for quad: PackedVector2Array in _band_quads:
		draw_colored_polygon(quad, fill)
	if _band_line.size() < 2:
		return
	if active:
		draw_polyline(_band_line, Color(GREEN, 0.12), 6.0 * k, true)
		draw_polyline(_band_line, Color(GREEN, 0.3), 3.0 * k, true)
		draw_polyline(_band_line, line, 2.0 * k, true)
	elif night:
		draw_polyline(_band_line, line, 2.0 * k, true)
	else:
		draw_multiline(_band_line_dashes, line, 2.0 * k, true)

func _draw_plates(k: float) -> void:
	var plate_fill: Color = PLATE_NIGHT if night else PLATE_DAY
	var plate_rim: Color = PLATE_RIM_NIGHT if night else PLATE_RIM_DAY
	for item: StructureItem in _items:
		if item.kind == 0:
			draw_colored_polygon(item.plate, plate_fill)
			draw_polyline(item.plate_rim, plate_rim, 1.5 * k, true)
		elif item.kind == 2:
			for ring: PackedVector2Array in item.glow_rings:
				draw_colored_polygon(ring, Color(NUCLEUS_GLOW, NUCLEUS_GLOW.a * BLOB_RING_ALPHA))
			draw_colored_polygon(item.plate, NUCLEUS_PLATE)
			draw_polyline(item.plate_rim, NUCLEUS_PLATE_RIM, 2.0 * k, true)

func _show_ghost_wall(cell: Vector2i) -> void:
	_ghost_canvas.painter = null
	_ghost_canvas.cell = cell
	_ghost_canvas.walls.rebuild({cell: true}, projection)
	_ghost_group.visible = true
	_ghost_canvas.queue_redraw()


func _show_ghost_model(item: StructureItem) -> void:
	_ghost_canvas.painter = item.painter
	_ghost_canvas.foot = item.foot
	_ghost_canvas.tile_px = projection.tile_px
	_ghost_canvas.pose.time = anim_time
	_ghost_group.visible = true
	_ghost_canvas.queue_redraw()


func _hide_ghost() -> void:
	_ghost_group.visible = false


func _draw_structure_items() -> void:
	for item: StructureItem in _items:
		_draw_item(item)

## The ghost's wall or model is painted by _ghost_canvas, so only placed structures are drawn here.
func _draw_item(item: StructureItem) -> void:
	if item.kind == 1:
		_walls.paint_cell(self, item.cell, 1.0, _still_pose)
		return
	item.pose.time = anim_time + ViewRng.hash01(item.id, 1) * AnimDriver.IDLE_DESYNC_SECONDS
	# The island never damages a structure, so the pulse rate is constant and the phase is a plain product.
	item.pose.pulse_phase = fposmod(item.pose.time * NucleusPainter.pulse_rate(item.pose.hp_frac), 1.0)
	item.painter.paint(self, item.foot, item.pose, projection.tile_px)

func _draw_ghost(k: float) -> void:
	if _g_item == null or _g_border.size() < 2:
		return
	var tint: Color = GREEN if _ghost_valid else RED
	for frag: PackedVector2Array in _g_range_fill:
		draw_colored_polygon(frag, RANGE_FILL)
	if not _g_range_dashes.is_empty():
		draw_multiline(_g_range_dashes, RANGE_LINE, 2.0 * k, true)
	draw_colored_polygon(_g_fill, GHOST_OK_FILL if _ghost_valid else GHOST_BAD_FILL)
	if _ghost_valid:
		draw_polyline(_g_border, Color(tint, 0.15), 10.0 * k, true)
		draw_polyline(_g_border, Color(tint, 0.3), 6.0 * k, true)
	draw_polyline(_g_border, tint, 2.0 * k, true)
	for i: int in range(_g_dots.size()):
		draw_circle(_g_dots[i], 1.4 * k, Color(GHOST_DOT, GHOST_DOT.a * _g_dot_alpha[i]))

func _draw_markers() -> void:
	var t: float = projection.tile_px
	var size: float = 0.9 * t
	var font: Font = ThemeDB.fallback_font
	for m: UnitMarker in _markers:
		PlaceholderShapes.draw_shape(self, m.shape, Rect2(m.center - Vector2(size, size) * 0.5, Vector2(size, size)), m.color)
		if m.count > 1:
			var badge_r: float = maxf(t * 0.3, 6.0)
			var badge_c: Vector2 = m.center + Vector2(size * 0.5, -size * 0.5)
			draw_circle(badge_c, badge_r, Color.WHITE)
			draw_arc(badge_c, badge_r, 0.0, TAU, 16, Color(0.2, 0.2, 0.2, 0.6), 1.0, true)
			if font != null:
				var font_size: int = maxi(int(badge_r * 1.5), 9)
				var text: String = str(m.count)
				var str_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
				draw_string(font, Vector2(badge_c.x - str_size.x * 0.5, badge_c.y + str_size.y * 0.35), text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

func _draw_prediction() -> void:
	if predicted_structure_id <= 0 or grid == null:
		return
	var s: GridModel.PlacedStructure = grid.get_structure(predicted_structure_id)
	if s == null:
		return
	var t: float = projection.tile_px
	var center: Vector2 = projection.footprint_center(s.origin, s.footprint) + Vector2(0.0, -2.0 * t)
	var badge_r: float = t * 0.35
	draw_circle(center, badge_r, Color("#f1c40f"))
	draw_arc(center, badge_r, 0.0, TAU, 16, Color(0.1, 0.1, 0.1, 0.8), 1.5, true)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		var font_size: int = maxi(int(badge_r * 1.4), 10)
		var str_size: Vector2 = font.get_string_size("?", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(center.x - str_size.x * 0.5, center.y + str_size.y * 0.35), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
