class_name DefenseLogScreen
extends Control

## Living Base Defense log (#170): every AI raid on the player's base, newest first, with its outcome, what it
## cost and earned, what the base learned and how its pools evolved, and a Watch button that replays the
## recorded raid. It rehearses the Phase 3 defense log.

signal back_requested
signal replay_requested(log_index: int)

const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const COLUMN_WIDTH: float = 820.0
const WATCH_SIZE: Vector2 = Vector2(140.0, 52.0)
const EMPTY_TEXT: String = "No raids yet. Your base is safe for now."
const HELD_COLOR: Color = Color("#2ecc71")
const INFECTED_COLOR: Color = Color("#e74c3c")
const REVENGE_WINDOW_S: int = 24 * 3600
const LOADING_TEXT: String = "Loading..."
const ACTION_SIZE: Vector2 = Vector2(140.0, 52.0)

var session: Session = null
var fsm: GameStateMachine = null

var background: AmbientBackground = null
var btn_back: IconButton = null
var title_label: Label = null
var empty_label: Label = null
var scroll: ScrollContainer = null
var rows_box: VBoxContainer = null
## One per log entry, newest first: {"row", "watch", "index"}.
var rows: Array[Dictionary] = []
## Online mode: the next page cursor ("" = no more), the "Load more" button and a one-line message.
var next_cursor: String = ""
var btn_more: PillButton = null
var message_label: Label = null
## Tests set this to fake the clock; -1 reads the system clock.
var now_unix_override: int = -1


func _init() -> void:
	name = "DefenseLogScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func setup(p_session: Session, p_fsm: GameStateMachine = null) -> void:
	session = p_session
	fsm = p_fsm
	_populate()


func _build() -> void:
	background = AmbientBackground.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	btn_back = IconButton.new(IconButton.Kind.BACK)
	btn_back.name = "BtnBack"
	btn_back.position = BACK_POS
	btn_back.pressed.connect(func() -> void: back_requested.emit())
	add_child(btn_back)

	var outer := VBoxContainer.new()
	outer.name = "Column"
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_top = 24.0
	outer.offset_bottom = -24.0
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 12)
	add_child(outer)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Defense log"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(title_label, 40, 800, UiPalette.color(false, "ink"))
	outer.add_child(title_label)

	empty_label = Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = EMPTY_TEXT
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(empty_label, 18, 400, UiPalette.color(false, "muted"))
	outer.add_child(empty_label)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(center)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	rows_box.mouse_filter = Control.MOUSE_FILTER_PASS
	rows_box.add_theme_constant_override("separation", 12)
	center.add_child(rows_box)


func _populate() -> void:
	for c: Node in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	rows.clear()
	btn_more = null
	if session != null and session.living_flow != null and session.living_flow.is_online():
		_load_online_page("")
		return
	var log: Array[Dictionary] = session.profile.defense_log if (session != null and session.profile != null) else []
	empty_label.visible = log.is_empty()
	scroll.visible = not log.is_empty()
	if session == null or session.config == null:
		return
	for i: int in range(log.size()):
		_add_row(i, log[i])


func _add_row(index: int, entry: Dictionary) -> void:
	var cfg: GameConfig = session.config
	var card := FloatingCard.new()
	card.name = "Row_%d" % index
	card.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var held: bool = str(entry.get("outcome", "")) == "defender"
	var chip := Label.new()
	chip.name = "OutcomeChip"
	chip.text = outcome_text(entry)
	UiFonts.style_label(chip, 16, 800, HELD_COLOR if held else INFECTED_COLOR)
	head.add_child(chip)
	var raid := Label.new()
	raid.name = "RaidLabel"
	raid.text = raid_text(entry)
	raid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiFonts.style_label(raid, 20, 800, UiPalette.color(false, "ink"))
	head.add_child(raid)
	var watch := PillButton.new("Watch", PillButton.Variant.SECONDARY)
	watch.name = "BtnWatch_%d" % index
	watch.custom_minimum_size = WATCH_SIZE
	watch.disabled = not (entry.get("battle", null) is Dictionary)
	watch.pressed.connect(watch_replay.bind(index))
	head.add_child(watch)

	_add_line(box, "ArmyLabel", army_text(entry.get("army", {}), cfg), 15, 700)
	_add_line(box, "ResultLabel", result_text(entry), 15, 400)
	var learning: String = learning_text(entry.get("memory_changes", []), cfg)
	if not learning.is_empty():
		_add_line(box, "LearningLabel", learning, 14, 400)
	var evolution: String = evolution_text(entry.get("evolution", []), cfg)
	if not evolution.is_empty():
		_add_line(box, "EvolutionLabel", evolution, 14, 400)
	rows_box.add_child(card)
	rows.append({"row": card, "watch": watch, "index": index})


func _add_line(parent: Control, node_name: String, text: String, px: int, weight: int) -> void:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.style_label(l, px, weight, UiPalette.color(false, "ink" if weight >= 700 else "muted"))
	parent.add_child(l)


## Online: one page of defense_log_list. The first page replaces the rows, later pages add to them.
func _load_online_page(cursor: String) -> void:
	if message_label == null:
		message_label = Label.new()
		message_label.name = "MessageLabel"
		message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiFonts.style_label(message_label, 16, 700, UiPalette.color(false, "danger"))
		(empty_label.get_parent() as Control).add_child(message_label)
		(empty_label.get_parent() as Control).move_child(message_label, 2)
	message_label.text = ""
	if cursor.is_empty():
		empty_label.text = LOADING_TEXT
		empty_label.visible = true
	var res: Dictionary = await session.living_flow.backend().defense_log_list(cursor)
	if not bool(res.get("ok", false)):
		empty_label.visible = false
		message_label.text = NetCopy.error_text(str(res.get("error", "network_error")))
		return
	var entries: Array = res.get("entries", []) as Array
	if cursor.is_empty():
		rows.clear()
	next_cursor = str(res.get("cursor", ""))
	empty_label.text = EMPTY_TEXT
	empty_label.visible = entries.is_empty() and rows.is_empty()
	scroll.visible = not (entries.is_empty() and rows.is_empty())
	if btn_more != null:
		rows_box.remove_child(btn_more)
	for e: Variant in entries:
		_add_online_row(e as Dictionary)
	if not next_cursor.is_empty():
		if btn_more == null:
			btn_more = PillButton.new("Load more", PillButton.Variant.SECONDARY)
			btn_more.name = "BtnMore"
			btn_more.custom_minimum_size = Vector2(PillButton.MIN_WIDTH, 52.0)
			btn_more.pressed.connect(func() -> void: _load_online_page(next_cursor))
		rows_box.add_child(btn_more)
	elif btn_more != null:
		btn_more.queue_free()
		btn_more = null


func _now_unix() -> int:
	return now_unix_override if now_unix_override >= 0 else LivingBaseStore.now_unix()


## True while a Revenge raid on the attacker is still allowed (24 hours after the raid).
func revenge_allowed(entry: Dictionary) -> bool:
	return _now_unix() - int(entry.get("created_unix", 0)) < REVENGE_WINDOW_S and not str(entry.get("attacker_id", "")).is_empty()


func _add_online_row(entry: Dictionary) -> void:
	var cfg: GameConfig = session.config
	var card := FloatingCard.new()
	card.name = "Row_%s" % str(entry.get("raid_id", ""))
	card.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var held: bool = str(entry.get("outcome", "")) == "defender"
	var chip := Label.new()
	chip.name = "OutcomeChip"
	chip.text = outcome_text(entry)
	UiFonts.style_label(chip, 16, 800, HELD_COLOR if held else INFECTED_COLOR)
	head.add_child(chip)
	var who := Label.new()
	who.name = "RaidLabel"
	who.text = online_raid_text(entry)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiFonts.style_label(who, 20, 800, UiPalette.color(false, "ink"))
	head.add_child(who)
	var raid_id: String = str(entry.get("raid_id", ""))
	var watch := PillButton.new("Watch", PillButton.Variant.SECONDARY)
	watch.name = "BtnWatch_%s" % raid_id
	watch.custom_minimum_size = WATCH_SIZE
	watch.disabled = not bool(entry.get("has_battle", entry.get("battle", null) is Dictionary))
	watch.pressed.connect(watch_online.bind(raid_id))
	head.add_child(watch)
	var revenge: PillButton = null
	if revenge_allowed(entry):
		revenge = PillButton.new("Revenge", PillButton.Variant.PRIMARY)
		revenge.name = "BtnRevenge_%s" % raid_id
		revenge.custom_minimum_size = ACTION_SIZE
		revenge.pressed.connect(take_revenge.bind(str(entry.get("attacker_id", ""))))
		head.add_child(revenge)
	_add_line(box, "ArmyLabel", army_text(entry.get("army", {}), cfg), 15, 700)
	_add_line(box, "ResultLabel", online_result_text(entry), 15, 400)
	var learning: String = learning_text(entry.get("memory_changes", []), cfg)
	if not learning.is_empty():
		_add_line(box, "LearningLabel", learning, 14, 400)
	var evolution: String = evolution_text(entry.get("evolution", []), cfg)
	if not evolution.is_empty():
		_add_line(box, "EvolutionLabel", evolution, 14, 400)
	rows_box.add_child(card)
	rows.append({"row": card, "watch": watch, "revenge": revenge, "index": rows.size(), "raid_id": raid_id})


## Fetches the full entry (with its battle) and replays it exactly as the offline log does.
func watch_online(raid_id: String) -> void:
	if session == null or session.living_flow == null:
		return
	var res: Dictionary = await session.living_flow.backend().defense_log_get(raid_id)
	if not bool(res.get("ok", false)):
		message_label.text = NetCopy.error_text(str(res.get("error", "network_error")))
		return
	if not session.living_flow.begin_replay_entry(res.get("entry", {}) as Dictionary):
		message_label.text = "That raid has no replay."
		return
	replay_requested.emit(-1)
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.INFECTION)


## Revenge: a raid on the attacker. It skips trophy matching but the server still honours shields.
func take_revenge(attacker_id: String) -> void:
	if session == null or session.living_flow == null:
		return
	var res: Dictionary = await session.living_flow.begin_pvp_raid(attacker_id)
	if not bool(res.get("ok", false)):
		message_label.text = NetCopy.error_text(str(res.get("error", "network_error")))
		return
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.INCUBATION)


## "vs Ada · live" style title for an online entry.
static func online_raid_text(entry: Dictionary) -> String:
	var name_text: String = str(entry.get("attacker_name", ""))
	return "vs %s" % (name_text if not name_text.is_empty() else "Player")


## "-80 ATP · +12 Amino Acids · -20 trophies".
static func online_result_text(entry: Dictionary) -> String:
	var text: String = result_text(entry)
	var trophies: int = int(entry.get("trophies_delta", 0))
	if trophies != 0:
		text += " · %s" % ResultsPhase.trophies_text(trophies)
	return text


## Replays log entry `index` in Infection. Nothing about the profile changes.
func watch_replay(index: int) -> void:
	if session == null or session.living_flow == null or not session.living_flow.begin_replay(index):
		return
	replay_requested.emit(index)
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.INFECTION)


# --- text -------------------------------------------------------------------------------------

static func outcome_text(entry: Dictionary) -> String:
	return "Held" if str(entry.get("outcome", "")) == "defender" else "Infected"


## "Raid #12", with " · live" for a live raid.
static func raid_text(entry: Dictionary) -> String:
	var text: String = "Raid #%d" % (int(entry.get("raid_index", 0)) + 1)
	if bool(entry.get("live", false)):
		text += " · live"
	return text


## "18 Rhinovirus · 4 Staphylococcus", biggest group first.
static func army_text(army: Variant, cfg: GameConfig) -> String:
	if not (army is Dictionary) or (army as Dictionary).is_empty():
		return "No army"
	var types: Array[String] = []
	for k: Variant in (army as Dictionary).keys():
		types.append(str(k))
	types.sort_custom(func(a: String, b: String) -> bool:
		var ca: int = int((army as Dictionary)[a])
		var cb: int = int((army as Dictionary)[b])
		return ca > cb if ca != cb else a < b
	)
	var parts: Array[String] = []
	for t: String in types:
		var def: PathogenDef = cfg.pathogens.get(t) as PathogenDef
		var display: String = def.display_name if def != null and not def.display_name.is_empty() else t
		parts.append("%d %s" % [int((army as Dictionary)[t]), display])
	return " · ".join(parts)


## "-80 ATP · +12 Amino Acids"; "Nothing lost" when both are zero.
static func result_text(entry: Dictionary) -> String:
	var parts: Array[String] = []
	if int(entry.get("atp_lost", 0)) > 0:
		parts.append("-%d ATP" % int(entry.get("atp_lost", 0)))
	if int(entry.get("amino_gained", 0)) > 0:
		parts.append("+%d Amino Acids" % int(entry.get("amino_gained", 0)))
	return " · ".join(parts) if not parts.is_empty() else "Nothing lost"


## "Learned Rhinovirus/wild → level 2". Empty when the base learned nothing.
static func learning_text(changes: Variant, cfg: GameConfig) -> String:
	if not (changes is Array):
		return ""
	var parts: Array[String] = []
	for c_val: Variant in changes:
		if not (c_val is Dictionary):
			continue
		var c: Dictionary = c_val
		if str(c.get("reason", "")) != "learned":
			continue
		var key: String = str(c.get("strain_key", ""))
		var type_id: String = key.get_slice("/", 0)
		var def: PathogenDef = cfg.pathogens.get(type_id) as PathogenDef
		var display: String = def.display_name if def != null and not def.display_name.is_empty() else type_id
		parts.append("%s/%s → level %d" % [display, key.get_slice("/", 1), int(c.get("to", 0))])
	return "Learned " + ", ".join(parts) if not parts.is_empty() else ""


## "B-Cell pool: generation 3". Only the structure pools that bred; empty when none did.
static func evolution_text(evolution: Variant, cfg: GameConfig) -> String:
	if not (evolution is Array):
		return ""
	var parts: Array[String] = []
	for e_val: Variant in evolution:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		var type_id: String = str(e.get("type_id", ""))
		if not bool(e.get("bred", false)) or not cfg.structures.has(type_id):
			continue
		parts.append("%s pool: generation %d" % [CoevolutionPanel.type_name(type_id, cfg), int(e.get("generation", 0))])
	return " · ".join(parts)
