class_name GridView
extends Node2D

## The isometric island for Synthesis, Incubation and Infection (docs/MVP_UI_SPEC.md section 3).
## Reads the flat integer grid and draws it through an IsoProjection. Never modifies core state.

signal cell_pressed(cell: Vector2i)
signal cell_dragged(cell: Vector2i)
signal cell_released(cell: Vector2i)
## A touch ended off the grid, after a press that began on it.
signal touch_cancelled
## A one-finger press was abandoned because a second finger landed (a pinch). Nothing should be committed.
signal press_cancelled

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
## Pinch zoom range, as a multiple of the fitted tile size.
const MAX_ZOOM: float = 4.0
const NO_CELL: Vector2i = Vector2i(-99999, -99999)

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
const NUCLEUS_GLOW_RING: Color = Color(NUCLEUS_GLOW, NUCLEUS_GLOW.a * BLOB_RING_ALPHA)
const BAND_ACTIVE_LINE: Color = Color(GREEN, 0.9)
const BAND_ACTIVE_GLOW_OUTER: Color = Color(GREEN, 0.12)
const BAND_ACTIVE_GLOW_INNER: Color = Color(GREEN, 0.3)
const GHOST_OK_GLOW_OUTER: Color = Color(GREEN, 0.15)
const GHOST_OK_GLOW_INNER: Color = Color(GREEN, 0.3)
const MARKER_BADGE_RIM: Color = Color(0.2, 0.2, 0.2, 0.6)
const PREDICTION_FILL: Color = Color("#f1c40f")
const PREDICTION_RIM: Color = Color(0.1, 0.1, 0.1, 0.8)
## Extra px around the island in the ground texture, for the rim's half width and its antialiasing.
const GROUND_MARGIN_PX: float = 4.0

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
	var label: String = ""

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
## A wall line ghost: one cell per entry, and whether each can be built. Empty for a single-cell ghost.
var _ghost_line: Array[Vector2i] = []
var _ghost_line_ok: Array[bool] = []
var _g_line_fill: Array[PackedVector2Array] = []
var _g_line_border: Array[PackedVector2Array] = []

var _last_cell: Vector2i = NO_CELL
var _touching: bool = false
## Live finger positions (local px) by touch index, and the tile size fit_to_rect chose (the zoom floor).
var _fingers: Dictionary = {}
var _fit_tile_px: float = 0.0

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

## The static island (slab, surface, decor, and the band and plates unless the band is pulsing) is painted
## once into a SubViewport and drawn as one texture (docs/MODEL_PIPELINE_PLAN.md section 3.4). It is painted
## again only when the theme, the phase flags, T, the origin, the structures or the screen scale change.
var _ground_vp: SubViewport = null
var _ground_canvas: GroundCanvas = null
var _ground_sprite: GroundSprite = null
var _ground_dirty: bool = true
var _ground_scale: float = 0.0
## Times the ground texture was painted, for tests and the perf notes.
var ground_renders: int = 0
var _band_pts: PackedVector2Array = PackedVector2Array()
var _band_cols: PackedColorArray = PackedColorArray()
var _band_idx: PackedInt32Array = PackedInt32Array()
var _band_fill: Color = Color.TRANSPARENT


## Paints the ground layers into the SubViewport, offset and scaled to its pixels.
class GroundCanvas extends Node2D:
	var view: GridView = null

	func _draw() -> void:
		if view != null:
			view._paint_ground(self)


## Draws the cached ground texture behind GridView's own commands. The SubViewport holds premultiplied colour
## (translucent edges were blended over a clear target), so it composites with the premultiplied blend.
class GroundSprite extends Node2D:
	var texture: Texture2D = null
	var rect: Rect2 = Rect2()

	func _init() -> void:
		show_behind_parent = true
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		material = mat

	func _draw() -> void:
		if texture != null and rect.size.x > 0.0 and rect.size.y > 0.0:
			draw_texture_rect(texture, rect, false)


class GhostCanvas extends Node2D:
	var walls: WallRenderer = WallRenderer.new()
	var cell: Vector2i = Vector2i.ZERO
	## A run of wall cells; when set it is painted instead of `cell`.
	var cells: Array[Vector2i] = []
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
		if cells.is_empty():
			walls.paint_cell(self, cell, 1.0, pose)
		else:
			for c: Vector2i in cells:
				walls.paint_cell(self, c, 1.0, pose)


func _init() -> void:
	_ghost_group = CanvasGroup.new()
	_ghost_group.name = "Ghost"
	_ghost_group.visible = false
	_ghost_group.self_modulate = Color(1.0, 1.0, 1.0, PlaceholderBillboard.GHOST_OPACITY)
	_ghost_canvas = GhostCanvas.new()
	_ghost_group.add_child(_ghost_canvas)
	add_child(_ghost_group, false, Node.INTERNAL_MODE_BACK)
	_ground_vp = SubViewport.new()
	_ground_vp.name = "GroundCache"
	_ground_vp.transparent_bg = true
	_ground_vp.disable_3d = true
	_ground_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ground_vp.size = Vector2i(2, 2)
	_ground_canvas = GroundCanvas.new()
	_ground_canvas.view = self
	_ground_vp.add_child(_ground_canvas)
	add_child(_ground_vp, false, Node.INTERNAL_MODE_FRONT)
	_ground_sprite = GroundSprite.new()
	_ground_sprite.name = "Ground"
	_ground_sprite.texture = _ground_vp.get_texture()
	add_child(_ground_sprite, false, Node.INTERNAL_MODE_FRONT)

func set_draw_structures(val: bool) -> void:
	if draw_structures != val:
		_ground_dirty = true
	draw_structures = val
	queue_redraw()

func set_deploy_mode(val: bool) -> void:
	if deploy_mode != val:
		deploy_mode = val
		_markers_dirty = true
		_ground_dirty = true
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
		_ground_dirty = true
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
	_fit_tile_px = t
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
	_ghost_line = []
	_ghost_line_ok = []
	_ghost_dirty = true
	queue_redraw()

## Previews a straight run of `type_id` cells; `ok[i]` says whether cells[i] can be built.
func set_ghost_line(type_id: String, cells: Array[Vector2i], ok: Array[bool]) -> void:
	if cells.is_empty():
		clear_ghost()
		return
	_has_ghost = true
	_ghost_type_id = type_id
	_ghost_origin = cells[0]
	_ghost_valid = ok.has(true)
	_ghost_line = cells.duplicate()
	_ghost_line_ok = ok.duplicate()
	_ghost_dirty = true
	queue_redraw()

func clear_ghost() -> void:
	if _has_ghost:
		_has_ghost = false
		_ghost_type_id = ""
		_ghost_line = []
		_ghost_line_ok = []
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
		if touch.pressed:
			_fingers[touch.index] = to_local(touch.position)
			if _fingers.size() >= 2:
				_cancel_press()
				return
		else:
			var was_pinching: bool = _fingers.size() >= 2
			_fingers.erase(touch.index)
			if was_pinching:
				return
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
		if _fingers.size() >= 2:
			if _fingers.has(drag.index):
				_pinch(drag.index, to_local(drag.position))
			return
		if _fingers.has(drag.index):
			_fingers[drag.index] = to_local(drag.position)
		if drag.index != 0 or not _touching:
			return
		_handle_drag(drag.position)

func _cancel_press() -> void:
	if not _touching:
		return
	_touching = false
	_last_cell = NO_CELL
	press_cancelled.emit()

## Zooms about the midpoint of the first two fingers, and pans with it, clamped to [fit, fit * MAX_ZOOM].
func _pinch(index: int, new_pos: Vector2) -> void:
	var ids: Array = _fingers.keys()
	ids.sort()
	var a: int = ids[0]
	var b: int = ids[1]
	var old_a: Vector2 = _fingers[a]
	var old_b: Vector2 = _fingers[b]
	_fingers[index] = new_pos
	if index != a and index != b:
		return
	var new_a: Vector2 = _fingers[a]
	var new_b: Vector2 = _fingers[b]
	var old_dist: float = old_a.distance_to(old_b)
	if old_dist < 1.0:
		return
	var ratio: float = new_a.distance_to(new_b) / old_dist
	var floor_px: float = _fit_tile_px if _fit_tile_px > 0.0 else projection.tile_px
	var target: float = clampf(projection.tile_px * ratio, floor_px, floor_px * MAX_ZOOM)
	apply_zoom(target, (old_a + old_b) * 0.5, (new_a + new_b) * 0.5)

## Sets the tile size so the ground point under `from_pt` lands on `to_pt` (local px).
func apply_zoom(new_tile_px: float, from_pt: Vector2, to_pt: Vector2) -> void:
	var k: float = new_tile_px / projection.tile_px
	projection.origin = to_pt - (from_pt - projection.origin) * k
	projection.tile_px = new_tile_px
	_geometry_dirty = true
	_items_dirty = true
	_markers_dirty = true
	_ghost_dirty = true
	queue_redraw()

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
		touch_cancelled.emit()
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
	_ground_dirty = true
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
	_band_pts = PackedVector2Array()
	_band_cols = PackedColorArray()
	_band_idx = PackedInt32Array()
	_band_fill = Color.TRANSPARENT
	_band_line = PackedVector2Array()
	_band_line_dashes = PackedVector2Array()
	if ring > 0.0 and w > ring * 2.0 and h > ring * 2.0:
		var outer: PackedVector2Array = _project(KitDraw.rounded_rect_points(Rect2(0.0, 0.0, w, h), CORNER_RADIUS_TILES, ARC_STEPS))
		var inner_ground: PackedVector2Array = KitDraw.rounded_rect_points(
				Rect2(ring, ring, w - ring * 2.0, h - ring * 2.0), maxf(CORNER_RADIUS_TILES - ring, 0.05), ARC_STEPS)
		var inner: PackedVector2Array = _project(inner_ground)
		var n: int = mini(outer.size(), inner.size())
		for i: int in range(n):
			_band_pts.append(outer[i])
			_band_pts.append(inner[i])
		_band_cols.resize(_band_pts.size())
		for i: int in range(n):
			var a: int = i * 2
			var b: int = ((i + 1) % n) * 2
			_band_idx.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))
		_band_line = _closed(inner)
		_band_line_dashes = _dash_segments(_band_line, false)

func _rebuild_items() -> void:
	_items_dirty = false
	_ground_dirty = true
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
		m.label = str(m.count)
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
	if not _ghost_line.is_empty() and _g_item.kind == 1:
		_rebuild_ghost_line()
		return
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
	_update_ground_cache()
	if _band_live():
		_draw_band(self, k)
		if draw_structures:
			_draw_plates(self, k)
	if draw_structures:
		_walls.paint_shadows(self)
		_draw_structure_items()
	if _has_ghost:
		_draw_ghost(k)
	if deploy_mode:
		_draw_markers()
	_draw_prediction()

## The night deploy band pulses in Incubation, so it and the plates above it stay live, outside the cache.
func _band_live() -> bool:
	return night and deploy_mode

## Screen px per local px (the stretch and any parent scale), so the cached texture stays sharp.
func _screen_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var xf: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	return clampf(xf.get_scale().x, 0.25, 4.0)

## Bounding box in local px of everything the ground pass paints: the island top and the slab below it.
func ground_rect() -> Rect2:
	if _outline.is_empty():
		return Rect2()
	var r := Rect2(_outline[0], Vector2.ZERO)
	for p: Vector2 in _outline:
		r = r.expand(p)
	r.size.y += SLAB_T * projection.tile_px
	var m: float = GROUND_MARGIN_PX * maxf(projection.tile_px / 14.0, 1.0)
	r = r.grow(m)
	var pos := Vector2(floorf(r.position.x), floorf(r.position.y))
	return Rect2(pos, Vector2(ceilf(r.end.x) - pos.x, ceilf(r.end.y) - pos.y))

func _update_ground_cache() -> void:
	var s: float = _screen_scale()
	if s != _ground_scale:
		_ground_scale = s
		_ground_dirty = true
	if not _ground_dirty:
		return
	_ground_dirty = false
	var rect: Rect2 = ground_rect()
	var px := Vector2i(maxi(int(ceilf(rect.size.x * s)), 2), maxi(int(ceilf(rect.size.y * s)), 2))
	_ground_vp.size = px
	_ground_canvas.scale = Vector2(s, s)
	_ground_canvas.position = -rect.position * s
	_ground_canvas.queue_redraw()
	_ground_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ground_sprite.rect = Rect2(rect.position, Vector2(px) / s)
	_ground_sprite.queue_redraw()
	ground_renders += 1

## The static ground layers, back to front, onto `ci` (the cache's canvas).
func _paint_ground(ci: CanvasItem) -> void:
	if grid == null or _outline.is_empty():
		return
	var k: float = projection.tile_px / 14.0
	_draw_slab(ci)
	_draw_top(ci, k)
	_draw_decor(ci, k)
	if not _band_live():
		_draw_band(ci, k)
		if draw_structures:
			_draw_plates(ci, k)

func _draw_slab(ci: CanvasItem) -> void:
	var th: float = SLAB_T * projection.tile_px
	ci.draw_set_transform(Vector2(0.0, th), 0.0, Vector2.ONE)
	ci.draw_colored_polygon(_outline, SHADOW_NIGHT if night else SHADOW_DAY)
	for i: int in range(SLAB_LAYERS, 0, -1):
		var col: Color
		if night:
			col = SLAB_HI_NIGHT if i > 3 else SLAB_LO_NIGHT
		else:
			col = SLAB_HI_DAY if i > 3 else SLAB_LO_DAY
		ci.draw_set_transform(Vector2(0.0, th * float(i) / float(SLAB_LAYERS)), 0.0, Vector2.ONE)
		ci.draw_colored_polygon(_outline, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_top(ci: CanvasItem, k: float) -> void:
	ci.draw_colored_polygon(_outline, TOP_NIGHT if night else TOP_DAY)
	ci.draw_polyline(_outline_closed, RIM_NIGHT if night else RIM_DAY, 3.0 * k, true)

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

func _draw_decor(ci: CanvasItem, k: float) -> void:
	for i: int in range(_decor_polys.size()):
		var col: Color = _decor_color(_decor_kinds[i])
		col.a *= _decor_alpha[i]
		if col.a > 0.0:
			ci.draw_colored_polygon(_decor_polys[i], col)
	var rim: Color = CELL_RIM_NIGHT if night else CELL_RIM_DAY
	for line: PackedVector2Array in _decor_rims:
		ci.draw_polyline(line, rim, 1.5 * k, true)

func _draw_band(ci: CanvasItem, k: float) -> void:
	var fill: Color
	var line: Color
	var active: bool = night and deploy_mode
	if night:
		if active:
			var pulse: float = 0.5 + 0.5 * sin(_pulse_time / PULSE_PERIOD_S * TAU)
			fill = GREEN
			fill.a = lerpf(BAND_ACTIVE_ALPHA_LO, BAND_ACTIVE_ALPHA_HI, pulse)
			line = BAND_ACTIVE_LINE
		else:
			fill = BAND_NIGHT_IDLE
			line = BAND_LINE_NIGHT_IDLE
	else:
		fill = BAND_DAY
		line = BAND_LINE_DAY
	if not _band_idx.is_empty():
		if fill != _band_fill:
			_band_fill = fill
			_band_cols.fill(fill)
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _band_idx, _band_pts, _band_cols)
	if _band_line.size() < 2:
		return
	if active:
		ci.draw_polyline(_band_line, BAND_ACTIVE_GLOW_OUTER, 6.0 * k, true)
		ci.draw_polyline(_band_line, BAND_ACTIVE_GLOW_INNER, 3.0 * k, true)
		ci.draw_polyline(_band_line, line, 2.0 * k, true)
	elif night:
		ci.draw_polyline(_band_line, line, 2.0 * k, true)
	else:
		ci.draw_multiline(_band_line_dashes, line, 2.0 * k, true)

func _draw_plates(ci: CanvasItem, k: float) -> void:
	var plate_fill: Color = PLATE_NIGHT if night else PLATE_DAY
	var plate_rim: Color = PLATE_RIM_NIGHT if night else PLATE_RIM_DAY
	for item: StructureItem in _items:
		if item.kind == 0:
			ci.draw_colored_polygon(item.plate, plate_fill)
			ci.draw_polyline(item.plate_rim, plate_rim, 1.5 * k, true)
		elif item.kind == 2:
			for ring: PackedVector2Array in item.glow_rings:
				ci.draw_colored_polygon(ring, NUCLEUS_GLOW_RING)
			ci.draw_colored_polygon(item.plate, NUCLEUS_PLATE)
			ci.draw_polyline(item.plate_rim, NUCLEUS_PLATE_RIM, 2.0 * k, true)

func _rebuild_ghost_line() -> void:
	_g_line_fill.clear()
	_g_line_border.clear()
	var walls: Dictionary = {}
	for cell: Vector2i in _ghost_line:
		var fill: PackedVector2Array = _project(KitDraw.rounded_rect_points(Rect2(Vector2(cell), Vector2.ONE), 0.35, ARC_STEPS))
		_g_line_fill.append(fill)
		_g_line_border.append(_closed(fill))
		walls[cell] = true
	_ghost_canvas.painter = null
	_ghost_canvas.cells = _ghost_line.duplicate()
	_ghost_canvas.walls.rebuild(walls, projection)
	_ghost_group.visible = true
	_ghost_canvas.queue_redraw()


func _show_ghost_wall(cell: Vector2i) -> void:
	_ghost_canvas.painter = null
	_ghost_canvas.cell = cell
	_ghost_canvas.cells = []
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

func _draw_ghost_line(k: float) -> void:
	for i: int in range(_g_line_fill.size()):
		var ok: bool = _ghost_line_ok[i]
		draw_colored_polygon(_g_line_fill[i], GHOST_OK_FILL if ok else GHOST_BAD_FILL)
		draw_polyline(_g_line_border[i], GREEN if ok else RED, 2.0 * k, true)

func _draw_ghost(k: float) -> void:
	if _g_item == null or _g_border.size() < 2:
		return
	if not _ghost_line.is_empty():
		_draw_ghost_line(k)
		return
	var tint: Color = GREEN if _ghost_valid else RED
	for frag: PackedVector2Array in _g_range_fill:
		draw_colored_polygon(frag, RANGE_FILL)
	if not _g_range_dashes.is_empty():
		draw_multiline(_g_range_dashes, RANGE_LINE, 2.0 * k, true)
	draw_colored_polygon(_g_fill, GHOST_OK_FILL if _ghost_valid else GHOST_BAD_FILL)
	if _ghost_valid:
		draw_polyline(_g_border, GHOST_OK_GLOW_OUTER, 10.0 * k, true)
		draw_polyline(_g_border, GHOST_OK_GLOW_INNER, 6.0 * k, true)
	draw_polyline(_g_border, tint, 2.0 * k, true)
	var dot: Color = GHOST_DOT
	for i: int in range(_g_dots.size()):
		dot.a = GHOST_DOT.a * _g_dot_alpha[i]
		draw_circle(_g_dots[i], 1.4 * k, dot)

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
			draw_arc(badge_c, badge_r, 0.0, TAU, 16, MARKER_BADGE_RIM, 1.0, true)
			if font != null:
				var font_size: int = maxi(int(badge_r * 1.5), 9)
				var str_size: Vector2 = font.get_string_size(m.label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
				draw_string(font, Vector2(badge_c.x - str_size.x * 0.5, badge_c.y + str_size.y * 0.35), m.label,
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
	draw_circle(center, badge_r, PREDICTION_FILL)
	draw_arc(center, badge_r, 0.0, TAU, 16, PREDICTION_RIM, 1.5, true)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		var font_size: int = maxi(int(badge_r * 1.4), 10)
		var str_size: Vector2 = font.get_string_size("?", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(center.x - str_size.x * 0.5, center.y + str_size.y * 0.35), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
