class_name ImportDialog
extends Control

signal load_requested(text: String)
signal canceled

var backdrop: ColorRect = null
var panel: PanelContainer = null
var title_label: Label = null
var text_edit: TextEdit = null
var error_label: Label = null
var btn_cancel: Button = null
var btn_load: Button = null

func _init() -> void:
	visible = false
	layout_mode = 1
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if btn_load != null:
		return

	backdrop = get_node_or_null("Backdrop") as ColorRect
	panel = get_node_or_null("PanelContainer") as PanelContainer
	title_label = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/TitleLabel") as Label
	text_edit = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/TextEdit") as TextEdit
	error_label = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ErrorLabel") as Label
	btn_cancel = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ButtonRow/BtnCancel") as Button
	btn_load = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ButtonRow/BtnLoad") as Button

	if btn_load != null:
		_wire_nodes()
		return

	# Programmatic node creation fallback
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.05, 0.08, 0.12, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.name = "PanelContainer"
	panel.custom_minimum_size = Vector2(460.0, 340.0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Import"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color("#12304f"))
	vbox.add_child(title_label)

	text_edit = TextEdit.new()
	text_edit.name = "TextEdit"
	text_edit.custom_minimum_size = Vector2(420.0, 160.0)
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.placeholder_text = "Paste JSON snapshot here..."
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(text_edit)

	error_label = Label.new()
	error_label.name = "ErrorLabel"
	error_label.visible = false
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_color_override("font_color", Color("#e74c3c"))
	error_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(error_label)

	var btn_row := HBoxContainer.new()
	btn_row.name = "ButtonRow"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	btn_cancel = Button.new()
	btn_cancel.name = "BtnCancel"
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(120.0, 48.0)
	btn_row.add_child(btn_cancel)

	btn_load = Button.new()
	btn_load.name = "BtnLoad"
	btn_load.text = "Load"
	btn_load.custom_minimum_size = Vector2(120.0, 48.0)
	btn_row.add_child(btn_load)

	_wire_nodes()


func _wire_nodes() -> void:
	if btn_cancel != null and not btn_cancel.pressed.is_connected(_on_cancel_pressed):
		btn_cancel.pressed.connect(_on_cancel_pressed)
	if btn_load != null and not btn_load.pressed.is_connected(_on_load_pressed):
		btn_load.pressed.connect(_on_load_pressed)


func open(title: String = "Import") -> void:
	_ensure_nodes()
	if title_label != null:
		title_label.text = title
	if text_edit != null:
		text_edit.text = ""
	clear_error()
	visible = true


func close() -> void:
	visible = false


func set_error(msg: String) -> void:
	_ensure_nodes()
	if error_label != null:
		error_label.text = msg
		error_label.visible = not msg.is_empty()


func clear_error() -> void:
	_ensure_nodes()
	if error_label != null:
		error_label.text = ""
		error_label.visible = false


func _on_cancel_pressed() -> void:
	close()
	canceled.emit()


func _on_load_pressed() -> void:
	var txt: String = text_edit.text if text_edit != null else ""
	load_requested.emit(txt)
