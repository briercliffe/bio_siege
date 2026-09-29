class_name HudBuild
extends Control

signal finalize_requested

const CARD_SCENE: PackedScene = preload("res://src/ui/hud_card.tscn")
const CONFIRMATION_SCENE: PackedScene = preload("res://src/ui/confirmation_popup.tscn")

var session: Session = null
var controller: BuildController = null

var top_bar: PanelContainer = null
var atp_icon: Control = null
var atp_label: Label = null
var stats_label: Label = null
var title_label: Label = null
var btn_finalize: Button = null

var bottom_tray: PanelContainer = null
var scroll_container: ScrollContainer = null
var cards_container: HBoxContainer = null
var cards: Array[HudCard] = []

var confirmation_dialog: ConfirmationPopup = null
var _atp_tween: Tween = null

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_nodes() -> void:
	if top_bar != null:
		return

	top_bar = get_node_or_null("TopBar") as PanelContainer
	atp_icon = get_node_or_null("TopBar/MarginContainer/HBoxContainer/LeftBox/Row1/AtpIcon") as Control
	atp_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/LeftBox/Row1/AtpLabel") as Label
	stats_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/LeftBox/StatsLabel") as Label
	title_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/TitleLabel") as Label
	btn_finalize = get_node_or_null("TopBar/MarginContainer/HBoxContainer/BtnFinalize") as Button

	bottom_tray = get_node_or_null("BottomTray") as PanelContainer
	scroll_container = get_node_or_null("BottomTray/MarginContainer/ScrollContainer") as ScrollContainer
	cards_container = get_node_or_null("BottomTray/MarginContainer/ScrollContainer/CardsContainer") as HBoxContainer

	confirmation_dialog = get_node_or_null("ConfirmationDialog") as ConfirmationPopup

	if top_bar != null:
		_wire_static_nodes()
		return

	# Programmatic node creation fallback (for tests creating HudBuild.new())
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(0.0, 64.0)
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
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
	top_margin.add_child(top_hbox)

	var left_box := VBoxContainer.new()
	left_box.name = "LeftBox"
	left_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_child(left_box)

	var row1 := HBoxContainer.new()
	row1.name = "Row1"
	row1.add_theme_constant_override("separation", 6)
	left_box.add_child(row1)

	atp_icon = Control.new()
	atp_icon.name = "AtpIcon"
	atp_icon.custom_minimum_size = Vector2(24.0, 24.0)
	row1.add_child(atp_icon)

	atp_label = Label.new()
	atp_label.name = "AtpLabel"
	atp_label.text = "ATP 1000"
	atp_label.theme_type_variation = "Large"
	atp_label.add_theme_font_size_override("font_size", 28)
	atp_label.add_theme_color_override("font_color", Color("#12304f"))
	row1.add_child(atp_label)

	stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.text = "Structures: 0 · Walls: 0"
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color("#576574"))
	left_box.add_child(stats_label)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "SYNTHESIS: Build your immune system"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("#12304f"))
	top_hbox.add_child(title_label)

	btn_finalize = Button.new()
	btn_finalize.name = "BtnFinalize"
	btn_finalize.text = "Finalize Base"
	btn_finalize.custom_minimum_size = Vector2(140.0, 48.0)
	btn_finalize.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_hbox.add_child(btn_finalize)

	bottom_tray = PanelContainer.new()
	bottom_tray.name = "BottomTray"
	bottom_tray.custom_minimum_size = Vector2(0.0, 140.0)
	bottom_tray.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_tray.offset_top = -140.0
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
	scroll_container.custom_minimum_size = Vector2(0.0, 120.0)
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

	confirmation_dialog = CONFIRMATION_SCENE.instantiate() as ConfirmationPopup
	confirmation_dialog.name = "ConfirmationDialog"
	add_child(confirmation_dialog)

	_wire_static_nodes()

func _wire_static_nodes() -> void:
	if atp_icon != null and not atp_icon.draw.is_connected(_on_atp_icon_draw):
		atp_icon.draw.connect(_on_atp_icon_draw)
	if btn_finalize != null and not btn_finalize.pressed.is_connected(_on_finalize_button_pressed):
		btn_finalize.pressed.connect(_on_finalize_button_pressed)
	if confirmation_dialog != null and not confirmation_dialog.confirmed.is_connected(_on_confirmation_dialog_confirmed):
		confirmation_dialog.confirmed.connect(_on_confirmation_dialog_confirmed)

func _ready() -> void:
	_ensure_nodes()
	_update_stats_label()

func setup(p_session: Session, p_controller: BuildController) -> void:
	_ensure_nodes()

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
		_update_atp_label(session.wallet.get_amount("atp"), false)

	if session != null and session.grid != null:
		session.grid.structure_placed.connect(_on_structure_placed)
		session.grid.structure_removed.connect(_on_structure_removed)
		_update_stats_label()

	if controller != null:
		controller.tool_changed.connect(_on_tool_changed)

	_populate_tray()
	_update_card_affordability()

func _populate_tray() -> void:
	for c in cards:
		c.queue_free()
	cards.clear()

	if session == null or session.config == null:
		return

	var buildable_ids: Array[String] = session.config.buildable_structure_ids()
	for id in buildable_ids:
		var sdef: StructureDef = session.config.structures.get(id)
		if sdef == null:
			continue
		var card: HudCard = null
		if CARD_SCENE != null:
			card = CARD_SCENE.instantiate() as HudCard
		if card == null:
			card = HudCard.new()
		card.setup_structure(sdef)
		card.pressed.connect(func() -> void:
			if controller != null:
				controller.select_tool(card.tool_id)
		)
		cards_container.add_child(card)
		cards.append(card)

	var sell_card: HudCard = null
	if CARD_SCENE != null:
		sell_card = CARD_SCENE.instantiate() as HudCard
	if sell_card == null:
		sell_card = HudCard.new()
	sell_card.setup_sell()
	sell_card.pressed.connect(func() -> void:
		if controller != null:
			controller.select_tool("sell")
	)
	cards_container.add_child(sell_card)
	cards.append(sell_card)

func get_cards() -> Array[HudCard]:
	return cards

func get_card(id: String) -> HudCard:
	for c in cards:
		if c.tool_id == id:
			return c
	return null

func get_cheapest_pathogen_cost() -> int:
	if session == null or session.config == null or session.config.pathogens.is_empty():
		return 0
	var cheapest: int = -1
	for pdef: PathogenDef in session.config.pathogens.values():
		var c: int = int(pdef.cost.get("atp", 0))
		if cheapest < 0 or c < cheapest:
			cheapest = c
	return maxi(cheapest, 0)

func finalize_base() -> void:
	var cheapest: int = get_cheapest_pathogen_cost()
	var current_atp: int = session.wallet.get_amount("atp") if (session != null and session.wallet != null) else 0
	if current_atp < cheapest:
		var msg: String = "You have %d ATP left, which is not enough for any pathogen (cheapest costs %d). Finalize anyway?" % [current_atp, cheapest]
		if confirmation_dialog != null:
			confirmation_dialog.dialog_text = msg
			confirmation_dialog.popup_centered()
	else:
		finalize_requested.emit()

func _on_finalize_button_pressed() -> void:
	finalize_base()

func _on_confirmation_dialog_confirmed() -> void:
	finalize_requested.emit()

func _on_tool_changed(tool_id: String) -> void:
	for c in cards:
		c.set_selected(c.tool_id == tool_id)

func _on_wallet_changed(currency: String, new_amount: int) -> void:
	if currency == "atp":
		_update_atp_label(new_amount, true)
	_update_card_affordability()

func _update_card_affordability() -> void:
	if session == null or session.wallet == null:
		return
	var wallet_atp: int = session.wallet.get_amount("atp")
	for c in cards:
		c.update_affordability(wallet_atp)

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

func _on_structure_placed(_s: GridModel.PlacedStructure) -> void:
	_update_stats_label()

func _on_structure_removed(_s: GridModel.PlacedStructure) -> void:
	_update_stats_label()

func _update_stats_label() -> void:
	if stats_label == null:
		return
	var walls: int = 0
	var structures: int = 0
	if session != null and session.grid != null and session.config != null:
		for s: GridModel.PlacedStructure in session.grid.structures():
			if s.type_id == "nucleus":
				continue
			var sdef: StructureDef = session.config.structures.get(s.type_id)
			if sdef != null:
				if sdef.has_tag("core"):
					continue
				if sdef.has_tag("wall"):
					walls += 1
				else:
					structures += 1
			else:
				structures += 1
	stats_label.text = "Structures: %d · Walls: %d" % [structures, walls]

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
