class_name SegmentedTabs
extends HBoxContainer

## Capsule of mutually exclusive tabs (about 300x56). The selected segment has an accent fill and white text.

signal tab_changed(index: int)

const SIZE_DEFAULT: Vector2 = Vector2(300.0, 56.0)
const PAD: float = 4.0

var night: bool = false:
	set = set_night
var selected_index: int = 0

var _buttons: Array[Button] = []


func _init(labels: Array[String] = []) -> void:
	custom_minimum_size = SIZE_DEFAULT
	add_theme_constant_override("separation", 0)
	sort_children.connect(_layout_padded)
	for i: int in range(labels.size()):
		add_tab(labels[i])


func add_tab(label: String) -> void:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(64.0, 48.0)
	var idx: int = _buttons.size()
	b.pressed.connect(func() -> void: select(idx, true))
	_buttons.append(b)
	add_child(b)
	_refresh()


func select(index: int, emit: bool = false) -> void:
	if index < 0 or index >= _buttons.size():
		return
	var changed: bool = index != selected_index
	selected_index = index
	_refresh()
	if changed and emit:
		tab_changed.emit(index)


func set_night(value: bool) -> void:
	night = value
	_refresh()


## Inset the segments so the selected fill floats inside the capsule.
func _layout_padded() -> void:
	if _buttons.is_empty():
		return
	var w: float = (size.x - PAD * 2.0) / float(_buttons.size())
	for i: int in range(_buttons.size()):
		fit_child_in_rect(_buttons[i], Rect2(PAD + w * float(i), PAD, w, size.y - PAD * 2.0))


func _draw() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	KitDraw.draw_box(self, Rect2(Vector2.ZERO, size), pal["panel"] as Color, -1.0, 2, pal["panel_border"] as Color,
			pal["panel_shadow"] as Color, 22, Vector2(0.0, 8.0))


func _refresh() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	for i: int in range(_buttons.size()):
		var b: Button = _buttons[i]
		var on: bool = i == selected_index
		var fill: StyleBoxFlat = KitDraw.make_box(pal["accent"] as Color if on else Color.TRANSPARENT, 24.0)
		var pressed_fill: StyleBoxFlat = KitDraw.make_box((pal["accent"] as Color).darkened(0.1), 24.0)
		for state: String in ["normal", "hover", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, fill)
		b.add_theme_stylebox_override("pressed", pressed_fill)
		b.add_theme_stylebox_override("hover_pressed", pressed_fill)
		var col: Color = pal["on_accent"] as Color if on else (pal["ink"] as Color)
		for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				"font_disabled_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, col)
		b.add_theme_font_override("font", UiFonts.weight(700))
		b.add_theme_font_size_override("font_size", 16)
	queue_redraw()
