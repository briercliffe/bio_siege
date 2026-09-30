class_name IconSlot
extends Control

## A small control that draws one IconPainter icon. Used inside rows, pills and cards.

var icon_id: String = "":
	set(value):
		icon_id = value
		queue_redraw()
var config: GameConfig = null


func _init(id: String = "", px: float = 34.0) -> void:
	icon_id = id
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	IconPainter.draw_icon(self, icon_id, Rect2(Vector2.ZERO, size), config)
