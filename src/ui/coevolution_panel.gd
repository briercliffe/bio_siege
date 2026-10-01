class_name CoevolutionPanel
extends PanelContainer

## Read-only view of what each breeding type carries (coevolution flag). Nothing here is tappable.

const EMPTY_TEXT: String = "No mutations yet. The fittest fighters parent the next generation."

var session: Session = null
var rows_box: VBoxContainer = null
var title_label: Label = null
var empty_label: Label = null


func _init() -> void:
	name = "CoevolutionPanel"
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
	title_label.text = "Populations"
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


## A pool is worth a row once any genome carries an allele.
static func should_show_type(pool: BreedPool) -> bool:
	return pool != null and not pool.is_wild()


## "B-Cell: Binder A vs Capsule A · parent 5/8". The parent clause needs a bred summary.
static func row_text(type_id: String, pool: BreedPool, breed_summary: Dictionary, config: GameConfig) -> String:
	var receptor: String = _modal_allele(pool, true, config)
	var antigen: String = _modal_allele(pool, false, config)
	var receptor_text: String = "no binder" if receptor.is_empty() else str(config.coevo_receptor_name.get(receptor, receptor))
	var antigen_text: String = "no marker" if antigen.is_empty() else str(config.coevo_antigen_name.get(antigen, antigen))
	var text: String = "%s: %s vs %s" % [type_name(type_id, config), receptor_text, antigen_text]
	if bool(breed_summary.get("bred", false)):
		text += " · parent %d/%d" % [int(breed_summary.get("top_count", 0)), int(breed_summary.get("pool_size", 0))]
	return text


static func type_name(type_id: String, config: GameConfig) -> String:
	if config != null:
		if config.pathogens.has(type_id):
			var p_def: PathogenDef = config.pathogens[type_id]
			if not p_def.display_name.is_empty():
				return p_def.display_name
		if config.structures.has(type_id):
			var s_def: StructureDef = config.structures[type_id]
			if not s_def.display_name.is_empty():
				return s_def.display_name
	return type_id


## The allele that fills the most slots across the pool ("" when every slot is empty).
## Ties go to the allele that comes first in the JSON catalog.
static func _modal_allele(pool: BreedPool, receptors: bool, config: GameConfig) -> String:
	var counts: Dictionary = {}
	for g: Genome in pool.genomes:
		var slots: Array[String] = g.receptors if receptors else g.antigens
		for allele: String in slots:
			if not allele.is_empty():
				counts[allele] = int(counts.get(allele, 0)) + 1
	var catalog: Array = (config.coevo_receptor_name if receptors else config.coevo_antigen_name).keys()
	var best: String = ""
	var best_count: int = 0
	for allele_var: Variant in catalog:
		var c: int = int(counts.get(allele_var, 0))
		if c > best_count:
			best_count = c
			best = str(allele_var)
	return best


## The latest breed summary for a type from last_result["evolution"], or {} when it has not bred.
static func summary_for(last_result: Dictionary, type_id: String) -> Dictionary:
	var evo: Variant = last_result.get("evolution", [])
	if evo is Array:
		for e_val: Variant in evo:
			if e_val is Dictionary and str((e_val as Dictionary).get("type_id", "")) == type_id and bool((e_val as Dictionary).get("bred", false)):
				return e_val
	return {}


func refresh() -> void:
	if rows_box == null:
		return
	for c: Node in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	var cfg: GameConfig = session.config if session != null else null
	if cfg == null or not cfg.coevolution_enabled():
		empty_label.visible = true
		return
	var type_ids: Array[String] = cfg.coevo_types.duplicate()
	type_ids.sort()
	var shown: int = 0
	for type_id: String in type_ids:
		var pool: BreedPool = session.population(type_id)
		if not should_show_type(pool):
			continue
		var lbl := Label.new()
		lbl.name = "Row_" + type_id
		lbl.text = row_text(type_id, pool, summary_for(session.last_result, type_id), cfg)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 12)
		rows_box.add_child(lbl)
		shown += 1
	empty_label.visible = shown == 0
