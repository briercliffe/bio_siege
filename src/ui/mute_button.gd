class_name MuteButton
extends Button

## Speaker toggle drawn from shapes; bound to the Sfx autoload's mute state.

const MIN_SIZE: Vector2 = Vector2(48.0, 48.0)
const ICON_COLOR: Color = Color("#ffffff")
const MUTED_SLASH_COLOR: Color = Color("#e74c3c")


static func create() -> MuteButton:
	var button := MuteButton.new()
	button.name = "BtnMute"
	return button


func _init() -> void:
	custom_minimum_size = MIN_SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text = ""


func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	if not Sfx.mute_changed.is_connected(_on_mute_changed):
		Sfx.mute_changed.connect(_on_mute_changed)
	queue_redraw()


func _exit_tree() -> void:
	if Sfx.mute_changed.is_connected(_on_mute_changed):
		Sfx.mute_changed.disconnect(_on_mute_changed)


func _on_pressed() -> void:
	Sfx.toggle_mute()


func _on_mute_changed(_is_muted: bool) -> void:
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var u: float = minf(size.x, size.y) / 48.0
	# Speaker body: a box plus a cone opening to the right.
	draw_rect(Rect2(c + Vector2(-13.0, -5.0) * u, Vector2(8.0, 10.0) * u), ICON_COLOR)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-5.0, -5.0) * u,
		c + Vector2(3.0, -12.0) * u,
		c + Vector2(3.0, 12.0) * u,
		c + Vector2(-5.0, 5.0) * u,
	]), ICON_COLOR)
	if Sfx.muted:
		draw_line(c + Vector2(8.0, -8.0) * u, c + Vector2(18.0, 8.0) * u, MUTED_SLASH_COLOR, 3.0 * u, true)
		draw_line(c + Vector2(18.0, -8.0) * u, c + Vector2(8.0, 8.0) * u, MUTED_SLASH_COLOR, 3.0 * u, true)
	else:
		draw_arc(c + Vector2(3.0, 0.0) * u, 8.0 * u, -0.9, 0.9, 12, ICON_COLOR, 2.0 * u, true)
		draw_arc(c + Vector2(3.0, 0.0) * u, 14.0 * u, -0.9, 0.9, 16, ICON_COLOR, 2.0 * u, true)
