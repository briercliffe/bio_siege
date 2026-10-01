class_name UpgradesScreen
extends Control

## Living Base Upgrades screen (#168): Amino Acids buy breadth upgrades, never flat HP or damage. One row per
## upgrade with its level, what it does now, and a Buy button showing the next cost. Buying spends from the
## wallet, saves the profile and refreshes.

signal back_requested
signal upgrade_bought(upgrade_id: String)

const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const ROW_HEIGHT: float = 76.0
const BUY_SIZE: Vector2 = Vector2(180.0, 52.0)
const COLUMN_WIDTH: float = 760.0
const TITLE_TEXT: String = "Upgrades"
const SUBTITLE_TEXT: String = "Amino Acids buy breadth, not raw power."

var session: Session = null
var fsm: GameStateMachine = null

var background: AmbientBackground = null
var btn_back: IconButton = null
var title_label: Label = null
var amino_label: Label = null
var rows_box: VBoxContainer = null
## Upgrade id -> {"row", "name", "level", "effect", "buy"}.
var rows: Dictionary = {}


func _init() -> void:
	name = "UpgradesScreen"
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

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = TITLE_TEXT
	UiFonts.style_label(title_label, 40, 800, UiPalette.color(false, "ink"))
	column.add_child(title_label)
	var sub := Label.new()
	sub.text = SUBTITLE_TEXT
	UiFonts.style_label(sub, 16, 400, UiPalette.color(false, "muted"))
	column.add_child(sub)
	amino_label = Label.new()
	amino_label.name = "AminoLabel"
	UiFonts.style_label(amino_label, 18, 800, UiPalette.color(false, "ink"))
	column.add_child(amino_label)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows_box.add_theme_constant_override("separation", 12)
	column.add_child(rows_box)


func _populate() -> void:
	for c: Node in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	rows.clear()
	if session == null or session.config == null or session.profile == null:
		return
	for id: String in GameConfig.KNOWN_UPGRADES:
		if session.config.upgrade_defs.has(id):
			_add_row(id)
	refresh()


func _add_row(id: String) -> void:
	var def: Dictionary = session.config.upgrade_defs[id]
	var panel := FloatingCard.new()
	panel.name = "Row_%s" % id
	panel.custom_minimum_size = Vector2(COLUMN_WIDTH, ROW_HEIGHT)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(texts)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 12)
	texts.add_child(head)
	var name_label := Label.new()
	name_label.text = str(def["display_name"])
	UiFonts.style_label(name_label, 20, 800, UiPalette.color(false, "ink"))
	head.add_child(name_label)
	var level_label := Label.new()
	level_label.name = "LevelLabel"
	UiFonts.style_label(level_label, 14, 700, UiPalette.color(false, "muted"))
	head.add_child(level_label)
	var effect_label := Label.new()
	effect_label.name = "EffectLabel"
	UiFonts.style_label(effect_label, 15, 400, UiPalette.color(false, "muted"))
	texts.add_child(effect_label)
	var buy := PillButton.new("Buy", PillButton.Variant.PRIMARY)
	buy.name = "BtnBuy_%s" % id
	buy.custom_minimum_size = BUY_SIZE
	buy.pressed.connect(_on_buy_pressed.bind(id))
	hbox.add_child(buy)
	rows_box.add_child(panel)
	rows[id] = {"row": panel, "name": name_label, "level": level_label, "effect": effect_label, "buy": buy}


## Re-reads levels, effects, costs and the wallet.
func refresh() -> void:
	if session == null or session.config == null or session.profile == null:
		return
	var cfg: GameConfig = session.config
	var ups: Dictionary = session.profile.upgrades
	amino_label.text = "Amino Acids: %d" % session.wallet.get_amount("amino_acids")
	for id: String in rows.keys():
		var r: Dictionary = rows[id]
		var lv: int = BaseUpgrades.level(ups, id)
		var top: int = BaseUpgrades.max_level(cfg, id)
		(r["level"] as Label).text = "Level %d / %d" % [lv, top]
		(r["effect"] as Label).text = effect_text(cfg, ups, id)
		var buy: PillButton = r["buy"] as PillButton
		var cost: Dictionary = BaseUpgrades.next_cost(cfg, ups, id)
		if cost.is_empty():
			buy.text = "Maxed"
			buy.disabled = true
		else:
			buy.text = "Buy · %s" % cost_text(cost)
			buy.disabled = not session.wallet.can_afford(cost)
		buy.queue_redraw()


func _on_buy_pressed(id: String) -> void:
	if session == null or session.living_flow == null:
		return
	if session.living_flow.buy_upgrade(id):
		upgrade_bought.emit(id)
		refresh()


## What the upgrade does right now, for the current level.
static func effect_text(cfg: GameConfig, upgrades: Dictionary, id: String) -> String:
	match id:
		"memory_slot":
			return "Remembers %d strains" % BaseUpgrades.memory_slots(cfg, upgrades)
		"analysis_speed":
			var faster: int = 100 - BaseUpgrades.analysis_threshold_pct(cfg, upgrades)
			return "Analysis %d%% faster" % faster if faster > 0 else "Analysis at normal speed"
		"memory_retention":
			return "Memory lasts %d raids" % BaseUpgrades.memory_decay_raids(cfg, upgrades)
	return ""


## "150 Amino Acids" (other currencies by their short names).
static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for cur: Variant in cost.keys():
		var label: String = {"amino_acids": "AA", "dna": "DNA", "atp": "ATP"}.get(str(cur), str(cur))
		parts.append("%d %s" % [int(cost[cur]), label])
	return " + ".join(parts)
