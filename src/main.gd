extends Node

@onready var normal_ui: Control = $NormalUI
@onready var error_panel: Panel = $ErrorPanel
@onready var error_label: RichTextLabel = $ErrorPanel/MarginContainer/VBoxContainer/ErrorLabel
@onready var fsm: GameStateMachine = $GameStateMachine
@onready var debug_overlay: DebugOverlay = $DebugOverlay

func _ready() -> void:
	check_config_errors()
	if GameData.load_errors.is_empty() and fsm != null:
		fsm.start()
	if debug_overlay != null and fsm != null:
		debug_overlay.setup(fsm)

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
	if fsm != null and fsm.phase_root != null:
		fsm.phase_root.visible = false
	if debug_overlay != null:
		debug_overlay.visible = false

func _show_normal_ui() -> void:
	if normal_ui != null:
		normal_ui.visible = true
	if error_panel != null:
		error_panel.visible = false
	if fsm != null and fsm.phase_root != null:
		fsm.phase_root.visible = true
	if debug_overlay != null and OS.is_debug_build():
		debug_overlay.visible = true
