class_name IconButton
extends Button

## Round 52x52 HUD button with a code-drawn glyph (BACK is a 110x52 pill with the text "Back").

enum Kind { MENU, PAUSE, BACK, CLOSE, HELP, SPEAKER }

const ROUND_SIZE: Vector2 = Vector2(52.0, 52.0)
const BACK_SIZE: Vector2 = Vector2(110.0, 52.0)
const STROKE: float = 2.6

var night: bool = false:
	set = set_night
var kind: Kind = Kind.MENU:
	set = set_kind
## Only used by SPEAKER: draws the muted slash instead of the sound waves.
var muted: bool = false:
	set = set_muted


func _init(k: Kind = Kind.MENU) -> void:
	kind = k
	KitDraw.make_button_blank(self)
	_refresh_size()


func set_night(value: bool) -> void:
	night = value
	queue_redraw()


func set_kind(value: Kind) -> void:
	kind = value
	_refresh_size()
	queue_redraw()


func set_muted(value: bool) -> void:
	muted = value
	queue_redraw()


func _refresh_size() -> void:
	custom_minimum_size = BACK_SIZE if kind == Kind.BACK else ROUND_SIZE


func _draw() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var rect := Rect2(Vector2.ZERO, size)
	var fill: Color = pal["panel"] as Color
	if get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED:
		fill = fill.lerp(pal["accent"] as Color, 0.18)
	KitDraw.draw_box(self, rect, fill, -1.0, 2, pal["panel_border"] as Color,
			pal["panel_shadow"] as Color, 22, Vector2(0.0, 8.0))
	var ink: Color = pal["ink"] as Color
	var c: Vector2 = size * 0.5
	match kind:
		Kind.MENU:
			for dy: float in [-5.0, 0.0, 5.0]:
				draw_line(c + Vector2(-9.0, dy * 1.6), c + Vector2(9.0, dy * 1.6), ink, STROKE, true)
		Kind.PAUSE:
			draw_line(c + Vector2(-5.0, -8.0), c + Vector2(-5.0, 8.0), ink, 4.0, true)
			draw_line(c + Vector2(5.0, -8.0), c + Vector2(5.0, 8.0), ink, 4.0, true)
		Kind.CLOSE:
			draw_line(c + Vector2(-7.0, -7.0), c + Vector2(7.0, 7.0), ink, STROKE, true)
			draw_line(c + Vector2(7.0, -7.0), c + Vector2(-7.0, 7.0), ink, STROKE, true)
		Kind.HELP:
			KitDraw.draw_text_centered(self, "?", rect, 24, 800, ink)
		Kind.BACK:
			var left: float = 20.0
			var chevron := PackedVector2Array([
				Vector2(left + 8.0, c.y - 8.0), Vector2(left, c.y), Vector2(left + 8.0, c.y + 8.0),
			])
			draw_polyline(chevron, ink, STROKE, true)
			KitDraw.draw_text_at(self, "Back", left + 20.0, c.y, 17, 700, ink)
		Kind.SPEAKER:
			_draw_speaker(c, ink, pal["danger"] as Color)


func _draw_speaker(c: Vector2, ink: Color, slash: Color) -> void:
	var u: float = 0.8
	draw_rect(Rect2(c + Vector2(-13.0, -5.0) * u, Vector2(8.0, 10.0) * u), ink)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-5.0, -5.0) * u, c + Vector2(3.0, -12.0) * u,
		c + Vector2(3.0, 12.0) * u, c + Vector2(-5.0, 5.0) * u,
	]), ink)
	if muted:
		draw_line(c + Vector2(8.0, -8.0) * u, c + Vector2(18.0, 8.0) * u, slash, 3.0 * u, true)
		draw_line(c + Vector2(18.0, -8.0) * u, c + Vector2(8.0, 8.0) * u, slash, 3.0 * u, true)
	else:
		draw_arc(c + Vector2(3.0, 0.0) * u, 8.0 * u, -0.9, 0.9, 12, ink, 2.0, true)
		draw_arc(c + Vector2(3.0, 0.0) * u, 14.0 * u, -0.9, 0.9, 16, ink, 2.0, true)
