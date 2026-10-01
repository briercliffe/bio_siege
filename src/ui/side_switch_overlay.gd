class_name SideSwitchOverlay
extends Control

## Screen 08 (Switching sides): a split day/night backdrop with flat shapes, a night card and a
## 3 s countdown. It fades in, auto-continues, a tap or the button skips, it logs `side_switch`
## and emits `finished(duration_ms, skipped)`. Positions come from SwitchSides.dc.html at 1280x720.

signal finished(duration_ms: int, skipped: bool)

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const AUTO_CONTINUE_S: int = 3
const FADE_S: float = 0.3

const DAY_FILL: Color = Color("#eaf3fb")
const NIGHT_FILL: Color = Color("#1a0709")
## The 105 degree split line, as fractions of the width at the top and the bottom edge.
const SPLIT_TOP_X: float = 736.0 / 1280.0
const SPLIT_BOTTOM_X: float = 544.0 / 1280.0

const CARD_WIDTH: float = 600.0
const CARD_FILL: Color = Color("#2a0b10")
const CARD_BORDER: Color = Color("#59202a")
const CARD_RADIUS: float = 20.0
const CARD_PADDING: int = 40
const CARD_GAP: int = 14
const CARD_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.4)
const CARD_SHADOW_SIZE: int = 48

const KICKER_TEXT: String = "END OF SYNTHESIS"
const TITLE_TEXT: String = "Switching sides"
const SUBTITLE_TEXT: String = "You are now the Pathogen"
const BODY_FORMAT: String = "Your base is locked in. Spend the %d ATP you kept on an army and deploy it from the outer ring."
const BODY_MAX_WIDTH: float = 440.0
const BUTTON_TEXT: String = "Begin Incubation"
const BUTTON_HEIGHT: float = 60.0
const BUTTON_MARGIN_TOP: int = 12
const COUNTDOWN_FORMAT: String = "Continues automatically in %d s"
const SUBTITLE_COLOR: Color = Color("#2ecc71")
const TITLE_COLOR: Color = Color("#f5e6e8")
const MUTED_COLOR: Color = Color("#d3aab0")

const SHAPE_CIRCLE: String = "circle"
const SHAPE_TRIANGLE: String = "triangle"
const SHAPE_SQUARE: String = "square"
const SHAPE_LANDER: String = "lander"
const SHAPE_CLUSTER: String = "cluster"

## Flat backdrop shapes: kind, rect (x, y, w, h), colour, corner radius for squares, and the type
## whose JSON placeholder colour replaces `color` (keeping its opacity) when a config is loaded.
const SHAPES: Array[Dictionary] = [
	{"kind": SHAPE_CIRCLE, "rect": Rect2(120.0, 110.0, 150.0, 150.0), "color": Color(0.1804, 0.5255, 0.8706, 0.35), "type": "macrophage"},
	{"kind": SHAPE_TRIANGLE, "rect": Rect2(320.0, 250.0, 120.0, 120.0), "color": Color(0.2824, 0.8588, 0.9843, 0.4), "type": "b_cell"},
	{"kind": SHAPE_SQUARE, "rect": Rect2(90.0, 400.0, 110.0, 110.0), "color": Color(0.7843, 0.7255, 0.5412, 0.5), "radius": 12.0, "type": "mucous_wall"},
	{"kind": SHAPE_SQUARE, "rect": Rect2(250.0, 530.0, 130.0, 130.0), "color": Color(0.5569, 0.2667, 0.6784, 0.3), "radius": 20.0, "type": "nucleus"},
	{"kind": SHAPE_CIRCLE, "rect": Rect2(1000.0, 100.0, 90.0, 90.0), "color": Color("#2ecc71"), "type": "rhinovirus"},
	{"kind": SHAPE_CIRCLE, "rect": Rect2(1120.0, 190.0, 60.0, 60.0), "color": Color(0.1804, 0.8, 0.4431, 0.8), "type": "rhinovirus"},
	{"kind": SHAPE_CIRCLE, "rect": Rect2(900.0, 240.0, 70.0, 70.0), "color": Color(0.1804, 0.8, 0.4431, 0.6), "type": "rhinovirus"},
	{"kind": SHAPE_LANDER, "rect": Rect2(1060.0, 420.0, 150.0, 150.0), "color": Color("#e67e22"), "type": "bacteriophage"},
	{"kind": SHAPE_CLUSTER, "rect": Rect2(930.0, 560.0, 120.0, 120.0), "color": Color("#f1c40f"), "type": "staphylococcus"},
]
## Cluster discs as (x fraction, y fraction, radius fraction of the width).
const CLUSTER_DISCS: Array[Vector3] = [
	Vector3(0.32, 0.34, 0.22), Vector3(0.68, 0.34, 0.22), Vector3(0.50, 0.70, 0.26),
]

var card: PanelContainer = null
var kicker_label: Label = null
var title_label: Label = null
var subtitle_label: Label = null
var body_label: Label = null
var btn_begin: PillButton = null
var countdown_label: Label = null

var _start_time_ms: int = 0
var _is_dismissing: bool = false
var _active_tween: Tween = null
var _hold_left: float = float(AUTO_CONTINUE_S)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if card != null:
		return
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = KitDraw.make_box(CARD_FILL, CARD_RADIUS, 2, CARD_BORDER, CARD_SHADOW, CARD_SHADOW_SIZE)
	sb.set_content_margin_all(float(CARD_PADDING))
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.name = "VBoxContainer"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", CARD_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	kicker_label = _label(box, "KickerLabel", KICKER_TEXT, 13, 700, MUTED_COLOR)
	var spaced := FontVariation.new()
	spaced.base_font = UiFonts.weight(700)
	spaced.spacing_glyph = 2
	kicker_label.add_theme_font_override("font", spaced)
	title_label = _label(box, "TitleLabel", TITLE_TEXT, 52, 800, TITLE_COLOR)
	subtitle_label = _label(box, "SubtitleLabel", SUBTITLE_TEXT, 26, 700, SUBTITLE_COLOR)

	body_label = _label(box, "BodyLabel", BODY_FORMAT % 0, 16, 400, MUTED_COLOR)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(BODY_MAX_WIDTH, 0.0)
	body_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var margin := MarginContainer.new()
	margin.name = "ButtonMargin"
	margin.add_theme_constant_override("margin_top", BUTTON_MARGIN_TOP)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(margin)
	btn_begin = PillButton.new(BUTTON_TEXT, PillButton.Variant.PRIMARY)
	btn_begin.name = "BeginButton"
	btn_begin.night = true
	btn_begin.font_px = 20
	btn_begin.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	btn_begin.pressed.connect(func() -> void: dismiss(true))
	margin.add_child(btn_begin)

	countdown_label = _label(box, "CountdownLabel", COUNTDOWN_FORMAT % AUTO_CONTINUE_S, 14, 400, MUTED_COLOR)


func _label(parent: Control, node_name: String, text: String, px: int, w: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.style_label(l, px, w, color)
	parent.add_child(l)
	return l


func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), DAY_FILL)
	draw_colored_polygon(PackedVector2Array([
		Vector2(s.x * SPLIT_TOP_X, 0.0), Vector2(s.x, 0.0), Vector2(s.x, s.y), Vector2(s.x * SPLIT_BOTTOM_X, s.y),
	]), NIGHT_FILL)
	var k: float = minf(s.x / DESIGN_SIZE.x, s.y / DESIGN_SIZE.y)
	var origin: Vector2 = (s - DESIGN_SIZE * k) * 0.5
	var cfg: GameConfig = GameData.config if GameData != null else null
	for shape: Dictionary in SHAPES:
		var r: Rect2 = shape["rect"] as Rect2
		r = Rect2(origin + r.position * k, r.size * k)
		_draw_shape(shape["kind"] as String, r, _shape_color(shape, cfg), float(shape.get("radius", 0.0)) * k)


func _shape_color(shape: Dictionary, cfg: GameConfig) -> Color:
	var base: Color = shape["color"] as Color
	if cfg == null:
		return base
	var id: String = shape["type"] as String
	var json: Color = base
	if cfg.structures.has(id):
		json = (cfg.structures[id] as StructureDef).placeholder_color
	elif cfg.pathogens.has(id):
		json = (cfg.pathogens[id] as PathogenDef).placeholder_color
	else:
		return base
	return Color(json.r, json.g, json.b, base.a)


func _draw_shape(kind: String, r: Rect2, col: Color, radius: float) -> void:
	match kind:
		SHAPE_CIRCLE:
			draw_circle(r.get_center(), r.size.x * 0.5, col)
		SHAPE_TRIANGLE:
			draw_colored_polygon(PackedVector2Array([
				r.position + Vector2(0.50, 0.04) * r.size,
				r.position + Vector2(0.96, 0.94) * r.size,
				r.position + Vector2(0.04, 0.94) * r.size,
			]), col)
		SHAPE_SQUARE:
			KitDraw.draw_box(self, r, col, radius)
		SHAPE_LANDER:
			var pts := PackedVector2Array()
			for u: Vector2 in IconPainter.LANDER:
				pts.append(r.position + u * r.size)
			draw_colored_polygon(pts, col)
		SHAPE_CLUSTER:
			for d: Vector3 in CLUSTER_DISCS:
				draw_circle(r.position + Vector2(d.x, d.y) * r.size, d.z * r.size.x, col)


func play(remaining_atp: int) -> void:
	_ensure_nodes()
	set_remaining_atp(remaining_atp)

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	_is_dismissing = false
	_start_time_ms = Time.get_ticks_msec()
	_hold_left = float(AUTO_CONTINUE_S)
	_refresh_countdown()
	visible = true
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 1.0, FADE_S)


func set_remaining_atp(remaining_atp: int) -> void:
	_ensure_nodes()
	body_label.text = BODY_FORMAT % remaining_atp


func _process(delta: float) -> void:
	if _is_dismissing or not visible:
		return
	_hold_left -= delta
	_refresh_countdown()
	if _hold_left <= 0.0:
		dismiss(false)


func _refresh_countdown() -> void:
	if countdown_label != null:
		countdown_label.text = COUNTDOWN_FORMAT % clampi(ceili(_hold_left), 0, AUTO_CONTINUE_S)


func dismiss(skipped: bool = false) -> void:
	if _is_dismissing:
		return
	_is_dismissing = true
	set_process(false)

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	var duration_ms: int = Time.get_ticks_msec() - _start_time_ms
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("side_switch", {
			"duration_ms": duration_ms,
			"skipped": skipped
		})

	_active_tween = create_tween()
	if _active_tween != null:
		_active_tween.tween_property(self, "modulate:a", 0.0, FADE_S)
		_active_tween.tween_callback(func() -> void:
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			finished.emit(duration_ms, skipped)
		)
	else:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		finished.emit(duration_ms, skipped)


func _gui_input(event: InputEvent) -> void:
	if not visible or _is_dismissing:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			accept_event()
			dismiss(true)
