class_name HudSpawn
extends Control

signal launch_requested
signal back_requested
signal deploy_type_selected(type_id: String)
signal recall_tool_selected(on: bool)

const CARD_SCENE: PackedScene = preload("res://src/ui/hud_spawn_card.tscn")

var session: Session = null

var top_bar: PanelContainer = null
var atp_icon: Control = null
var atp_label: Label = null
var btn_back: Button = null
var title_label: Label = null
var btn_launch: Button = null

var bottom_tray: PanelContainer = null
var scroll_container: ScrollContainer = null
var cards_container: HBoxContainer = null
var cards: Array[HudSpawnCard] = []

var selected_type_id: String = ""
var recall_active: bool = false
var _atp_tween: Tween = null

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_nodes() -> void:
	if top_bar != null:
		return

	top_bar = get_node_or_null("TopBar") as PanelContainer
	atp_icon = get_node_or_null("TopBar/MarginContainer/HBoxContainer/LeftBox/AtpIcon") as Control
	atp_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/LeftBox/AtpLabel") as Label
	btn_back = get_node_or_null("TopBar/MarginContainer/HBoxContainer/LeftBox/BtnBack") as Button
	title_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/TitleLabel") as Label
	btn_launch = get_node_or_null("TopBar/MarginContainer/HBoxContainer/BtnLaunch") as Button

	bottom_tray = get_node_or_null("BottomTray") as PanelContainer
	scroll_container = get_node_or_null("BottomTray/MarginContainer/ScrollContainer") as ScrollContainer
	cards_container = get_node_or_null("BottomTray/MarginContainer/ScrollContainer/CardsContainer") as HBoxContainer

	if top_bar != null:
		_wire_static_nodes()
		return

	# Programmatic node creation fallback (for unit tests creating HudSpawn.new())
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(0.0, 64.0)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 64.0
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_bar)

	var top_margin := MarginContainer.new()
	top_margin.name = "MarginContainer"
	top_margin.add_theme_constant_override("margin_left", 16)
	top_margin.add_theme_constant_override("margin_right", 16)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_bottom", 8)
	top_bar.add_child(top_margin)

	var top_hbox := HBoxContainer.new()
	top_hbox.name = "HBoxContainer"
	top_hbox.add_theme_constant_override("separation", 16)
	top_margin.add_child(top_hbox)

	var left_box := HBoxContainer.new()
	left_box.name = "LeftBox"
	left_box.alignment = BoxContainer.ALIGNMENT_CENTER
	left_box.add_theme_constant_override("separation", 12)
	top_hbox.add_child(left_box)

	atp_icon = Control.new()
	atp_icon.name = "AtpIcon"
	atp_icon.custom_minimum_size = Vector2(24.0, 24.0)
	left_box.add_child(atp_icon)

	atp_label = Label.new()
	atp_label.name = "AtpLabel"
	atp_label.text = "ATP 1000"
	atp_label.theme_type_variation = "Large"
	atp_label.add_theme_font_size_override("font_size", 28)
	atp_label.add_theme_color_override("font_color", Color("#f5e6e8"))
	left_box.add_child(atp_label)

	btn_back = Button.new()
	btn_back.name = "BtnBack"
	btn_back.text = "◀ Back to base"
	btn_back.custom_minimum_size = Vector2(140.0, 48.0)
	btn_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left_box.add_child(btn_back)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "INCUBATION: Build your army"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("#f5e6e8"))
	top_hbox.add_child(title_label)

	btn_launch = Button.new()
	btn_launch.name = "BtnLaunch"
	btn_launch.text = "Launch Attack"
	btn_launch.custom_minimum_size = Vector2(150.0, 48.0)
	btn_launch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_hbox.add_child(btn_launch)

	bottom_tray = PanelContainer.new()
	bottom_tray.name = "BottomTray"
	bottom_tray.custom_minimum_size = Vector2(0.0, 160.0)
	bottom_tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_tray.offset_top = -160.0
	bottom_tray.offset_bottom = 0.0
	bottom_tray.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bottom_tray)

	var bot_margin := MarginContainer.new()
	bot_margin.name = "MarginContainer"
	bot_margin.add_theme_constant_override("margin_left", 16)
	bot_margin.add_theme_constant_override("margin_right", 16)
	bot_margin.add_theme_constant_override("margin_top", 10)
	bot_margin.add_theme_constant_override("margin_bottom", 10)
	bottom_tray.add_child(bot_margin)

	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.custom_minimum_size = Vector2(0.0, 140.0)
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot_margin.add_child(scroll_container)

	cards_container = HBoxContainer.new()
	cards_container.name = "CardsContainer"
	cards_container.add_theme_constant_override("separation", 12)
	cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll_container.add_child(cards_container)

	_wire_static_nodes()

func _wire_static_nodes() -> void:
	if atp_icon != null and not atp_icon.draw.is_connected(_on_atp_icon_draw):
		atp_icon.draw.connect(_on_atp_icon_draw)
	if btn_back != null and not btn_back.pressed.is_connected(_on_back_pressed):
		btn_back.pressed.connect(_on_back_pressed)
	if btn_launch != null and not btn_launch.pressed.is_connected(_on_launch_pressed):
		btn_launch.pressed.connect(_on_launch_pressed)

func _ready() -> void:
	_ensure_nodes()

func setup(p_session: Session) -> void:
	_ensure_nodes()

	if session != null and session.wallet != null and session.wallet.changed.is_connected(_on_wallet_changed):
		session.wallet.changed.disconnect(_on_wallet_changed)
	if session != null and session.army != null and session.army.changed.is_connected(_on_army_changed):
		session.army.changed.disconnect(_on_army_changed)

	session = p_session

	if session != null and session.wallet != null:
		session.wallet.changed.connect(_on_wallet_changed)
		_update_atp_label(session.wallet.get_amount("atp"), false)

	if session != null and session.army != null:
		session.army.changed.connect(_on_army_changed)

	_populate_tray()
	_update_army_ui()

func _populate_tray() -> void:
	if cards_container == null or session == null or session.config == null:
		return

	for c: Node in cards_container.get_children():
		c.queue_free()
	cards.clear()

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

	for tid: String in p_ids:
		var p_def: PathogenDef = session.config.pathogens.get(tid)
		if p_def == null:
			continue
		var card: HudSpawnCard = (CARD_SCENE.instantiate() as HudSpawnCard) if CARD_SCENE != null else HudSpawnCard.new()
		cards_container.add_child(card)
		card.setup_pathogen(p_def)
		card.pressed.connect(func(): _on_card_pressed(card))
		card.buy_requested.connect(_on_card_buy_requested)
		card.unbuy_requested.connect(_on_card_unbuy_requested)
		cards.append(card)

	var recall_card: HudSpawnCard = (CARD_SCENE.instantiate() as HudSpawnCard) if CARD_SCENE != null else HudSpawnCard.new()
	cards_container.add_child(recall_card)
	recall_card.setup_recall()
	recall_card.pressed.connect(func(): _on_card_pressed(recall_card))
	cards.append(recall_card)

func _update_army_ui() -> void:
	var total_army: int = session.army.total_count() if (session != null and session.army != null) else 0

	if btn_launch != null:
		btn_launch.disabled = (total_army == 0)
		btn_launch.tooltip_text = "Buy at least one pathogen" if (total_army == 0) else ""

	var wallet_atp: int = session.wallet.get_amount("atp") if (session != null and session.wallet != null) else 0

	for c: HudSpawnCard in cards:
		if c.is_recall:
			continue
		var res_cnt: int = session.army.reserve_count(c.type_id) if (session != null and session.army != null) else 0
		var dep_cnt: int = session.army.deployed_count(c.type_id) if (session != null and session.army != null) else 0
		c.update_counts(res_cnt, dep_cnt)
		c.update_affordability(wallet_atp)

func _on_card_buy_requested(type_id: String) -> void:
	if session != null and session.army != null and session.wallet != null:
		session.army.buy(type_id, session.wallet)

func _on_card_unbuy_requested(type_id: String) -> void:
	if session != null and session.army != null and session.wallet != null:
		session.army.unbuy(type_id, session.wallet)

func _on_card_pressed(card: HudSpawnCard) -> void:
	if card.is_recall:
		_toggle_recall(card)
		return

	selected_type_id = card.type_id
	recall_active = false

	for c: HudSpawnCard in cards:
		if c.is_recall:
			c.set_selected(false)
		else:
			c.set_selected(c.type_id == selected_type_id)

	recall_tool_selected.emit(false)
	deploy_type_selected.emit(selected_type_id)

func _toggle_recall(card: HudSpawnCard) -> void:
	recall_active = not recall_active
	selected_type_id = ""

	for c: HudSpawnCard in cards:
		if c.is_recall:
			c.set_selected(recall_active)
		else:
			c.set_selected(false)

	deploy_type_selected.emit("")
	recall_tool_selected.emit(recall_active)

func _on_back_pressed() -> void:
	if session != null and session.army != null and session.wallet != null:
		session.army.refund_all(session.wallet)
	back_requested.emit()

func _on_launch_pressed() -> void:
	if session != null and session.army != null and session.army.total_count() > 0:
		launch_requested.emit()

func _on_wallet_changed(currency: String, new_amount: int) -> void:
	if currency == "atp":
		_update_atp_label(new_amount, true)
	_update_army_ui()

func _on_army_changed() -> void:
	_update_army_ui()

func _update_atp_label(amount: int, pulse: bool) -> void:
	if atp_label == null:
		return
	atp_label.text = "ATP %d" % amount
	atp_label.pivot_offset = atp_label.size * 0.5
	if pulse:
		if _atp_tween != null and _atp_tween.is_valid():
			_atp_tween.kill()
		atp_label.scale = Vector2.ONE
		_atp_tween = create_tween()
		if _atp_tween != null:
			_atp_tween.tween_property(atp_label, "scale", Vector2(1.15, 1.15), 0.075).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_atp_tween.tween_property(atp_label, "scale", Vector2.ONE, 0.075).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _on_atp_icon_draw() -> void:
	if atp_icon == null:
		return
	var w: float = atp_icon.size.x
	var h: float = atp_icon.size.y
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(w * 0.58, h * 0.05),
		Vector2(w * 0.18, h * 0.52),
		Vector2(w * 0.48, h * 0.52),
		Vector2(w * 0.32, h * 0.95),
		Vector2(w * 0.82, h * 0.42),
		Vector2(w * 0.52, h * 0.42),
		Vector2(w * 0.68, h * 0.05),
	])
	atp_icon.draw_colored_polygon(pts, Color("#f1c40f"))

func get_card(type_id: String) -> HudSpawnCard:
	for c: HudSpawnCard in cards:
		if not c.is_recall and c.type_id == type_id:
			return c
	return null

func get_recall_card() -> HudSpawnCard:
	for c: HudSpawnCard in cards:
		if c.is_recall:
			return c
	return null
