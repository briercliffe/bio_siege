class_name HudCard
extends Button

var tool_id: String = ""
var is_sell: bool = false
var cost_atp: int = 0
var is_selected: bool = false

var shape: String = ""
var shape_color: Color = Color.WHITE

var icon_control: Control = null
var name_label: Label = null
var cost_label: Label = null
var role_label: Label = null

var _style_normal: StyleBoxFlat = null
var _style_selected: StyleBoxFlat = null

func _init() -> void:
	custom_minimum_size = Vector2(120.0, 120.0)
	_build_styles()

func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color("#ffffff")
	_style_normal.set_corner_radius_all(8)
	_style_normal.set_border_width_all(1)
	_style_normal.border_color = Color("#c5d9ed")

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color("#ffffff")
	_style_selected.set_corner_radius_all(8)
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = Color("#1e5aa8")

func _ensure_nodes() -> void:
	if icon_control != null:
		return

	icon_control = get_node_or_null("MarginContainer/VBoxContainer/IconControl") as Control
	name_label = get_node_or_null("MarginContainer/VBoxContainer/NameLabel") as Label
	cost_label = get_node_or_null("MarginContainer/VBoxContainer/CostLabel") as Label
	role_label = get_node_or_null("MarginContainer/VBoxContainer/RoleLabel") as Label

	if icon_control != null:
		return

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	icon_control = Control.new()
	icon_control.name = "IconControl"
	icon_control.custom_minimum_size = Vector2(36.0, 36.0)
	icon_control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_control)

	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color("#12304f"))
	vbox.add_child(name_label)

	cost_label = Label.new()
	cost_label.name = "CostLabel"
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_label.add_theme_font_size_override("font_size", 12)
	cost_label.add_theme_color_override("font_color", Color("#1e5aa8"))
	vbox.add_child(cost_label)

	role_label = Label.new()
	role_label.name = "RoleLabel"
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	role_label.add_theme_font_size_override("font_size", 10)
	role_label.add_theme_color_override("font_color", Color("#576574"))
	vbox.add_child(role_label)

func _ready() -> void:
	_ensure_nodes()
	_apply_style()
	if icon_control != null and not icon_control.draw.is_connected(_on_icon_draw):
		icon_control.draw.connect(_on_icon_draw)

func setup_structure(sdef: StructureDef) -> void:
	_ensure_nodes()
	tool_id = sdef.id
	is_sell = false
	cost_atp = int(sdef.cost.get("atp", 0))
	shape = sdef.placeholder_shape
	shape_color = sdef.placeholder_color

	if name_label != null:
		name_label.text = sdef.display_name
	if cost_label != null:
		cost_label.text = "%d ATP" % cost_atp
		cost_label.add_theme_color_override("font_color", Color("#1e5aa8"))
	if role_label != null:
		role_label.text = sdef.role
	if icon_control != null:
		icon_control.queue_redraw()

func setup_sell() -> void:
	_ensure_nodes()
	tool_id = "sell"
	is_sell = true
	cost_atp = 0
	shape = ""
	shape_color = Color.WHITE

	if name_label != null:
		name_label.text = "Sell"
	if cost_label != null:
		cost_label.text = "Full refund"
		cost_label.add_theme_color_override("font_color", Color("#576574"))
	if role_label != null:
		role_label.text = ""
	if icon_control != null:
		icon_control.queue_redraw()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_apply_style()

func _apply_style() -> void:
	var style: StyleBoxFlat = _style_selected if is_selected else _style_normal
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("focus", style)

func update_affordability(wallet_atp: int) -> void:
	if not is_sell and cost_atp > wallet_atp:
		modulate.a = 0.4
	else:
		modulate.a = 1.0

func _on_icon_draw() -> void:
	if icon_control == null:
		return
	if is_sell:
		var pad: float = 6.0
		var s: Vector2 = icon_control.size
		var col := Color("#e74c3c")
		icon_control.draw_line(Vector2(pad, pad), Vector2(s.x - pad, s.y - pad), col, 3.0, true)
		icon_control.draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y - pad), col, 3.0, true)
	else:
		PlaceholderShapes.draw_shape(icon_control, shape, Rect2(Vector2.ZERO, icon_control.size), shape_color)
