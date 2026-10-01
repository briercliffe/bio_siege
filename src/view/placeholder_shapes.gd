class_name PlaceholderShapes
extends RefCounted

# Scratch geometry shared by every call; the draw commands copy their points, so drawing allocates nothing.
static var _tri: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _tri_line: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _quad: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _quad_line: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _rounded: StyleBoxFlat = null

static func draw_shape(ci: CanvasItem, shape: String, rect: Rect2, color: Color) -> void:
	if ci == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var outline_color: Color = color.darkened(0.4)

	match shape:
		"square":
			_draw_square(ci, rect, color, outline_color)
		"rounded_square":
			_draw_rounded_square(ci, rect, color, outline_color)
		"circle":
			_draw_circle(ci, rect, color, outline_color)
		"triangle":
			_draw_triangle(ci, rect, color, outline_color)
		"diamond":
			_draw_diamond(ci, rect, color, outline_color)
		"lander":
			_draw_lander(ci, rect, color, outline_color)
		"cluster":
			_draw_cluster(ci, rect, color, outline_color)
		_:
			_draw_square(ci, rect, color, outline_color)

static func _draw_square(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var inset: Rect2 = rect.grow(-2.0) if rect.size.x > 4.0 and rect.size.y > 4.0 else rect
	ci.draw_rect(inset, color, true)
	ci.draw_rect(inset, outline_color, false, 2.0)

static func _draw_rounded_square(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	if _rounded == null:
		_rounded = StyleBoxFlat.new()
	var style: StyleBoxFlat = _rounded
	style.bg_color = color
	var radius: int = int(rect.size.x * 0.25)
	style.set_corner_radius_all(radius)
	style.set_border_width_all(2)
	style.border_color = outline_color
	style.draw(ci.get_canvas_item(), rect)

static func _draw_circle(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var center: Vector2 = rect.get_center()
	var radius: float = 0.4 * minf(rect.size.x, rect.size.y)
	ci.draw_circle(center, radius, color)
	ci.draw_arc(center, radius, 0.0, TAU, 32, outline_color, 2.0, true)

static func _draw_triangle(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var inset: Rect2 = rect.grow(-2.0) if rect.size.x > 4.0 and rect.size.y > 4.0 else rect
	var p_top := Vector2(inset.position.x + inset.size.x * 0.5, inset.position.y)
	var p_br := Vector2(inset.position.x + inset.size.x, inset.position.y + inset.size.y)
	var p_bl := Vector2(inset.position.x, inset.position.y + inset.size.y)
	_tri[0] = p_top
	_tri[1] = p_br
	_tri[2] = p_bl
	_tri_line[0] = p_top
	_tri_line[1] = p_br
	_tri_line[2] = p_bl
	_tri_line[3] = p_top
	ci.draw_colored_polygon(_tri, color)
	ci.draw_polyline(_tri_line, outline_color, 2.0, true)

static func _draw_diamond(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var inset: Rect2 = rect.grow(-2.0) if rect.size.x > 4.0 and rect.size.y > 4.0 else rect
	var p_top := Vector2(inset.position.x + inset.size.x * 0.5, inset.position.y)
	var p_right := Vector2(inset.position.x + inset.size.x, inset.position.y + inset.size.y * 0.5)
	var p_bottom := Vector2(inset.position.x + inset.size.x * 0.5, inset.position.y + inset.size.y)
	var p_left := Vector2(inset.position.x, inset.position.y + inset.size.y * 0.5)
	_draw_kite(ci, p_top, p_right, p_bottom, p_left, color, outline_color)

static func _draw_lander(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var top_h: float = rect.size.y * 0.55
	var top_rect := Rect2(rect.position.x, rect.position.y, rect.size.x, top_h)
	var top_inset: Rect2 = top_rect.grow(-2.0) if top_rect.size.x > 4.0 and top_rect.size.y > 4.0 else top_rect
	var p_top := Vector2(top_inset.position.x + top_inset.size.x * 0.5, top_inset.position.y)
	var p_right := Vector2(top_inset.position.x + top_inset.size.x, top_inset.position.y + top_inset.size.y * 0.5)
	var p_bottom := Vector2(top_inset.position.x + top_inset.size.x * 0.5, top_inset.position.y + top_inset.size.y)
	var p_left := Vector2(top_inset.position.x, top_inset.position.y + top_inset.size.y * 0.5)

	_draw_kite(ci, p_top, p_right, p_bottom, p_left, color, outline_color)

	var leg_bl := Vector2(rect.position.x + 2.0, rect.position.y + rect.size.y - 2.0)
	var leg_bc := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y - 2.0)
	var leg_br := Vector2(rect.position.x + rect.size.x - 2.0, rect.position.y + rect.size.y - 2.0)
	ci.draw_line(p_bottom, leg_bl, outline_color, 2.0, true)
	ci.draw_line(p_bottom, leg_bc, outline_color, 2.0, true)
	ci.draw_line(p_bottom, leg_br, outline_color, 2.0, true)

static func _draw_cluster(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var size: float = minf(rect.size.x, rect.size.y)
	var r: float = 0.22 * size
	var center: Vector2 = rect.get_center()
	var offset: float = r * 0.85
	var c1 := center + Vector2(0.0, -offset)
	var c2 := center + Vector2(-offset * 0.866025, offset * 0.5)
	var c3 := center + Vector2(offset * 0.866025, offset * 0.5)

	_draw_ball(ci, c1, r, color, outline_color)
	_draw_ball(ci, c2, r, color, outline_color)
	_draw_ball(ci, c3, r, color, outline_color)

static func _draw_ball(ci: CanvasItem, c: Vector2, r: float, color: Color, outline_color: Color) -> void:
	ci.draw_circle(c, r, color)
	ci.draw_arc(c, r, 0.0, TAU, 24, outline_color, 2.0, true)

static func _draw_kite(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color, outline_color: Color) -> void:
	_quad[0] = a
	_quad[1] = b
	_quad[2] = c
	_quad[3] = d
	for i: int in range(4):
		_quad_line[i] = _quad[i]
	_quad_line[4] = a
	ci.draw_colored_polygon(_quad, color)
	ci.draw_polyline(_quad_line, outline_color, 2.0, true)
