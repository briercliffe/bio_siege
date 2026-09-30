class_name KitDraw
extends RefCounted

## Shared drawing helpers for the HUD kit. Everything is drawn in code.

const ARC_STEPS: int = 10


static func rounded_rect_points(rect: Rect2, radius: float, steps: int = ARC_STEPS) -> PackedVector2Array:
	var r: float = clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners: Array[Vector2] = [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r),
	]
	for ci: int in range(4):
		var start: float = -PI * 0.5 + float(ci) * PI * 0.5
		for s: int in range(steps + 1):
			var a: float = start + PI * 0.5 * float(s) / float(steps)
			pts.append(corners[ci] + Vector2(cos(a), sin(a)) * r)
	return pts


## A StyleBoxFlat with the usual kit options.
static func make_box(fill: Color, radius: float, border_w: int = 0, border: Color = Color.TRANSPARENT,
		shadow: Color = Color.TRANSPARENT, shadow_size: int = 0, shadow_offset: Vector2 = Vector2.ZERO) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(maxf(radius, 0.0)))
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.shadow_color = shadow
	sb.shadow_size = shadow_size
	sb.shadow_offset = shadow_offset
	sb.anti_aliasing = true
	return sb


## `radius < 0` means a full capsule.
static func draw_box(ci: CanvasItem, rect: Rect2, fill: Color, radius: float, border_w: int = 0,
		border: Color = Color.TRANSPARENT, shadow: Color = Color.TRANSPARENT, shadow_size: int = 0,
		shadow_offset: Vector2 = Vector2.ZERO) -> void:
	var r: float = minf(rect.size.x, rect.size.y) * 0.5 if radius < 0.0 else radius
	make_box(fill, r, border_w, border, shadow, shadow_size, shadow_offset).draw(ci.get_canvas_item(), rect)


## Vertical gradient over a rounded rectangle, drawn with per-vertex colours.
static func draw_gradient_rounded(ci: CanvasItem, rect: Rect2, radius: float, top: Color, bottom: Color) -> void:
	var r: float = minf(rect.size.x, rect.size.y) * 0.5 if radius < 0.0 else radius
	var pts: PackedVector2Array = rounded_rect_points(rect, r)
	var cols := PackedColorArray()
	for p: Vector2 in pts:
		var t: float = clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
		cols.append(top.lerp(bottom, t))
	ci.draw_polygon(pts, cols)


static func draw_text_centered(ci: CanvasItem, text: String, rect: Rect2, font_size: int, w: int, color: Color) -> void:
	var font: Font = UiFonts.weight(w)
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent: float = font.get_ascent(font_size)
	var pos := Vector2(rect.position.x + (rect.size.x - sz.x) * 0.5, rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + ascent)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func draw_text_at(ci: CanvasItem, text: String, left: float, center_y: float, font_size: int, w: int, color: Color) -> void:
	var font: Font = UiFonts.weight(w)
	var h: float = font.get_height(font_size)
	ci.draw_string(font, Vector2(left, center_y - h * 0.5 + font.get_ascent(font_size)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Dashed outline along a rounded rectangle.
static func draw_dashed_rounded(ci: CanvasItem, rect: Rect2, radius: float, color: Color, width: float,
		dash: float = 8.0, gap: float = 6.0) -> void:
	var pts: PackedVector2Array = rounded_rect_points(rect, radius, 6)
	pts.append(pts[0])
	var on: bool = true
	var remaining: float = dash
	for i: int in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0:
			continue
		var dir: Vector2 = (b - a) / seg_len
		var pos: float = 0.0
		while pos < seg_len:
			var step: float = minf(remaining, seg_len - pos)
			if on:
				ci.draw_line(a + dir * pos, a + dir * (pos + step), color, width, true)
			pos += step
			remaining -= step
			if remaining <= 0.0:
				on = not on
				remaining = dash if on else gap


## Makes a Button draw nothing natively so the script can draw it all in _draw().
static func make_button_blank(btn: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		btn.add_theme_stylebox_override(state, empty)
	for col: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_disabled_color", "font_hover_pressed_color", "font_outline_color"]:
		btn.add_theme_color_override(col, Color.TRANSPARENT)
	btn.focus_mode = Control.FOCUS_NONE


## Approximates a CSS vertical gradient on a polygon by clipping it into horizontal bands.
static func draw_banded_polygon(ci: CanvasItem, poly: PackedVector2Array, bounds: Rect2, stops: Array[Color], bands: int = 12) -> void:
	var band_h: float = bounds.size.y / float(bands)
	for b: int in range(bands):
		var t: float = (float(b) + 0.5) / float(bands)
		var col: Color = sample_stops(stops, t)
		var y0: float = bounds.position.y + band_h * float(b)
		var y1: float = y0 + band_h + 0.5
		var band := PackedVector2Array([
			Vector2(bounds.position.x - 1.0, y0),
			Vector2(bounds.end.x + 1.0, y0),
			Vector2(bounds.end.x + 1.0, y1),
			Vector2(bounds.position.x - 1.0, y1),
		])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, band):
			if piece.size() >= 3:
				ci.draw_colored_polygon(piece, col)


static func sample_stops(stops: Array[Color], t: float) -> Color:
	if stops.size() == 1:
		return stops[0]
	var seg: float = clampf(t, 0.0, 1.0) * float(stops.size() - 1)
	var i: int = mini(int(seg), stops.size() - 2)
	return stops[i].lerp(stops[i + 1], seg - float(i))
