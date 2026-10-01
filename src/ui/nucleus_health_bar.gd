class_name NucleusHealthBar
extends Control

## The 26 px Nucleus HP bar of the Infection HUD (mockup 11): a dark capsule track and a purple
## gradient fill, left to right.

const BAR_HEIGHT: float = 26.0
const FILL_START: Color = Color("#c39bd3")
const FILL_END: Color = Color("#8e44ad")

## Fraction of max HP, 0..1.
var ratio: float = 1.0:
	set = set_ratio


func _init() -> void:
	custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_ratio(value: float) -> void:
	var v: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(v, ratio):
		return
	ratio = v
	queue_redraw()


func _draw() -> void:
	var radius: float = BAR_HEIGHT * 0.5
	KitDraw.draw_box(self, Rect2(0.0, 0.0, size.x, BAR_HEIGHT), UiPalette.color(true, "track"), radius)
	if ratio <= 0.0:
		return
	var w: float = maxf(size.x * ratio, BAR_HEIGHT)
	var pts: PackedVector2Array = KitDraw.rounded_rect_points(Rect2(0.0, 0.0, w, BAR_HEIGHT), radius)
	var cols := PackedColorArray()
	for p: Vector2 in pts:
		cols.append(FILL_START.lerp(FILL_END, clampf(p.x / w, 0.0, 1.0)))
	draw_polygon(pts, cols)
