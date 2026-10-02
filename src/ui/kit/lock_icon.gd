class_name LockIcon
extends Control

## A small padlock drawn in code (no outside art): a body with a shackle arc. Used for locked strain variants.

const ICON_SIZE: Vector2 = Vector2(18.0, 20.0)

var color: Color = Color("#d3aab0")


func _init(p_color: Color = Color("#d3aab0")) -> void:
	color = p_color
	custom_minimum_size = ICON_SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = ICON_SIZE.x
	var h: float = ICON_SIZE.y
	var body := Rect2(Vector2(1.0, h * 0.45), Vector2(w - 2.0, h * 0.55))
	draw_rect(body, color)
	draw_arc(Vector2(w * 0.5, h * 0.45), w * 0.3, PI, TAU, 16, color, 2.0)
	draw_circle(Vector2(w * 0.5, h * 0.72), 1.8, Color(0.0, 0.0, 0.0, 0.55))
