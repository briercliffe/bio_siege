class_name PlaceholderBillboard
extends RefCounted

## Stand-in models drawn in screen space until the real painters land (#67 to #70).
## Also reused by the battle view (#64). Wall faces are built once, then drawn many times.

const WALL_HEIGHT_T: float = 0.8
const GHOST_OPACITY: float = 0.75
const WALL_TOP: Color = Color("#ecdfaa")
const WALL_LEFT_A: Color = Color("#dccd99")
const WALL_LEFT_B: Color = Color("#bfae7a")
const WALL_RIGHT_A: Color = Color("#b4a572")
const WALL_RIGHT_B: Color = Color("#968758")

static var _left_cols: PackedColorArray = PackedColorArray([WALL_LEFT_A, WALL_LEFT_A, WALL_LEFT_B, WALL_LEFT_B])
static var _right_cols: PackedColorArray = PackedColorArray([WALL_RIGHT_A, WALL_RIGHT_A, WALL_RIGHT_B, WALL_RIGHT_B])
static var _left_cols_ghost: PackedColorArray = _faded(_left_cols)
static var _right_cols_ghost: PackedColorArray = _faded(_right_cols)

## Draws a placeholder shape whose bottom-centre sits on `foot`.
static func draw_billboard(ci: CanvasItem, shape: String, color: Color, foot: Vector2, width: float, height: float) -> void:
	PlaceholderShapes.draw_shape(ci, shape, Rect2(foot.x - width * 0.5, foot.y - height, width, height), color)

## The three faces of one extruded wall tile: [left, right, top]. `cell` is the tile's ground cell.
static func wall_faces(proj: IsoProjection, cell: Vector2i) -> Array[PackedVector2Array]:
	var lift := Vector2(0.0, -WALL_HEIGHT_T * proj.tile_px)
	var c: Vector2 = Vector2(cell)
	var n: Vector2 = proj.ground_to_screen(c)
	var e: Vector2 = proj.ground_to_screen(c + Vector2(1.0, 0.0))
	var s: Vector2 = proj.ground_to_screen(c + Vector2(1.0, 1.0))
	var w: Vector2 = proj.ground_to_screen(c + Vector2(0.0, 1.0))
	var faces: Array[PackedVector2Array] = []
	faces.append(PackedVector2Array([w + lift, s + lift, s, w]))
	faces.append(PackedVector2Array([s + lift, e + lift, e, s]))
	faces.append(PackedVector2Array([n + lift, e + lift, s + lift, w + lift]))
	return faces

static func draw_wall_faces(ci: CanvasItem, faces: Array[PackedVector2Array], ghost: bool = false) -> void:
	ci.draw_polygon(faces[0], _left_cols_ghost if ghost else _left_cols)
	ci.draw_polygon(faces[1], _right_cols_ghost if ghost else _right_cols)
	var top: Color = WALL_TOP
	if ghost:
		top.a = GHOST_OPACITY
	ci.draw_colored_polygon(faces[2], top)

static func _faded(cols: PackedColorArray) -> PackedColorArray:
	var out := PackedColorArray()
	for c: Color in cols:
		out.append(Color(c.r, c.g, c.b, GHOST_OPACITY))
	return out
