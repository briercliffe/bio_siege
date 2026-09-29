class_name PlaceholderShapes
extends RefCounted

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
	var style := StyleBoxFlat.new()
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
	ci.draw_colored_polygon(PackedVector2Array([p_top, p_br, p_bl]), color)
	ci.draw_polyline(PackedVector2Array([p_top, p_br, p_bl, p_top]), outline_color, 2.0, true)

static func _draw_diamond(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var inset: Rect2 = rect.grow(-2.0) if rect.size.x > 4.0 and rect.size.y > 4.0 else rect
	var p_top := Vector2(inset.position.x + inset.size.x * 0.5, inset.position.y)
	var p_right := Vector2(inset.position.x + inset.size.x, inset.position.y + inset.size.y * 0.5)
	var p_bottom := Vector2(inset.position.x + inset.size.x * 0.5, inset.position.y + inset.size.y)
	var p_left := Vector2(inset.position.x, inset.position.y + inset.size.y * 0.5)
	ci.draw_colored_polygon(PackedVector2Array([p_top, p_right, p_bottom, p_left]), color)
	ci.draw_polyline(PackedVector2Array([p_top, p_right, p_bottom, p_left, p_top]), outline_color, 2.0, true)

static func _draw_lander(ci: CanvasItem, rect: Rect2, color: Color, outline_color: Color) -> void:
	var top_h: float = rect.size.y * 0.55
	var top_rect := Rect2(rect.position.x, rect.position.y, rect.size.x, top_h)
	var top_inset: Rect2 = top_rect.grow(-2.0) if top_rect.size.x > 4.0 and top_rect.size.y > 4.0 else top_rect
	var p_top := Vector2(top_inset.position.x + top_inset.size.x * 0.5, top_inset.position.y)
	var p_right := Vector2(top_inset.position.x + top_inset.size.x, top_inset.position.y + top_inset.size.y * 0.5)
	var p_bottom := Vector2(top_inset.position.x + top_inset.size.x * 0.5, top_inset.position.y + top_inset.size.y)
	var p_left := Vector2(top_inset.position.x, top_inset.position.y + top_inset.size.y * 0.5)

	ci.draw_colored_polygon(PackedVector2Array([p_top, p_right, p_bottom, p_left]), color)
	ci.draw_polyline(PackedVector2Array([p_top, p_right, p_bottom, p_left, p_top]), outline_color, 2.0, true)

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

	for c_pos in [c1, c2, c3]:
		ci.draw_circle(c_pos, r, color)
		ci.draw_arc(c_pos, r, 0.0, TAU, 24, outline_color, 2.0, true)
