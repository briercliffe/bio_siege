class_name WallRenderer
extends RefCounted

## The Mucous Wall as connected, extruded segments (#69, docs/MVP_UI_SPEC.md section 4), ported from the
## wall loop and post model in docs/mockups/canvas/Field.dc.html. Walls are not per-unit sprites: each wall
## cell is a core square plus bridges to its left and up neighbours, so a run of cells reads as one membrane.
##
## Topology (segment_rects, needs_post, height_tiles) is pure and tested. Drawing is split from it:
## rebuild() turns the wall set into screen-space geometry once and bakes each cell part into one cached
## triangle list, so painting a segment or a post is a single polygon command on cached arrays, with no
## allocation and no per-frame triangulation. rebuild() runs only when the wall set, the projection or the
## tile size changes.
##
## The triangle lists go through RenderingServer.canvas_item_add_triangle_array on the CanvasItem being
## drawn, the call draw_polygon makes after triangulating. Do not switch to draw_mesh: on the GL
## Compatibility renderer it costs about 26 us per call, several times a polygon command.
##
## Ground rects are in tile units. Screen heights are tile units times T px, negative y up.

const THICK_T: float = 0.72
const INSET_T: float = (1.0 - THICK_T) * 0.5
const HEIGHT_T: float = 0.8
const HURT_HEIGHT_T: float = 0.55
const POST_HEIGHT_T: float = 1.35
const POST_EVERY: int = 4

## Canvas px are multiples of k = T / 14; in tiles that is 1 / 14.
const K_T: float = 1.0 / 14.0
const STRIPE_W_T: float = 2.0 * K_T
const STRIPE_STEP_T: float = 6.0 * K_T
const TOP_RADIUS_K: float = 0.28
const SHADOW_RADIUS_K: float = 0.25
const TOP_OUTLINE_T: float = 1.3 * K_T
const CAP_RING_T: float = 1.2 * K_T
const SHADOW_OFFSET_T: Vector2 = Vector2(0.5, 0.5)
## Below this tile size the post highlight is skipped.
const DETAIL_T_PX: float = 10.0

## Below this tile size a wall is built coarse: square top corners (the rounding is about 2 px there), no
## face stripes, 8-point ellipses and a post cap shaded per vertex instead of from its focus. Each small
## triangle costs raster setup whatever its size, and the full build made the stress scene slower than the
## old wall boxes (docs/PERF_BASELINE.md).
const FINE_T_PX: float = 28.0
const CORNER_STEPS_FINE: int = 3
const ELLIPSE_POINTS_FINE: int = 18
const ELLIPSE_POINTS_COARSE: int = 8
const GLOSS_POINTS_COARSE: int = 4

const POST_BASE: Rect2 = Rect2(-0.46, -0.24, 0.92, 0.46)
const POST_BODY: Rect2 = Rect2(-0.42, -1.35, 0.84, 1.33)
const POST_CAP: Rect2 = Rect2(-0.42, -1.57, 0.84, 0.44)
const POST_GLOSS: Rect2 = Rect2(-0.16, -1.45, 0.3, 0.14)
const CAP_FOCUS: Vector2 = Vector2(0.4, 0.35)
const CAP_DARK_AT: float = 0.8

## Crossed cracks: the diagonals of the 0.8 T square inset 0.1 T in the tile. A band is |x - y| <= h, so it
## is h * sqrt(2) wide, about 10% of the diagonal (the canvas's 44% to 56% gradient stops).
const CRACK_INSET_T: float = 0.1
const CRACK_SIZE_T: float = 0.8
const CRACK_HALF_W_T: float = 0.08
## Crack alphas are painted from this many cached colour steps between 0 and 1.
const CRACK_ALPHA_STEPS: int = 32

const SHAKE_T: float = 0.05
const SHAKE_RAD_PER_S: float = 60.0

const CHUNK_COUNT: int = 4
const CHUNK_T: float = 0.3
const CHUNK_DIST_T: float = 0.8
const CHUNK_HOP_T: float = 0.6
const CHUNK_ANGLES_DEG: Array[float] = [45.0, 135.0, 225.0, 315.0]
const CHUNK_Y_SQUASH: float = 0.5
const GOO_RECT: Rect2 = Rect2(-0.6, -0.3, 1.2, 0.6)

const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.2)
const LEFT_A: Color = Color("#dccd99")
const LEFT_B: Color = Color("#bfae7a")
const RIGHT_A: Color = Color("#b4a572")
const RIGHT_B: Color = Color("#968758")
const LEFT_STRIPE: Color = Color(0.0, 0.0, 0.0, 0.10)
const RIGHT_STRIPE: Color = Color(0.0, 0.0, 0.0, 0.12)
const TOP_A: Color = Color("#f6ebc3")
const TOP_B: Color = Color("#e2d19b")
const HURT_TOP_A: Color = Color("#d9c993")
const HURT_TOP_B: Color = Color("#c8b67f")
const OUTLINE: Color = Color("#8f8157")
const POST_L: Color = Color("#e0cf9a")
const POST_M: Color = Color("#c9b87f")
const POST_R: Color = Color("#978859")
const CAP_LIGHT: Color = Color("#fff6d2")
const CAP_DARK: Color = Color("#e2d09a")
const GLOSS: Color = Color(1.0, 1.0, 1.0, 0.75)
## The crack colour is opaque here; paint_cracks() takes the alpha (resting or pulsing).
const CRACK: Color = Color(60.0 / 255.0, 40.0 / 255.0, 10.0 / 255.0, 1.0)
const CRACK_ALPHA: float = 0.85
const CHUNK: Color = Color("#dccd99")
const GOO: Color = Color(200.0 / 255.0, 185.0 / 255.0, 138.0 / 255.0, 0.45)

const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## A cached triangle list: every three indices are one triangle, painted in order.
class Tris extends RefCounted:
	var points: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()


## Cached geometry of one wall cell.
class CellGeo extends RefCounted:
	var foot: Vector2 = Vector2.ZERO
	var post: bool = false
	var body: Tris = null
	var body_hurt: Tris = null
	var post_tris: Tris = null
	## The full-height body followed by the post, for one command when nothing sorts between them.
	var body_post: Tris = null
	## The two crack bands as triangles on the full and on the damaged top face.
	var cracks: PackedVector2Array = PackedVector2Array()
	var cracks_hurt: PackedVector2Array = PackedVector2Array()


## Tints the baked colours, for ghost previews. Applied by rebuild(); opaque white is a no-op.
var modulate: Color = Color.WHITE
## Screen offset added to every draw, for painters that bake a lone cell around the local origin.
var offset: Vector2 = Vector2.ZERO

var _cells: Dictionary = {}
var _shadows: Tris = null
var _proj: IsoProjection = null
var _t: float = 14.0

# Geometry-building scratch, only touched inside rebuild().
var _verts: PackedVector2Array = PackedVector2Array()
var _cols: PackedColorArray = PackedColorArray()
var _idx: PackedInt32Array = PackedInt32Array()
var _ring: PackedVector2Array = PackedVector2Array()
var _ring_cols: PackedColorArray = PackedColorArray()
var _corner_steps: int = CORNER_STEPS_FINE
var _ellipse_points: int = ELLIPSE_POINTS_FINE
var _fine: bool = true
## One single-colour array per crack alpha step, and the index list every crack triangle set shares.
var _crack_cols: Array[PackedColorArray] = []
var _crack_indices: PackedInt32Array = PackedInt32Array()


# --- topology ---------------------------------------------------------------

## Ground rects of a wall cell in tile units: the core square, then a bridge to the left neighbour and a
## bridge to the up neighbour when those cells are walls. Right and down joins belong to those neighbours.
static func segment_rects(cell: Vector2i, walls: Dictionary) -> Array[Rect2]:
	var c: Vector2 = Vector2(cell)
	var out: Array[Rect2] = [Rect2(c.x + INSET_T, c.y + INSET_T, THICK_T, THICK_T)]
	if walls.has(cell + Vector2i(-1, 0)):
		out.append(Rect2(c.x - 0.5, c.y + INSET_T, 1.0, THICK_T))
	if walls.has(cell + Vector2i(0, -1)):
		out.append(Rect2(c.x + INSET_T, c.y - 0.5, THICK_T, 1.0))
	return out


## Posts stand at corners, ends and junctions, and on every fourth tile of a straight run. A damaged
## segment never carries a post.
static func needs_post(cell: Vector2i, walls: Dictionary, hurt: bool) -> bool:
	if hurt:
		return false
	var right: bool = walls.has(cell + NEIGHBOURS[0])
	var left: bool = walls.has(cell + NEIGHBOURS[1])
	var down: bool = walls.has(cell + NEIGHBOURS[2])
	var up: bool = walls.has(cell + NEIGHBOURS[3])
	var n: int = int(right) + int(left) + int(down) + int(up)
	var straight: bool = n == 2 and ((left and right) or (up and down))
	return not straight or (cell.x + cell.y) % POST_EVERY == 0


## Extrusion height in tiles: lower once the wall is below half its HP.
static func height_tiles(hp: int, max_hp: int) -> float:
	return HURT_HEIGHT_T if hp * 2 < max_hp else HEIGHT_T


static func is_hurt(hp_frac: float) -> bool:
	return hp_frac < 0.5


# --- cache ------------------------------------------------------------------

## Rebuilds all cached geometry from `walls` (Vector2i -> true, the live wall cells) under `projection`.
func rebuild(walls: Dictionary, projection: IsoProjection) -> void:
	_proj = projection
	_t = projection.tile_px
	_fine = _t >= FINE_T_PX
	_corner_steps = CORNER_STEPS_FINE if _fine else 0
	_ellipse_points = ELLIPSE_POINTS_FINE if _fine else ELLIPSE_POINTS_COARSE
	_build_crack_colours()
	_cells.clear()
	_begin()
	for cell_var: Variant in walls:
		var cell: Vector2i = cell_var
		for q: Rect2 in segment_rects(cell, walls):
			_add_shadow(q)
	_shadows = _commit()
	for cell_var: Variant in walls:
		var cell: Vector2i = cell_var
		var geo := CellGeo.new()
		geo.foot = projection.cell_center(cell)
		geo.post = needs_post(cell, walls, false)
		var rects: Array[Rect2] = segment_rects(cell, walls)
		# A neighbour's bridge always covers the core face on that side, and it is painted later.
		var covered := Vector2i(int(walls.has(cell + NEIGHBOURS[0])), int(walls.has(cell + NEIGHBOURS[2])))
		geo.body = _build_body(rects, HEIGHT_T, false, covered)
		geo.body_hurt = _build_body(rects, HURT_HEIGHT_T, true, covered)
		if geo.post:
			geo.post_tris = _build_post(geo.foot)
			geo.body_post = _join(geo.body, geo.post_tris)
		geo.cracks = _build_cracks(cell, -HEIGHT_T * _t)
		geo.cracks_hurt = _build_cracks(cell, -HURT_HEIGHT_T * _t)
		_cells[cell] = geo


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func cell_count() -> int:
	return _cells.size()


## True when the cell carries a post at full health (the cached needs_post result).
func has_post(cell: Vector2i) -> bool:
	var geo: CellGeo = _cells.get(cell)
	return geo != null and geo.post


func tile_px() -> float:
	return _t


## The cached geometry of a cell, or null when it is not a live wall cell.
func cell_geo(cell: Vector2i) -> CellGeo:
	return _cells.get(cell)


# --- painting ---------------------------------------------------------------

## Everything for one cell in a pass with no units to interleave (Synthesis, the viewer): faces and top,
## then the post (full health only), then the cracks (below half HP).
func paint_cell(ci: CanvasItem, cell: Vector2i, hp_frac: float, pose: ModelPose) -> void:
	var hurt: bool = is_hurt(hp_frac)
	if not hurt:
		paint_body_and_post(ci, cell, pose)
		return
	paint_body(ci, cell, true, pose)
	paint_cracks(ci, cell, true, CRACK_ALPHA, pose)


## Faces, stripes and top of one cell, at the full or the damaged height.
func paint_body(ci: CanvasItem, cell: Vector2i, hurt: bool, pose: ModelPose) -> void:
	var geo: CellGeo = _cells.get(cell)
	if geo == null:
		return
	_paint_tris(ci, geo.body_hurt if hurt else geo.body, Vector2(_shake_px(pose), 0.0))


func paint_post(ci: CanvasItem, cell: Vector2i, pose: ModelPose) -> void:
	var geo: CellGeo = _cells.get(cell)
	if geo == null or geo.post_tris == null:
		return
	_paint_tris(ci, geo.post_tris, Vector2(_shake_px(pose), 0.0))


## The full-height body and its post (if any) in one command, the same paint order as paint_body() then
## paint_post().
func paint_body_and_post(ci: CanvasItem, cell: Vector2i, pose: ModelPose) -> void:
	var geo: CellGeo = _cells.get(cell)
	if geo == null:
		return
	_paint_tris(ci, geo.body_post if geo.body_post != null else geo.body, Vector2(_shake_px(pose), 0.0))


## Crossed cracks on the top face. `alpha` is the crack colour alpha (0.85 at rest, pulsing while a
## pathogen is breaking the wall), painted from the nearest of CRACK_ALPHA_STEPS cached steps.
func paint_cracks(ci: CanvasItem, cell: Vector2i, hurt: bool, alpha: float, pose: ModelPose) -> void:
	var geo: CellGeo = _cells.get(cell)
	if geo == null or _crack_cols.is_empty():
		return
	var step: int = clampi(roundi(alpha * CRACK_ALPHA_STEPS), 0, CRACK_ALPHA_STEPS)
	var moved: Vector2 = offset + Vector2(_shake_px(pose), 0.0)
	if moved != Vector2.ZERO:
		ci.draw_set_transform(moved)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _crack_indices,
		geo.cracks_hurt if hurt else geo.cracks, _crack_cols[step])
	if moved != Vector2.ZERO:
		ci.draw_set_transform(Vector2.ZERO)


## Every cached ground shadow in one draw, on the ground pass before any depth-sorted item.
func paint_shadows(ci: CanvasItem) -> void:
	_paint_tris(ci, _shadows, Vector2.ZERO)


## Break effect at a destroyed cell, `death_t` 0..1 over DEATH_TICKS["mucous_wall"]: four tan chunks fly
## out on fixed diagonals with a parabolic hop, fading. The cell does not need to be in the cache.
func paint_break(ci: CanvasItem, cell: Vector2i, death_t: float) -> void:
	if _proj == null or death_t >= 1.0:
		return
	var d: float = clampf(death_t, 0.0, 1.0)
	var start: Vector2 = _proj.cell_center(cell) + offset + Vector2(0.0, -HEIGHT_T * 0.5 * _t)
	var size: float = CHUNK_T * _t
	var hop: float = CHUNK_HOP_T * _t * 4.0 * d * (1.0 - d)
	var col := Color(CHUNK, CHUNK.a * (1.0 - d))
	for a_deg: float in CHUNK_ANGLES_DEG:
		var a: float = deg_to_rad(a_deg)
		var dir := Vector2(cos(a), -sin(a) * CHUNK_Y_SQUASH)
		var c: Vector2 = start + dir * CHUNK_DIST_T * _t * d + Vector2(0.0, -hop)
		ci.draw_rect(Rect2(c.x - size * 0.5, c.y - size * 0.5, size, size), col)


## The goo decal a destroyed cell leaves on the ground. `alpha` scales its colour (0..1).
func paint_goo(ci: CanvasItem, cell: Vector2i, alpha: float = 1.0) -> void:
	if _proj == null or alpha <= 0.0:
		return
	var foot: Vector2 = _proj.cell_center(cell) + offset
	PaintKit.ellipse(ci, PaintKit.part_rect(foot, _t, GOO_RECT.position.x, GOO_RECT.position.y, GOO_RECT.size.x, GOO_RECT.size.y),
		Color(GOO, GOO.a * alpha))


func _paint_tris(ci: CanvasItem, tris: Tris, shift: Vector2) -> void:
	if tris == null:
		return
	var moved: Vector2 = offset + shift
	if moved != Vector2.ZERO:
		ci.draw_set_transform(moved)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), tris.indices, tris.points, tris.colors)
	if moved != Vector2.ZERO:
		ci.draw_set_transform(Vector2.ZERO)


func _shake_px(pose: ModelPose) -> float:
	if pose == null or pose.shake <= 0.0:
		return 0.0
	return sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * _t * pose.shake


# --- geometry building (rebuild only) ----------------------------------------

func _begin() -> void:
	_verts = PackedVector2Array()
	_cols = PackedColorArray()
	_idx = PackedInt32Array()


func _commit() -> Tris:
	if _idx.is_empty():
		return null
	var tris := Tris.new()
	tris.points = _verts
	tris.colors = _cols
	tris.indices = _idx
	if modulate != Color.WHITE:
		for i: int in range(tris.colors.size()):
			tris.colors[i] *= modulate
	return tris


## Appends a vertex and returns its index. Shapes share their corner vertices through the index list.
func _vert(p: Vector2, col: Color) -> int:
	_verts.append(p)
	_cols.append(col)
	return _verts.size() - 1


func _tri_idx(a: int, b: int, c: int) -> void:
	_idx.append(a)
	_idx.append(b)
	_idx.append(c)


## Quad a-b-c-d in order around its edge, one colour per corner.
func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var ia: int = _vert(a, ca)
	var ib: int = _vert(b, cb)
	var ic: int = _vert(c, cc)
	var id: int = _vert(d, cd)
	_tri_idx(ia, ib, ic)
	_tri_idx(ia, ic, id)


## Triangle fan over the convex ring in _ring / _ring_cols around `centre`.
func _fan(centre: Vector2, centre_col: Color) -> void:
	var ic: int = _vert(centre, centre_col)
	var first: int = _verts.size()
	var n: int = _ring.size()
	for i: int in range(n):
		_vert(_ring[i], _ring_cols[i])
	for i: int in range(n):
		_tri_idx(ic, first + i, first + (i + 1) % n)


## Fills the convex ring in _ring / _ring_cols from its first point. Colours are interpolated linearly, so
## any triangulation reproduces a linear gradient exactly; only a radial one needs _fan's centre point.
func _fill_convex() -> void:
	var first: int = _verts.size()
	for i: int in range(_ring.size()):
		_vert(_ring[i], _ring_cols[i])
	for i: int in range(1, _ring.size() - 1):
		_tri_idx(first, first + i, first + i + 1)


func _ground(g: Vector2, lift_px: float) -> Vector2:
	return _proj.ground_to_screen(g) + Vector2(0.0, lift_px)


## Outline of a rounded rect in ground tile units, clockwise from the top-right corner. Square when the
## build is coarse.
func _corner_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if _corner_steps <= 0:
		out.append(Vector2(rect.end.x, rect.position.y))
		out.append(rect.end)
		out.append(Vector2(rect.position.x, rect.end.y))
		out.append(rect.position)
		return out
	var r: float = clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var corners: Array[Vector2] = [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r),
	]
	for k: int in range(4):
		var start: float = -PI * 0.5 + float(k) * PI * 0.5
		for s: int in range(_corner_steps + 1):
			var a: float = start + PI * 0.5 * float(s) / float(_corner_steps)
			out.append(corners[k] + Vector2(cos(a), sin(a)) * r)
	return out


## Rounded rect in ground tile units, projected and lifted, into _ring (colour left to the caller).
func _rounded_ring(rect: Rect2, radius: float, lift_px: float) -> void:
	_ring = PackedVector2Array()
	for g: Vector2 in _corner_points(rect, radius):
		_ring.append(_ground(g, lift_px))


func _add_shadow(q: Rect2) -> void:
	var rect := Rect2(q.position + SHADOW_OFFSET_T, q.size)
	_rounded_ring(rect, SHADOW_RADIUS_K * THICK_T, 0.0)
	_ring_cols = PackedColorArray()
	for i: int in range(_ring.size()):
		_ring_cols.append(SHADOW)
	_fill_convex()


## `covered` flags the core's right (x) and front-left (y) faces as hidden by a neighbour's bridge.
func _build_body(rects: Array[Rect2], h_t: float, hurt: bool, covered: Vector2i) -> Tris:
	_begin()
	var h: float = -h_t * _t
	var stripes: bool = _t >= FINE_T_PX
	for i: int in range(rects.size()):
		var q: Rect2 = rects[i]
		var x0: float = q.position.x
		var y0: float = q.position.y
		var x1: float = q.end.x
		var y1: float = q.end.y
		# Front-left face: the +y edge, lit.
		var a := Vector2(x0, y1)
		var b := Vector2(x1, y1)
		if i != 0 or covered.y == 0:
			_quad(_ground(a, h), _ground(b, h), _ground(b, 0.0), _ground(a, 0.0), LEFT_A, LEFT_A, LEFT_B, LEFT_B)
			if stripes:
				_add_stripes(a, b, h, LEFT_STRIPE)
		# Front-right face: the +x edge, in shade.
		a = Vector2(x1, y0)
		b = Vector2(x1, y1)
		if i != 0 or covered.x == 0:
			_quad(_ground(a, h), _ground(b, h), _ground(b, 0.0), _ground(a, 0.0), RIGHT_A, RIGHT_A, RIGHT_B, RIGHT_B)
			if stripes:
				_add_stripes(a, b, h, RIGHT_STRIPE)
		# Glossy top with its outline ring, drawn as a slightly larger dark rect underneath.
		var e: float = TOP_OUTLINE_T
		var radius: float = TOP_RADIUS_K * THICK_T
		_rounded_ring(Rect2(x0 - e, y0 - e, q.size.x + e * 2.0, q.size.y + e * 2.0), radius + e, h)
		_ring_cols = PackedColorArray()
		for _j: int in range(_ring.size()):
			_ring_cols.append(OUTLINE)
		_fill_convex()
		_add_top(q, radius, h, HURT_TOP_A if hurt else TOP_A, HURT_TOP_B if hurt else TOP_B)
	return _commit()


## The 135-degree gradient: `ca` at the rect's ground origin corner, `cb` at the far corner.
func _add_top(q: Rect2, radius: float, h: float, ca: Color, cb: Color) -> void:
	_ring = PackedVector2Array()
	_ring_cols = PackedColorArray()
	var span: float = q.size.x + q.size.y
	for g: Vector2 in _corner_points(q, radius):
		_ring.append(_ground(g, h))
		_ring_cols.append(ca.lerp(cb, clampf(((g.x - q.position.x) + (g.y - q.position.y)) / span, 0.0, 1.0)))
	_fill_convex()


## Vertical stripes along the ground edge a -> b, 2k wide every 6k, full face height.
func _add_stripes(a: Vector2, b: Vector2, h: float, col: Color) -> void:
	var length: float = a.distance_to(b)
	var dir: Vector2 = (b - a) / length
	var u: float = 0.0
	while u < length:
		var u1: float = minf(u + STRIPE_W_T, length)
		var p0: Vector2 = a + dir * u
		var p1: Vector2 = a + dir * u1
		_quad(_ground(p0, h), _ground(p1, h), _ground(p1, 0.0), _ground(p0, 0.0), col, col, col, col)
		u += STRIPE_STEP_T


func _build_post(foot: Vector2) -> Tris:
	_begin()
	var t: float = _t
	_add_ellipse(PaintKit.part_rect(foot, t, POST_BASE.position.x, POST_BASE.position.y, POST_BASE.size.x, POST_BASE.size.y), OUTLINE)
	var body: Rect2 = PaintKit.part_rect(foot, t, POST_BODY.position.x, POST_BODY.position.y, POST_BODY.size.x, POST_BODY.size.y)
	var mid: float = body.position.x + body.size.x * 0.5
	var y0: float = body.position.y
	var y1: float = body.end.y
	_quad(Vector2(body.position.x, y0), Vector2(mid, y0), Vector2(mid, y1), Vector2(body.position.x, y1), POST_L, POST_M, POST_M, POST_L)
	_quad(Vector2(mid, y0), Vector2(body.end.x, y0), Vector2(body.end.x, y1), Vector2(mid, y1), POST_M, POST_R, POST_R, POST_M)
	var cap: Rect2 = PaintKit.part_rect(foot, t, POST_CAP.position.x, POST_CAP.position.y, POST_CAP.size.x, POST_CAP.size.y)
	_add_ellipse(cap.grow(CAP_RING_T * t), OUTLINE)
	_add_cap(cap)
	if t >= DETAIL_T_PX:
		_add_ellipse(PaintKit.part_rect(foot, t, POST_GLOSS.position.x, POST_GLOSS.position.y, POST_GLOSS.size.x, POST_GLOSS.size.y), GLOSS,
			_ellipse_points if _fine else GLOSS_POINTS_COARSE)
	return _commit()


func _ellipse_ring(rect: Rect2, points: int) -> void:
	_ring = PackedVector2Array()
	var c: Vector2 = rect.get_center()
	var r: Vector2 = rect.size * 0.5
	for i: int in range(points):
		var a: float = float(i) / float(points) * TAU
		_ring.append(c + Vector2(cos(a), sin(a)) * r)


func _add_ellipse(rect: Rect2, col: Color, points: int = -1) -> void:
	_ellipse_ring(rect, _ellipse_points if points < 0 else points)
	_ring_cols = PackedColorArray()
	for i: int in range(_ring.size()):
		_ring_cols.append(col)
	_fill_convex()


## radial-gradient(circle at 40% 35%, light, dark 80%): a fan from the offset focus. The coarse build
## shades the rim only and fills without the focus point.
func _add_cap(rect: Rect2) -> void:
	_ellipse_ring(rect, _ellipse_points)
	var focus: Vector2 = rect.position + rect.size * CAP_FOCUS
	var far: float = (rect.size * (Vector2.ONE - CAP_FOCUS)).length()
	_ring_cols = PackedColorArray()
	for p: Vector2 in _ring:
		_ring_cols.append(CAP_LIGHT.lerp(CAP_DARK, clampf(p.distance_to(focus) / (far * CAP_DARK_AT), 0.0, 1.0)))
	if _fine:
		_fan(focus, CAP_LIGHT)
	else:
		_fill_convex()


## `a` followed by `b` as one triangle list; either may be null.
func _join(a: Tris, b: Tris) -> Tris:
	if a == null or b == null:
		return b if a == null else a
	var out := Tris.new()
	out.points = a.points + b.points
	out.colors = a.colors + b.colors
	out.indices = a.indices.duplicate()
	var base: int = a.points.size()
	for i: int in b.indices:
		out.indices.append(base + i)
	return out


func _build_crack_colours() -> void:
	_crack_cols.clear()
	for step: int in range(CRACK_ALPHA_STEPS + 1):
		var a: float = float(step) / float(CRACK_ALPHA_STEPS)
		_crack_cols.append(PackedColorArray([Color(CRACK.r * modulate.r, CRACK.g * modulate.g, CRACK.b * modulate.b, a * modulate.a)]))


## Two diagonal bands across the crack square on the top face at `lift_px`, as one triangle list.
func _build_cracks(cell: Vector2i, lift_px: float) -> PackedVector2Array:
	var o: Vector2 = Vector2(cell) + Vector2(CRACK_INSET_T, CRACK_INSET_T)
	var s: float = CRACK_SIZE_T
	var h: float = CRACK_HALF_W_T
	# Band along (1, 1): |x - y| <= h inside the square, a convex hexagon.
	var along: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(h, 0.0), Vector2(s, s - h), Vector2(s, s), Vector2(s - h, s), Vector2(0.0, h)]
	# Band along (1, -1): |x + y - s| <= h.
	var across: Array[Vector2] = [Vector2(s, 0.0), Vector2(s, h), Vector2(h, s), Vector2(0.0, s), Vector2(0.0, s - h), Vector2(s - h, 0.0)]
	var out := PackedVector2Array()
	for p: Vector2 in along + across:
		out.append(_ground(o + p, lift_px))
	if _crack_indices.is_empty():
		# Each hexagon fanned from its first corner.
		for band: int in range(2):
			var first: int = band * along.size()
			for i: int in range(1, along.size() - 1):
				_crack_indices.append(first)
				_crack_indices.append(first + i)
				_crack_indices.append(first + i + 1)
	return out
