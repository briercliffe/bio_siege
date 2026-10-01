class_name HudCombat
extends Control

## Infection HUD, screen 11 (night theme). Positions come from the mockup canvas source Combat.dc.html
## at 1280x720; the pills and cards are anchored to their corners so a larger viewport keeps the layout.
## Every number is read from the BattleSim (or the config before a sim exists) and refreshed on
## BattleRunner.ticked.

## The Pause button was pressed; the Infection phase opens the Pause menu.
signal pause_requested

const PAUSE_POS: Vector2 = Vector2(20.0, 14.0)
const PHASE_POS: Vector2 = Vector2(84.0, 14.0)
const PILL_HEIGHT: float = 52.0
const PHASE_TITLE: String = "PHASE 3 · INFECTION"
const PHASE_SUBTITLE: String = "Siege in progress"
const TIMER_TOP: float = 10.0
const TIMER_SIZE: Vector2 = Vector2(220.0, 56.0)
const ALIVE_TOP: float = 14.0
const EDGE: float = 20.0
const CARD_TOP: float = 96.0
const CARD_WIDTH: float = 300.0
const NUCLEUS_SIZE: Vector2 = Vector2(828.0, 72.0)
const NUCLEUS_BOTTOM: float = 16.0
const NUCLEUS_ICON_PX: float = 44.0
const NUCLEUS_RADIUS: float = 36.0
const NUCLEUS_ALPHA: float = 0.92
const KICKER_SPACING: int = 2
## Below this many seconds the timer turns to the danger colour.
const TIMER_WARN_S: int = 20
const TIMER_WARN_COLOR: Color = Color("#ff8a7e")

const LEGEND: Array[Dictionary] = [
	{"kind": CombatLegendSwatch.Kind.INTENT_LINE, "text": "Line: who a unit is heading for"},
	{"kind": CombatLegendSwatch.Kind.WALL_CRACKS, "text": "Cracks: a wall is being broken"},
	{"kind": CombatLegendSwatch.Kind.HEALTH_BAR, "text": "Bar: health of a damaged unit"},
	{"kind": CombatLegendSwatch.Kind.ANTIBODY, "text": "Glow: an antibody in flight"},
]

var session: Session = null
var runner: BattleRunner = null
var custom_sim: BattleSim = null

var pause_button: IconButton = null
var phase_pill: PillPanel = null
var timer_pill: PillPanel = null
var timer_caption: Label = null
var timer_label: Label = null
var alive_pill: PillPanel = null
var alive_value_label: Label = null
var alive_total_label: Label = null
var left_card: FloatingCard = null
var intent_switch: ToggleSwitch = null
var right_card: FloatingCard = null
var army_box: VBoxContainer = null
## Pathogen type id -> ListRow, in config order.
var army_rows: Dictionary = {}
var walls_tile: StatTile = null
var towers_tile: StatTile = null
var nucleus_card: PanelContainer = null
var nucleus_bar: NucleusHealthBar = null
var nucleus_hp_label: Label = null
var nucleus_max_label: Label = null

var timer_color: Color = UiPalette.color(true, "ink")
var _intent_lines_fallback: bool = true
var _army_types: Array[String] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _ready() -> void:
	update_display()


func setup(p_session: Session, p_runner: BattleRunner) -> void:
	session = p_session
	runner = p_runner
	if runner != null and not runner.ticked.is_connected(_on_runner_ticked):
		runner.ticked.connect(_on_runner_ticked)
	update_display()


func set_sim(p_sim: BattleSim) -> void:
	custom_sim = p_sim
	update_display()


func get_sim() -> BattleSim:
	if custom_sim != null:
		return custom_sim
	if runner != null:
		return runner.sim
	return null


func _on_runner_ticked() -> void:
	update_display()


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _on_intent_toggled(on: bool) -> void:
	if session != null:
		session.intent_lines_enabled = on
	else:
		_intent_lines_fallback = on
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("intent_lines_toggled", {"on": on})


func intent_lines_on() -> bool:
	return session.intent_lines_enabled if session != null else _intent_lines_fallback


func update_display(p_sim: BattleSim = null) -> void:
	if p_sim != null:
		custom_sim = p_sim
	intent_switch.set_pressed_no_signal(intent_lines_on())
	intent_switch.queue_redraw()

	var sim: BattleSim = get_sim()
	var cfg: GameConfig = _config(sim)
	_update_timer(sim, cfg)
	_update_alive(sim)
	_update_army(sim, cfg)
	_update_defense(sim)
	_update_nucleus(sim, cfg)


func _config(sim: BattleSim) -> GameConfig:
	if sim != null and sim.config != null:
		return sim.config
	if runner != null and runner.config != null:
		return runner.config
	if session != null:
		return session.config
	return null


func _update_timer(sim: BattleSim, cfg: GameConfig) -> void:
	if cfg == null:
		timer_label.text = "-:--"
		return
	var tick_rate: int = maxi(cfg.tick_rate, 1)
	var cur_tick: int = sim.tick if sim != null else 0
	var remaining_ticks: int = maxi(0, cfg.battle_timeout_ticks - cur_tick)
	var remaining_s: int = remaining_ticks / tick_rate
	timer_label.text = "%d:%02d" % [remaining_s / 60, remaining_s % 60]
	timer_color = TIMER_WARN_COLOR if remaining_s < TIMER_WARN_S else UiPalette.color(true, "ink")
	timer_label.add_theme_color_override("font_color", timer_color)


func _update_alive(sim: BattleSim) -> void:
	var alive: int = 0
	var total: int = 0
	if sim != null:
		total = sim.pathogens.size()
		for p: PathogenState in sim.pathogens:
			if p != null and p.alive:
				alive += 1
	alive_value_label.text = str(alive)
	alive_total_label.text = "of %d" % total


## "Rhinovirus 4 of 5": alive of launched, one row per type in the battle.
func _update_army(sim: BattleSim, cfg: GameConfig) -> void:
	var alive: Dictionary = {}
	var launched: Dictionary = {}
	if sim != null:
		for p: PathogenState in sim.pathogens:
			if p == null:
				continue
			launched[p.type_id] = int(launched.get(p.type_id, 0)) + 1
			if p.alive:
				alive[p.type_id] = int(alive.get(p.type_id, 0)) + 1
	var types: Array[String] = []
	if cfg != null:
		for id: Variant in cfg.pathogens.keys():
			if launched.has(str(id)):
				types.append(str(id))
	for id: Variant in launched.keys():
		if not types.has(str(id)):
			types.append(str(id))
	if types != _army_types:
		_rebuild_army_rows(types, cfg)
	for id: String in types:
		var row: ListRow = army_rows[id] as ListRow
		row.setup(id, _pathogen_name(id, cfg), int(alive.get(id, 0)), int(launched[id]), cfg)


func _rebuild_army_rows(types: Array[String], cfg: GameConfig) -> void:
	for row: Variant in army_rows.values():
		(row as ListRow).queue_free()
	army_rows.clear()
	_army_types = types.duplicate()
	for id: String in types:
		var row := ListRow.new()
		row.name = "Row_%s" % id
		row.night = true
		row.suffix_format = "of %d"
		row.setup(id, _pathogen_name(id, cfg), 0, 0, cfg)
		army_box.add_child(row)
		army_rows[id] = row


static func _pathogen_name(id: String, cfg: GameConfig) -> String:
	if cfg != null and cfg.pathogens.has(id):
		var def: PathogenDef = cfg.pathogens[id] as PathogenDef
		if def.display_name != "":
			return def.display_name
	return id.capitalize()


## Walls are wall-tagged structures; towers are structures with an attack.
func _update_defense(sim: BattleSim) -> void:
	var walls_alive: int = 0
	var walls_total: int = 0
	var towers_alive: int = 0
	var towers_total: int = 0
	if sim != null:
		for s: StructureState in sim.structures:
			if s == null or s.def == null:
				continue
			if s.def.has_tag("wall"):
				walls_total += 1
				if s.alive:
					walls_alive += 1
			elif s.def.has_attack:
				towers_total += 1
				if s.alive:
					towers_alive += 1
	walls_tile.setup("Walls", str(walls_alive), "of %d" % walls_total)
	towers_tile.setup("Towers", str(towers_alive), "of %d" % towers_total)


func _update_nucleus(sim: BattleSim, cfg: GameConfig) -> void:
	var hp: int = 0
	var max_hp: int = 0
	var nuc: StructureState = _find_nucleus(sim)
	if nuc != null:
		hp = nuc.hp if nuc.alive else 0
		max_hp = nuc.max_hp
	elif sim == null and cfg != null and cfg.structures.has("nucleus"):
		max_hp = (cfg.structures["nucleus"] as StructureDef).hp
		hp = max_hp
	nucleus_hp_label.text = str(hp)
	nucleus_max_label.text = " / %d" % max_hp
	nucleus_bar.ratio = float(hp) / float(max_hp) if max_hp > 0 else 0.0


static func _find_nucleus(sim: BattleSim) -> StructureState:
	if sim == null:
		return null
	if sim.nucleus_id != 0:
		var nuc: StructureState = sim.structure(sim.nucleus_id)
		if nuc != null:
			return nuc
	for s: StructureState in sim.structures:
		if s.def != null and s.def.has_tag("core"):
			return s
	return null


# --- layout --------------------------------------------------------------------

func _build() -> void:
	var pal: Dictionary = UiPalette.for_theme(true)
	var ink: Color = pal["ink"] as Color
	var muted: Color = pal["muted"] as Color

	pause_button = IconButton.new(IconButton.Kind.PAUSE)
	pause_button.name = "PauseButton"
	pause_button.night = true
	pause_button.position = PAUSE_POS
	pause_button.pressed.connect(_on_pause_pressed)
	add_child(pause_button)

	phase_pill = _pill("PhasePill", PILL_HEIGHT)
	phase_pill.position = PHASE_POS
	var phase_box := _vbox(0)
	phase_box.alignment = BoxContainer.ALIGNMENT_CENTER
	phase_box.add_child(_kicker(PHASE_TITLE, pal["accent"] as Color))
	phase_box.add_child(_label(PHASE_SUBTITLE, 15, 700, ink))
	phase_pill.add_child(phase_box)

	timer_pill = _pill("TimerPill", TIMER_SIZE.y)
	timer_pill.custom_minimum_size = TIMER_SIZE
	_anchor_top_center(timer_pill, TIMER_TOP, TIMER_SIZE)
	var timer_row := _hbox(10)
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_caption = _label("Time left", 14, 400, muted)
	timer_label = _label("0:00", 28, 800, ink)
	timer_label.name = "TimerLabel"
	timer_row.add_child(timer_caption)
	timer_row.add_child(timer_label)
	timer_pill.add_child(timer_row)

	alive_pill = _pill("AlivePill", PILL_HEIGHT)
	_anchor_top_right(alive_pill, ALIVE_TOP, PILL_HEIGHT)
	var alive_row := _hbox(10)
	alive_row.alignment = BoxContainer.ALIGNMENT_CENTER
	alive_value_label = _label("0", 26, 800, ink)
	alive_value_label.name = "AliveValue"
	alive_total_label = _label("of 0", 14, 400, muted)
	alive_total_label.name = "AliveTotal"
	alive_row.add_child(_label("Alive", 14, 400, muted))
	alive_row.add_child(alive_value_label)
	alive_row.add_child(alive_total_label)
	alive_pill.add_child(alive_row)

	_build_left_card(ink, muted)
	_build_right_card(muted)
	_build_nucleus_card(ink, muted)


func _build_left_card(ink: Color, muted: Color) -> void:
	left_card = FloatingCard.new()
	left_card.name = "LeftCard"
	left_card.night = true
	left_card.mouse_filter = Control.MOUSE_FILTER_STOP
	left_card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	left_card.position = Vector2(EDGE, CARD_TOP)
	add_child(left_card)
	var box := _vbox(14)
	left_card.add_child(box)

	var intent_row := _hbox(10)
	intent_row.custom_minimum_size = Vector2(0.0, 56.0)
	intent_switch = ToggleSwitch.new()
	intent_switch.name = "IntentSwitch"
	intent_switch.night = true
	intent_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intent_switch.toggled.connect(_on_intent_toggled)
	intent_row.add_child(intent_switch)
	var intent_text := _vbox(0)
	intent_text.alignment = BoxContainer.ALIGNMENT_CENTER
	intent_text.add_child(_label("Intent lines", 16, 700, ink))
	intent_text.add_child(_wrapping(_label("Each pathogen to its target", 14, 400, muted)))
	intent_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intent_row.add_child(intent_text)
	box.add_child(intent_row)

	box.add_child(_kicker("READING THE BATTLE", muted))
	var legend := _vbox(12)
	for entry: Dictionary in LEGEND:
		var row := _hbox(12)
		row.add_child(CombatLegendSwatch.new(entry["kind"] as CombatLegendSwatch.Kind))
		row.add_child(_wrapping(_label(entry["text"] as String, 14, 400, ink)))
		legend.add_child(row)
	box.add_child(legend)


func _build_right_card(muted: Color) -> void:
	right_card = FloatingCard.new()
	right_card.name = "RightCard"
	right_card.night = true
	right_card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	right_card.anchor_left = 1.0
	right_card.anchor_right = 1.0
	right_card.offset_left = -EDGE - CARD_WIDTH
	right_card.offset_right = -EDGE
	right_card.offset_top = CARD_TOP
	right_card.offset_bottom = CARD_TOP
	right_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(right_card)
	var box := _vbox(12)
	right_card.add_child(box)

	box.add_child(_kicker("ARMY", muted))
	army_box = _vbox(8)
	army_box.name = "ArmyRows"
	box.add_child(army_box)

	var defense_kicker: Label = _kicker("DEFENSE", muted)
	var defense_wrap := MarginContainer.new()
	defense_wrap.add_theme_constant_override("margin_top", 6)
	defense_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	defense_wrap.add_child(defense_kicker)
	box.add_child(defense_wrap)
	var tiles := _hbox(8)
	walls_tile = StatTile.new("Walls", "0", "of 0")
	walls_tile.name = "WallsTile"
	towers_tile = StatTile.new("Towers", "0", "of 0")
	towers_tile.name = "TowersTile"
	for tile: StatTile in [walls_tile, towers_tile]:
		tile.night = true
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(tile)
	box.add_child(tiles)


func _build_nucleus_card(ink: Color, muted: Color) -> void:
	var pal: Dictionary = UiPalette.for_theme(true)
	nucleus_card = PanelContainer.new()
	nucleus_card.name = "NucleusCard"
	nucleus_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: Color = pal["panel"] as Color
	fill.a = NUCLEUS_ALPHA
	var sb: StyleBoxFlat = KitDraw.make_box(fill, NUCLEUS_RADIUS, 2, pal["panel_border"] as Color,
			pal["panel_shadow"] as Color, 22, Vector2(0.0, 8.0))
	sb.content_margin_left = 18.0
	sb.content_margin_right = 28.0
	nucleus_card.add_theme_stylebox_override("panel", sb)
	nucleus_card.anchor_left = 0.5
	nucleus_card.anchor_right = 0.5
	nucleus_card.anchor_top = 1.0
	nucleus_card.anchor_bottom = 1.0
	nucleus_card.offset_left = -NUCLEUS_SIZE.x * 0.5
	nucleus_card.offset_right = NUCLEUS_SIZE.x * 0.5
	nucleus_card.offset_top = -NUCLEUS_BOTTOM - NUCLEUS_SIZE.y
	nucleus_card.offset_bottom = -NUCLEUS_BOTTOM
	nucleus_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	nucleus_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(nucleus_card)

	var row := _hbox(16)
	nucleus_card.add_child(row)
	row.add_child(IconSlot.new("nucleus", NUCLEUS_ICON_PX))
	row.add_child(_label("Nucleus", 18, 800, ink))
	nucleus_bar = NucleusHealthBar.new()
	nucleus_bar.name = "NucleusBar"
	row.add_child(nucleus_bar)
	var value_row := _hbox(0)
	nucleus_hp_label = _label("0", 22, 800, ink)
	nucleus_hp_label.name = "NucleusHp"
	nucleus_max_label = _label(" / 0", 16, 600, muted)
	nucleus_max_label.name = "NucleusMax"
	nucleus_max_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_row.add_child(nucleus_hp_label)
	value_row.add_child(nucleus_max_label)
	row.add_child(value_row)


func _pill(node_name: String, height: float) -> PillPanel:
	var pill := PillPanel.new()
	pill.name = node_name
	pill.night = true
	pill.custom_minimum_size = Vector2(0.0, height)
	add_child(pill)
	return pill


func _anchor_top_center(c: Control, top: float, sz: Vector2) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -sz.x * 0.5
	c.offset_right = sz.x * 0.5
	c.offset_top = top
	c.offset_bottom = top + sz.y
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _anchor_top_right(c: Control, top: float, height: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.offset_left = -EDGE
	c.offset_right = -EDGE
	c.offset_top = top
	c.offset_bottom = top + height
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _label(text: String, px: int, weight: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiFonts.style_label(l, px, weight, color)
	return l


## The default font runs a little wider than the canvas font, so card text wraps rather than widening the card.
func _wrapping(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _kicker(text: String, color: Color) -> Label:
	var l: Label = _label(text, 12, 700, color)
	var v := FontVariation.new()
	v.base_font = UiFonts.weight(700)
	v.spacing_glyph = KICKER_SPACING
	l.add_theme_font_override("font", v)
	return l


func _hbox(sep: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b
