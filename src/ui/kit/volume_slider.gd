class_name VolumeSlider
extends HSlider

## Restyled HSlider: 8 px track, accent fill, and a 32 px white grabber with a 3 px accent ring.
## The grabber is a radial GradientTexture2D built in code (no image files).

const GRABBER_PX: int = 32
const TRACK_PX: float = 8.0

var night: bool = false:
	set = set_night


func _init() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.01
	value = 0.5
	custom_minimum_size = Vector2(200.0, 48.0)
	focus_mode = Control.FOCUS_NONE
	_restyle()


func set_night(v: bool) -> void:
	night = v
	_restyle()


func _restyle() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var accent: Color = pal["accent"] as Color
	var track: StyleBoxFlat = KitDraw.make_box(pal["track"] as Color, TRACK_PX * 0.5)
	var fill: StyleBoxFlat = KitDraw.make_box(accent, TRACK_PX * 0.5)
	for sb: StyleBoxFlat in [track, fill]:
		sb.content_margin_top = TRACK_PX * 0.5
		sb.content_margin_bottom = TRACK_PX * 0.5
	if not night:
		track.bg_color = Color("#c5d9ed")
	add_theme_stylebox_override("slider", track)
	add_theme_stylebox_override("grabber_area", fill)
	add_theme_stylebox_override("grabber_area_highlight", fill)
	var grabber: GradientTexture2D = _make_grabber(accent, pal["knob"] as Color)
	add_theme_icon_override("grabber", grabber)
	add_theme_icon_override("grabber_highlight", grabber)
	add_theme_icon_override("grabber_disabled", grabber)


static func _make_grabber(ring: Color, face: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	var clear := Color(ring.r, ring.g, ring.b, 0.0)
	# Radius 16 px: face to 12.5 px, ring from 12.5 to 15.5 px (3 px), then a soft edge.
	grad.offsets = PackedFloat32Array([0.0, 0.76, 0.80, 0.95, 0.99, 1.0])
	grad.colors = PackedColorArray([face, face, ring, ring, ring, clear])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = GRABBER_PX
	tex.height = GRABBER_PX
	return tex
