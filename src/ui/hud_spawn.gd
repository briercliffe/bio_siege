class_name HudSpawn
extends Control

## Incubation HUD, screens 09 and 10 (night theme). Positions come from the mockup canvas sources SpawnBuying
## and SpawnReady at 1280x720: the ATP and phase pills and the buttons across the top, the Your turn / unit
## card on the left, the Army card on the right and the stepper tray at the bottom centre. Everything is
## anchored to its edge or centre, so a larger viewport keeps the layout. Deployed units are sent back by
## tapping them (see DeployController), so there is no recall tool.

signal launch_requested
signal help_requested
signal back_requested
signal deploy_type_selected(type_id: String)
signal predict_mode_selected(on: bool)
## "Import…" in the menu: open the Saved bases and armies screen on the Armies tab.
signal library_requested(kind: String)
signal settings_requested
signal quit_requested

const ATP_OVER_BUDGET_COLOR: Color = Color("#e74c3c")
const IMPORT_DIALOG_SCENE: PackedScene = preload("res://src/ui/import_dialog.tscn")

const MENU_SAVE: int = 0
const MENU_IMPORT: int = 1
const MENU_HOW_TO_PLAY: int = 2
const MENU_SOUND: int = 3
const MENU_PREDICT: int = 4
const MENU_SETTINGS: int = 5
const MENU_QUIT: int = 6
const MENU_SAVE_TEXT: String = "Save army…"
const MENU_IMPORT_TEXT: String = "Import…"
const MENU_PREDICT_TEXT: String = "Predict first to fall"
const PREDICT_TOAST: String = "Tap the structure you think falls first"
const DEFAULT_NAME: String = "Army %d"
const LAUNCH_HINT: String = "Buy at least one pathogen"

const EDGE: float = 20.0
const CARD_TOP: float = 96.0
const CARD_WIDTH: float = 300.0
const PILL_HEIGHT: float = 52.0
const ATP_POS: Vector2 = Vector2(20.0, 14.0)
const PHASE_TOP: float = 10.0
const BUTTON_TOP: float = 12.0
const EDIT_RIGHT: float = 196.0
const EDIT_SIZE: Vector2 = Vector2(112.0, 52.0)
const LAUNCH_SIZE: Vector2 = Vector2(164.0, 52.0)
## The menu button sits right after the phase pill: half its width plus a gap from the centre line.
const MENU_FROM_CENTER: float = PillPanel.PHASE_SIZE.x * 0.5 + 12.0
const MENU_SHEET_WIDTH: float = 260.0
const MENU_ITEM_HEIGHT: float = 48.0
const TRAY_BOTTOM: float = 16.0
const TRAY_GAP: int = 14
const PHASE_TITLE: String = "PHASE 2 · INCUBATION"
const PHASE_SUBTITLE: String = "Deploy your army"
const DISC_DIAMETER: float = 60.0
const DISC_ICON_PX: float = 34.0

const TURN_STEPS: Array[String] = [
	"Tap + on a card to buy a unit.",
	"Select a card, then tap the glowing band to deploy.",
	"Press Launch Attack.",
]
const RECALL_HINT: String = "Tap a deployed unit to send it back to the reserve."
const ARMY_NOTE: String = "Units left in reserve appear on random tiles of the glowing band when you launch."


## A 60 px night disc holding one pathogen icon (the unit card header).
class IconDisc:
	extends Control

	var icon_id: String = "":
		set(value):
			icon_id = value
			queue_redraw()
	var config: GameConfig = null

	func _init() -> void:
		custom_minimum_size = Vector2(DISC_DIAMETER, DISC_DIAMETER)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = DISC_DIAMETER * 0.5
		draw_circle(c, r, Color(1.0, 1.0, 1.0, 0.07))
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.16), 2.0, true)
		IconPainter.draw_icon(self, icon_id, Rect2(c - Vector2(DISC_ICON_PX, DISC_ICON_PX) * 0.5,
				Vector2(DISC_ICON_PX, DISC_ICON_PX)), config)


## The dashed "No pathogens yet" box of the empty Army card.
class DashedBox:
	extends PanelContainer

	const RADIUS: float = 20.0
	const DASH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.18)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb: StyleBoxFlat = KitDraw.make_box(Color(1.0, 1.0, 1.0, 0.03), RADIUS)
		sb.set_content_margin_all(22.0)
		add_theme_stylebox_override("panel", sb)

	func _draw() -> void:
		KitDraw.draw_dashed_rounded(self, Rect2(Vector2.ZERO, size).grow(-1.0), RADIUS, DASH_COLOR, 2.0, 7.0, 6.0)


var session: Session = null

var atp_pill: PillPanel = null
var atp_label: Label = null
var phase_pill: PillPanel = null
var btn_menu: IconButton = null
var btn_back: PillButton = null
var btn_launch: PillButton = null

var left_card: FloatingCard = null
var turn_box: VBoxContainer = null
var turn_title_label: Label = null
var turn_body_label: RichTextLabel = null
var unit_box: VBoxContainer = null
var icon_disc: IconDisc = null
var unit_name_label: Label = null
var unit_role_label: Label = null
## "health", "speed", "damage" and "cost" -> StatTile.
var unit_tiles: Dictionary = {}
var unit_desc_label: Label = null
var strain_button: PillButton = null
var strain_summary_label: Label = null
## Living Base: the variants still locked for this pathogen, with a drawn padlock.
var strain_lock_row: HBoxContainer = null
var strain_lock_label: Label = null
var memory_hint_label: Label = null

var right_card: FloatingCard = null
var army_box: VBoxContainer = null
var empty_block: VBoxContainer = null
var spent_value: Label = null
var spent_total_label: Label = null
var spent_track: ProgressTrack = null
var owned_block: VBoxContainer = null
var rows_box: VBoxContainer = null
## Pathogen type id -> ListRow.
var army_rows: Dictionary = {}
var deployed_value: Label = null
var deployed_total_label: Label = null
var deployed_track: ProgressTrack = null
var memory_panel: MemoryPanel = null
var coevolution_panel: CoevolutionPanel = null

var tray: HBoxContainer = null
var cards_container: HBoxContainer = null
var cards: Array[HudSpawnCard] = []

var menu_catcher: Control = null
var menu_sheet: FloatingCard = null
## Menu id (MENU_*) -> PillButton.
var menu_buttons: Dictionary = {}

var import_dialog: ImportDialog = null
var save_dialog: SaveNameDialog = null
## The save library folder; the Incubation phase passes the game's, tests pass a temp one.
var saves_root: String = SaveLibrary.DEFAULT_ROOT
var last_toast_message: String = ""

var selected_type_id: String = ""
var predict_active: bool = false
## The ATP the player holds at the start of Incubation: the wallet plus anything already bought.
var budget_atp: int = 0

var _atp_tween: Tween = null
var _ink: Color = UiPalette.color(true, "ink")
var _muted: Color = UiPalette.color(true, "muted")


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _ready() -> void:
	_update_all()


# --- setup and signals ------------------------------------------------------------

func setup(p_session: Session) -> void:
	if session != null and session.wallet != null and session.wallet.changed.is_connected(_on_wallet_changed):
		session.wallet.changed.disconnect(_on_wallet_changed)
	if session != null and session.army != null and session.army.changed.is_connected(_on_army_changed):
		session.army.changed.disconnect(_on_army_changed)

	session = p_session

	if session != null and session.wallet != null:
		session.wallet.changed.connect(_on_wallet_changed)
	if session != null and session.army != null:
		session.army.changed.connect(_on_army_changed)
	_capture_budget()

	_populate_tray()
	_sync_memory_panel()
	_sync_coevolution_panel()
	_update_all()


func _capture_budget() -> void:
	budget_atp = 0
	if session == null or session.wallet == null:
		return
	budget_atp = session.wallet.get_amount("atp")
	if session.army != null:
		budget_atp += int(session.army.total_cost().get("atp", 0))


## Shows the read-only MemoryPanel inside the Army card, only when immune memory is enabled.
func _sync_memory_panel() -> void:
	var enabled: bool = session != null and session.config != null and session.config.memory_enabled()
	if memory_panel == null and enabled:
		memory_panel = MemoryPanel.new()
		memory_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		memory_panel.offset_left = 0.0
		memory_panel.offset_right = 0.0
		memory_panel.offset_top = 0.0
		memory_panel.offset_bottom = 0.0
		army_box.add_child(memory_panel)
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
		army_box.add_child(coevolution_panel)
	if coevolution_panel != null:
		if memory_panel != null and memory_panel.get_parent() == coevolution_panel.get_parent():
			coevolution_panel.get_parent().move_child(coevolution_panel, memory_panel.get_index() + 1)
		coevolution_panel.visible = enabled
		if enabled:
			coevolution_panel.setup(session)


func _update_all() -> void:
	if session != null and session.wallet != null:
		_update_atp_label(session.wallet.get_amount("atp"), false)
	_update_army_ui()


# --- tray -----------------------------------------------------------------------------

func _strains_enabled() -> bool:
	return session != null and session.config != null and session.config.flag("strains")


func _sorted_pathogen_ids() -> Array[String]:
	var p_ids: Array[String] = session.config.pathogen_ids()
	p_ids.sort_custom(func(a: String, b: String) -> bool:
		var p_a: PathogenDef = session.config.pathogens.get(a)
		var p_b: PathogenDef = session.config.pathogens.get(b)
		var cost_a: int = int(p_a.cost.get("atp", 0)) if p_a != null else 0
		var cost_b: int = int(p_b.cost.get("atp", 0)) if p_b != null else 0
		if cost_a != cost_b:
			return cost_a < cost_b
		return a < b
	)
	return p_ids


func _populate_tray() -> void:
	for c: HudSpawnCard in cards:
		cards_container.remove_child(c)
		c.queue_free()
	cards.clear()
	if session == null or session.config == null:
		return

	for tid: String in _sorted_pathogen_ids():
		var p_def: PathogenDef = session.config.pathogens.get(tid)
		if p_def == null:
			continue
		var card := HudSpawnCard.new()
		card.setup_pathogen(p_def, session.config)
		card.selected.connect(_on_card_selected.bind(card))
		card.buy_requested.connect(_on_card_buy_requested)
		card.unbuy_requested.connect(_on_card_unbuy_requested)
		cards_container.add_child(card)
		cards.append(card)
	_apply_selection()


## Re-reads names, costs and roles after a config hot reload (#27).
## The tray is rebuilt only when pathogens were added, removed or re-ordered by cost.
func refresh_config() -> void:
	if session == null or session.config == null:
		return
	var expected_ids: Array[String] = _sorted_pathogen_ids()
	var current_ids: Array[String] = []
	for c: HudSpawnCard in cards:
		current_ids.append(c.type_id)
	if current_ids == expected_ids:
		for c: HudSpawnCard in cards:
			var p_def: PathogenDef = session.config.pathogens.get(c.type_id)
			if p_def != null:
				c.setup_pathogen(p_def, session.config)
	else:
		_populate_tray()
		if not selected_type_id.is_empty() and not session.config.pathogens.has(selected_type_id):
			selected_type_id = ""
			deploy_type_selected.emit("")
			_apply_selection()
	_sync_memory_panel()
	_sync_coevolution_panel()
	_update_all()


func get_cards() -> Array[HudSpawnCard]:
	return cards


func get_card(type_id: String) -> HudSpawnCard:
	for c: HudSpawnCard in cards:
		if c.type_id == type_id:
			return c
	return null


func _apply_selection() -> void:
	for c: HudSpawnCard in cards:
		c.set_selected(not selected_type_id.is_empty() and c.type_id == selected_type_id)


## Tapping a card selects its type for deploying; tapping the selected card again deselects it.
func _on_card_selected(card: HudSpawnCard) -> void:
	selected_type_id = "" if selected_type_id == card.type_id else card.type_id
	_apply_selection()
	_update_left_card()
	deploy_type_selected.emit(selected_type_id)


func _on_card_buy_requested(type_id: String) -> void:
	if session != null and session.army != null and session.wallet != null:
		var ok: bool = session.army.buy(type_id, session.wallet)
		if ok and SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("unit_bought", {"type": type_id})


func _on_card_unbuy_requested(type_id: String) -> void:
	if session != null and session.army != null and session.wallet != null:
		var ok: bool = session.army.unbuy(type_id, session.wallet)
		if ok and SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("unit_unbought", {"type": type_id})


func _on_strain_button_pressed() -> void:
	if selected_type_id.is_empty():
		return
	_on_card_strain_cycle_requested(selected_type_id)


func _on_card_strain_cycle_requested(type_id: String) -> void:
	if not _strains_enabled() or session.army == null:
		return
	var p_def: PathogenDef = session.config.pathogens.get(type_id)
	if p_def == null:
		return
	var ids: Array[String] = p_def.strain_ids()
	var idx: int = ids.find(session.army.strain_of(type_id))
	var next_id: String = ids[(idx + 1) % ids.size()]
	# A locked variant cannot be picked: the cycle skips it (unlock it in the Mutation Lab).
	for step: int in range(ids.size()):
		var candidate: String = ids[(idx + 1 + step) % ids.size()]
		if session.strain_unlocked(type_id, candidate):
			next_id = candidate
			break
	if not session.army.set_strain(type_id, next_id):
		_show_toast("Remove all %ss to change strain" % p_def.display_name)


# --- buttons and reactions ---------------------------------------------------------------

func _on_back_pressed() -> void:
	if session != null and session.army != null and session.wallet != null:
		session.army.refund_all(session.wallet)
	back_requested.emit()


func _on_launch_pressed() -> void:
	if session != null and session.army != null and session.army.total_count() > 0:
		launch_requested.emit()


func set_predict_mode(active: bool) -> void:
	predict_active = active
	predict_mode_selected.emit(predict_active)


func _on_wallet_changed(currency: String, new_amount: int) -> void:
	if currency == "atp":
		_update_atp_label(new_amount, true)
	_update_army_ui()


func _on_army_changed() -> void:
	_update_army_ui()


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


func _update_army_ui() -> void:
	var has_army: bool = session != null and session.army != null
	var total_army: int = session.army.total_count() if has_army else 0
	btn_launch.disabled = total_army == 0
	btn_launch.tooltip_text = LAUNCH_HINT if total_army == 0 else ""

	var wallet_atp: int = session.wallet.get_amount("atp") if (session != null and session.wallet != null) else 0
	for c: HudSpawnCard in cards:
		var res_cnt: int = session.army.reserve_count(c.type_id) if has_army else 0
		var dep_cnt: int = session.army.deployed_count(c.type_id) if has_army else 0
		c.update_counts(res_cnt, dep_cnt)
		if has_army:
			c.set_unit_cost(int(session.army.unit_cost(c.type_id).get("atp", 0)))
		c.update_affordability(wallet_atp)
	_update_left_card()
	_update_army_card()


# --- left card: Your turn or the selected unit ------------------------------------------------

func _update_left_card() -> void:
	var pdef: PathogenDef = null
	if session != null and session.config != null and not selected_type_id.is_empty():
		pdef = session.config.pathogens.get(selected_type_id) as PathogenDef
	turn_box.visible = pdef == null
	unit_box.visible = pdef != null
	if pdef == null:
		turn_body_label.text = "Spend the [b]%d[/b] ATP you kept on an army, then break your own defense." % budget_atp
		return
	var cfg: GameConfig = session.config
	icon_disc.icon_id = pdef.id
	icon_disc.config = cfg
	unit_name_label.text = pdef.display_name
	unit_role_label.text = pdef.role
	var tick_rate: int = maxi(cfg.tick_rate, 1)
	var cost_atp: int = int(session.army.unit_cost(pdef.id).get("atp", 0)) if session.army != null else int(pdef.cost.get("atp", 0))
	(unit_tiles["health"] as StatTile).setup("Health", str(pdef.hp))
	(unit_tiles["speed"] as StatTile).setup("Speed", "%s tiles/s" % _trim(float(pdef.speed_mt_per_tick * tick_rate) / 1000.0))
	(unit_tiles["damage"] as StatTile).setup("Damage", "%d / %s s" % [pdef.attack_damage,
			_trim(float(pdef.attack_interval_ticks) / float(tick_rate))])
	(unit_tiles["cost"] as StatTile).setup("Cost", "%d ATP" % cost_atp)
	unit_desc_label.text = UnitCopy.description(pdef.id, cfg)
	_update_strain_controls(pdef)


## "5" for a whole number, otherwise one decimal ("2.5").
static func _trim(v: float) -> String:
	var s: String = "%.1f" % v
	return s.trim_suffix(".0")


## Locked variants (Living Base only) are listed under the picker with a padlock; Lab shows none.
func _update_strain_locks(pdef: PathogenDef) -> void:
	var locked: Array[String] = []
	for s: StrainDef in pdef.strains:
		if not session.strain_unlocked(pdef.id, s.id):
			locked.append("%s (%d DNA)" % [s.display_name, s.unlock_dna])
	strain_lock_row.visible = not locked.is_empty()
	strain_lock_label.text = "Locked: " + ", ".join(locked) if not locked.is_empty() else ""


func _update_strain_controls(pdef: PathogenDef) -> void:
	var on: bool = _strains_enabled()
	strain_button.visible = on
	strain_summary_label.visible = on
	if not on:
		strain_lock_row.visible = false
		memory_hint_label.visible = false
		return
	var strain: StrainDef = pdef.strain(session.army.strain_of(pdef.id))
	if strain == null:
		strain = StrainDef.wild()
	var remembered: int = 0
	if session.config.memory_enabled():
		remembered = session.defender_memory().effective_level("%s/%s" % [pdef.id, strain.id], session.config)
	strain_button.text = strain.display_name
	strain_button.queue_redraw()
	strain_summary_label.text = strain.summary()
	_update_strain_locks(pdef)
	memory_hint_label.visible = remembered > 0
	memory_hint_label.text = "Remembered L%d" % remembered if remembered > 0 else ""


# --- right card: Army --------------------------------------------------------------------------------

func _update_army_card() -> void:
	if session == null or session.army == null or session.config == null or session.wallet == null:
		return
	var army: Army = session.army
	var total: int = army.total_count()
	var wallet_atp: int = session.wallet.get_amount("atp")
	var spent: int = maxi(0, budget_atp - wallet_atp)
	empty_block.visible = total == 0
	owned_block.visible = total > 0
	spent_value.text = str(spent)
	spent_total_label.text = "of %d ATP" % budget_atp
	spent_track.value = float(spent) / float(budget_atp) if budget_atp > 0 else 0.0
	if total == 0:
		return

	var wanted: Array[String] = []
	for tid: String in _sorted_pathogen_ids():
		if army.reserve_count(tid) + army.deployed_count(tid) > 0:
			wanted.append(tid)
	var existing: Array[String] = []
	for tid: Variant in army_rows.keys():
		existing.append(str(tid))
	if existing != wanted:
		for row: Variant in army_rows.values():
			(row as Node).queue_free()
			rows_box.remove_child(row as Node)
		army_rows.clear()
		for tid: String in wanted:
			var row := ListRow.new()
			row.name = "Row_%s" % tid
			row.night = true
			rows_box.add_child(row)
			army_rows[tid] = row
	var deployed_total: int = 0
	for tid: String in wanted:
		var pdef: PathogenDef = session.config.pathogens.get(tid) as PathogenDef
		var deployed: int = army.deployed_count(tid)
		deployed_total += deployed
		(army_rows[tid] as ListRow).setup(tid, pdef.display_name if pdef != null else tid, deployed,
				army.reserve_count(tid) + deployed, session.config)
	deployed_value.text = str(deployed_total)
	deployed_total_label.text = "of %d units" % total
	deployed_track.value = float(deployed_total) / float(total)


## "3 of 5 out" for one army row, or "" when the type is not owned.
func army_row_text(type_id: String) -> String:
	var row: ListRow = army_rows.get(type_id) as ListRow
	return row.count_text() if row != null else ""


## "Deployed 3", as shown (the caption and the number are separate labels).
func deployed_text() -> String:
	return "Deployed %s" % deployed_value.text


## "Spent 0", as shown.
func spent_text() -> String:
	return "Spent %s" % spent_value.text


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
		MENU_PREDICT:
			set_predict_mode(not predict_active)
			if predict_active:
				_show_toast(PREDICT_TOAST)
		MENU_SAVE:
			open_save_dialog()
		MENU_IMPORT:
			library_requested.emit(SaveLibrary.KIND_ARMY)
		MENU_SETTINGS:
			settings_requested.emit()
		MENU_QUIT:
			quit_requested.emit()


func open_import_dialog() -> void:
	import_dialog.open("Import Army")


## "Save army…": asks for a name, defaulting to "Army N" after the slots already saved.
func open_save_dialog() -> void:
	var n: int = SaveLibrary.new(saves_root).count(SaveLibrary.KIND_ARMY) + 1
	save_dialog.open(MENU_SAVE_TEXT, DEFAULT_NAME % n)


## Saves the deployed army as a library slot. Errors (a full library) show in the name dialog.
func save_army(slot_name: String) -> Dictionary:
	if session == null or session.army == null:
		return {"ok": false, "path": "", "error": "Nothing to save"}
	var lib := SaveLibrary.new(saves_root)
	var res: Dictionary = lib.save_army(slot_name, session.army, session.config)
	if not bool(res.get("ok", false)):
		save_dialog.set_error(str(res.get("error", "")))
		return res
	save_dialog.close()
	_show_toast("Saved '%s'" % slot_name)
	return res


func import_army(json_text: String) -> bool:
	if session == null or session.config == null or session.army == null or session.wallet == null:
		return false
	var res: Dictionary = SnapshotIO.parse_army(json_text, session.config)
	if not res.get("ok", false):
		var err_msg: String = str(res.get("error", "Failed to parse army"))
		import_dialog.set_error(err_msg)
		return false

	import_dialog.close()
	_show_toast(army_loaded_message(SaveLibrary.apply_army(session, res)))
	return true


## "Army loaded", or how many units fit when the ATP ran out.
static func army_loaded_message(result: Dictionary) -> String:
	var deployed: int = int(result.get("deployed", 0))
	var total: int = int(result.get("total", 0))
	if deployed < total:
		return "Only %d of %d units fit your ATP" % [deployed, total]
	return "Army loaded"


func _on_import_load_requested(text: String) -> void:
	import_army(text)


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

	import_dialog = IMPORT_DIALOG_SCENE.instantiate() as ImportDialog
	import_dialog.name = "ImportDialog"
	import_dialog.load_requested.connect(_on_import_load_requested)
	add_child(import_dialog)

	save_dialog = SaveNameDialog.new()
	save_dialog.name = "SaveDialog"
	save_dialog.save_requested.connect(save_army)
	add_child(save_dialog)


func _build_atp_pill() -> void:
	atp_pill = _pill("AtpPill")
	atp_pill.position = ATP_POS
	var row: HBoxContainer = HudParts.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(IconSlot.new("atp", 24.0))
	atp_label = HudParts.label("0", 24, 800, _ink)
	atp_label.name = "AtpLabel"
	row.add_child(atp_label)
	row.add_child(HudParts.label("ATP", 14, 700, _muted))
	atp_pill.add_child(row)


func _build_phase_pill() -> void:
	phase_pill = _pill("PhasePill")
	phase_pill.set_phase(PHASE_TITLE, PHASE_SUBTITLE)
	_anchor_top_center(phase_pill, PHASE_TOP, PillPanel.PHASE_SIZE)


func _build_buttons() -> void:
	btn_menu = IconButton.new(IconButton.Kind.MENU)
	btn_menu.name = "BtnMenu"
	btn_menu.night = true
	btn_menu.anchor_left = 0.5
	btn_menu.anchor_right = 0.5
	btn_menu.offset_left = MENU_FROM_CENTER
	btn_menu.offset_right = MENU_FROM_CENTER + IconButton.ROUND_SIZE.x
	btn_menu.offset_top = BUTTON_TOP
	btn_menu.offset_bottom = BUTTON_TOP + IconButton.ROUND_SIZE.y
	btn_menu.pressed.connect(_on_btn_menu_pressed)
	add_child(btn_menu)

	btn_back = PillButton.new("Edit base", PillButton.Variant.SECONDARY)
	btn_back.name = "BtnBack"
	btn_back.night = true
	btn_back.font_weight = 700
	_place_top_right(btn_back, EDIT_RIGHT, EDIT_SIZE)
	btn_back.pressed.connect(_on_back_pressed)
	add_child(btn_back)

	btn_launch = PillButton.new("Launch Attack", PillButton.Variant.PRIMARY)
	btn_launch.name = "BtnLaunch"
	btn_launch.night = true
	_place_top_right(btn_launch, EDGE, LAUNCH_SIZE)
	btn_launch.pressed.connect(_on_launch_pressed)
	add_child(btn_launch)


func _place_top_right(c: Control, right: float, sz: Vector2) -> void:
	c.custom_minimum_size = sz
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.offset_right = -right
	c.offset_left = -right - sz.x
	c.offset_top = BUTTON_TOP
	c.offset_bottom = BUTTON_TOP + sz.y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _build_left_card() -> void:
	left_card = _card("LeftCard")
	left_card.position = Vector2(EDGE, CARD_TOP)
	var holder: VBoxContainer = HudParts.vbox(0)
	left_card.add_child(holder)

	turn_box = HudParts.vbox(14)
	turn_box.name = "TurnBox"
	turn_box.add_child(HudParts.kicker("YOUR TURN", _muted))
	turn_title_label = HudParts.wrapping(HudParts.label("You are the pathogen now.", 24, 800, _ink))
	turn_box.add_child(turn_title_label)
	turn_body_label = RichTextLabel.new()
	turn_body_label.name = "TurnBody"
	turn_body_label.bbcode_enabled = true
	turn_body_label.fit_content = true
	turn_body_label.scroll_active = false
	turn_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_body_label.add_theme_font_override("normal_font", UiFonts.weight(400))
	turn_body_label.add_theme_font_override("bold_font", UiFonts.weight(800))
	turn_body_label.add_theme_font_size_override("normal_font_size", 15)
	turn_body_label.add_theme_font_size_override("bold_font_size", 15)
	turn_body_label.add_theme_color_override("default_color", _muted)
	turn_box.add_child(turn_body_label)
	var steps: VBoxContainer = HudParts.vbox(12)
	for i: int in range(TURN_STEPS.size()):
		var row: HBoxContainer = HudParts.hbox(12)
		var badge := NumberBadge.new(i + 1)
		badge.night = true
		row.add_child(badge)
		row.add_child(HudParts.wrapping(HudParts.label(TURN_STEPS[i], 15, 400, _ink)))
		steps.add_child(row)
	turn_box.add_child(steps)
	holder.add_child(turn_box)

	unit_box = HudParts.vbox(14)
	unit_box.name = "UnitBox"
	unit_box.visible = false
	var header: HBoxContainer = HudParts.hbox(14)
	icon_disc = IconDisc.new()
	header.add_child(icon_disc)
	var names: VBoxContainer = HudParts.vbox(0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_name_label = HudParts.wrapping(HudParts.label("", 22, 800, _ink))
	unit_role_label = HudParts.wrapping(HudParts.label("", 14, 400, _muted))
	names.add_child(unit_name_label)
	names.add_child(unit_role_label)
	header.add_child(names)
	unit_box.add_child(header)

	var tile_grid := GridContainer.new()
	tile_grid.columns = 2
	tile_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_grid.add_theme_constant_override("h_separation", 8)
	tile_grid.add_theme_constant_override("v_separation", 8)
	for key: String in ["health", "speed", "damage", "cost"]:
		var tile := StatTile.new()
		tile.name = "Tile_%s" % key
		tile.night = true
		tile.accent_value = key == "cost"
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_tiles[key] = tile
		tile_grid.add_child(tile)
	unit_box.add_child(tile_grid)

	strain_button = PillButton.new("", PillButton.Variant.SECONDARY)
	strain_button.name = "StrainButton"
	strain_button.night = true
	strain_button.font_weight = 700
	strain_button.visible = false
	strain_button.pressed.connect(_on_strain_button_pressed)
	unit_box.add_child(strain_button)
	strain_summary_label = HudParts.wrapping(HudParts.label("", 14, 400, _muted))
	strain_summary_label.name = "StrainSummaryLabel"
	strain_summary_label.visible = false
	unit_box.add_child(strain_summary_label)
	strain_lock_row = HBoxContainer.new()
	strain_lock_row.name = "StrainLockRow"
	strain_lock_row.visible = false
	strain_lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strain_lock_row.add_theme_constant_override("separation", 8)
	strain_lock_row.add_child(LockIcon.new())
	strain_lock_label = HudParts.wrapping(HudParts.label("", 13, 400, _muted))
	strain_lock_label.name = "StrainLockLabel"
	strain_lock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strain_lock_row.add_child(strain_lock_label)
	unit_box.add_child(strain_lock_row)
	memory_hint_label = HudParts.label("", 14, 700, Color("#48dbfb"))
	memory_hint_label.name = "MemoryHintLabel"
	memory_hint_label.visible = false
	unit_box.add_child(memory_hint_label)

	unit_desc_label = HudParts.wrapping(HudParts.label("", 14, 400, _muted))
	unit_box.add_child(unit_desc_label)
	unit_box.add_child(HudParts.wrapping(HudParts.label(RECALL_HINT, 14, 400, _muted)))
	holder.add_child(unit_box)


func _build_right_card() -> void:
	right_card = _card("RightCard")
	right_card.anchor_left = 1.0
	right_card.anchor_right = 1.0
	right_card.offset_left = -EDGE - CARD_WIDTH
	right_card.offset_right = -EDGE
	right_card.offset_top = CARD_TOP
	right_card.offset_bottom = CARD_TOP
	right_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	army_box = HudParts.vbox(14)
	right_card.add_child(army_box)
	army_box.add_child(HudParts.kicker("ARMY", _muted))

	empty_block = HudParts.vbox(14)
	empty_block.name = "EmptyBlock"
	var dashed := DashedBox.new()
	dashed.name = "EmptyBox"
	var dashed_text: VBoxContainer = HudParts.vbox(6)
	dashed_text.alignment = BoxContainer.ALIGNMENT_CENTER
	var empty_title: Label = HudParts.wrapping(HudParts.label("No pathogens yet", 17, 800, _ink))
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var empty_body: Label = HudParts.wrapping(HudParts.label("Launch Attack unlocks once you own a unit.", 14, 400, _muted))
	empty_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dashed_text.add_child(empty_title)
	dashed_text.add_child(empty_body)
	dashed.add_child(dashed_text)
	empty_block.add_child(dashed)
	var spent_block: VBoxContainer = HudParts.vbox(8)
	var spent_row: HBoxContainer = HudParts.hbox(5)
	spent_row.add_child(HudParts.label("Spent", 15, 400, _ink))
	spent_value = HudParts.label("0", 15, 800, _ink)
	spent_value.name = "SpentValue"
	spent_row.add_child(spent_value)
	spent_total_label = HudParts.label("of 0 ATP", 15, 400, _muted)
	spent_total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spent_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spent_row.add_child(spent_total_label)
	spent_block.add_child(spent_row)
	spent_track = ProgressTrack.new()
	spent_track.name = "SpentTrack"
	spent_track.night = true
	spent_block.add_child(spent_track)
	empty_block.add_child(spent_block)
	army_box.add_child(empty_block)

	owned_block = HudParts.vbox(14)
	owned_block.name = "OwnedBlock"
	owned_block.visible = false
	rows_box = HudParts.vbox(8)
	rows_box.name = "Rows"
	owned_block.add_child(rows_box)
	var deployed_block: VBoxContainer = HudParts.vbox(8)
	var deployed_row: HBoxContainer = HudParts.hbox(5)
	deployed_row.add_child(HudParts.label("Deployed", 15, 400, _ink))
	deployed_value = HudParts.label("0", 15, 800, _ink)
	deployed_value.name = "DeployedValue"
	deployed_row.add_child(deployed_value)
	deployed_total_label = HudParts.label("of 0 units", 15, 400, _muted)
	deployed_total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deployed_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	deployed_row.add_child(deployed_total_label)
	deployed_block.add_child(deployed_row)
	deployed_track = ProgressTrack.new()
	deployed_track.name = "DeployedTrack"
	deployed_track.night = true
	deployed_block.add_child(deployed_track)
	owned_block.add_child(deployed_block)
	owned_block.add_child(HudParts.wrapping(HudParts.label(ARMY_NOTE, 14, 400, _muted)))
	army_box.add_child(owned_block)


func _build_tray() -> void:
	tray = HBoxContainer.new()
	tray.name = "Tray"
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_theme_constant_override("separation", TRAY_GAP)
	tray.anchor_left = 0.5
	tray.anchor_right = 0.5
	tray.anchor_top = 1.0
	tray.anchor_bottom = 1.0
	tray.offset_top = -TRAY_BOTTOM - StepperCard.CARD_SIZE.y
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

	menu_sheet = _card("MenuSheet")
	menu_sheet.visible = false
	menu_sheet.custom_minimum_size = Vector2(MENU_SHEET_WIDTH, 0.0)
	menu_sheet.anchor_left = 0.5
	menu_sheet.anchor_right = 0.5
	menu_sheet.offset_left = MENU_FROM_CENTER
	menu_sheet.offset_right = MENU_FROM_CENTER + MENU_SHEET_WIDTH
	menu_sheet.offset_top = BUTTON_TOP + IconButton.ROUND_SIZE.y + 8.0
	menu_sheet.offset_bottom = menu_sheet.offset_top
	var column: VBoxContainer = HudParts.vbox(8)
	menu_sheet.add_child(column)
	var items: Array[Array] = [
		[MENU_HOW_TO_PLAY, "How to play"],
		[MENU_SOUND, "Sound: On"],
		[MENU_PREDICT, MENU_PREDICT_TEXT],
		[MENU_SAVE, MENU_SAVE_TEXT],
		[MENU_IMPORT, MENU_IMPORT_TEXT],
		[MENU_SETTINGS, "Settings"],
		[MENU_QUIT, "Quit to title"],
	]
	for item: Array in items:
		var id: int = item[0] as int
		var button := PillButton.new(item[1] as String, PillButton.Variant.SECONDARY)
		button.name = "Menu_%d" % id
		button.night = true
		button.font_weight = 700
		button.custom_minimum_size = Vector2(PillButton.MIN_WIDTH, MENU_ITEM_HEIGHT)
		button.pressed.connect(_on_menu_item.bind(id))
		column.add_child(button)
		menu_buttons[id] = button


func _card(node_name: String) -> FloatingCard:
	var card := FloatingCard.new()
	card.name = node_name
	card.night = true
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	add_child(card)
	return card


func _pill(node_name: String) -> PillPanel:
	var pill := PillPanel.new()
	pill.name = node_name
	pill.night = true
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
