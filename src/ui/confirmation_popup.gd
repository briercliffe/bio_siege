class_name ConfirmationPopup
extends Control

## Modal confirmation card (screen 07, "Finalize this base?"), built from the UI kit. A dim scrim blocks the
## screen, a rounded card shows a kicker, a title, a body, optional summary tiles and two pill buttons.
## Reused by the Saved screen, so every piece of copy has a setter.

signal confirmed
signal canceled

const CARD_WIDTH: float = 500.0
const CARD_RADIUS: float = 40.0
const CARD_PADDING: float = 36.0
const CARD_NIGHT_FILL: Color = Color("#2a0b10")
const GAP: int = 16
const BUTTON_HEIGHT: float = 58.0
const TILE_RADIUS: float = 20.0
const KICKER_SPACING: int = 2

var dialog_text: String:
	get:
		if message_label != null:
			return message_label.text
		return _dialog_text
	set(val):
		_dialog_text = val
		if message_label != null:
			message_label.text = val
			message_label.visible = val != ""

var night: bool = false:
	set = set_night

var _dialog_text: String = ""

var backdrop: DimOverlay = null
var panel: PanelContainer = null
var kicker_label: Label = null
var title_label: Label = null
var message_label: Label = null
var tiles_row: HBoxContainer = null
var warning_label: Label = null
var btn_cancel: PillButton = null
var btn_ok: PillButton = null

var ok_button: Button:
	get:
		return btn_ok

var cancel_button: Button:
	get:
		return btn_cancel


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	if not btn_cancel.pressed.is_connected(_on_cancel_pressed):
		btn_cancel.pressed.connect(_on_cancel_pressed)
	if not btn_ok.pressed.is_connected(_on_ok_pressed):
		btn_ok.pressed.connect(_on_ok_pressed)


func _build() -> void:
	backdrop = DimOverlay.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.name = "PanelContainer"
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", GAP)
	margin.add_child(vbox)

	kicker_label = Label.new()
	kicker_label.name = "KickerLabel"
	kicker_label.visible = false
	vbox.add_child(kicker_label)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Are you sure?"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_label)

	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.visible = false
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message_label)

	tiles_row = HBoxContainer.new()
	tiles_row.name = "TilesRow"
	tiles_row.visible = false
	tiles_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tiles_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tiles_row)

	warning_label = Label.new()
	warning_label.name = "WarningLabel"
	warning_label.visible = false
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(warning_label)

	var btn_row := HBoxContainer.new()
	btn_row.name = "ButtonRow"
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	btn_cancel = PillButton.new("Cancel", PillButton.Variant.SECONDARY)
	btn_cancel.name = "BtnCancel"
	btn_cancel.font_weight = 700
	_size_button(btn_cancel)
	btn_row.add_child(btn_cancel)

	btn_ok = PillButton.new("OK", PillButton.Variant.PRIMARY)
	btn_ok.name = "BtnOk"
	_size_button(btn_ok)
	btn_row.add_child(btn_ok)

	_restyle()


static func _size_button(btn: PillButton) -> void:
	btn.custom_minimum_size = Vector2(PillButton.MIN_WIDTH, BUTTON_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_night(value: bool) -> void:
	night = value
	_restyle()


func _restyle() -> void:
	if panel == null:
		return
	var pal: Dictionary = UiPalette.for_theme(night)
	backdrop.night = night
	btn_cancel.night = night
	btn_ok.night = night
	var fill: Color = CARD_NIGHT_FILL if night else Color.WHITE
	var sb: StyleBoxFlat = KitDraw.make_box(fill, CARD_RADIUS, 2, pal["panel_border"] as Color,
			Color(0.0, 0.0, 0.0, 0.4), 60, Vector2(0.0, 20.0))
	sb.set_content_margin_all(0.0)
	panel.add_theme_stylebox_override("panel", sb)
	var margin: MarginContainer = panel.get_node("MarginContainer") as MarginContainer
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(CARD_PADDING))
	UiFonts.style_label(kicker_label, 12, 700, pal["accent"] as Color)
	var spaced := FontVariation.new()
	spaced.base_font = UiFonts.weight(700)
	spaced.spacing_glyph = KICKER_SPACING
	kicker_label.add_theme_font_override("font", spaced)
	UiFonts.style_label(title_label, 30, 800, pal["ink"] as Color)
	UiFonts.style_label(message_label, 16, 400, pal["muted"] as Color)
	UiFonts.style_label(warning_label, 15, 600, pal["danger"] as Color)


func set_kicker(text: String) -> void:
	kicker_label.text = text
	kicker_label.visible = text != ""


func set_title(text: String) -> void:
	title_label.text = text


func set_body(text: String) -> void:
	dialog_text = text


## The red line under the tiles (for example "not enough ATP for any pathogen"). Empty hides it.
func set_warning(text: String) -> void:
	warning_label.text = text
	warning_label.visible = text != ""


## Summary tiles under the body. Each entry is {"label": String, "value": String, "color": Color}.
func set_tiles(tiles: Array) -> void:
	for child: Node in tiles_row.get_children():
		tiles_row.remove_child(child)
		child.queue_free()
	var pal: Dictionary = UiPalette.for_theme(night)
	for entry: Variant in tiles:
		var data: Dictionary = entry as Dictionary
		var tile := PanelContainer.new()
		tile.name = "Tile_%s" % str(data.get("label", ""))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill: Color = data.get("color", pal["chip"]) as Color
		var sb: StyleBoxFlat = KitDraw.make_box(fill, TILE_RADIUS)
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		sb.content_margin_top = 12.0
		sb.content_margin_bottom = 12.0
		tile.add_theme_stylebox_override("panel", sb)
		var box := VBoxContainer.new()
		box.name = "Box"
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.name = "Label"
		label.text = str(data.get("label", ""))
		UiFonts.style_label(label, 13, 400, pal["muted"] as Color)
		var value := Label.new()
		value.name = "Value"
		value.text = str(data.get("value", ""))
		UiFonts.style_label(value, 22, 800, pal["ink"] as Color)
		box.add_child(label)
		box.add_child(value)
		tile.add_child(box)
		tiles_row.add_child(tile)
	tiles_row.visible = tiles_row.get_child_count() > 0


## The label and value text of tile `index`, for tests.
func tile_label(index: int) -> String:
	return (tiles_row.get_child(index).get_node("Box/Label") as Label).text


func tile_value(index: int) -> String:
	return (tiles_row.get_child(index).get_node("Box/Value") as Label).text


func set_buttons(cancel_text: String, ok_text: String) -> void:
	btn_cancel.text = cancel_text
	btn_ok.text = ok_text
	btn_cancel.queue_redraw()
	btn_ok.queue_redraw()


func get_ok_button() -> Button:
	return btn_ok


func get_cancel_button() -> Button:
	return btn_cancel


func popup_centered() -> void:
	visible = true


func show_dialog(text: String) -> void:
	dialog_text = text
	visible = true


func hide_dialog() -> void:
	visible = false


func _on_ok_pressed() -> void:
	visible = false
	confirmed.emit()


func _on_cancel_pressed() -> void:
	visible = false
	canceled.emit()
