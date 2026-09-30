class_name DimOverlay
extends ColorRect

## Full-rect scrim behind dialogs. Blocks input to everything underneath.

var night: bool = false:
	set = set_night


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	color = UiPalette.color(false, "dim_overlay")


func set_night(value: bool) -> void:
	night = value
	color = UiPalette.color(night, "dim_overlay")
