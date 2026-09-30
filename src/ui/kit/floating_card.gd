class_name FloatingCard
extends PanelContainer

## Floating HUD card (selection card, status card, dialogs). Radius 28, padding 20, default width 300.

const RADIUS: int = 28
const PADDING: float = 20.0
const DEFAULT_WIDTH: float = 300.0

var night: bool = false:
	set = set_night


func _init() -> void:
	custom_minimum_size = Vector2(DEFAULT_WIDTH, 0.0)
	_refresh_style()


func set_night(value: bool) -> void:
	night = value
	_refresh_style()


func _refresh_style() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var sb: StyleBoxFlat = KitDraw.make_box(pal["panel"] as Color, float(RADIUS), 2, pal["panel_border"] as Color,
			pal["panel_shadow"] as Color, 28, Vector2(0.0, 10.0))
	sb.set_content_margin_all(PADDING)
	add_theme_stylebox_override("panel", sb)
