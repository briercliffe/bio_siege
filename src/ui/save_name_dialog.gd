class_name SaveNameDialog
extends Control

## "Save base…" / "Save army…" from the Synthesis and Incubation HUD menus: a name field, Cancel and Save.

signal save_requested(slot_name: String)
signal canceled

const PANEL_SIZE: Vector2 = Vector2(420.0, 0.0)
const FIELD_SIZE: Vector2 = Vector2(380.0, 52.0)
const BUTTON_SIZE: Vector2 = Vector2(140.0, 52.0)
const MAX_NAME_LENGTH: int = SaveLibrary.MAX_NAME_LENGTH

var backdrop: ColorRect = null
var panel: FloatingCard = null
var title_label: Label = null
var name_edit: LineEdit = null
var error_label: Label = null
var btn_cancel: PillButton = null
var btn_save: PillButton = null


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func open(title: String, default_name: String) -> void:
	title_label.text = title
	name_edit.text = default_name
	clear_error()
	visible = true
	if is_inside_tree():
		name_edit.grab_focus()
		name_edit.select_all()


func close() -> void:
	visible = false


func set_error(msg: String) -> void:
	error_label.text = msg
	error_label.visible = not msg.is_empty()


func clear_error() -> void:
	set_error("")


func _build() -> void:
	var pal: Dictionary = UiPalette.for_theme(false)
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = pal["dim_overlay"] as Color
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = FloatingCard.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	title_label = Label.new()
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(title_label, 20, 800, pal["ink"] as Color)
	box.add_child(title_label)

	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.custom_minimum_size = FIELD_SIZE
	name_edit.max_length = MAX_NAME_LENGTH
	name_edit.placeholder_text = "Name"
	name_edit.add_theme_font_override("font", UiFonts.weight(600))
	name_edit.add_theme_font_size_override("font_size", 17)
	name_edit.add_theme_color_override("font_color", pal["ink"] as Color)
	var field: StyleBoxFlat = KitDraw.make_box(pal["stepper_bg"] as Color, 16.0, 2, pal["stepper_border"] as Color)
	field.content_margin_left = 16.0
	field.content_margin_right = 16.0
	name_edit.add_theme_stylebox_override("normal", field)
	var focus: StyleBoxFlat = field.duplicate() as StyleBoxFlat
	focus.border_color = pal["accent"] as Color
	name_edit.add_theme_stylebox_override("focus", focus)
	name_edit.text_submitted.connect(_on_submitted)
	box.add_child(name_edit)

	error_label = Label.new()
	error_label.name = "Error"
	error_label.visible = false
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.custom_minimum_size = Vector2(FIELD_SIZE.x, 0.0)
	UiFonts.style_label(error_label, 14, 600, pal["danger"] as Color)
	box.add_child(error_label)

	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	btn_cancel = PillButton.new("Cancel", PillButton.Variant.SECONDARY)
	btn_cancel.name = "BtnCancel"
	btn_cancel.custom_minimum_size = BUTTON_SIZE
	btn_cancel.pressed.connect(_on_cancel_pressed)
	row.add_child(btn_cancel)
	btn_save = PillButton.new("Save", PillButton.Variant.PRIMARY)
	btn_save.name = "BtnSave"
	btn_save.custom_minimum_size = BUTTON_SIZE
	btn_save.pressed.connect(_on_save_pressed)
	row.add_child(btn_save)


func _on_submitted(_text: String) -> void:
	_on_save_pressed()


func _on_save_pressed() -> void:
	var slot_name: String = name_edit.text.strip_edges()
	if slot_name.is_empty():
		set_error("Type a name first")
		return
	save_requested.emit(slot_name)


func _on_cancel_pressed() -> void:
	close()
	canceled.emit()
