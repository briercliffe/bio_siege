class_name StepperCard
extends PanelContainer

## Night tray card with a count stepper (about 330x72): icon, name, cost, then - count + buttons.
## Tapping the card body emits `selected`; the - and + buttons emit `minus_pressed` and `plus_pressed`.

signal plus_pressed
signal minus_pressed
signal selected

const CARD_SIZE: Vector2 = Vector2(330.0, 72.0)
const STEP_SIZE: Vector2 = Vector2(48.0, 48.0)

var night: bool = true:
	set = set_night
var count: int = 0:
	set = set_count
var plus_enabled: bool = true:
	set = set_plus_enabled
var is_chosen: bool = false:
	set = set_chosen
var config: GameConfig = null:
	set(value):
		config = value
		_icon.config = value

var minus_button: Button = Button.new()
var plus_button: Button = Button.new()

var _icon: IconSlot = IconSlot.new("", 34.0)
var _name: Label = Label.new()
var _cost: Label = Label.new()
var _count: Label = Label.new()


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(_name)
	texts.add_child(_cost)
	_count.custom_minimum_size = Vector2(28.0, 0.0)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	minus_button.text = "−"
	plus_button.text = "+"
	for b: Button in [minus_button, plus_button]:
		b.custom_minimum_size = STEP_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	minus_button.pressed.connect(_on_minus)
	plus_button.pressed.connect(_on_plus)
	row.add_child(_icon)
	row.add_child(texts)
	row.add_child(minus_button)
	row.add_child(_count)
	row.add_child(plus_button)
	add_child(row)
	gui_input.connect(_on_gui_input)
	_refresh()


func setup(icon_id: String, display_name: String, cost_text: String, start_count: int = 0) -> void:
	_icon.icon_id = icon_id
	_name.text = display_name
	_cost.text = cost_text
	count = start_count


func set_night(value: bool) -> void:
	night = value
	_refresh()


func set_count(value: int) -> void:
	count = value
	_count.text = str(value)


func set_plus_enabled(value: bool) -> void:
	plus_enabled = value
	plus_button.disabled = not value
	_refresh()


func set_chosen(value: bool) -> void:
	is_chosen = value
	_refresh()


func _on_plus() -> void:
	if plus_enabled:
		plus_pressed.emit()


func _on_minus() -> void:
	minus_pressed.emit()


func _on_gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null or touch.pressed:
		return
	if not Rect2(Vector2.ZERO, size).has_point(touch.position):
		return
	for b: Button in [minus_button, plus_button]:
		if b.get_global_rect().has_point(get_global_transform() * touch.position):
			return
	selected.emit()


func _refresh() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var accent: Color = pal["accent"] as Color
	var card: StyleBoxFlat
	if is_chosen:
		card = KitDraw.make_box(pal["stepper_card"] as Color, 24.0, 3, accent, pal["accent_ring"] as Color, 6, Vector2.ZERO)
	else:
		card = KitDraw.make_box(pal["stepper_card"] as Color, 24.0, 2, pal["panel_border"] as Color,
				pal["panel_shadow"] as Color, 20, Vector2(0.0, 8.0))
	card.content_margin_left = 13.0
	card.content_margin_right = 10.0
	card.content_margin_top = 0.0
	card.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", card)
	UiFonts.style_label(_name, 15, 700, pal["ink"] as Color)
	UiFonts.style_label(_cost, 14, 800, accent)
	UiFonts.style_label(_count, 20, 800, pal["ink"] as Color)
	_style_step_button(minus_button, pal["stepper_bg"] as Color, pal["stepper_border"] as Color, pal["ink"] as Color, 2, 700)
	var plus_fill: Color = accent
	var plus_text: Color = pal["on_accent"] as Color
	if not plus_enabled:
		plus_fill = PLUS_DISABLED_FILL if night else (pal["disabled_fill"] as Color)
		plus_text = PLUS_DISABLED_TEXT if night else (pal["disabled_text"] as Color)
	_style_step_button(plus_button, plus_fill, Color.TRANSPARENT, plus_text, 0, 800)


const PLUS_DISABLED_FILL: Color = UiPalette.PLUS_DISABLED_FILL
const PLUS_DISABLED_TEXT: Color = UiPalette.PLUS_DISABLED_TEXT


func _style_step_button(btn: Button, fill: Color, border: Color, text_col: Color, border_w: int, w: int) -> void:
	var normal: StyleBoxFlat = KitDraw.make_box(fill, 24.0, border_w, border)
	var pressed_style: StyleBoxFlat = KitDraw.make_box(fill.darkened(0.15), 24.0, border_w, border)
	for state: String in ["normal", "hover", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, normal)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("hover_pressed", pressed_style)
	btn.add_theme_font_override("font", UiFonts.weight(w))
	btn.add_theme_font_size_override("font_size", 24)
	for col: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_disabled_color", "font_hover_pressed_color"]:
		btn.add_theme_color_override(col, text_col)
