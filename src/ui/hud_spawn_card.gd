class_name HudSpawnCard
extends Button

signal buy_requested(type_id: String)
signal unbuy_requested(type_id: String)
signal strain_cycle_requested(type_id: String)

var type_id: String = ""
var is_recall: bool = false
var is_card_selected: bool = false
var cost_atp: int = 0
var shape: String = ""
var shape_color: Color = Color.WHITE

var icon_control: Control = null
var name_label: Label = null
var cost_label: Label = null
var role_label: Label = null
var count_badge: Label = null
var buttons_container: HBoxContainer = null
var btn_minus: Button = null
var btn_plus: Button = null
var strain_button: Button = null
var strain_summary_label: Label = null

var _style_normal: StyleBoxFlat = null
var _style_hover: StyleBoxFlat = null
var _style_selected: StyleBoxFlat = null

func _init() -> void:
	custom_minimum_size = Vector2(140.0, 130.0)
	_build_styles()

func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.16470589, 0.043137256, 0.0627451, 0.95)
	_style_normal.set_corner_radius_all(8)
	_style_normal.set_border_width_all(1)
	_style_normal.border_color = Color(0.35, 0.12, 0.15, 1.0)

	_style_hover = StyleBoxFlat.new()
	_style_hover.bg_color = Color(0.20, 0.05, 0.08, 0.95)
	_style_hover.set_corner_radius_all(8)
	_style_hover.set_border_width_all(1)
	_style_hover.border_color = Color(0.5, 0.18, 0.22, 1.0)

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0.16470589, 0.043137256, 0.0627451, 0.95)
	_style_selected.set_corner_radius_all(8)
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = Color(0.15294118, 0.68235294, 0.3764706, 1.0)

	add_theme_stylebox_override("normal", _style_normal)
	add_theme_stylebox_override("hover", _style_hover)
	add_theme_stylebox_override("pressed", _style_hover)
	add_theme_stylebox_override("focus", _style_normal)

func _ensure_nodes() -> void:
	if icon_control != null:
		return

	icon_control = get_node_or_null("MarginContainer/VBoxContainer/Header/IconControl") as Control
	name_label = get_node_or_null("MarginContainer/VBoxContainer/Header/InfoBox/NameLabel") as Label
	cost_label = get_node_or_null("MarginContainer/VBoxContainer/Header/InfoBox/CostLabel") as Label
	role_label = get_node_or_null("MarginContainer/VBoxContainer/RoleLabel") as Label
	count_badge = get_node_or_null("MarginContainer/VBoxContainer/CountBadge") as Label
	buttons_container = get_node_or_null("MarginContainer/VBoxContainer/ButtonsContainer") as HBoxContainer
	btn_minus = get_node_or_null("MarginContainer/VBoxContainer/ButtonsContainer/BtnMinus") as Button
	btn_plus = get_node_or_null("MarginContainer/VBoxContainer/ButtonsContainer/BtnPlus") as Button

	if icon_control != null:
		_wire_buttons()
		return

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	icon_control = Control.new()
	icon_control.name = "IconControl"
	icon_control.custom_minimum_size = Vector2(24.0, 24.0)
	icon_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon_control)

	var infobox := VBoxContainer.new()
	infobox.name = "InfoBox"
	infobox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	infobox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	infobox.add_theme_constant_override("separation", 0)
	header.add_child(infobox)

	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color("#f5e6e8"))
	infobox.add_child(name_label)

	cost_label = Label.new()
	cost_label.name = "CostLabel"
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.add_theme_color_override("font_color", Color("#27ae60"))
	infobox.add_child(cost_label)

	role_label = Label.new()
	role_label.name = "RoleLabel"
	role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_label.add_theme_font_size_override("font_size", 10)
	role_label.add_theme_color_override("font_color", Color("#b0a0a4"))
	vbox.add_child(role_label)

	count_badge = Label.new()
	count_badge.name = "CountBadge"
	count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_badge.add_theme_font_size_override("font_size", 11)
	count_badge.add_theme_color_override("font_color", Color("#ffffff"))
	count_badge.text = "0 · 0 deployed"
	vbox.add_child(count_badge)

	buttons_container = HBoxContainer.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons_container)

	btn_minus = Button.new()
	btn_minus.name = "BtnMinus"
	btn_minus.text = "-"
	btn_minus.custom_minimum_size = Vector2(48.0, 48.0)
	btn_minus.add_theme_font_size_override("font_size", 20)
	buttons_container.add_child(btn_minus)

	btn_plus = Button.new()
	btn_plus.name = "BtnPlus"
	btn_plus.text = "+"
	btn_plus.custom_minimum_size = Vector2(48.0, 48.0)
	btn_plus.add_theme_font_size_override("font_size", 20)
	buttons_container.add_child(btn_plus)

	_wire_buttons()

func _wire_buttons() -> void:
	if icon_control != null and not icon_control.draw.is_connected(_on_icon_draw):
		icon_control.draw.connect(_on_icon_draw)
	if btn_minus != null and not btn_minus.pressed.is_connected(_on_btn_minus_pressed):
		btn_minus.pressed.connect(_on_btn_minus_pressed)
	if btn_plus != null and not btn_plus.pressed.is_connected(_on_btn_plus_pressed):
		btn_plus.pressed.connect(_on_btn_plus_pressed)

func _ready() -> void:
	_ensure_nodes()

func set_selected(selected: bool) -> void:
	is_card_selected = selected
	if is_card_selected:
		add_theme_stylebox_override("normal", _style_selected)
		add_theme_stylebox_override("hover", _style_selected)
		add_theme_stylebox_override("focus", _style_selected)
	else:
		add_theme_stylebox_override("normal", _style_normal)
		add_theme_stylebox_override("hover", _style_hover)
		add_theme_stylebox_override("focus", _style_normal)

func setup_pathogen(p_def: PathogenDef) -> void:
	_ensure_nodes()
	is_recall = false
	type_id = p_def.id
	cost_atp = int(p_def.cost.get("atp", 0))
	shape = p_def.placeholder_shape
	shape_color = p_def.placeholder_color

	if name_label != null:
		name_label.text = p_def.display_name
	if cost_label != null:
		cost_label.text = "%d ATP" % cost_atp
	if role_label != null:
		role_label.text = p_def.role
	if buttons_container != null:
		buttons_container.visible = true

	update_counts(0, 0)
	if icon_control != null:
		icon_control.queue_redraw()

func setup_recall() -> void:
	_ensure_nodes()
	is_recall = true
	type_id = ""
	cost_atp = 0
	shape = ""

	if name_label != null:
		name_label.text = "Recall"
	if cost_label != null:
		cost_label.text = ""
	if role_label != null:
		role_label.text = "Refund deployed"
	if count_badge != null:
		count_badge.text = "Tap to toggle"
	if buttons_container != null:
		buttons_container.visible = false

	if icon_control != null:
		icon_control.queue_redraw()

## Adds (once) and refreshes the StrainButton. Only called when the strains flag is on.
func setup_strain(p_def: PathogenDef, strain: StrainDef) -> void:
	_ensure_nodes()
	if is_recall:
		return
	var vbox: VBoxContainer = get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vbox == null:
		return
	if strain_button == null:
		strain_button = Button.new()
		strain_button.name = "StrainButton"
		strain_button.custom_minimum_size = Vector2(0.0, 48.0)
		strain_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strain_button.add_theme_font_size_override("font_size", 11)
		strain_button.clip_text = true
		strain_button.pressed.connect(_on_strain_button_pressed)
		vbox.add_child(strain_button)
		vbox.move_child(strain_button, role_label.get_index() + 1 if role_label != null else 1)
		strain_summary_label = Label.new()
		strain_summary_label.name = "StrainSummaryLabel"
		strain_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strain_summary_label.add_theme_font_size_override("font_size", 10)
		strain_summary_label.add_theme_color_override("font_color", Color("#b0a0a4"))
		strain_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(strain_summary_label)
		vbox.move_child(strain_summary_label, strain_button.get_index() + 1)
		custom_minimum_size = Vector2(custom_minimum_size.x, 210.0)
	strain_button.text = strain.display_name
	strain_summary_label.text = strain.summary()

func set_unit_cost(atp: int) -> void:
	cost_atp = atp
	if cost_label != null and not is_recall:
		cost_label.text = "%d ATP" % cost_atp

func _on_strain_button_pressed() -> void:
	strain_cycle_requested.emit(type_id)

func update_counts(reserve_cnt: int, deployed_cnt: int) -> void:
	_ensure_nodes()
	if is_recall:
		return
	if count_badge != null:
		count_badge.text = "%d · %d deployed" % [reserve_cnt, deployed_cnt]
	if btn_minus != null:
		btn_minus.disabled = (reserve_cnt <= 0)

func update_affordability(wallet_atp: int) -> void:
	_ensure_nodes()
	if is_recall:
		return
	if btn_plus != null:
		btn_plus.disabled = (wallet_atp < cost_atp)

func buy() -> void:
	buy_requested.emit(type_id)

func unbuy() -> void:
	unbuy_requested.emit(type_id)

func _on_btn_minus_pressed() -> void:
	unbuy()

func _on_btn_plus_pressed() -> void:
	buy()

func _on_icon_draw() -> void:
	if icon_control == null:
		return
	if is_recall:
		var center: Vector2 = icon_control.size * 0.5
		var radius: float = minf(icon_control.size.x, icon_control.size.y) * 0.38
		icon_control.draw_arc(center, radius, PI * 0.25, PI * 1.75, 24, Color("#f39c12"), 2.5, true)
		var arrow_pt: Vector2 = center + Vector2(cos(PI * 0.25), sin(PI * 0.25)) * radius
		var p1: Vector2 = arrow_pt + Vector2(-4.0, -5.0)
		var p2: Vector2 = arrow_pt + Vector2(5.0, -3.0)
		icon_control.draw_line(arrow_pt, p1, Color("#f39c12"), 2.5)
		icon_control.draw_line(arrow_pt, p2, Color("#f39c12"), 2.5)
	elif not shape.is_empty():
		PlaceholderShapes.draw_shape(icon_control, shape, Rect2(Vector2.ZERO, icon_control.size), shape_color)
