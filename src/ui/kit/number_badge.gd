class_name NumberBadge
extends Control

## 30 px accent circle with a white number ("Getting started" steps).

const DIAMETER: float = 30.0

var night: bool = false:
	set = set_night
var number: int = 1:
	set = set_number


func _init(n: int = 1) -> void:
	number = n
	custom_minimum_size = Vector2(DIAMETER, DIAMETER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_night(value: bool) -> void:
	night = value
	queue_redraw()


func set_number(value: int) -> void:
	number = value
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	draw_circle(c, minf(size.x, size.y) * 0.5, UiPalette.color(night, "accent"))
	KitDraw.draw_text_centered(self, str(number), Rect2(Vector2.ZERO, size), 14, 800, Color.WHITE)
