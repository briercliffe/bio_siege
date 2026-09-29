class_name ConfirmationPopup
extends Control

signal confirmed
signal canceled

var dialog_text: String:
	get:
		if message_label != null:
			return message_label.text
		return _dialog_text
	set(val):
		_dialog_text = val
		if message_label != null:
			message_label.text = val

var _dialog_text: String = ""

var backdrop: ColorRect = null
var panel: PanelContainer = null
var message_label: Label = null
var btn_cancel: Button = null
var btn_ok: Button = null

var ok_button: Button:
	get:
		_ensure_nodes()
		return btn_ok

var cancel_button: Button:
	get:
		_ensure_nodes()
		return btn_cancel

func _init() -> void:
	visible = false
	layout_mode = 1
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ensure_nodes() -> void:
	if btn_ok != null:
		return

	backdrop = get_node_or_null("Backdrop") as ColorRect
	panel = get_node_or_null("PanelContainer") as PanelContainer
	message_label = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/MessageLabel") as Label
	btn_cancel = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ButtonRow/BtnCancel") as Button
	btn_ok = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/ButtonRow/BtnOk") as Button

	if btn_ok != null:
		return

	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.05, 0.08, 0.12, 0.6)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.name = "PanelContainer"
	panel.custom_minimum_size = Vector2(380.0, 180.0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
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
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Finalize Base?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#12304f"))
	vbox.add_child(title)

	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.text = _dialog_text
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.add_theme_color_override("font_color", Color("#12304f"))
	vbox.add_child(message_label)

	var btn_row := HBoxContainer.new()
	btn_row.name = "ButtonRow"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	btn_cancel = Button.new()
	btn_cancel.name = "BtnCancel"
	btn_cancel.text = "Keep building"
	btn_cancel.custom_minimum_size = Vector2(140.0, 48.0)
	btn_cancel.focus_mode = Control.FOCUS_ALL
	btn_row.add_child(btn_cancel)

	btn_ok = Button.new()
	btn_ok.name = "BtnOk"
	btn_ok.text = "Finalize"
	btn_ok.custom_minimum_size = Vector2(140.0, 48.0)
	btn_ok.focus_mode = Control.FOCUS_ALL
	btn_row.add_child(btn_ok)

func _ready() -> void:
	_ensure_nodes()
	if not _dialog_text.is_empty() and message_label != null:
		message_label.text = _dialog_text
	if btn_cancel != null and not btn_cancel.pressed.is_connected(_on_cancel_pressed):
		btn_cancel.pressed.connect(_on_cancel_pressed)
	if btn_ok != null and not btn_ok.pressed.is_connected(_on_ok_pressed):
		btn_ok.pressed.connect(_on_ok_pressed)

func get_ok_button() -> Button:
	_ensure_nodes()
	return btn_ok

func get_cancel_button() -> Button:
	_ensure_nodes()
	return btn_cancel

func popup_centered() -> void:
	_ensure_nodes()
	visible = true

func show_dialog(text: String) -> void:
	_ensure_nodes()
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
