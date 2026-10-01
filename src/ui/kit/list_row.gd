class_name ListRow
extends PanelContainer

## 48 px capsule row: icon, name, and a right-aligned "3 of 5 out".

const ROW_HEIGHT: float = 48.0

var night: bool = false:
	set = set_night
## Format of the muted text after the count; `%d` is the total.
var suffix_format: String = "of %d out"

var _icon: IconSlot = IconSlot.new("", 24.0)
var _name: Label = Label.new()
var _count: Label = Label.new()
var _of_text: Label = Label.new()


func _init() -> void:
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_icon)
	row.add_child(_name)
	row.add_child(_count)
	row.add_child(_of_text)
	add_child(row)
	_refresh()
	resized.connect(_refresh_radius)


func setup(icon_id: String, display_name: String, count: int, total: int, config: GameConfig = null) -> void:
	_icon.icon_id = icon_id
	_icon.config = config
	_name.text = display_name
	_count.text = str(count)
	_of_text.text = suffix_format % total


## The visible count and suffix, e.g. "4 of 5".
func count_text() -> String:
	return "%s %s" % [_count.text, _of_text.text]


func set_night(value: bool) -> void:
	night = value
	_refresh()


func _refresh() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var sb: StyleBoxFlat = KitDraw.make_box(pal["chip"] as Color, ROW_HEIGHT * 0.5)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", sb)
	UiFonts.style_label(_name, 15, 600, pal["ink"] as Color)
	UiFonts.style_label(_count, 15, 800, pal["ink"] as Color)
	UiFonts.style_label(_of_text, 14, 400, pal["muted"] as Color)


func _refresh_radius() -> void:
	var sb: StyleBoxFlat = get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.set_corner_radius_all(int(size.y * 0.5))
