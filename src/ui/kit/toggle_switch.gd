class_name ToggleSwitch
extends Button

## 64x36 track with a 28 px knob. The hit area is 64x48. Toggles on a touch press and release inside it,
## and emits the standard `toggled(on)` signal. Mouse events are ignored here because the project emulates
## touch from the mouse, so handling both would toggle twice.

const TRACK: Vector2 = Vector2(64.0, 36.0)
const KNOB: float = 28.0
const HIT: Vector2 = Vector2(64.0, 48.0)

var night: bool = false:
	set = set_night

var _press_inside: bool = false


func _init() -> void:
	toggle_mode = true
	custom_minimum_size = HIT
	KitDraw.make_button_blank(self)


func set_night(value: bool) -> void:
	night = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		accept_event()
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null or disabled:
		return
	var inside: bool = Rect2(Vector2.ZERO, size).has_point(touch.position)
	if touch.pressed:
		_press_inside = inside
	else:
		if _press_inside and inside:
			button_pressed = not button_pressed
		_press_inside = false
	accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		queue_redraw()


func _toggled(_on: bool) -> void:
	queue_redraw()


func _draw() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var track_rect := Rect2((size - TRACK) * 0.5, TRACK)
	var fill: Color = pal["accent"] as Color if button_pressed else (pal["toggle_off"] as Color)
	if disabled:
		fill = pal["disabled_fill"] as Color
	KitDraw.draw_box(self, track_rect, fill, -1.0)
	var pad: float = (TRACK.y - KNOB) * 0.5
	var knob_x: float = track_rect.end.x - pad - KNOB if button_pressed else track_rect.position.x + pad
	var knob_c := Vector2(knob_x + KNOB * 0.5, track_rect.get_center().y)
	draw_circle(knob_c + Vector2(0.0, 1.5), KNOB * 0.5 + 1.0, Color(0.0, 0.0, 0.0, 0.18))
	draw_circle(knob_c, KNOB * 0.5, pal["knob"] as Color)
