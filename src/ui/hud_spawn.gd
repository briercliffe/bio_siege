class_name HudSpawn
extends Control

signal launch_requested
signal back_requested
signal deploy_type_selected(type_id: String)
signal recall_tool_selected(on: bool)
signal predict_mode_selected(on: bool)

const ATP_OVER_BUDGET_COLOR: Color = Color("#e74c3c")
const CARD_SCENE: PackedScene = preload("res://src/ui/hud_spawn_card.tscn")
const IMPORT_DIALOG_SCENE: PackedScene = preload("res://src/ui/import_dialog.tscn")

var session: Session = null

var top_bar: PanelContainer = null
var atp_icon: Control = null
var atp_label: Label = null
var btn_back: Button = null
var title_label: Label = null
var btn_predict: Button = null
var btn_launch: Button = null
var btn_menu: Button = null
var popup_menu: PopupMenu = null
var import_dialog: ImportDialog = null
var last_toast_message: String = ""

var bottom_tray: PanelContainer = null
var scroll_container: ScrollContainer = null
var cards_container: HBoxContainer = null
var cards: Array[HudSpawnCard] = []

var selected_type_id: String = ""
var recall_active: bool = false
var predict_active: bool = false
var _atp_tween: Tween = null
var _atp_base_color: Color = Color.WHITE
var _atp_base_color_captured: bool = false

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
	btn_predict = get_node_or_null("TopBar/MarginContainer/HBoxContainer/BtnPredict") as Button
	btn_launch = get_node_or_null("TopBar/MarginContainer/HBoxContainer/BtnLaunch") as Button
	btn_menu = get_node_or_null("TopBar/MarginContainer/HBoxContainer/BtnMenu") as Button
	popup_menu = get_node_or_null("PopupMenu") as PopupMenu
	import_dialog = get_node_or_null("ImportDialog") as ImportDialog

	bottom_tray = get_node_or_null("BottomTray") as PanelContainer
	scroll_container = get_node_or_null("BottomTray/MarginContainer/ScrollContainer") as ScrollContainer
	cards_container = get_node_or_null("BottomTray/MarginContainer/ScrollContainer/CardsContainer") as HBoxContainer

	if top_bar != null:
		if popup_menu == null:
			popup_menu = PopupMenu.new()
			popup_menu.name = "PopupMenu"
			popup_menu.add_item("Export army", 0)
			popup_menu.add_item("Import army", 1)
			add_child(popup_menu)
		if import_dialog == null:
			import_dialog = IMPORT_DIALOG_SCENE.instantiate() as ImportDialog
			import_dialog.name = "ImportDialog"
			add_child(import_dialog)
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

	btn_predict = Button.new()
	btn_predict.name = "BtnPredict"
	btn_predict.text = "Predict"
	btn_predict.custom_minimum_size = Vector2(90.0, 48.0)
	btn_predict.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_hbox.add_child(btn_predict)

	btn_launch = Button.new()
	btn_launch.name = "BtnLaunch"
	btn_launch.text = "Launch Attack"
	btn_launch.custom_minimum_size = Vector2(150.0, 48.0)
	btn_launch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_hbox.add_child(btn_launch)

	btn_menu = Button.new()
	btn_menu.name = "BtnMenu"
	btn_menu.text = "⋯"
	btn_menu.custom_minimum_size = Vector2(48.0, 48.0)
	btn_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_hbox.add_child(btn_menu)

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

	popup_menu = PopupMenu.new()
	popup_menu.name = "PopupMenu"
	popup_menu.add_item("Export army", 0)
	popup_menu.add_item("Import army", 1)
	add_child(popup_menu)

	import_dialog = ImportDialog.new()
	import_dialog.name = "ImportDialog"
	add_child(import_dialog)

	_wire_static_nodes()

func _wire_static_nodes() -> void:
	if atp_icon != null and not atp_icon.draw.is_connected(_on_atp_icon_draw):
		atp_icon.draw.connect(_on_atp_icon_draw)
	if btn_back != null and not btn_back.pressed.is_connected(_on_back_pressed):
		btn_back.pressed.connect(_on_back_pressed)
	if btn_predict != null and not btn_predict.pressed.is_connected(_on_predict_pressed):
		btn_predict.pressed.connect(_on_predict_pressed)
	if btn_launch != null and not btn_launch.pressed.is_connected(_on_launch_pressed):
		btn_launch.pressed.connect(_on_launch_pressed)
	if btn_menu != null and not btn_menu.pressed.is_connected(_on_btn_menu_pressed):
		btn_menu.pressed.connect(_on_btn_menu_pressed)
	if popup_menu != null and not popup_menu.id_pressed.is_connected(_on_popup_menu_item_selected):
		popup_menu.id_pressed.connect(_on_popup_menu_item_selected)
	if import_dialog != null and not import_dialog.load_requested.is_connected(_on_import_load_requested):
		import_dialog.load_requested.connect(_on_import_load_requested)

func _on_predict_pressed() -> void:
	set_predict_mode(not predict_active)
	if predict_active:
		_show_toast("Tap the structure you think falls first")

func set_predict_mode(active: bool) -> void:
	predict_active = active
	predict_mode_selected.emit(predict_active)

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

	var p_ids: Array[String] = _sorted_pathogen_ids()

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

## Re-reads names, costs and roles after a config hot reload (#27).
## The tray is rebuilt only when pathogens were added, removed or re-ordered by cost.
func refresh_config() -> void:
	_ensure_nodes()
	if session == null or session.config == null or cards_container == null:
		return
	var expected_ids: Array[String] = _sorted_pathogen_ids()
	var current_ids: Array[String] = []
	for c: HudSpawnCard in cards:
		if not c.is_recall:
			current_ids.append(c.type_id)
	if current_ids == expected_ids:
		for c: HudSpawnCard in cards:
			var p_def: PathogenDef = session.config.pathogens.get(c.type_id)
			if not c.is_recall and p_def != null:
				c.setup_pathogen(p_def)
	else:
		_populate_tray()
		if not selected_type_id.is_empty() and not session.config.pathogens.has(selected_type_id):
			selected_type_id = ""
			deploy_type_selected.emit("")
		for c: HudSpawnCard in cards:
			c.set_selected(recall_active if c.is_recall else (not selected_type_id.is_empty() and c.type_id == selected_type_id))
	if session.wallet != null:
		_update_atp_label(session.wallet.get_amount("atp"), false)
	_update_army_ui()

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
		var ok: bool = session.army.buy(type_id, session.wallet)
		if ok and SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("unit_bought", {"type": type_id})

func _on_card_unbuy_requested(type_id: String) -> void:
	if session != null and session.army != null and session.wallet != null:
		var ok: bool = session.army.unbuy(type_id, session.wallet)
		if ok and SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("unit_unbought", {"type": type_id})

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
	if not _atp_base_color_captured:
		_atp_base_color = atp_label.get_theme_color("font_color")
		_atp_base_color_captured = true
	atp_label.add_theme_color_override("font_color", ATP_OVER_BUDGET_COLOR if amount < 0 else _atp_base_color)
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


func _on_btn_menu_pressed() -> void:
	if popup_menu != null:
		var pos: Vector2 = btn_menu.global_position + Vector2(0.0, btn_menu.size.y) if btn_menu != null else Vector2.ZERO
		popup_menu.popup(Rect2i(Vector2i(pos), Vector2i(140, 0)))


func _on_popup_menu_item_selected(id: int) -> void:
	match id:
		0:
			export_army()
		1:
			open_import_dialog()


func open_import_dialog() -> void:
	if import_dialog != null:
		import_dialog.open("Import Army")


func export_army() -> String:
	if session == null or session.army == null:
		return ""
	var army_dict: Dictionary = SnapshotIO.army_to_dict(session.army.deployments)
	var json_str: String = SnapshotIO.to_json(army_dict)
	DisplayServer.clipboard_set(json_str)
	_show_toast("Army copied to clipboard")

	if not DirAccess.dir_exists_absolute("user://armies"):
		DirAccess.make_dir_recursive_absolute("user://armies")
	var unix_time: int = int(Time.get_unix_time_from_system())
	var file_path: String = "user://armies/army_%d.json" % unix_time
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file != null:
		file.store_string(json_str)
		file.close()
	return json_str


func import_army(json_text: String) -> bool:
	if session == null or session.config == null or session.army == null or session.wallet == null:
		return false
	var res: Dictionary = SnapshotIO.parse_army(json_text, session.config)
	if not res.get("ok", false):
		var err_msg: String = str(res.get("error", "Failed to parse army"))
		if import_dialog != null:
			import_dialog.set_error(err_msg)
		return false

	if import_dialog != null:
		import_dialog.close()

	session.army.refund_all(session.wallet)
	var units: Array = res.get("units", [])
	var total_units: int = units.size()
	var deployed_count: int = 0
	for item: Variant in units:
		if item is Dictionary:
			var tid: String = str(item.get("type", ""))
			var cell_val: Variant = item.get("cell", Vector2i.ZERO)
			var cell: Vector2i = Vector2i.ZERO
			if cell_val is Vector2i:
				cell = cell_val
			elif cell_val is Array and (cell_val as Array).size() >= 2:
				cell = Vector2i(int((cell_val as Array)[0]), int((cell_val as Array)[1]))

			if not session.army.buy(tid, session.wallet):
				break
			if not session.army.deploy(tid, cell):
				session.army.unbuy(tid, session.wallet)
				break
			deployed_count += 1

	if deployed_count < total_units:
		_show_toast("Only %d of %d units fit your ATP" % [deployed_count, total_units])
	else:
		_show_toast("Army loaded")
	return true


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

