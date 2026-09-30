class_name PillPanel
extends PanelContainer

## Capsule-shaped floating panel: the ATP pill and the phase pill.

const PILL_HEIGHT: float = 52.0
const PHASE_HEIGHT: float = 56.0
const PHASE_SIZE: Vector2 = Vector2(340.0, 56.0)

var night: bool = false:
	set = set_night

var _style: StyleBoxFlat = null
var _title: Label = null
var _subtitle: Label = null


func _init() -> void:
	custom_minimum_size = Vector2(0.0, PILL_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_refresh_radius)
	_refresh_style()


func set_night(value: bool) -> void:
	night = value
	_refresh_style()
	_restyle_phase_labels()


## Builds the "PHASE 1 · SYNTHESIS" / subtitle layout from the mockups.
func set_phase(title: String, subtitle: String) -> void:
	if _title == null:
		custom_minimum_size = PHASE_SIZE
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title = Label.new()
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_subtitle = Label.new()
		_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_title)
		box.add_child(_subtitle)
		add_child(box)
	_title.text = title
	_subtitle.text = subtitle
	_restyle_phase_labels()


func _restyle_phase_labels() -> void:
	if _title == null:
		return
	var pal: Dictionary = UiPalette.for_theme(night)
	UiFonts.style_label(_title, 12, 700, pal["accent"] as Color)
	_title.add_theme_constant_override("outline_size", 0)
	_title.add_theme_font_override("font", _letter_spaced_font())
	UiFonts.style_label(_subtitle, 17, 700, pal["ink"] as Color)


func _letter_spaced_font() -> Font:
	var v := FontVariation.new()
	v.base_font = UiFonts.weight(700)
	v.spacing_glyph = 2
	return v


func _refresh_style() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var radius: float = maxf(size.y, custom_minimum_size.y) * 0.5
	_style = KitDraw.make_box(pal["panel"] as Color, radius, 2, pal["panel_border"] as Color,
			pal["panel_shadow"] as Color, 22, Vector2(0.0, 8.0))
	_style.content_margin_left = 20.0
	_style.content_margin_right = 20.0
	_style.content_margin_top = 0.0
	_style.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", _style)


func _refresh_radius() -> void:
	if _style == null:
		return
	var r: int = int(size.y * 0.5)
	if _style.corner_radius_top_left != r:
		_style.set_corner_radius_all(r)
		queue_redraw()
