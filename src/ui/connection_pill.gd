class_name ConnectionPill
extends PanelContainer

## Read-only chip showing the backend connection: Offline / Connecting / Online / Update required.

const PILL_SIZE: Vector2 = Vector2(170.0, 36.0)
const LABELS: Dictionary = {
	"offline": "Offline",
	"connecting": "Connecting",
	"online": "Online",
	"update_required": "Update required",
}
const TOKENS: Dictionary = {
	"offline": "muted",
	"connecting": "status_connecting",
	"online": "status_online",
	"update_required": "status_update",
}

var night: bool = false
var shown_status: String = ""

var _backend: BackendClient = null
var _dot: Control = null
var _label: Label = null


func _init() -> void:
	custom_minimum_size = PILL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot = Control.new()
	_dot.custom_minimum_size = Vector2(12.0, 12.0)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	row.add_child(_dot)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	add_child(row)
	set_status(BackendClient.STATUS_OFFLINE)


## Follows the backend's status_changed signal. Safe to call again with the same backend.
func bind(backend: BackendClient) -> void:
	if backend == _backend:
		set_status(backend.status())
		return
	if _backend != null and _backend.status_changed.is_connected(set_status):
		_backend.status_changed.disconnect(set_status)
	_backend = backend
	if _backend != null:
		_backend.status_changed.connect(set_status)
		set_status(_backend.status())


func set_status(status: String) -> void:
	shown_status = status if LABELS.has(status) else BackendClient.STATUS_OFFLINE
	var pal: Dictionary = UiPalette.for_theme(night)
	var tint: Color = pal[TOKENS[shown_status]] as Color
	_label.text = LABELS[shown_status] as String
	UiFonts.style_label(_label, 14, 700, pal["ink"] as Color)
	var box: StyleBoxFlat = KitDraw.make_box(pal["panel"] as Color, PILL_SIZE.y * 0.5, 2, tint,
			pal["panel_shadow"] as Color, 10, Vector2(0.0, 3.0))
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	add_theme_stylebox_override("panel", box)
	_dot.set_meta("tint", tint)
	_dot.queue_redraw()


func _draw_dot() -> void:
	var tint: Color = _dot.get_meta("tint", Color.GRAY) as Color
	_dot.draw_circle(_dot.size * 0.5, minf(_dot.size.x, _dot.size.y) * 0.5, tint)
