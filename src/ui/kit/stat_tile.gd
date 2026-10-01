class_name StatTile
extends PanelContainer

## Small stat chip: muted label over a bold value, with an optional muted suffix ("of 52").

var night: bool = false:
	set = set_night
## Draws the value in the theme accent (the green "10 ATP" cost tile).
var accent_value: bool = false:
	set = set_accent_value

var _label: Label = Label.new()
var _value: Label = Label.new()
var _suffix: Label = Label.new()


func _init(label_text: String = "", value_text: String = "", suffix_text: String = "") -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_value)
	row.add_child(_suffix)
	box.add_child(_label)
	box.add_child(row)
	add_child(box)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	setup(label_text, value_text, suffix_text)


func setup(label_text: String, value_text: String, suffix_text: String = "") -> void:
	_label.text = label_text
	_value.text = value_text
	_suffix.text = suffix_text
	_suffix.visible = suffix_text != ""
	_refresh()


func label_text() -> String:
	return _label.text


func value_text() -> String:
	return _value.text


func suffix_text() -> String:
	return _suffix.text


func set_night(value: bool) -> void:
	night = value
	_refresh()


func set_accent_value(value: bool) -> void:
	accent_value = value
	_refresh()


func _refresh() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var sb: StyleBoxFlat = KitDraw.make_box(pal["chip"] as Color, 16.0)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", sb)
	UiFonts.style_label(_label, 12, 400, pal["muted"] as Color)
	UiFonts.style_label(_value, 18, 800, (pal["accent"] if accent_value else pal["ink"]) as Color)
	UiFonts.style_label(_suffix, 14, 400, pal["muted"] as Color)
	_suffix.size_flags_vertical = Control.SIZE_SHRINK_END
