class_name ResultsPhase
extends Control

## Results screens 13 (Nucleus destroyed) and 14 (Defense held), night theme at 1280x720. The left column
## (x 64 to 764) holds the outcome header, four stat tiles, the ATP split card and the three choice buttons.
## The right column (x 820 to 1216) holds the final-state card, the one-question survey and the log export.
## Positions follow the mockup canvas sources Victory and Defeat; both columns are anchored to their edge.

signal choice_made(choice: String)

const KICKER_TEXT: String = "PHASE 4 · RESULTS"
const KICKER_ATTACKER: Color = Color("#2ecc71")
const KICKER_DEFENDER: Color = Color("#8fb8ff")
const BADGE_FILL: Color = Color("#1f3b66")
const BADGE_TEXT: String = "Time limit reached"
const SPLIT_COLOR_BASE: Color = Color("#2e86de")
const SPLIT_COLOR_ARMY: Color = Color("#2ecc71")
const SPLIT_COLOR_UNSPENT: Color = Color("#8a7a7e")
## get_atp_split_widths() is reported against this bar width; the drawn bar uses the same fractions.
const SPLIT_BAR_WIDTH: float = 560.0
const SPLIT_BAR_HEIGHT: float = 28.0
const SPLIT_GAP: float = 2.0

const MARGIN: float = 64.0
const TOP: float = 48.0
const LEFT_WIDTH: float = 700.0
const RIGHT_WIDTH: float = 396.0
const TILE_SIZE: Vector2 = Vector2(165.0, 88.0)
const BUTTON_HEIGHT: float = 72.0
const RE_RAID_WIDTH: float = 250.0
const EDIT_WIDTH: float = 210.0
const NEW_BASE_WIDTH: float = 212.0
const ISLAND_SIZE: Vector2 = Vector2(230.0, 150.0)

const TITLE_ATTACKER: String = "Nucleus destroyed"
const TITLE_DEFENDER: String = "Defense held"


## Holds the final-state island thumbnail and clips it to its frame.
class IslandHolder:
	extends Control

	func _init() -> void:
		custom_minimum_size = ISLAND_SIZE
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE


## A small coloured dot for the ATP legend.
class LegendDot:
	extends Control

	var color: Color = Color.WHITE

	func _init(p_color: Color) -> void:
		color = p_color
		custom_minimum_size = Vector2(12.0, 12.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 6.0, color)


var session: Session = null
var fsm: GameStateMachine = null
## Receives the survey and export events. Null means the SessionLogger autoload; tests pass their own.
var logger: Node = null

var background: AmbientBackground = null

# Header
var kicker_label: Label = null
var badge: PanelContainer = null
var title_label: Label = null
var reason_label: Label = null
var score_label: Label = null
var loot_label: Label = null
var memory_label: Label = null
var evolution_label: Label = null

# Stat tiles
var tile_battle_time: StatTile = null
var tile_nucleus_hp: StatTile = null
var tile_pathogens_alive: StatTile = null
var tile_structures_lost: StatTile = null

var stats: Dictionary = {}

# ATP split card
var atp_title_label: Label = null
var atp_track: ProgressTrack = null
## "base", "army" and "unspent" -> the bold amount label in the legend.
var legend_values: Dictionary = {}

var base_atp: int = 0
var army_atp: int = 0
var unspent_atp: int = 0
var split_widths: Dictionary = {}

# Buttons
var btn_re_raid: PillButton = null
var btn_edit_base: PillButton = null
var btn_new_base: PillButton = null

# Right column
var final_card: FloatingCard = null
var island_holder: IslandHolder = null
var island_view: GridView = null
var island_grid: GridModel = null
var final_title_label: Label = null
var final_summary_label: Label = null
var survey_card: ResultsSurveyCard = null
var btn_export_logs: ResultsSurveyCard.TextLink = null

var _ink: Color = UiPalette.color(true, "ink")
var _muted: Color = UiPalette.color(true, "muted")


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


func setup(p_session: Session, p_fsm: GameStateMachine = null) -> void:
	session = p_session
	fsm = p_fsm
	_populate()


# --- build -------------------------------------------------------------------------------

func _build() -> void:
	background = AmbientBackground.new()
	background.name = "Background"
	background.night = true
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_build_left_column()
	_build_right_column()


func _build_left_column() -> void:
	var col := HudParts.vbox(14)
	col.name = "LeftColumn"
	col.set_anchors_preset(Control.PRESET_TOP_LEFT)
	col.offset_left = MARGIN
	col.offset_top = TOP
	col.offset_right = MARGIN + LEFT_WIDTH
	col.custom_minimum_size = Vector2(LEFT_WIDTH, 0.0)
	add_child(col)

	var head := HudParts.vbox(0)
	col.add_child(head)

	var kicker_row := HudParts.hbox(14)
	head.add_child(kicker_row)
	kicker_label = HudParts.kicker(KICKER_TEXT, KICKER_ATTACKER)
	kicker_label.name = "KickerLabel"
	kicker_label.add_theme_font_size_override("font_size", 13)
	kicker_row.add_child(kicker_label)
	badge = PanelContainer.new()
	badge.name = "TimeoutBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_box: StyleBoxFlat = KitDraw.make_box(BADGE_FILL, 999.0)
	badge_box.content_margin_left = 14.0
	badge_box.content_margin_right = 14.0
	badge_box.content_margin_top = 4.0
	badge_box.content_margin_bottom = 4.0
	badge.add_theme_stylebox_override("panel", badge_box)
	badge.add_child(HudParts.label(BADGE_TEXT, 13, 700, Color.WHITE))
	badge.visible = false
	kicker_row.add_child(badge)

	title_label = HudParts.label(TITLE_ATTACKER, 64, 800, _ink)
	title_label.name = "TitleLabel"
	head.add_child(title_label)

	reason_label = HudParts.wrapping(HudParts.label("", 18, 400, _muted))
	reason_label.name = "ReasonLabel"
	head.add_child(reason_label)

	# Lines for the optional flags (raid score, immune memory). Hidden when their flags are off.
	var extras := HudParts.vbox(4)
	extras.name = "FlagLines"
	head.add_child(extras)
	score_label = HudParts.wrapping(HudParts.label("", 14, 700, _ink))
	score_label.name = "ScoreLabel"
	score_label.visible = false
	extras.add_child(score_label)
	loot_label = HudParts.wrapping(HudParts.label("", 14, 700, KICKER_ATTACKER))
	loot_label.name = "LootLabel"
	loot_label.visible = false
	extras.add_child(loot_label)
	memory_label = HudParts.wrapping(HudParts.label("", 14, 400, _muted))
	memory_label.name = "MemoryLabel"
	memory_label.visible = false
	extras.add_child(memory_label)
	evolution_label = HudParts.wrapping(HudParts.label("", 14, 400, _muted))
	evolution_label.name = "EvolutionLabel"
	evolution_label.visible = false
	extras.add_child(evolution_label)

	var tiles := HudParts.hbox(12)
	tiles.name = "StatTiles"
	col.add_child(tiles)
	tile_battle_time = _make_tile(tiles, "Battle time", "TileBattleTime")
	tile_nucleus_hp = _make_tile(tiles, "Nucleus HP left", "TileNucleusHp")
	tile_pathogens_alive = _make_tile(tiles, "Pathogens alive", "TilePathogensAlive")
	tile_structures_lost = _make_tile(tiles, "Structures lost", "TileStructuresLost")

	col.add_child(_build_atp_card())

	var buttons := HudParts.hbox(12)
	buttons.name = "ChoiceButtons"
	col.add_child(buttons)
	btn_re_raid = _make_choice_button(buttons, "BtnReRaid", "Re-raid", "Same base, new army",
			PillButton.Variant.PRIMARY, RE_RAID_WIDTH, "re_raid")
	btn_edit_base = _make_choice_button(buttons, "BtnEditBase", "Edit base", "Back to Synthesis",
			PillButton.Variant.SECONDARY, EDIT_WIDTH, "edit_base")
	btn_new_base = _make_choice_button(buttons, "BtnNewBase", "New base", "Reset to 1000 ATP",
			PillButton.Variant.SECONDARY, NEW_BASE_WIDTH, "new_base")


func _make_tile(parent: Control, label: String, node_name: String) -> StatTile:
	var tile := StatTile.new(label, "", "")
	tile.name = node_name
	tile.night = true
	tile.label_px = 14
	tile.value_px = 28
	tile.custom_minimum_size = TILE_SIZE
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(tile)
	return tile


func _make_choice_button(parent: Control, node_name: String, title: String, sub: String,
		variant: PillButton.Variant, width: float, choice: String) -> PillButton:
	var b := PillButton.new(title, variant)
	b.name = node_name
	b.night = true
	b.pressed.connect(make_choice.bind(choice))
	parent.add_child(b)
	_set_button(b, title, sub, width)
	return b


## Sets a choice button's two lines and its fixed size. PillButton resets its minimum size whenever the
## subtitle changes, so the size is applied last.
func _set_button(b: PillButton, title: String, sub: String, width: float) -> void:
	b.text = title
	b.subtitle = sub
	b.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)


func _build_atp_card() -> FloatingCard:
	var card := FloatingCard.new()
	card.name = "AtpCard"
	card.night = true
	card.custom_minimum_size = Vector2(LEFT_WIDTH, 0.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var box := HudParts.vbox(14)
	margin.add_child(box)

	atp_title_label = HudParts.label("", 17, 700, _ink)
	atp_title_label.name = "AtpTitleLabel"
	box.add_child(atp_title_label)

	atp_track = ProgressTrack.new()
	atp_track.name = "AtpTrack"
	atp_track.night = true
	atp_track.track_height = SPLIT_BAR_HEIGHT
	atp_track.segment_gap = SPLIT_GAP
	box.add_child(atp_track)

	var legend := HudParts.hbox(22)
	legend.name = "AtpLegend"
	box.add_child(legend)
	_add_legend_entry(legend, "base", "Base", SPLIT_COLOR_BASE)
	_add_legend_entry(legend, "army", "Army", SPLIT_COLOR_ARMY)
	_add_legend_entry(legend, "unspent", "Unspent", SPLIT_COLOR_UNSPENT)
	return card


func _add_legend_entry(parent: Control, key: String, label: String, color: Color) -> void:
	var entry := HudParts.hbox(8)
	entry.add_child(LegendDot.new(color))
	entry.add_child(HudParts.label(label, 14, 400, _muted))
	var value: Label = HudParts.label("0", 14, 800, _ink)
	value.name = "Legend%s" % label
	entry.add_child(value)
	legend_values[key] = value
	parent.add_child(entry)


func _build_right_column() -> void:
	var col := HudParts.vbox(22)
	col.name = "RightColumn"
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_right = -MARGIN
	col.offset_left = -MARGIN - RIGHT_WIDTH
	col.offset_top = TOP
	col.custom_minimum_size = Vector2(RIGHT_WIDTH, 0.0)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(col)

	final_card = FloatingCard.new()
	final_card.name = "FinalStateCard"
	final_card.night = true
	final_card.custom_minimum_size = Vector2(RIGHT_WIDTH, 186.0)
	col.add_child(final_card)
	var row := HudParts.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	final_card.add_child(row)
	island_holder = IslandHolder.new()
	island_holder.name = "IslandHolder"
	island_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(island_holder)
	var text_col := HudParts.vbox(4)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_col)
	final_title_label = HudParts.label("Final state", 17, 800, _ink)
	final_title_label.name = "FinalTitleLabel"
	text_col.add_child(final_title_label)
	final_summary_label = HudParts.wrapping(HudParts.label("", 14, 400, _muted))
	final_summary_label.name = "FinalSummaryLabel"
	final_summary_label.custom_minimum_size = Vector2(96.0, 0.0)
	text_col.add_child(final_summary_label)

	survey_card = ResultsSurveyCard.new()
	survey_card.name = "SurveyCard"
	survey_card.answered.connect(_on_survey_answered)
	survey_card.skipped.connect(_on_survey_skipped)
	col.add_child(survey_card)
	survey_card.setup(0)

	btn_export_logs = ResultsSurveyCard.TextLink.new("Export playtest logs")
	btn_export_logs.name = "BtnExportLogs"
	btn_export_logs.font_px = 13
	btn_export_logs.pressed.connect(_on_export_logs_pressed)
	col.add_child(btn_export_logs)


# --- populate ------------------------------------------------------------------------------

## "1:48" from seconds.
static func format_time(seconds: float) -> String:
	var total: int = maxi(int(seconds), 0)
	@warning_ignore("integer_division")
	var minutes: int = total / 60
	return "%d:%02d" % [minutes, total % 60]


func _populate() -> void:
	var res: Dictionary = session.last_result if session != null else {}
	var end_reason: String = str(res.get("end_reason", ""))
	var outcome: String = str(res.get("outcome", ""))
	var battle_s: float = float(res.get("battle_s", 0.0))
	var nucleus_hp: int = int(res.get("nucleus_hp", 0))
	var is_attacker_win: bool = (end_reason == "nucleus_destroyed" or outcome == "attacker")
	var is_timeout: bool = end_reason == "timeout"

	# Header
	kicker_label.add_theme_color_override("font_color", KICKER_ATTACKER if is_attacker_win else KICKER_DEFENDER)
	badge.visible = is_timeout
	title_label.text = TITLE_ATTACKER if is_attacker_win else TITLE_DEFENDER
	if end_reason == "nucleus_destroyed" or (is_attacker_win and end_reason.is_empty()):
		reason_label.text = ("Your army broke through the enemy base in %s." if is_living_base() else "Your army broke through your own defense in %s.") % format_time(battle_s)
	elif is_timeout:
		reason_label.text = "The %s timer ran out with the Nucleus at %d HP." % [format_time(_timeout_s(res, battle_s)), nucleus_hp]
	else:
		reason_label.text = "Every pathogen was eliminated after %s." % format_time(battle_s)

	# Stat tiles
	var nucleus_max_hp: int = int(res.get("nucleus_max_hp", 2000))
	var structures_destroyed: int = int(res.get("structures_destroyed", 0))
	var structures_total: int = int(res.get("structures_total", 0))
	var pathogens_lost: int = int(res.get("pathogens_lost", res.get("pathogens_killed", 0)))
	var pathogens_total: int = int(res.get("pathogens_total", 0))
	var pathogens_alive: int = maxi(pathogens_total - pathogens_lost, 0)
	var first_contact_s: float = float(res.get("first_contact_s", -1.0))

	tile_battle_time.setup("Battle time", format_time(battle_s))
	tile_nucleus_hp.setup("Nucleus HP left", str(nucleus_hp))
	tile_pathogens_alive.setup("Pathogens alive", str(pathogens_alive), "of %d" % pathogens_total)
	tile_structures_lost.setup("Structures lost", str(structures_destroyed), "of %d" % structures_total)

	var first_type: String = str(res.get("first_destroyed_structure_type", ""))
	var first_id: int = int(res.get("first_destroyed_structure_id", 0))
	var first_structure: String = str(res.get("first_structure_to_fall", ""))
	if first_structure.is_empty():
		first_structure = _structure_name(first_type) if (first_id > 0 and not first_type.is_empty()) else "none"

	stats = {
		"Battle time": format_time(battle_s),
		"Nucleus HP remaining": "%d / %d" % [nucleus_hp, nucleus_max_hp],
		"Structures destroyed": "%d / %d" % [structures_destroyed, structures_total],
		"Pathogens lost": "%d / %d" % [pathogens_lost, pathogens_total],
		"First structure to fall": first_structure,
		"Time to first contact": "never" if first_contact_s < 0.0 else format_time(first_contact_s),
	}

	_populate_final_state(res, first_id, first_type)
	_populate_score(res, is_attacker_win)
	_populate_loot(res)
	_populate_memory(res)
	_populate_evolution(res)
	_populate_atp_split()
	if is_living_base():
		_configure_living_base_buttons()
	else:
		_update_new_base_label()
	_populate_survey()


func _timeout_s(res: Dictionary, battle_s: float) -> float:
	if session != null and session.config != null and session.config.tick_rate > 0 and session.config.battle_timeout_ticks > 0:
		return float(session.config.battle_timeout_ticks) / float(session.config.tick_rate)
	var from_result: float = float(res.get("timeout_s", 0.0))
	return from_result if from_result > 0.0 else battle_s


func _structure_name(type_id: String) -> String:
	if session != null and session.config != null and session.config.structures.has(type_id):
		return (session.config.structures[type_id] as StructureDef).display_name
	return type_id.capitalize()


## One line under "Final state": what fell first, plus the player's prediction (#25) when one was made.
func _populate_final_state(res: Dictionary, first_id: int, first_type: String) -> void:
	var text: String = "No structure fell." if first_type.is_empty() else "The %s fell first." % _structure_name(first_type)
	var pred_id: int = int(res.get("prediction_structure_id", session.prediction_structure_id if session != null else 0))
	if pred_id > 0:
		if first_id > 0 and pred_id == first_id:
			text += " You predicted it ✓"
			stats["Prediction"] = "Your prediction: ✓ correct"
		else:
			var predicted_type: String = _predicted_type(pred_id)
			text += " You predicted the %s ✗" % (_structure_name(predicted_type) if not predicted_type.is_empty() else "wrong structure")
			stats["Prediction"] = "Your prediction: ✗ it was the %s" % (_structure_name(first_type) if not first_type.is_empty() else "none")
	final_summary_label.text = text
	_build_island(res)


func _predicted_type(pred_id: int) -> String:
	if session == null:
		return ""
	if session.attack_grid() != null:
		var placed: GridModel.PlacedStructure = session.attack_grid().get_structure(pred_id)
		if placed != null:
			return placed.type_id
	if session.battle_setup != null and pred_id >= 1 and pred_id <= session.battle_setup.structures.size():
		return str(session.battle_setup.structures[pred_id - 1].get("type", ""))
	return ""


## Rebuilds the thumbnail from the sim's surviving structures. Without `alive_structure_ids` (an old
## result) it shows the whole base.
func _build_island(res: Dictionary) -> void:
	if island_view == null:
		island_view = (load("res://src/view/grid_view.tscn") as PackedScene).instantiate() as GridView
		# GridView turns its input handling on at ready; the thumbnail is display-only.
		island_view.set_process_unhandled_input(false)
		island_holder.add_child(island_view)
	var cfg: GameConfig = session.config if session != null else null
	if cfg == null:
		island_grid = null
		return
	var alive_ids: Variant = res.get("alive_structure_ids", null)
	island_grid = build_final_grid(cfg, _final_layout(), alive_ids as Array if alive_ids is Array else [], alive_ids is Array)
	island_view.setup(island_grid, cfg)
	island_view.set_night(true)
	island_view.fit_to_rect(Rect2(Vector2.ZERO, ISLAND_SIZE))


func _final_layout() -> Array:
	if session == null:
		return []
	if session.battle_setup != null:
		return session.battle_setup.structures
	if session.grid != null:
		return session.grid.to_layout()
	return []


## A display-only GridModel holding the structures still alive at the end of the raid. Sim structure ids
## are 1-based positions in the battle setup, so `alive_ids` index into `layout`. With `filter` off the
## whole layout is shown.
static func build_final_grid(cfg: GameConfig, layout: Array, alive_ids: Array, filter: bool = true) -> GridModel:
	var grid := GridModel.new(cfg)
	# Display only: the wallet just has to afford every structure so place() accepts them.
	var rich: Dictionary = {}
	for cur: Variant in cfg.start_wallet.keys():
		rich[str(cur)] = 1000000000
	var wallet := Wallet.new(rich)
	var entries: Array[Dictionary] = []
	for i: int in range(layout.size()):
		if filter and not alive_ids.has(i + 1):
			continue
		var entry: Dictionary = layout[i]
		entries.append({"type": str(entry.get("type", "")), "origin": entry.get("origin", Vector2i.ZERO)})
	var core_entry: Dictionary = {}
	for e: Dictionary in entries:
		var sdef: StructureDef = cfg.structures.get(str(e["type"]))
		if sdef != null and sdef.has_tag("core") or str(e["type"]) == "nucleus":
			core_entry = e
			break
	if not core_entry.is_empty():
		grid.reset_with_nucleus()
		var core: GridModel.PlacedStructure = grid.find_core()
		if core != null:
			grid.move_structure(core.id, core_entry["origin"] as Vector2i)
	for e: Dictionary in entries:
		if e == core_entry:
			continue
		grid.place(str(e["type"]), e["origin"] as Vector2i, wallet)
	return grid


## Immune-memory line (immune_memory flag). Hidden and absent from stats when there are no changes.
func _populate_memory(res: Dictionary) -> void:
	var text: String = ""
	if session != null and session.config != null and session.config.memory_enabled() and res.has("memory_changes"):
		if is_living_base():
			text = base_learned_text(res.get("memory_changes", []), session.config)
		else:
			text = memory_changes_text(res.get("memory_changes", []), session.config)
	memory_label.text = text
	memory_label.visible = not text.is_empty()
	if not text.is_empty():
		stats["memory"] = text


## Coevolution line (coevolution flag). Hidden and absent from stats when nothing bred.
func _populate_evolution(res: Dictionary) -> void:
	var text: String = ""
	if session != null and session.config != null and session.config.coevolution_enabled() and res.has("evolution"):
		if is_living_base():
			text = base_evolved_text(res.get("evolution", []), session.config)
		else:
			text = evolution_line(res.get("evolution", []), session.config)
	evolution_label.text = text
	evolution_label.visible = not text.is_empty()
	if not text.is_empty():
		stats["evolution"] = text


## "Populations: Rhinovirus parent 6/8 · B-Cell parent 5/8". Empty when no type bred.
static func evolution_line(entries: Array, config: GameConfig) -> String:
	var parts: Array[String] = []
	for e_val: Variant in entries:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if not bool(e.get("bred", false)):
			continue
		parts.append("%s parent %d/%d" % [CoevolutionPanel.type_name(str(e.get("type_id", "")), config), int(e.get("top_count", 0)), int(e.get("pool_size", 0))])
	if parts.is_empty():
		return ""
	return "Populations: " + " · ".join(parts)


## True in a Living Base session; the Results screen then talks about the AI base.
func is_living_base() -> bool:
	return session != null and session.mode == Session.Mode.LIVING_BASE and session.living_flow != null


## "+120 ATP · +30 Amino Acids" (and "· +5 DNA" when any). Empty when nothing was won.
static func loot_text(res: Dictionary) -> String:
	var parts: Array[String] = []
	if int(res.get("atp_looted", 0)) > 0:
		parts.append("+%d ATP" % int(res.get("atp_looted", 0)))
	if int(res.get("amino_attacker", 0)) > 0:
		parts.append("+%d Amino Acids" % int(res.get("amino_attacker", 0)))
	if int(res.get("dna_attacker", 0)) > 0:
		parts.append("+%d DNA" % int(res.get("dna_attacker", 0)))
	return " · ".join(parts)


func _populate_loot(res: Dictionary) -> void:
	var text: String = ""
	if is_living_base() and res.has("living_base"):
		text = loot_text(res["living_base"] as Dictionary)
	loot_label.text = text
	loot_label.visible = not text.is_empty()
	if not text.is_empty():
		stats["loot"] = text


## Raid again (same opponent while it still stands) and Back to base replace the Lab choices.
func _configure_living_base_buttons() -> void:
	var still_there: bool = session.living_flow.has_raid_target()
	_set_button(btn_re_raid, "Raid again" if still_there else "New target", "Same base, new army" if still_there else "Pick another base", RE_RAID_WIDTH)
	_set_button(btn_edit_base, "Back to base", "Home", EDIT_WIDTH)
	btn_new_base.visible = false


## "The base learned: Rhinovirus (wild) level 2 · Staphylococcus (wild) forgotten"
static func base_learned_text(changes: Array, config: GameConfig) -> String:
	var parts: Array[String] = []
	for c_val: Variant in changes:
		if not (c_val is Dictionary):
			continue
		var c: Dictionary = c_val
		var label: String = MemoryPanel.strain_label(str(c.get("strain_key", "")), config)
		var reason: String = str(c.get("reason", ""))
		if reason == "forgotten":
			parts.append("%s forgotten" % label)
		elif reason == "evicted":
			parts.append("%s evicted" % label)
		else:
			parts.append("%s level %d" % [label, int(c.get("to", 0))])
	if parts.is_empty():
		return ""
	return "The base learned: " + " · ".join(parts)


## "The base evolved: B-Cell parent 5/8". Only the AI base's own (structure) pools are listed.
static func base_evolved_text(entries: Array, config: GameConfig) -> String:
	var own: Array = []
	for e_val: Variant in entries:
		if e_val is Dictionary and config.structures.has(str((e_val as Dictionary).get("type_id", ""))):
			own.append(e_val)
	var line: String = evolution_line(own, config)
	return line.replace("Populations:", "The base evolved:")


## "Immune memory: Rhinovirus (wild) 1→2 · Staphylococcus (wild) forgotten"
static func memory_changes_text(changes: Array, config: GameConfig) -> String:
	if changes.is_empty():
		return ""
	var parts: Array[String] = []
	for c_val: Variant in changes:
		if not (c_val is Dictionary):
			continue
		var c: Dictionary = c_val
		var label: String = MemoryPanel.strain_label(str(c.get("strain_key", "")), config)
		var to_level: int = int(c.get("to", 0))
		if str(c.get("reason", "")) == "forgotten":
			parts.append("%s forgotten" % label)
		elif str(c.get("reason", "")) == "evicted":
			parts.append("%s evicted" % label)
		else:
			parts.append("%s %d→%d" % [label, int(c.get("from", 0)), to_level])
	if parts.is_empty():
		return ""
	return "Immune memory: " + " · ".join(parts)


## Raid-score row (raid_score flag). Hidden and absent from stats when the flag is off.
func _populate_score(res: Dictionary, is_attacker_win: bool) -> void:
	var enabled: bool = session != null and session.config != null and session.config.flag("raid_score") and res.has("score")
	if not enabled:
		score_label.visible = false
		score_label.text = ""
		return
	var score: int = int(res.get("score", 0))
	var base_value: int = int(res.get("base_value", 0))
	var best: int = int(res.get("best_score", session.best_score))
	stats["score"] = str(score)
	stats["best_score"] = str(best)
	var line: String
	if is_attacker_win:
		line = "Score %d: you broke a %d ATP base" % [score, base_value]
	else:
		line = "Score %d: the %d ATP base held" % [score, base_value]
	score_label.text = "%s\nBest this session: %d" % [line, best]
	score_label.visible = true


func _populate_atp_split() -> void:
	base_atp = 0
	army_atp = 0
	unspent_atp = 0
	if session != null:
		if not session.last_launch.is_empty():
			base_atp = int(session.last_launch.get("base_atp", 0))
			army_atp = int(session.last_launch.get("army_atp", 0))
			unspent_atp = int(session.last_launch.get("unspent_atp", 0))
		else:
			if session.grid != null:
				base_atp = int(session.grid.total_cost().get("atp", 0))
			if session.army != null:
				army_atp = int(session.army.total_cost().get("atp", 0))
			if session.wallet != null:
				unspent_atp = session.wallet.get_amount("atp")

	var total_atp: int = base_atp + army_atp + unspent_atp
	var w_base: float = 0.0
	var w_army: float = 0.0
	var w_unspent: float = 0.0
	if total_atp > 0:
		w_base = roundf(SPLIT_BAR_WIDTH * float(base_atp) / float(total_atp))
		w_army = roundf(SPLIT_BAR_WIDTH * float(army_atp) / float(total_atp))
		w_unspent = maxf(0.0, SPLIT_BAR_WIDTH - w_base - w_army)
	split_widths = {"base": w_base, "army": w_army, "unspent": w_unspent}

	var segs: Array[Dictionary] = []
	segs.append({"frac": w_base / SPLIT_BAR_WIDTH, "color": SPLIT_COLOR_BASE})
	segs.append({"frac": w_army / SPLIT_BAR_WIDTH, "color": SPLIT_COLOR_ARMY})
	segs.append({"frac": w_unspent / SPLIT_BAR_WIDTH, "color": SPLIT_COLOR_UNSPENT})
	atp_track.segments = segs

	atp_title_label.text = "Where your %d ATP went" % total_atp
	(legend_values["base"] as Label).text = str(base_atp)
	(legend_values["army"] as Label).text = str(army_atp)
	(legend_values["unspent"] as Label).text = str(unspent_atp)


func _update_new_base_label() -> void:
	var start_atp: int = 1000
	if session != null and session.config != null:
		start_atp = int(session.config.start_wallet.get("atp", 1000))
	_set_button(btn_new_base, "New base", "Reset to %d ATP" % start_atp, NEW_BASE_WIDTH)


## Called by GameStateMachine after a config hot reload was applied (#27).
func on_config_changed(_summary: Dictionary) -> void:
	_update_new_base_label()


func get_stat(stat_name: String) -> String:
	return str(stats.get(stat_name, ""))


func get_atp_split_widths() -> Dictionary:
	return split_widths.duplicate()


func make_choice(p_choice: String) -> void:
	var choice: String = p_choice
	if is_living_base():
		# The first two buttons keep their slots; in Living Base they mean Raid again and Back to base.
		choice = {"re_raid": "raid_again", "edit_base": "back_to_base"}.get(p_choice, p_choice)
	_log("results_choice", {"choice": choice})
	choice_made.emit(choice)
	apply_choice(choice, session, fsm)


# --- survey and export ---------------------------------------------------------------------

func _populate_survey() -> void:
	survey_card.setup(session.battle_count if session != null else 0)


func _on_survey_answered(key: String, value: Variant) -> void:
	_log("survey", {key: value, "question": key})


func _on_survey_skipped(key: String) -> void:
	_log("survey_skipped", {"question": key})


func _log(event: String, data: Dictionary) -> void:
	var target: Node = logger if logger != null else SessionLogger
	if target != null and target.has_method("log_event"):
		target.call("log_event", event, data)


func _on_export_logs_pressed() -> void:
	export_playtest_logs()


static func export_playtest_logs() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(SessionLogger.all_sessions_text().to_utf8_buffer(), "bio_siege_telemetry.jsonl", "application/x-ndjson")
	else:
		OS.shell_open(ProjectSettings.globalize_path("user://telemetry"))
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("logs_exported", {})


static func apply_choice(choice: String, session: Session, fsm: GameStateMachine = null) -> void:
	if session == null:
		return

	match choice:
		"raid_again":
			# Living Base: the army was spent. Same opponent if it still exists, else back to the base.
			var aimed: bool = session.living_flow != null and session.living_flow.raid_again()
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.INCUBATION if aimed else GameStateMachine.Phase.SYNTHESIS)
		"back_to_base":
			if session.living_flow != null:
				session.living_flow.end_raid()
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
		"re_raid":
			if session.army != null:
				session.army.refund_all(session.wallet)
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.INCUBATION)
		"edit_base":
			if session.army != null:
				session.army.refund_all(session.wallet)
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
		"new_base":
			session.best_score = 0
			session.memory = ImmuneMemory.new()
			session.reset_populations()
			if session.wallet != null and session.config != null:
				session.wallet.reset(session.config.start_wallet)
			if session.grid != null:
				session.grid.reset_with_nucleus()
			session.army = Army.new(session.config)
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
