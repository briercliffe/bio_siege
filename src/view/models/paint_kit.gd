class_name PaintKit
extends RefCounted

## Drawing helpers for model painters, ported from the design canvas (docs/MODEL_PIPELINE_PLAN.md
## section 7.2). Every helper takes the CanvasItem and pixel coordinates. Point arrays are cached or
## reused, so a call allocates nothing beyond the engine's own draw command.
##
## Mirroring: painters draw facing right. For facing left call
## ci.draw_set_transform(anchor, 0.0, Vector2(-1, 1)), draw at the local origin, then reset with
## ci.draw_set_transform(Vector2.ZERO). Mirror the placement, never the lighting: draw highlight parts
## with x negated back. Do not copy the canvas's per-part flip; it breaks clip-path shapes.

const ELLIPSE_POINTS: int = 24
const CIRCLE_TOLERANCE_PX: float = 0.01

const HEX_01: PackedVector2Array = [
	Vector2(0.5, 0.0), Vector2(1.0, 0.25), Vector2(1.0, 0.75),
	Vector2(0.5, 1.0), Vector2(0.0, 0.75), Vector2(0.0, 0.25),
]

static var _unit_circle: PackedVector2Array = _build_unit_circle()
static var _scratch: PackedVector2Array = PackedVector2Array()
static var _quad: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _hex_pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _hex_cols: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
static var _quad_cols: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])


static func _build_unit_circle() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in range(ELLIPSE_POINTS):
		var a: float = float(i) / float(ELLIPSE_POINTS) * TAU
		out.append(Vector2(cos(a), sin(a)))
	return out


## The canvas P(dx, dy, w, h): a rect in tile units relative to the ground anchor.
static func part_rect(anchor: Vector2, t_px: float, dx: float, dy: float, w: float, h: float) -> Rect2:
	return Rect2(anchor.x + dx * t_px, anchor.y + dy * t_px, w * t_px, h * t_px)


static func ellipse(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var c: Vector2 = rect.get_center()
	var r: Vector2 = rect.size * 0.5
	# A circle takes the engine's fast path: draw_colored_polygon triangulates on the CPU every call, which
	# dominated the 200-unit bench (docs/PERF_BASELINE.md).
	if absf(r.x - r.y) < CIRCLE_TOLERANCE_PX:
		ci.draw_circle(c, r.x, color)
		return
	if _scratch.size() != ELLIPSE_POINTS:
		_scratch.resize(ELLIPSE_POINTS)
	for i: int in range(ELLIPSE_POINTS):
		_scratch[i] = c + _unit_circle[i] * r
	ci.draw_colored_polygon(_scratch, color)


## Fakes radial-gradient(circle at 34% 28%, light 0, mid 55%, dark 100%) with four stacked ellipses.
static func sphere(ci: CanvasItem, rect: Rect2, light: Color, mid: Color, dark: Color) -> void:
	ellipse(ci, rect, dark)
	ellipse(ci, _scaled(rect, 0.86, Vector2(-0.04, -0.05)), mid)
	ellipse(ci, _scaled(rect, 0.55, Vector2(-0.12, -0.15)), mid.lerp(light, 0.5))
	ellipse(ci, _scaled(rect, 0.25, Vector2(-0.18, -0.24)), light)


## `rect` scaled about its centre, then moved by `offset` times its size.
static func _scaled(rect: Rect2, factor: float, offset: Vector2) -> Rect2:
	var size: Vector2 = rect.size * factor
	var c: Vector2 = rect.get_center() + offset * rect.size
	return Rect2(c - size * 0.5, size)


## The canvas B(...): a rounded bar from `a` to `b`.
static func bar(ci: CanvasItem, a: Vector2, b: Vector2, thickness_px: float, color: Color) -> void:
	ci.draw_line(a, b, color, thickness_px)
	var r: float = thickness_px * 0.5
	ci.draw_circle(a, r, color)
	ci.draw_circle(b, r, color)


static func hex(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	clip_poly(ci, rect, HEX_01, color)


## Hexagon with a vertical gradient: `top` at the top vertex, `mid` at `mid_at` (0..1 of the height) and
## `bottom` at the bottom vertex, interpolated per vertex. The shading a canvas linear-gradient clipped to HEX gives.
static func hex_gradient(ci: CanvasItem, rect: Rect2, top: Color, mid: Color, bottom: Color, mid_at: float = 0.55) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var upper: Color = top.lerp(mid, 0.25 / mid_at)
	var lower: Color = mid.lerp(bottom, (0.75 - mid_at) / (1.0 - mid_at))
	for i: int in range(6):
		_hex_pts[i] = rect.position + HEX_01[i] * rect.size
	_hex_cols[0] = top
	_hex_cols[1] = upper
	_hex_cols[2] = lower
	_hex_cols[3] = bottom
	_hex_cols[4] = lower
	_hex_cols[5] = upper
	ci.draw_polygon(_hex_pts, _hex_cols)


## Maps 0..1 points into `rect`, the way the canvas clip-path does.
static func clip_poly(ci: CanvasItem, rect: Rect2, points_01: PackedVector2Array, color: Color) -> void:
	var n: int = points_01.size()
	if n < 3 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if _scratch.size() != n:
		_scratch.resize(n)
	for i: int in range(n):
		_scratch[i] = rect.position + points_01[i] * rect.size
	ci.draw_colored_polygon(_scratch, color)


## Short cylinder pedestal. `half` is the radius, `y0` the ground level, all in tiles.
## cols = [bottom ellipse, body left, body middle, body right, top ellipse]; a 4-entry list reuses the
## middle body colour for the top.
static func cylinder(ci: CanvasItem, anchor: Vector2, t_px: float, half: float, y0: float, height: float, cols: Array[Color]) -> void:
	if cols.size() < 4:
		return
	var top_col: Color = cols[4] if cols.size() > 4 else cols[2]
	ellipse(ci, part_rect(anchor, t_px, -half, y0 - 0.45, half * 2.0, 0.7), cols[0])
	var body: Rect2 = part_rect(anchor, t_px, -half, y0 - 0.45 - height, half * 2.0, height + 0.35)
	var mid_x: float = body.position.x + body.size.x * 0.5
	_fill_quad(ci, body.position.x, mid_x, body.position.y, body.end.y, cols[1], cols[2], cols[1], cols[2])
	_fill_quad(ci, mid_x, body.end.x, body.position.y, body.end.y, cols[2], cols[3], cols[2], cols[3])
	ellipse(ci, part_rect(anchor, t_px, -half, y0 - 0.8 - height, half * 2.0, 0.7), top_col)


static func vertical_gradient_rect(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	_fill_quad(ci, rect.position.x, rect.end.x, rect.position.y, rect.end.y, top, top, bottom, bottom)


static func horizontal_gradient_rect(ci: CanvasItem, rect: Rect2, left: Color, right: Color) -> void:
	_fill_quad(ci, rect.position.x, rect.end.x, rect.position.y, rect.end.y, left, right, left, right)


## Quad with one colour per corner: top-left, top-right, bottom-left, bottom-right.
static func _fill_quad(ci: CanvasItem, x0: float, x1: float, y0: float, y1: float, c_tl: Color, c_tr: Color, c_bl: Color, c_br: Color) -> void:
	_quad[0] = Vector2(x0, y0)
	_quad[1] = Vector2(x1, y0)
	_quad[2] = Vector2(x1, y1)
	_quad[3] = Vector2(x0, y1)
	_quad_cols[0] = c_tl
	_quad_cols[1] = c_tr
	_quad_cols[2] = c_br
	_quad_cols[3] = c_bl
	ci.draw_polygon(_quad, _quad_cols)
