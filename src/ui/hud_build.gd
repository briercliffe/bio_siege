class_name HudBuild
extends Control

## Synthesis HUD, screens 05, 06 and 07 (day theme). Positions come from the mockup canvas sources
## BuildEmpty, BuildPlacing and FinalizeConfirm at 1280x720. Pills and cards float over a full-bleed
## background: the ATP and phase pills and the buttons across the top, the Getting started / selection card
## on the left, the Base status card on the right and the tray at the bottom centre. Everything is anchored
## to its edge or centre, so a larger viewport keeps the layout.

signal finalize_requested
signal help_requested
## "Import…" in the menu: open the Saved bases and armies screen on the Bases tab.
signal library_requested(kind: String)
signal settings_requested
signal quit_requested

const ATP_OVER_BUDGET_COLOR: Color = Color("#e74c3c")
const IMPORT_DIALOG_SCENE: PackedScene = preload("res://src/ui/import_dialog.tscn")

const MENU_SAVE: int = 0
const MENU_IMPORT: int = 1
const MENU_HOW_TO_PLAY: int = 2
const MENU_SOUND: int = 3
const MENU_SETTINGS: int = 4
const MENU_QUIT: int = 5
const MENU_SAVE_TEXT: String = "Save base…"
const MENU_IMPORT_TEXT: String = "Import…"
const DEFAULT_NAME: String = "Base %d"

const EDGE: float = 20.0
const CARD_TOP: float = 96.0
const CARD_WIDTH: float = 300.0
const PILL_HEIGHT: float = 52.0
const ATP_POS: Vector2 = Vector2(20.0, 14.0)
const PHASE_TOP: float = 10.0
const BUTTON_TOP: float = 12.0
const MENU_RIGHT: float = 196.0
const FINALIZE_SIZE: Vector2 = Vector2(164.0, 52.0)
const MENU_SHEET_WIDTH: float = 260.0
const MENU_ITEM_HEIGHT: float = 48.0
const TRAY_BOTTOM: float = 16.0
const TRAY_GAP: int = 12
const PHASE_TITLE: String = "PHASE 1 · SYNTHESIS"
const PHASE_SUBTITLE: String = "Build your defense"
const DASH: String = "—"
const KICKER_SPACING: int = 2

const START_STEPS: Array[String] = [
	"Pick a structure below.",
	"Tap the island to place it.",
	"Use Sell to take any piece back for a full refund.",
]
const SELL_TEXT: String = "Tap any of your pieces for a 100% refund. The Nucleus can't be sold."
const MOVE_TEXT: String = "Drag the Nucleus to a new spot. It's free."
const FINALIZE_BODY: String = "Your defense is locked in and you become the attacker. The ATP you kept carries over to buy your army."
const BASE_TILE_COLOR: Color = Color("#eaf3fb")


## A 60 px white disc holding one structure icon (the selection card header).
class IconDisc:
	extends Control

	const DIAMETER: float = 60.0
	const ICON_PX: float = 34.0

	var icon_id: String = "":
		set(value):
			icon_id = value
			queue_redraw()
	var config: GameConfig = null

	func _init() -> void:
		custom_minimum_size = Vector2(DIAMETER, DIAMETER)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = DIAMETER * 0.5
		draw_circle(c, r, Color("#c5d9ed"))
		draw_circle(c, r - 2.0, Color("#d7e9f8"))
		draw_circle(c + Vector2(-3.0, -4.0), r * 0.68, Color("#eaf4fc"))
		draw_circle(c + Vector2(-6.0, -8.0), r * 0.36, Color("#ffffff"))
		IconPainter.draw_icon(self, icon_id, Rect2(c - Vector2(ICON_PX, ICON_PX) * 0.5, Vector2(ICON_PX, ICON_PX)), config)


## Small swatch for the status card legend.
class Swatch:
	extends Control

	enum Kind { GREEN, RED, DASHED }

	var kind: Kind = Kind.GREEN

	func _init(k: Kind = Kind.GREEN) -> void:
		kind = k
		var px: float = 22.0 if k == Kind.DASHED else 18.0
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		match kind:
			Kind.GREEN:
				KitDraw.draw_box(self, rect, Color(Color("#2ecc71"), 0.3), 6.0, 2, Color("#2ecc71"))
			Kind.RED:
				KitDraw.draw_box(self, rect, Color(Color("#e74c3c"), 0.3), 6.0, 2, Color("#e74c3c"))
			_:
				var accent: Color = UiPalette.color(false, "accent")
				KitDraw.draw_box(self, rect, Color(accent, 0.1), 8.0)
				KitDraw.draw_dashed_rounded(self, rect.grow(-1.0), 8.0, Color(accent, 0.45), 2.0, 4.0, 3.0)


var session: Session = null
var controller: BuildController = null

var atp_pill: PillPanel = null
var atp_label: Label = null
var phase_pill: PillPanel = null
var btn_menu: IconButton = null
var btn_finalize: PillButton = null

var left_card: FloatingCard = null
var start_box: VBoxContainer = null
var start_title_label: Label = null
var selection_box: VBoxContainer = null
var icon_disc: IconDisc = null
var selection_name_label: Label = null
var selection_role_label: Label = null
## "health", "damage", "interval" and "footprint" -> StatTile.
var selection_tiles: Dictionary = {}
var tile_grid: GridContainer = null
var selection_desc_label: Label = null
var cost_badge: PanelContainer = null
var cost_badge_label: Label = null

var right_card: FloatingCard = null
var status_box: VBoxContainer = null
var spent_caption: Label = null
var spent_value: Label = null
var spent_total_label: Label = null
var spent_track: ProgressTrack = null
var stays_label: Label = null
var chips_flow: HFlowContainer = null
## Structure type id -> chip PanelContainer.
var chips: Dictionary = {}
var empty_legend: VBoxContainer = null
var placing_legend: VBoxContainer = null
var tiles_caption: Label = null
var tiles_value: Label = null
var memory_panel: MemoryPanel = null
var coevolution_panel: CoevolutionPanel = null

var tray: HBoxContainer = null
var cards_container: HBoxContainer = null
var cards: Array[HudCard] = []

var menu_catcher: Control = null
var menu_sheet: FloatingCard = null
## Menu id (MENU_*) -> PillButton.
var menu_buttons: Dictionary = {}

var confirmation_dialog: ConfirmationPopup = null
var import_dialog: ImportDialog = null
var save_dialog: SaveNameDialog = null
## The save library folder; the Synthesis phase passes the game's, tests pass a temp one.
var saves_root: String = SaveLibrary.DEFAULT_ROOT
var last_toast_message: String = ""

var _atp_tween: Tween = null
var _ink: Color = UiPalette.color(false, "ink")
var _muted: Color = UiPalette.color(false, "muted")


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _ready() -> void:
	_update_all()


# --- setup and signals ------------------------------------------------------------

func setup(p_session: Session, p_controller: BuildController) -> void:
	# Disconnect previous if setup called again
	if session != null and session.wallet != null and session.wallet.changed.is_connected(_on_wallet_changed):
		session.wallet.changed.disconnect(_on_wallet_changed)
	if session != null and session.grid != null:
		if session.grid.structure_placed.is_connected(_on_structure_placed):
			session.grid.structure_placed.disconnect(_on_structure_placed)
		if session.grid.structure_removed.is_connected(_on_structure_removed):
			session.grid.structure_removed.disconnect(_on_structure_removed)
	if controller != null and controller.tool_changed.is_connected(_on_tool_changed):
		controller.tool_changed.disconnect(_on_tool_changed)

	session = p_session
	controller = p_controller

	if session != null and session.wallet != null:
		session.wallet.changed.connect(_on_wallet_changed)
	if session != null and session.grid != null:
		session.grid.structure_placed.connect(_on_structure_placed)
		session.grid.structure_removed.connect(_on_structure_removed)
	if controller != null:
		controller.tool_changed.connect(_on_tool_changed)

	_populate_tray()
	_sync_memory_panel()
	_sync_coevolution_panel()
	_update_all()


## Shows the read-only MemoryPanel inside the status card, only when immune memory is enabled.
func _sync_memory_panel() -> void:
	var enabled: bool = session != null and session.config != null and session.config.memory_enabled()
	if memory_panel == null and enabled:
		memory_panel = MemoryPanel.new()
		memory_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		memory_panel.offset_left = 0.0
		memory_panel.offset_right = 0.0
		memory_panel.offset_top = 0.0
		memory_panel.offset_bottom = 0.0
		status_box.add_child(memory_panel)
	if memory_panel != null:
		memory_panel.visible = enabled
		if enabled:
			memory_panel.setup(session)


## Shows the read-only CoevolutionPanel under the MemoryPanel, only when coevolution is enabled.
func _sync_coevolution_panel() -> void:
	var enabled: bool = session != null and session.config != null and session.config.coevolution_enabled()
	if coevolution_panel == null and enabled:
		coevolution_panel = CoevolutionPanel.new()
		coevolution_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		coevolution_panel.offset_left = 0.0
		coevolution_panel.offset_right = 0.0
		coevolution_panel.offset_top = 0.0
		coevolution_panel.offset_bottom = 0.0
		status_box.add_child(coevolution_panel)
	if coevolution_panel != null:
		if memory_panel != null and memory_panel.get_parent() == coevolution_panel.get_parent():
			coevolution_panel.get_parent().move_child(coevolution_panel, memory_panel.get_index() + 1)
		coevolution_panel.visible = enabled
		if enabled:
			coevolution_panel.setup(session)


func _update_all() -> void:
	if session != null and session.wallet != null:
		_update_atp_label(session.wallet.get_amount("atp"), false)
	_update_card_affordability()
	_update_sell_card()
	_update_left_card()
	_update_status()


# --- tray -----------------------------------------------------------------------------

func _populate_tray() -> void:
	for c: HudCard in cards:
		cards_container.remove_child(c)
		c.queue_free()
	cards.clear()

	if session == null or session.config == null:
		return

	var cfg: GameConfig = session.config
	for id: String in cfg.buildable_structure_ids():
		var sdef: StructureDef = cfg.structures.get(id)
		if sdef == null:
			continue
		var card := HudCard.new()
		card.setup_structure(sdef, cfg)
		_add_card(card)

	var sell_card := HudCard.new()
	sell_card.setup_sell()
	_add_card(sell_card)

	if cfg.move_nucleus_enabled():
		var move_card := HudCard.new()
		move_card.setup_move_nucleus(cfg.structures.get(cfg.core_structure_id()), cfg)
		_add_card(move_card)

	var tool_id: String = controller.tool if controller != null else ""
	for c: HudCard in cards:
		c.set_selected(c.tool_id == tool_id)


func _add_card(card: HudCard) -> void:
	card.pressed.connect(func() -> void:
		if controller != null:
			controller.select_tool(card.tool_id)
	)
	cards_container.add_child(card)
	cards.append(card)


## Re-reads names, costs and roles after a config hot reload (#27).
## The tray is rebuilt only when structures were added, removed or re-ordered by cost.
func refresh_config() -> void:
	if session == null or session.config == null:
		return
	var expected_ids: Array[String] = session.config.buildable_structure_ids()
	var current_ids: Array[String] = []
	var has_move_card: bool = false
	for c: HudCard in cards:
		if c.is_structure_card():
			current_ids.append(c.tool_id)
		elif c.is_move_nucleus:
			has_move_card = true
	if current_ids == expected_ids and has_move_card == session.config.move_nucleus_enabled():
		for c: HudCard in cards:
			var sdef: StructureDef = session.config.structures.get(c.tool_id)
			if c.is_structure_card() and sdef != null:
				c.setup_structure(sdef, session.config)
	else:
		var selected_tool: String = controller.tool if controller != null else ""
		_populate_tray()
		if controller != null and not selected_tool.is_empty():
			var move_still_valid: bool = selected_tool == BuildController.TOOL_MOVE_NUCLEUS \
				and session.config.move_nucleus_enabled()
			if selected_tool == "sell" or session.config.structures.has(selected_tool) or move_still_valid:
				_on_tool_changed(selected_tool)
			else:
				controller.select_tool(selected_tool)
	_update_all()


func get_cards() -> Array[HudCard]:
	return cards


func get_card(id: String) -> HudCard:
	for c: HudCard in cards:
		if c.tool_id == id:
			return c
	return null


func _update_card_affordability() -> void:
	if session == null or session.wallet == null:
		return
	var wallet_atp: int = session.wallet.get_amount("atp")
	for c: HudCard in cards:
		c.update_affordability(wallet_atp)


func _update_sell_card() -> void:
	var has_pieces: bool = session != null and session.grid != null and session.grid.occupied_cell_count() > 0
	for c: HudCard in cards:
		c.update_sellable(has_pieces)


# --- finalize -------------------------------------------------------------------------

func get_cheapest_pathogen_cost() -> int:
	if session == null or session.config == null or session.config.pathogens.is_empty():
		return 0
	var cheapest: int = -1
	for pdef: PathogenDef in session.config.pathogens.values():
		var c: int = int(pdef.cost.get("atp", 0))
		if cheapest < 0 or c < cheapest:
			cheapest = c
	return maxi(cheapest, 0)


## Opens the "Finalize this base?" dialog (screen 07). The phase changes only after "Finalize".
func finalize_base() -> void:
	var cheapest: int = get_cheapest_pathogen_cost()
	var current_atp: int = session.wallet.get_amount("atp") if (session != null and session.wallet != null) else 0
	var base_cost: int = int(session.grid.total_cost().get("atp", 0)) if (session != null and session.grid != null) else 0
	confirmation_dialog.set_kicker("READY TO SWITCH SIDES?")
	confirmation_dialog.set_title("Finalize this base?")
	confirmation_dialog.set_body(FINALIZE_BODY)
	confirmation_dialog.set_tiles([
		{"label": "Base", "value": "%d ATP" % base_cost, "color": BASE_TILE_COLOR},
		{"label": "Army budget", "value": "%d ATP" % current_atp, "color": UiPalette.color(false, "atp_badge")},
	])
	var warning: String = ""
	if current_atp < cheapest:
		warning = "You have %d ATP left, which is not enough for any pathogen (cheapest costs %d). Finalize anyway?" % [current_atp, cheapest]
	confirmation_dialog.set_warning(warning)
	confirmation_dialog.set_buttons("Keep building", "Finalize")
	confirmation_dialog.popup_centered()


func _on_finalize_button_pressed() -> void:
	finalize_base()


func _on_confirmation_dialog_confirmed() -> void:
	finalize_requested.emit()


# --- reactions ------------------------------------------------------------------------------

func _on_tool_changed(tool_id: String) -> void:
	for c: HudCard in cards:
		c.set_selected(c.tool_id == tool_id)
	_update_left_card()
	_update_status()


func _on_wallet_changed(currency: String, new_amount: int) -> void:
	if currency == "atp":
		_update_atp_label(new_amount, true)
	_update_card_affordability()
	_update_status()


func _on_structure_placed(_s: GridModel.PlacedStructure) -> void:
	_update_sell_card()
	_update_status()


func _on_structure_removed(_s: GridModel.PlacedStructure) -> void:
	_update_sell_card()
	_update_status()


func _update_atp_label(amount: int, pulse: bool) -> void:
	atp_label.text = str(amount)
	atp_label.add_theme_color_override("font_color", ATP_OVER_BUDGET_COLOR if amount < 0 else _ink)
	atp_label.pivot_offset = atp_label.size * 0.5
	if pulse:
		if _atp_tween != null and _atp_tween.is_valid():
			_atp_tween.kill()
		atp_label.scale = Vector2.ONE
		_atp_tween = create_tween()
		if _atp_tween != null:
			_atp_tween.tween_property(atp_label, "scale", Vector2(1.15, 1.15), 0.075).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_atp_tween.tween_property(atp_label, "scale", Vector2.ONE, 0.075).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# --- left card: Getting started or the selection -----------------------------------------

func _current_tool() -> String:
	return controller.tool if controller != null else ""


func _update_left_card() -> void:
	var tool_id: String = _current_tool()
	var cfg: GameConfig = session.config if session != null else null
	var is_tool: bool = tool_id == "sell" or tool_id == BuildController.TOOL_MOVE_NUCLEUS
	var sdef: StructureDef = cfg.structures.get(tool_id) if (cfg != null and not tool_id.is_empty()) else null
	start_box.visible = tool_id.is_empty() or (sdef == null and not is_tool)
	selection_box.visible = not start_box.visible
	if start_box.visible:
		return
	var show_stats: bool = sdef != null
	tile_grid.visible = show_stats
	cost_badge.visible = show_stats
	selection_role_label.visible = show_stats
	if tool_id == "sell":
		icon_disc.visible = false
		selection_name_label.text = "Sell"
		selection_desc_label.text = SELL_TEXT
	elif tool_id == BuildController.TOOL_MOVE_NUCLEUS:
		icon_disc.visible = true
		icon_disc.icon_id = "nucleus"
		icon_disc.config = cfg
		selection_name_label.text = "Move Nucleus"
		selection_desc_label.text = MOVE_TEXT
	else:
		icon_disc.visible = true
		icon_disc.icon_id = sdef.id
		icon_disc.config = cfg
		selection_name_label.text = sdef.display_name
		selection_role_label.text = sdef.role
		var tick_rate: int = maxi(cfg.tick_rate, 1)
		(selection_tiles["health"] as StatTile).setup("Health", str(sdef.hp))
		(selection_tiles["damage"] as StatTile).setup("Damage", str(sdef.attack_damage) if sdef.has_attack else DASH)
		(selection_tiles["interval"] as StatTile).setup("Fire interval",
				"%.1f s" % (float(sdef.attack_interval_ticks) / float(tick_rate)) if sdef.has_attack else DASH)
		(selection_tiles["footprint"] as StatTile).setup("Footprint", "%d × %d" % [sdef.footprint.x, sdef.footprint.y])
		selection_desc_label.text = UnitCopy.description(sdef.id)
		cost_badge_label.text = "%d ATP" % int(sdef.cost.get("atp", 0))


# --- right card: Base status ---------------------------------------------------------------

func _update_status() -> void:
	if session == null or session.config == null or session.wallet == null:
		return
	var wallet_atp: int = session.wallet.get_amount("atp")
	var start: int = int(session.config.start_wallet.get("atp", 0))
	var spent: int = maxi(0, start - wallet_atp)
	spent_value.text = str(spent)
	spent_total_label.text = "of %d ATP" % start
	spent_track.value = float(spent) / float(start) if start > 0 else 0.0
	stays_label.visible = spent > 0
	stays_label.text = "%d ATP stays as your attack budget." % maxi(wallet_atp, 0)

	var grid: GridModel = session.grid
	_update_chips(grid)
	var core: GridModel.PlacedStructure = grid.find_core() if grid != null else null
	var core_area: int = core.footprint.x * core.footprint.y if core != null else 0
	var used: int = (grid.occupied_cell_count() + core_area) if grid != null else 0
	var buildable: int = grid.buildable_cell_count() if grid != null else 0
	tiles_value.text = "%d of %d" % [used, buildable]

	var tool_id: String = _current_tool()
	var placing: bool = not tool_id.is_empty() and tool_id != "sell"
	var is_empty: bool = grid == null or grid.occupied_cell_count() == 0
	placing_legend.visible = placing
	empty_legend.visible = is_empty and tool_id.is_empty()


## One chip per placed structure type ("52 Walls"), in config order. The Nucleus has no chip.
func _update_chips(grid: GridModel) -> void:
	var counts: Dictionary = grid.count_by_type() if grid != null else {}
	var wanted: Array[String] = []
	for id: Variant in session.config.structures.keys():
		var def: StructureDef = session.config.structures[id] as StructureDef
		if def.has_tag("core") or int(counts.get(id, 0)) <= 0:
			continue
		wanted.append(str(id))
	var existing: Array[String] = []
	for id: Variant in chips.keys():
		existing.append(str(id))
	if existing != wanted:
		for chip: Variant in chips.values():
			(chip as Node).queue_free()
		chips.clear()
		for id: String in wanted:
			var chip: PanelContainer = _make_chip(id)
			chips_flow.add_child(chip)
			chips[id] = chip
	for id: String in wanted:
		var def: StructureDef = session.config.structures[id] as StructureDef
		var n: int = int(counts[id])
		var chip: PanelContainer = chips[id] as PanelContainer
		(chip.get_node("Row/Count") as Label).text = str(n)
		(chip.get_node("Row/Name") as Label).text = _chip_name(def, n)


func _make_chip(id: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Chip_%s" % id
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(0.0, 38.0)
	var sb: StyleBoxFlat = KitDraw.make_box(UiPalette.color(false, "chip"), 19.0)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	chip.add_theme_stylebox_override("panel", sb)
	var row: HBoxContainer = _hbox(8)
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := IconSlot.new(id, 18.0)
	icon.config = session.config
	row.add_child(icon)
	var count: Label = _label("0", 15, 800, _ink)
	count.name = "Count"
	row.add_child(count)
	var label: Label = _label("", 15, 400, _ink)
	label.name = "Name"
	row.add_child(label)
	chip.add_child(row)
	return chip


## "Wall" for any wall, otherwise the display name; plural unless the count is 1.
static func _chip_name(def: StructureDef, count: int) -> String:
	var base: String = "Wall" if def.has_tag("wall") else def.display_name
	return base if count == 1 else base + "s"


## "Spent 610", as shown (the caption and the value are separate labels).
func spent_text() -> String:
	return "%s %s" % [spent_caption.text, spent_value.text]


## "Tiles used 16 of 1296", as shown.
func tiles_text() -> String:
	return "%s %s" % [tiles_caption.text, tiles_value.text]


func chip_text(id: String) -> String:
	var chip: PanelContainer = chips.get(id) as PanelContainer
	if chip == null:
		return ""
	return "%s %s" % [(chip.get_node("Row/Count") as Label).text, (chip.get_node("Row/Name") as Label).text]


# --- menu sheet ----------------------------------------------------------------------------

func menu_open() -> bool:
	return menu_sheet.visible


func open_menu() -> void:
	_refresh_menu()
	menu_catcher.visible = true
	menu_sheet.visible = true


func close_menu() -> void:
	menu_catcher.visible = false
	menu_sheet.visible = false


func _refresh_menu() -> void:
	var sound: PillButton = menu_buttons[MENU_SOUND] as PillButton
	sound.text = "Sound: Off" if Sfx.muted else "Sound: On"
	sound.queue_redraw()


func _on_btn_menu_pressed() -> void:
	if menu_open():
		close_menu()
	else:
		open_menu()


func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		close_menu()


## The PillButton for a MENU_* id.
func menu_button(id: int) -> PillButton:
	return menu_buttons.get(id) as PillButton


func _on_menu_item(id: int) -> void:
	close_menu()
	match id:
		MENU_HOW_TO_PLAY:
			help_requested.emit()
		MENU_SOUND:
			Sfx.toggle_mute()
		MENU_SAVE:
			open_save_dialog()
		MENU_IMPORT:
			library_requested.emit(SaveLibrary.KIND_BASE)
		MENU_SETTINGS:
			settings_requested.emit()
		MENU_QUIT:
			quit_requested.emit()


func open_import_dialog() -> void:
	import_dialog.open("Import Base")


## "Save base…": asks for a name, defaulting to "Base N" after the slots already saved.
func open_save_dialog() -> void:
	var n: int = SaveLibrary.new(saves_root).count(SaveLibrary.KIND_BASE) + 1
	save_dialog.open(MENU_SAVE_TEXT, DEFAULT_NAME % n)


## Saves the current base as a library slot. Errors (a full library) show in the name dialog.
func save_base(slot_name: String) -> Dictionary:
	if session == null or session.grid == null:
		return {"ok": false, "path": "", "error": "Nothing to save"}
	var lib := SaveLibrary.new(saves_root)
	var populations: Dictionary = {}
	if session.config != null and session.config.coevolution_enabled():
		for type_id: String in session.config.coevo_types:
			populations[type_id] = session.population(type_id).to_dict()
	var res: Dictionary = lib.save_base(slot_name, session.grid, session.config, session.memory, populations)
	if not bool(res.get("ok", false)):
		save_dialog.set_error(str(res.get("error", "")))
		return res
	save_dialog.close()
	_show_toast("Saved '%s'" % slot_name)
	return res


func import_base(json_text: String) -> bool:
	if session == null or session.config == null or session.grid == null or session.wallet == null:
		return false
	var res: Dictionary = SnapshotIO.parse_base(json_text, session.config)
	if not res.get("ok", false):
		var err_msg: String = str(res.get("error", "Failed to parse base"))
		import_dialog.set_error(err_msg)
		return false

	var apply_error: String = SaveLibrary.apply_base(session, res)
	if not apply_error.is_empty():
		import_dialog.set_error(apply_error)
		return false
	_sync_memory_panel()
	_sync_coevolution_panel()
	_update_all()
	import_dialog.close()
	_show_toast("Base loaded")
	return true


func _on_import_load_requested(text: String) -> void:
	import_base(text)


func _show_toast(msg: String) -> void:
	last_toast_message = msg
	var t: Toast = get_node_or_null("../Toast") as Toast
	if t == null:
		t = get_node_or_null("Toast") as Toast
	if t == null:
		t = Toast.new()
		t.name = "Toast"
		add_child(t)
	t.show_message(msg)


# --- layout --------------------------------------------------------------------------------------

func _build() -> void:
	_build_atp_pill()
	_build_phase_pill()
	_build_buttons()
	_build_left_card()
	_build_right_card()
	_build_tray()
	_build_menu()

	confirmation_dialog = ConfirmationPopup.new()
	confirmation_dialog.name = "ConfirmationDialog"
	confirmation_dialog.confirmed.connect(_on_confirmation_dialog_confirmed)
	add_child(confirmation_dialog)

	import_dialog = IMPORT_DIALOG_SCENE.instantiate() as ImportDialog
	import_dialog.name = "ImportDialog"
	import_dialog.load_requested.connect(_on_import_load_requested)
	add_child(import_dialog)

	save_dialog = SaveNameDialog.new()
	save_dialog.name = "SaveDialog"
	save_dialog.save_requested.connect(save_base)
	add_child(save_dialog)


func _build_atp_pill() -> void:
	atp_pill = _pill("AtpPill")
	atp_pill.position = ATP_POS
	var row: HBoxContainer = _hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(IconSlot.new("atp", 24.0))
	atp_label = _label("0", 24, 800, _ink)
	atp_label.name = "AtpLabel"
	row.add_child(atp_label)
	row.add_child(_label("ATP", 14, 700, _muted))
	atp_pill.add_child(row)


func _build_phase_pill() -> void:
	phase_pill = _pill("PhasePill")
	phase_pill.set_phase(PHASE_TITLE, PHASE_SUBTITLE)
	_anchor_top_center(phase_pill, PHASE_TOP, PillPanel.PHASE_SIZE)


func _build_buttons() -> void:
	btn_menu = IconButton.new(IconButton.Kind.MENU)
	btn_menu.name = "BtnMenu"
	btn_menu.anchor_left = 1.0
	btn_menu.anchor_right = 1.0
	btn_menu.offset_right = -MENU_RIGHT
	btn_menu.offset_left = -MENU_RIGHT - IconButton.ROUND_SIZE.x
	btn_menu.offset_top = BUTTON_TOP
	btn_menu.offset_bottom = BUTTON_TOP + IconButton.ROUND_SIZE.y
	btn_menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn_menu.pressed.connect(_on_btn_menu_pressed)
	add_child(btn_menu)

	btn_finalize = PillButton.new("Finalize Base", PillButton.Variant.PRIMARY)
	btn_finalize.name = "BtnFinalize"
	btn_finalize.anchor_left = 1.0
	btn_finalize.anchor_right = 1.0
	btn_finalize.offset_right = -EDGE
	btn_finalize.offset_left = -EDGE - FINALIZE_SIZE.x
	btn_finalize.offset_top = BUTTON_TOP
	btn_finalize.offset_bottom = BUTTON_TOP + FINALIZE_SIZE.y
	btn_finalize.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn_finalize.pressed.connect(_on_finalize_button_pressed)
	add_child(btn_finalize)


func _build_left_card() -> void:
	left_card = FloatingCard.new()
	left_card.name = "LeftCard"
	left_card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	left_card.position = Vector2(EDGE, CARD_TOP)
	add_child(left_card)
	var holder: VBoxContainer = _vbox(0)
	left_card.add_child(holder)

	start_box = _vbox(14)
	start_box.name = "StartBox"
	start_box.add_child(_kicker("GETTING STARTED", _muted))
	start_title_label = _wrapping(_label("Protect the Nucleus.", 24, 800, _ink))
	start_box.add_child(start_title_label)
	start_box.add_child(_wrapping(_label(
			"You will attack this base yourself next, so build something you would struggle to break.", 15, 400, _muted)))
	var steps: VBoxContainer = _vbox(12)
	for i: int in range(START_STEPS.size()):
		var row: HBoxContainer = _hbox(12)
		row.add_child(NumberBadge.new(i + 1))
		row.add_child(_wrapping(_label(START_STEPS[i], 15, 400, _ink)))
		steps.add_child(row)
	start_box.add_child(steps)
	holder.add_child(start_box)

	selection_box = _vbox(14)
	selection_box.name = "SelectionBox"
	selection_box.visible = false
	var header: HBoxContainer = _hbox(14)
	icon_disc = IconDisc.new()
	header.add_child(icon_disc)
	var names: VBoxContainer = _vbox(0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_name_label = _wrapping(_label("", 22, 800, _ink))
	selection_role_label = _wrapping(_label("", 14, 400, _muted))
	names.add_child(selection_name_label)
	names.add_child(selection_role_label)
	header.add_child(names)
	selection_box.add_child(header)

	tile_grid = GridContainer.new()
	tile_grid.columns = 2
	tile_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_grid.add_theme_constant_override("h_separation", 8)
	tile_grid.add_theme_constant_override("v_separation", 8)
	for key: String in ["health", "damage", "interval", "footprint"]:
		var tile := StatTile.new()
		tile.name = "Tile_%s" % key
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selection_tiles[key] = tile
		tile_grid.add_child(tile)
	selection_box.add_child(tile_grid)

	selection_desc_label = _wrapping(_label("", 14, 400, _muted))
	selection_box.add_child(selection_desc_label)

	cost_badge = PanelContainer.new()
	cost_badge.name = "CostBadge"
	cost_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_badge.custom_minimum_size = Vector2(0.0, 36.0)
	cost_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb: StyleBoxFlat = KitDraw.make_box(UiPalette.color(false, "atp_badge"), 18.0)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	cost_badge.add_theme_stylebox_override("panel", sb)
	cost_badge_label = _label("", 15, 800, _ink)
	cost_badge.add_child(cost_badge_label)
	selection_box.add_child(cost_badge)
	holder.add_child(selection_box)


func _build_right_card() -> void:
	right_card = FloatingCard.new()
	right_card.name = "RightCard"
	right_card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	right_card.anchor_left = 1.0
	right_card.anchor_right = 1.0
	right_card.offset_left = -EDGE - CARD_WIDTH
	right_card.offset_right = -EDGE
	right_card.offset_top = CARD_TOP
	right_card.offset_bottom = CARD_TOP
	right_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(right_card)
	status_box = _vbox(14)
	right_card.add_child(status_box)

	status_box.add_child(_kicker("BASE STATUS", _muted))

	var spent_block: VBoxContainer = _vbox(8)
	var spent_row: HBoxContainer = _hbox(5)
	spent_caption = _label("Spent", 15, 400, _ink)
	spent_value = _label("0", 15, 800, _ink)
	spent_value.name = "SpentValue"
	spent_total_label = _label("of 0 ATP", 15, 400, _muted)
	spent_total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spent_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spent_row.add_child(spent_caption)
	spent_row.add_child(spent_value)
	spent_row.add_child(spent_total_label)
	spent_block.add_child(spent_row)
	spent_track = ProgressTrack.new()
	spent_track.name = "SpentTrack"
	spent_block.add_child(spent_track)
	stays_label = _wrapping(_label("", 14, 400, _muted))
	stays_label.name = "StaysLabel"
	stays_label.visible = false
	spent_block.add_child(stays_label)
	status_box.add_child(spent_block)

	chips_flow = HFlowContainer.new()
	chips_flow.name = "Chips"
	chips_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_flow.add_theme_constant_override("h_separation", 8)
	chips_flow.add_theme_constant_override("v_separation", 8)
	status_box.add_child(chips_flow)

	empty_legend = _vbox(14)
	empty_legend.name = "EmptyLegend"
	var nucleus_row: HBoxContainer = _hbox(10)
	nucleus_row.add_child(IconSlot.new("nucleus", 22.0))
	nucleus_row.add_child(_wrapping(_label("The Nucleus is free. Destroy it to win.", 14, 400, _muted)))
	empty_legend.add_child(nucleus_row)
	var zone_row: HBoxContainer = _hbox(10)
	zone_row.add_child(Swatch.new(Swatch.Kind.DASHED))
	zone_row.add_child(_wrapping(_label("The outer band is the deploy zone.", 14, 400, _muted)))
	empty_legend.add_child(zone_row)
	status_box.add_child(empty_legend)

	var tiles_row: HBoxContainer = _hbox(5)
	tiles_caption = _label("Tiles used", 14, 400, _muted)
	tiles_value = _label("0 of 0", 14, 800, _ink)
	tiles_value.name = "TilesValue"
	tiles_row.add_child(tiles_caption)
	tiles_row.add_child(tiles_value)
	status_box.add_child(tiles_row)

	placing_legend = _vbox(8)
	placing_legend.name = "PlacingLegend"
	placing_legend.visible = false
	for entry: Array in [[Swatch.Kind.GREEN, "Green: you can build here"], [Swatch.Kind.RED, "Red: blocked or too expensive"]]:
		var row: HBoxContainer = _hbox(10)
		row.add_child(Swatch.new(entry[0] as Swatch.Kind))
		row.add_child(_wrapping(_label(entry[1] as String, 14, 400, _muted)))
		placing_legend.add_child(row)
	status_box.add_child(placing_legend)


func _build_tray() -> void:
	tray = HBoxContainer.new()
	tray.name = "Tray"
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_theme_constant_override("separation", TRAY_GAP)
	tray.anchor_left = 0.5
	tray.anchor_right = 0.5
	tray.anchor_top = 1.0
	tray.anchor_bottom = 1.0
	tray.offset_top = -TRAY_BOTTOM - TrayCard.ITEM_SIZE.y
	tray.offset_bottom = -TRAY_BOTTOM
	tray.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(tray)
	cards_container = tray


## The menu sheet: a column of secondary pill buttons under the MENU button, and a catcher behind it
## that closes the sheet on a tap anywhere else.
func _build_menu() -> void:
	menu_catcher = Control.new()
	menu_catcher.name = "MenuCatcher"
	menu_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_catcher.visible = false
	menu_catcher.gui_input.connect(_on_catcher_input)
	add_child(menu_catcher)

	menu_sheet = FloatingCard.new()
	menu_sheet.name = "MenuSheet"
	menu_sheet.visible = false
	menu_sheet.custom_minimum_size = Vector2(MENU_SHEET_WIDTH, 0.0)
	menu_sheet.anchor_left = 1.0
	menu_sheet.anchor_right = 1.0
	menu_sheet.offset_right = -MENU_RIGHT
	menu_sheet.offset_left = -MENU_RIGHT - MENU_SHEET_WIDTH
	menu_sheet.offset_top = BUTTON_TOP + IconButton.ROUND_SIZE.y + 8.0
	menu_sheet.offset_bottom = menu_sheet.offset_top
	menu_sheet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(menu_sheet)
	var column: VBoxContainer = _vbox(8)
	menu_sheet.add_child(column)
	var items: Array[Array] = [
		[MENU_HOW_TO_PLAY, "How to play"],
		[MENU_SOUND, "Sound: On"],
		[MENU_SAVE, MENU_SAVE_TEXT],
		[MENU_IMPORT, MENU_IMPORT_TEXT],
		[MENU_SETTINGS, "Settings"],
		[MENU_QUIT, "Quit to title"],
	]
	for item: Array in items:
		var id: int = item[0] as int
		var button := PillButton.new(item[1] as String, PillButton.Variant.SECONDARY)
		button.name = "Menu_%d" % id
		button.font_weight = 700
		button.custom_minimum_size = Vector2(PillButton.MIN_WIDTH, MENU_ITEM_HEIGHT)
		button.pressed.connect(_on_menu_item.bind(id))
		column.add_child(button)
		menu_buttons[id] = button


func _pill(node_name: String) -> PillPanel:
	var pill := PillPanel.new()
	pill.name = node_name
	pill.custom_minimum_size = Vector2(0.0, PILL_HEIGHT)
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
