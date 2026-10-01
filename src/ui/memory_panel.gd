class_name MemoryPanel
extends PanelContainer

## Read-only view of the base's immune memory (immune_memory flag). Nothing here is tappable.

const PIP_COLOR: Color = Color("#48dbfb")
const PIP_SIZE: float = 10.0
const EMPTY_TEXT: String = "No memory yet. B-Cells remember strains they fully analyze."

var session: Session = null
var rows_box: VBoxContainer = null
var title_label: Label = null
var empty_label: Label = null


## Draws `max_level` pips: `level` filled, the rest outlined.
class PipRow:
	extends Control

	var level: int = 0
	var max_level: int = 0

	func _init(p_level: int, p_max: int) -> void:
		level = p_level
		max_level = p_max
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(float(p_max) * (PIP_SIZE + 2.0), PIP_SIZE + 4.0)

	func _draw() -> void:
		for i: int in range(max_level):
			var r := Rect2(Vector2(float(i) * (PIP_SIZE + 2.0), 2.0), Vector2(PIP_SIZE, PIP_SIZE))
			if i < level:
				draw_rect(r, PIP_COLOR, true)
			else:
				draw_rect(r, PIP_COLOR, false, 1.0)


func _init() -> void:
	name = "MemoryPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240.0, 0.0)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -256.0
	offset_right = -16.0
	offset_top = 72.0
	offset_bottom = 72.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 4)
	margin.add_child(outer)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Immune memory"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override("font_size", 14)
	outer.add_child(title_label)

	empty_label = Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = EMPTY_TEXT
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.add_theme_font_size_override("font_size", 11)
	empty_label.add_theme_color_override("font_color", Color("#9aa5b1"))
	outer.add_child(empty_label)

	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows_box.add_theme_constant_override("separation", 2)
	outer.add_child(rows_box)


func setup(p_session: Session) -> void:
	session = p_session
	refresh()


## "<pathogen display_name> · <strain display_name>", falling back to ids.
static func row_text(strain_key: String, config: GameConfig) -> String:
	var type_id: String = strain_key.get_slice("/", 0)
	var variant_id: String = strain_key.get_slice("/", 1)
	var p_def: PathogenDef = null
	if config != null and config.pathogens.has(type_id):
		p_def = config.pathogens[type_id]
	var p_name: String = p_def.display_name if p_def != null and not p_def.display_name.is_empty() else type_id
	var s_name: String = variant_id
	if p_def != null:
		var sd: StrainDef = p_def.strain(variant_id)
		if sd != null and not sd.display_name.is_empty():
			s_name = sd.display_name
	return "%s · %s" % [p_name, s_name]


## "Rhinovirus (wild)" style label used by the results line.
static func strain_label(strain_key: String, config: GameConfig) -> String:
	var type_id: String = strain_key.get_slice("/", 0)
	var variant_id: String = strain_key.get_slice("/", 1)
	var p_name: String = type_id
	if config != null and config.pathogens.has(type_id):
		var p_def: PathogenDef = config.pathogens[type_id]
		if not p_def.display_name.is_empty():
			p_name = p_def.display_name
	return "%s (%s)" % [p_name, variant_id]


func refresh() -> void:
	if rows_box == null:
		return
	for c: Node in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	var cfg: GameConfig = session.config if session != null else null
	var mem: ImmuneMemory = session.defender_memory() if session != null else null
	if cfg == null or mem == null or mem.is_empty():
		empty_label.visible = true
		return
	empty_label.visible = false

	var keys: Array[String] = []
	for k: Variant in mem.entries.keys():
		keys.append(str(k))
	keys.sort_custom(func(a: String, b: String) -> bool:
		var la: int = mem.level_of(a)
		var lb: int = mem.level_of(b)
		if la != lb:
			return la > lb
		return a < b
	)
	for key: String in keys:
		var entry: Dictionary = mem.entries[key]
		var row := HBoxContainer.new()
		row.name = "Row_" + key.replace("/", "_")
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = row_text(key, cfg)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl)
		if int(entry.get("absent", 0)) > 0:
			var fading := Label.new()
			fading.name = "FadingLabel"
			fading.text = "fading"
			fading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fading.add_theme_font_size_override("font_size", 10)
			fading.add_theme_color_override("font_color", Color("#7f8c8d"))
			row.add_child(fading)
		row.add_child(PipRow.new(int(entry.get("level", 0)), cfg.memory_max_level))
		rows_box.add_child(row)
