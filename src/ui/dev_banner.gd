class_name DevBanner
extends Control

enum Kind { NONE, INFO, ERROR }

const INFO_HIDE_S: float = 3.0
const MAX_ERRORS_SHOWN: int = 3
const SEPARATOR: String = " · "
const INFO_COLOR: Color = Color("#1e5aa8")
const ERROR_COLOR: Color = Color("#b3261e")

var kind: Kind = Kind.NONE
var current_text: String = ""

@onready var strip: PanelContainer = $Strip
@onready var message_label: Label = $Strip/Margin/MessageLabel
@onready var btn_dismiss: Button = $BtnDismiss
@onready var hide_timer: Timer = $HideTimer

func _ready() -> void:
	visible = false
	btn_dismiss.pressed.connect(dismiss)
	hide_timer.one_shot = true
	hide_timer.timeout.connect(dismiss)

static func format_errors(errors: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in range(mini(errors.size(), MAX_ERRORS_SHOWN)):
		parts.append(errors[i])
	if errors.size() > MAX_ERRORS_SHOWN:
		parts.append("+%d more" % (errors.size() - MAX_ERRORS_SHOWN))
	return SEPARATOR.join(parts)

func show_info(text: String) -> void:
	_show(Kind.INFO, text, INFO_COLOR)
	hide_timer.start(INFO_HIDE_S)

func show_errors(errors: PackedStringArray) -> void:
	_show(Kind.ERROR, format_errors(errors), ERROR_COLOR)
	hide_timer.stop()

func dismiss() -> void:
	kind = Kind.NONE
	current_text = ""
	visible = false
	hide_timer.stop()

func _show(new_kind: Kind, text: String, color: Color) -> void:
	kind = new_kind
	current_text = text
	message_label.text = text
	var style := StyleBoxFlat.new()
	style.bg_color = color
	strip.add_theme_stylebox_override("panel", style)
	visible = true
