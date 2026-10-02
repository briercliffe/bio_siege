class_name OpponentScreen
extends Control

## Living Base opponent picker (#161): one tappable card per AI base with its tier, a mini island,
## the loot on offer, what the base remembers and how often it was raided. Memory is never hidden.
## Tapping a card aims the session at that base and moves on to Incubation.

signal back_requested
signal opponent_chosen(opponent_id: String)

const CARD_SIZE: Vector2 = Vector2(312.0, 400.0)
const CARD_GAP: int = 24
const CARD_RADIUS: int = 28
const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const TITLE_TEXT: String = "Choose a target"
const SUBTITLE_TEXT: String = "AI bases remember what you raid them with and breed against it."
const MEMORY_EMPTY_TEXT: String = "Remembers nothing yet"
const PLAYERS_TAB: int = 0
const AI_TAB: int = 1
const NEXT_COOLDOWN_MS: int = 2000
const NO_PLAYERS_TEXT: String = "No players in range"
const LOADING_TEXT: String = "Looking for a player..."
const ACTION_SIZE: Vector2 = Vector2(180.0, 56.0)

var session: Session = null
var fsm: GameStateMachine = null

var background: AmbientBackground = null
var btn_back: IconButton = null
var title_label: Label = null
var subtitle_label: Label = null
var cards_row: HBoxContainer = null
## Opponent id -> OpponentCard.
var cards: Dictionary = {}

## Online mode: a Players tab (one matchmade player from find_opponent) next to the AI tab.
var tabs: SegmentedTabs = null
var players_box: VBoxContainer = null
var player_card: PanelContainer = null
var player_trophies_label: Label = null
var player_loot_label: Label = null
var player_memory_box: VBoxContainer = null
var player_thumb: SavedScreen.BaseThumb = null
var message_label: Label = null
var btn_raid: PillButton = null
var btn_next: PillButton = null
var current_defender_id: String = ""
## Tests set this to fake the clock; -1 reads the system clock.
var now_ms_override: int = -1
var _last_next_ms: int = -1000000
var _holder: CenterContainer = null


## One tappable opponent. The whole card is the button.
class OpponentCard:
	extends Button

	var opponent_id: String = ""
	var tier_label: Label = null
	var loot_label: Label = null
	var raided_label: Label = null
	var memory_box: VBoxContainer = null
	var thumb: SavedScreen.BaseThumb = null

	func _init(p_id: String) -> void:
		opponent_id = p_id
		name = "Card_%s" % p_id
		custom_minimum_size = CARD_SIZE
		focus_mode = Control.FOCUS_NONE
		var pal: Dictionary = UiPalette.for_theme(false)
		var normal: StyleBoxFlat = KitDraw.make_box(pal["panel"] as Color, float(CARD_RADIUS), 2, pal["panel_border"] as Color,
				pal["panel_shadow"] as Color, 24, Vector2(0.0, 8.0))
		var pressed_box: StyleBoxFlat = KitDraw.make_box((pal["chip"] as Color), float(CARD_RADIUS), 2, pal["panel_border"] as Color)
		for state: String in ["normal", "hover", "focus", "disabled"]:
			add_theme_stylebox_override(state, normal)
		add_theme_stylebox_override("pressed", pressed_box)
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side: String in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 18)
		add_child(margin)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 8)
		margin.add_child(box)
		tier_label = _label(box, 22, 800, UiPalette.color(false, "ink"))
		tier_label.name = "TierLabel"
		loot_label = _label(box, 16, 700, UiPalette.color(false, "ink"))
		loot_label.name = "LootLabel"
		raided_label = _label(box, 14, 400, UiPalette.color(false, "muted"))
		raided_label.name = "RaidedLabel"
		var memory_title: Label = _label(box, 12, 700, UiPalette.color(false, "muted"))
		memory_title.text = "MEMORY"
		memory_box = VBoxContainer.new()
		memory_box.name = "MemoryBox"
		memory_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		memory_box.add_theme_constant_override("separation", 4)
		box.add_child(memory_box)

	func _label(parent: Control, px: int, weight: int, color: Color) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiFonts.style_label(l, px, weight, color)
		parent.add_child(l)
		return l


func _init() -> void:
	name = "OpponentScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func setup(p_session: Session, p_fsm: GameStateMachine) -> void:
	session = p_session
	fsm = p_fsm
	_populate()
	if session != null and session.living_flow != null and session.living_flow.is_online():
		_setup_online()


func is_online() -> bool:
	return session != null and session.living_flow != null and session.living_flow.is_online()


## Adds the Players / AI tabs. Players is the default and loads one opponent from the server.
func _setup_online() -> void:
	if tabs == null:
		var column: VBoxContainer = get_node("Column") as VBoxContainer
		var tab_row := CenterContainer.new()
		tab_row.name = "TabRow"
		tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(tab_row)
		column.move_child(tab_row, 2)
		tabs = SegmentedTabs.new(["Players", "AI"] as Array[String])
		tabs.name = "Tabs"
		tabs.tab_changed.connect(_on_tab_changed)
		tab_row.add_child(tabs)
		message_label = Label.new()
		message_label.name = "MessageLabel"
		message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiFonts.style_label(message_label, 16, 700, UiPalette.color(false, "danger"))
		column.add_child(message_label)
		column.move_child(message_label, 3)
		_build_players_box(column)
	tabs.select(PLAYERS_TAB)
	_on_tab_changed(PLAYERS_TAB)
	_load_player()


func _build_players_box(column: VBoxContainer) -> void:
	players_box = VBoxContainer.new()
	players_box.name = "PlayersBox"
	players_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	players_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_box.alignment = BoxContainer.ALIGNMENT_CENTER
	players_box.add_theme_constant_override("separation", 14)
	column.add_child(players_box)
	player_card = PanelContainer.new()
	player_card.name = "PlayerCard"
	player_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pal: Dictionary = UiPalette.for_theme(false)
	player_card.add_theme_stylebox_override("panel", KitDraw.make_box(pal["panel"] as Color, float(CARD_RADIUS), 2,
			pal["panel_border"] as Color, pal["panel_shadow"] as Color, 24, Vector2(0.0, 8.0)))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	player_card.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "PlayerBox"
	box.custom_minimum_size = Vector2(CARD_SIZE.x, 0.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	player_trophies_label = _plain_label(box, 22, 800, UiPalette.color(false, "ink"))
	player_trophies_label.name = "TrophiesLabel"
	player_loot_label = _plain_label(box, 16, 700, UiPalette.color(false, "ink"))
	player_loot_label.name = "LootLabel"
	var memory_title: Label = _plain_label(box, 12, 700, UiPalette.color(false, "muted"))
	memory_title.text = "MEMORY"
	player_memory_box = VBoxContainer.new()
	player_memory_box.name = "MemoryBox"
	player_memory_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_memory_box.add_theme_constant_override("separation", 4)
	box.add_child(player_memory_box)
	players_box.add_child(player_card)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", 16)
	btn_raid = PillButton.new("Raid", PillButton.Variant.PRIMARY)
	btn_raid.name = "BtnRaid"
	btn_raid.custom_minimum_size = ACTION_SIZE
	btn_raid.pressed.connect(_on_raid_pressed)
	actions.add_child(btn_raid)
	btn_next = PillButton.new("Next", PillButton.Variant.SECONDARY)
	btn_next.name = "BtnNext"
	btn_next.custom_minimum_size = ACTION_SIZE
	btn_next.pressed.connect(_on_next_pressed)
	actions.add_child(btn_next)
	players_box.add_child(actions)
	player_card.visible = false
	btn_raid.disabled = true


func _plain_label(parent: Control, px: int, weight: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiFonts.style_label(l, px, weight, color)
	parent.add_child(l)
	return l


func _on_tab_changed(index: int) -> void:
	var players: bool = index == PLAYERS_TAB
	players_box.visible = players
	_holder.visible = not players


func _now_ms() -> int:
	return now_ms_override if now_ms_override >= 0 else Time.get_ticks_msec()


## Asks the server for one player in the trophy band. {"ai": true} switches to the AI tab.
func _load_player() -> void:
	message_label.text = ""
	player_card.visible = false
	btn_raid.disabled = true
	current_defender_id = ""
	player_loot_label.text = LOADING_TEXT
	var res: Dictionary = await session.living_flow.backend().find_opponent()
	if not bool(res.get("ok", false)):
		message_label.text = NetCopy.error_text(str(res.get("error", "network_error")))
		return
	if bool(res.get("ai", false)):
		message_label.text = NO_PLAYERS_TEXT
		tabs.select(AI_TAB, true)
		return
	show_player(res)


## Renders a find_opponent result: island preview, trophies, loot estimate and the memory, always visible.
func show_player(res: Dictionary) -> void:
	var cfg: GameConfig = session.config
	var preview: Dictionary = res.get("preview", {}) as Dictionary
	current_defender_id = str(res.get("defender_id", ""))
	player_trophies_label.text = "Trophies: %d" % int(res.get("trophies", preview.get("trophies", 0)))
	player_loot_label.text = loot_text(cfg, preview)
	if player_thumb != null:
		player_thumb.get_parent().remove_child(player_thumb)
		player_thumb.queue_free()
	player_thumb = SavedScreen.BaseThumb.new("player|%s|%d" % [current_defender_id, int(preview.get("updated_unix", 0))])
	var box: VBoxContainer = player_memory_box.get_parent() as VBoxContainer
	box.add_child(player_thumb)
	box.move_child(player_thumb, 0)
	var grid := GridModel.new(cfg)
	grid.load_layout(preview.get("layout", []) as Array, LivingBaseProfile.unlimited_wallet())
	player_thumb.render(grid, cfg)
	for c: Node in player_memory_box.get_children():
		player_memory_box.remove_child(c)
		c.queue_free()
	_fill_memory(player_memory_box, ImmuneMemory.from_dict(preview.get("memory", {}) as Dictionary, cfg), cfg)
	player_card.visible = true
	btn_raid.disabled = current_defender_id.is_empty()


## One find_opponent per two seconds: a faster tap does nothing.
func _on_next_pressed() -> void:
	var now: int = _now_ms()
	if now - _last_next_ms < NEXT_COOLDOWN_MS:
		return
	_last_next_ms = now
	_load_player()


func _on_raid_pressed() -> void:
	if current_defender_id.is_empty() or session == null or session.living_flow == null:
		return
	btn_raid.disabled = true
	var id: String = current_defender_id
	var res: Dictionary = await session.living_flow.begin_pvp_raid(id)
	if not bool(res.get("ok", false)):
		message_label.text = NetCopy.error_text(str(res.get("error", "network_error")))
		btn_raid.disabled = false
		return
	opponent_chosen.emit(id)
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.INCUBATION)


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

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = TITLE_TEXT
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(title_label, 40, 800, UiPalette.color(false, "ink"))
	column.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.text = SUBTITLE_TEXT
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(subtitle_label, 16, 400, UiPalette.color(false, "muted"))
	column.add_child(subtitle_label)

	_holder = CenterContainer.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_holder)
	cards_row = HBoxContainer.new()
	cards_row.name = "Cards"
	cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_row.add_theme_constant_override("separation", CARD_GAP)
	_holder.add_child(cards_row)


func _populate() -> void:
	for c: Node in cards_row.get_children():
		cards_row.remove_child(c)
		c.queue_free()
	cards.clear()
	if session == null or session.profile == null or session.config == null:
		return
	for opp: Dictionary in session.profile.opponents:
		var card: OpponentCard = _make_card(opp)
		cards_row.add_child(card)
		cards[str(opp["id"])] = card


func _make_card(opp: Dictionary) -> OpponentCard:
	var cfg: GameConfig = session.config
	var id: String = str(opp["id"])
	var card := OpponentCard.new(id)
	card.tier_label.text = tier_name(cfg, str(opp.get("tier", "")))
	card.loot_label.text = loot_text(cfg, opp)
	card.raided_label.text = raided_text(int(opp.get("raids", 0)))
	var box: VBoxContainer = card.memory_box.get_parent() as VBoxContainer
	card.thumb = SavedScreen.BaseThumb.new("opp|%s|%d" % [id, int(opp.get("seed", 0))])
	box.add_child(card.thumb)
	box.move_child(card.thumb, 1)
	var grid := GridModel.new(cfg)
	grid.load_layout(opp.get("layout", []), LivingBaseProfile.unlimited_wallet())
	card.thumb.render(grid, cfg)
	_fill_memory(card.memory_box, ImmuneMemory.from_dict(opp.get("memory", {}), cfg), cfg)
	card.pressed.connect(choose.bind(id))
	return card


func _fill_memory(into: VBoxContainer, memory: ImmuneMemory, cfg: GameConfig) -> void:
	MemoryPanel.fill_compact(into, memory, cfg, MEMORY_EMPTY_TEXT, UiPalette.color(false, "ink"), UiPalette.color(false, "muted"))


## Aims the session at the opponent and goes to Incubation.
func choose(opponent_id: String) -> void:
	if session == null or session.living_flow == null:
		return
	if not session.living_flow.begin_raid(opponent_id):
		return
	opponent_chosen.emit(opponent_id)
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.INCUBATION)


static func tier_name(cfg: GameConfig, tier_id: String) -> String:
	for t: Dictionary in cfg.ai_tiers:
		if str(t["id"]) == tier_id:
			return str(t["display_name"])
	return tier_id


## "Loot: up to 75 ATP": the share of the base's stored ATP a win would take.
static func loot_text(cfg: GameConfig, opp: Dictionary) -> String:
	return "Loot: up to %d ATP" % (int(opp.get("stored_atp", 0)) * cfg.loot_atp_pct / 100)


static func raided_text(raids: int) -> String:
	return "Raided %d time%s" % [raids, "" if raids == 1 else "s"]
