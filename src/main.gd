extends Node

@onready var normal_ui: Control = $NormalUI
@onready var error_panel: Panel = $ErrorPanel
@onready var error_label: RichTextLabel = $ErrorPanel/MarginContainer/VBoxContainer/ErrorLabel

func _ready() -> void:
	check_config_errors()

func check_config_errors() -> void:
	if not GameData.load_errors.is_empty():
		_show_config_error_ui()
	else:
		_show_normal_ui()

func _show_config_error_ui() -> void:
	if normal_ui != null:
		normal_ui.visible = false
	if error_panel != null:
		error_panel.visible = true
	if error_label != null:
		error_label.text = "\n".join(GameData.load_errors)

func _show_normal_ui() -> void:
	if normal_ui != null:
		normal_ui.visible = true
	if error_panel != null:
		error_panel.visible = false
