class_name UiFonts
extends RefCounted

## Fake Open Sans weights by emboldening Godot's default font. No font files are added.

const MIN_SIZE: int = 12

static var _cache: Dictionary = {}


static func weight(w: int) -> Font:
	var key: int = _bucket(w)
	if _cache.has(key):
		return _cache[key] as Font
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = _embolden_for(key)
	_cache[key] = font
	return font


static func _bucket(w: int) -> int:
	if w >= 800:
		return 800
	if w >= 700:
		return 700
	if w >= 600:
		return 600
	return 400


static func _embolden_for(bucket: int) -> float:
	match bucket:
		800:
			return 0.7
		700:
			return 0.35
		_:
			return 0.0


## Applies size, weight and colour to a Label.
static func style_label(label: Label, font_size: int, w: int, color: Color) -> void:
	label.add_theme_font_override("font", weight(w))
	label.add_theme_font_size_override("font_size", maxi(font_size, MIN_SIZE))
	label.add_theme_color_override("font_color", color)


static func text_size(text: String, font_size: int, w: int) -> Vector2:
	return weight(w).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
