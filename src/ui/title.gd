class_name TitleScreen
extends Control

## Screen 01 (Title): split day and night background, a night island backdrop with a fixed demo base,
## and the menu. Every position comes from the mockup canvas source Main.dc.html at 1280x720; a wider
## or taller viewport keeps the left column in place and moves the night side with the right edge.

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const DAY_WIDTH: float = 700.0
const NIGHT_LEFT: float = 600.0
const NIGHT_RADIUS: int = 120
const NIGHT_FILL: Color = Color("#240a10")
const ISLAND_RECT: Rect2 = Rect2(671.0, 190.0, 538.0, 342.0)

const COLUMN_POS: Vector2 = Vector2(80.0, 80.0)
const COLUMN_WIDTH: float = 480.0
const COLUMN_GAP: int = 12
const ICON_PX: float = 30.0
const ICON_GAP: int = 10
const ICON_ROW_MARGIN_BOTTOM: float = 8.0
const ICON_IDS: Array[String] = ["macrophage", "b_cell", "nucleus", "rhinovirus", "bacteriophage"]

const KICKER_TEXT: String = "BIOLOGICAL REVERSE TOWER DEFENSE"
const KICKER_PX: int = 13
const KICKER_SPACING: int = 2
const WORDMARK_LINES: Array[String] = ["BIO", "SIEGE"]
const WORDMARK_PX: int = 104
const WORDMARK_LINE_HEIGHT: float = 0.92
## The canvas uses -0.02em (-2 px); the extra -2 px offsets the width the heavier embolden adds.
const WORDMARK_SPACING: int = -4
## UiFonts' 800 embolden reads as a semibold at 104 px; the mockup's wordmark is a heavy black.
const WORDMARK_EMBOLDEN: float = 1.3
const TAGLINE_TEXT: String = "Build the immune defense. Then breed the pathogens that break it."
const TAGLINE_PX: int = 20
const TAGLINE_COLOR: Color = Color("#3f5670")
const TAGLINE_MAX_WIDTH: float = 420.0
const TAGLINE_LINE_HEIGHT: float = 1.4
const TAGLINE_MARGIN_TOP: int = 10
const TAGLINE_MARGIN_BOTTOM: int = 22

const PLAY_SIZE: Vector2 = Vector2(380.0, 68.0)
const WIDE_SIZE: Vector2 = Vector2(380.0, 56.0)
const HALF_SIZE: Vector2 = Vector2(184.0, 56.0)
const BUTTON_GAP: int = 12

const FOOTER_LEFT: float = 80.0
const FOOTER_BOTTOM: float = 30.0
const FOOTER_PX: int = 14
const BUILD_VERSION: String = "0.1"

const MODE_CARD_SIZE: Vector2 = Vector2(420.0, 76.0)
const MODE_LIVING_TITLE: String = "Living Base"
const MODE_LIVING_TEXT: String = "Your base persists. Raid AI bases. Defend AI raids."
const MODE_LAB_TITLE: String = "Lab"
const MODE_LAB_TEXT: String = "Sandbox with 1000 ATP. Test base builds."

## Demo base on the backdrop: a wall ring with a gap on the right side, two B-Cells and a Macrophage.
const DEMO_WALL_MIN: Vector2i = Vector2i(12, 12)
const DEMO_WALL_MAX: Vector2i = Vector2i(27, 27)
const DEMO_GAP_X: int = 27
const DEMO_GAP_Y_MIN: int = 16
const DEMO_GAP_Y_MAX: int = 23
const DEMO_TOWERS: Array[Dictionary] = [
	{"type": "b_cell", "origin": Vector2i(14, 14)},
	{"type": "b_cell", "origin": Vector2i(23, 23)},
	{"type": "macrophage", "origin": Vector2i(14, 23)},
]
const DEMO_WALL_TYPE: String = "mucous_wall"

var session: Session = null
var fsm: GameStateMachine = null
var build_info_path: String = BuildInfo.DEFAULT_PATH
## Where the Living Base profile lives; tests point this at a temp file.
var living_base_path: String = LivingBaseStore.DEFAULT_PATH

var demo_grid: GridModel = null

var base_fill: ColorRect = null
var day_background: AmbientBackground = null
var night_panel: Panel = null
var night_background: AmbientBackground = null
var island: Control = null
var grid_view: GridView = null
var column: VBoxContainer = null
var kicker_label: Label = null
var wordmark: Wordmark = null
var tagline_label: Label = null
var btn_play: PillButton = null
var btn_saved: PillButton = null
var btn_how_to_play: PillButton = null
var btn_settings: PillButton = null
var footer_label: Label = null
## Mode sheet shown by Play when the living_base flag is on.
var mode_overlay: DimOverlay = null
var mode_card: FloatingCard = null
var btn_mode_living: PillButton = null
var btn_mode_lab: PillButton = null
var btn_mode_close: IconButton = null


## "BIO / SIEGE" drawn with a CSS-style line height, which a Label cannot do.
class Wordmark extends Control:
	var lines: Array[String] = []
	var font: Font = null
	var font_px: int = 16
	var line_height: float = 1.0
	var color: Color = Color.BLACK

	func _init(p_lines: Array[String], p_font: Font, p_px: int, p_line_height: float, p_color: Color) -> void:
		lines = p_lines
		font = p_font
		font_px = p_px
		line_height = p_line_height
		color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, float(lines.size()) * line_px())

	func line_px() -> float:
		return float(font_px) * line_height

	func _draw() -> void:
		var lh: float = line_px()
		var ascent: float = font.get_ascent(font_px)
		var content: float = ascent + font.get_descent(font_px)
		for i: int in range(lines.size()):
			var baseline: float = float(i) * lh + (lh - content) * 0.5 + ascent
			draw_string(font, Vector2(0.0, baseline), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	resized.connect(_layout)


func _ready() -> void:
	# GridView turns its input handling on at ready; the backdrop is display-only.
	grid_view.set_process_unhandled_input(false)
	if demo_grid == null:
		_build_demo_base(GameData.config if GameData != null else null)
	refresh_footer()
	_layout()


func setup(p_session: Session, p_fsm: GameStateMachine) -> void:
	session = p_session
	fsm = p_fsm
	var cfg: GameConfig = session.config if session != null else null
	if cfg == null and GameData != null:
		cfg = GameData.config
	_build_demo_base(cfg)


## Called by GameStateMachine after a config hot reload was applied (#27).
func on_config_changed(_summary: Dictionary) -> void:
	if session != null:
		_build_demo_base(session.config)


static func footer_text_for(path: String) -> String:
	return "Playtest build %s · %s" % [BUILD_VERSION, BuildInfo.read(path)]


func refresh_footer() -> void:
	footer_label.text = footer_text_for(build_info_path)


## Fixed demo base, built on a local GridModel so the player's own base is never touched.
static func build_demo_grid(cfg: GameConfig) -> GridModel:
	var grid := GridModel.new(cfg)
	if cfg == null:
		return grid
	grid.reset_with_nucleus()
	var entries: Array[Dictionary] = []
	for y: int in range(DEMO_WALL_MIN.y, DEMO_WALL_MAX.y + 1):
		for x: int in range(DEMO_WALL_MIN.x, DEMO_WALL_MAX.x + 1):
			var edge: bool = x == DEMO_WALL_MIN.x or x == DEMO_WALL_MAX.x or y == DEMO_WALL_MIN.y or y == DEMO_WALL_MAX.y
			var gap: bool = x == DEMO_GAP_X and y >= DEMO_GAP_Y_MIN and y <= DEMO_GAP_Y_MAX
			if edge and not gap:
				entries.append({"type": DEMO_WALL_TYPE, "origin": Vector2i(x, y)})
	entries.append_array(DEMO_TOWERS)
	# A wallet holding exactly the demo's cost, since placing without one refuses anything that costs ATP.
	var costs: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var sdef: StructureDef = cfg.structures.get(entry["type"] as String) as StructureDef
		if sdef != null:
			costs.append(sdef.cost)
	var wallet := Wallet.new(Wallet.sum_costs(costs))
	for entry: Dictionary in entries:
		grid.place(entry["type"] as String, entry["origin"] as Vector2i, wallet)
	return grid


func _build_demo_base(cfg: GameConfig) -> void:
	if cfg == null:
		return
	demo_grid = build_demo_grid(cfg)
	grid_view.setup(demo_grid, cfg)
	grid_view.set_night(true)
	grid_view.fit_to_rect(Rect2(Vector2.ZERO, ISLAND_RECT.size))


func _build() -> void:
	base_fill = ColorRect.new()
	base_fill.name = "BaseFill"
	base_fill.color = UiPalette.color(false, "bg_mid")
	base_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(base_fill)

	day_background = AmbientBackground.new()
	day_background.name = "DayBackground"
	add_child(day_background)

	night_panel = Panel.new()
	night_panel.name = "NightPanel"
	night_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	night_panel.clip_contents = true
	# Clips the night background to the rounded left corners, not just the panel's rectangle.
	night_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var sb := StyleBoxFlat.new()
	sb.bg_color = NIGHT_FILL
	sb.corner_radius_top_left = NIGHT_RADIUS
	sb.corner_radius_bottom_left = NIGHT_RADIUS
	sb.corner_detail = 24
	night_panel.add_theme_stylebox_override("panel", sb)
	add_child(night_panel)

	night_background = AmbientBackground.new()
	night_background.name = "NightBackground"
	night_background.night = true
	night_panel.add_child(night_background)

	island = Control.new()
	island.name = "Island"
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(island)
	grid_view = (load("res://src/view/grid_view.tscn") as PackedScene).instantiate() as GridView
	island.add_child(grid_view)

	column = VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", COLUMN_GAP)
	add_child(column)

	var icon_row := HBoxContainer.new()
	icon_row.name = "IconRow"
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_theme_constant_override("separation", ICON_GAP)
	icon_row.custom_minimum_size = Vector2(0.0, ICON_PX + ICON_ROW_MARGIN_BOTTOM)
	for id: String in ICON_IDS:
		var icon := IconSlot.new(id, ICON_PX)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon_row.add_child(icon)
	column.add_child(icon_row)

	kicker_label = Label.new()
	kicker_label.name = "Kicker"
	kicker_label.text = KICKER_TEXT
	UiFonts.style_label(kicker_label, KICKER_PX, 700, UiPalette.color(false, "muted"))
	kicker_label.add_theme_font_override("font", _spaced_font(700, KICKER_SPACING))
	kicker_label.add_theme_constant_override("outline_size", 0)
	column.add_child(kicker_label)

	var wordmark_font: FontVariation = _spaced_font(800, WORDMARK_SPACING)
	wordmark_font.base_font = ThemeDB.fallback_font
	wordmark_font.variation_embolden = WORDMARK_EMBOLDEN
	wordmark = Wordmark.new(WORDMARK_LINES, wordmark_font, WORDMARK_PX,
			WORDMARK_LINE_HEIGHT, UiPalette.color(false, "ink"))
	wordmark.name = "Wordmark"
	column.add_child(wordmark)

	var tagline_margin := MarginContainer.new()
	tagline_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagline_margin.add_theme_constant_override("margin_top", TAGLINE_MARGIN_TOP)
	tagline_margin.add_theme_constant_override("margin_bottom", TAGLINE_MARGIN_BOTTOM)
	tagline_margin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tagline_margin.custom_minimum_size = Vector2(TAGLINE_MAX_WIDTH, 0.0)
	tagline_label = Label.new()
	tagline_label.name = "Tagline"
	tagline_label.text = TAGLINE_TEXT
	tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiFonts.style_label(tagline_label, TAGLINE_PX, 400, TAGLINE_COLOR)
	var tagline_font: Font = UiFonts.weight(400)
	tagline_label.add_theme_constant_override("line_spacing",
			roundi(float(TAGLINE_PX) * TAGLINE_LINE_HEIGHT - tagline_font.get_height(TAGLINE_PX)))
	tagline_margin.add_child(tagline_label)
	column.add_child(tagline_margin)

	btn_play = _make_button("BtnPlay", "Play", PillButton.Variant.PRIMARY, PLAY_SIZE, 23, 800)
	btn_play.pressed.connect(_on_play_pressed)
	column.add_child(btn_play)

	btn_saved = _make_button("BtnSaved", "Saved bases and armies", PillButton.Variant.SECONDARY, WIDE_SIZE, 18, 700)
	btn_saved.pressed.connect(_push_screen.bind("saved"))
	column.add_child(btn_saved)

	var row := HBoxContainer.new()
	row.name = "ButtonRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", BUTTON_GAP)
	btn_how_to_play = _make_button("BtnHowToPlay", "How to play", PillButton.Variant.SECONDARY, HALF_SIZE, 18, 700)
	btn_how_to_play.pressed.connect(_push_screen.bind("how_to_play"))
	row.add_child(btn_how_to_play)
	btn_settings = _make_button("BtnSettings", "Settings", PillButton.Variant.SECONDARY, HALF_SIZE, 18, 700)
	btn_settings.pressed.connect(_push_screen.bind("settings"))
	row.add_child(btn_settings)
	column.add_child(row)

	footer_label = Label.new()
	footer_label.name = "Footer"
	footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.style_label(footer_label, FOOTER_PX, 400, UiPalette.color(false, "muted"))
	footer_label.text = footer_text_for(build_info_path)
	add_child(footer_label)


func _make_button(node_name: String, label: String, v: PillButton.Variant, min_size: Vector2, px: int, w: int) -> PillButton:
	var b := PillButton.new(label, v)
	b.name = node_name
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.font_px = px
	b.font_weight = w
	return b


static func _spaced_font(w: int, spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = UiFonts.weight(w)
	font.spacing_glyph = spacing
	return font


func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = DESIGN_SIZE
	var dx: float = maxf(view.x - DESIGN_SIZE.x, 0.0)
	var dy: float = maxf(view.y - DESIGN_SIZE.y, 0.0)
	day_background.position = Vector2.ZERO
	day_background.size = Vector2(DAY_WIDTH + dx, view.y)
	night_panel.position = Vector2(NIGHT_LEFT + dx, 0.0)
	night_panel.size = Vector2(DESIGN_SIZE.x - NIGHT_LEFT, view.y)
	night_background.position = Vector2.ZERO
	night_background.size = night_panel.size
	island.position = ISLAND_RECT.position + Vector2(dx, dy * 0.5)
	island.size = ISLAND_RECT.size
	column.position = COLUMN_POS
	column.size = Vector2(COLUMN_WIDTH, 0.0)
	var footer_h: float = footer_label.get_combined_minimum_size().y
	footer_label.position = Vector2(FOOTER_LEFT, view.y - FOOTER_BOTTOM - footer_h)
	footer_label.size = Vector2(COLUMN_WIDTH, footer_h)


func _on_play_pressed() -> void:
	if session != null and session.config != null and session.config.flag("living_base"):
		open_mode_sheet()
		return
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)


func mode_sheet_open() -> bool:
	return mode_overlay != null and mode_overlay.visible


## Built on first use, so the Title is exactly today's when the living_base flag is off.
func open_mode_sheet() -> void:
	if mode_overlay == null:
		_build_mode_sheet()
	mode_overlay.visible = true


func close_mode_sheet() -> void:
	if mode_overlay != null:
		mode_overlay.visible = false


## Sets the session mode and goes to Synthesis. Living Base loads (or creates) the saved profile.
func choose_mode(mode: Session.Mode) -> void:
	close_mode_sheet()
	if session == null or session.config == null:
		return
	if mode == Session.Mode.LIVING_BASE:
		var store := LivingBaseStore.new()
		store.path = living_base_path
		LivingBaseFlow.new(store).enter(session)
	else:
		LivingBaseFlow.reset_to_lab(session)
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)


func _build_mode_sheet() -> void:
	mode_overlay = DimOverlay.new()
	mode_overlay.name = "ModeOverlay"
	add_child(mode_overlay)
	var center := CenterContainer.new()
	center.name = "ModeCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	mode_overlay.add_child(center)
	mode_card = FloatingCard.new()
	mode_card.name = "ModeCard"
	mode_card.custom_minimum_size = Vector2(MODE_CARD_SIZE.x + 2.0 * FloatingCard.PADDING, 0.0)
	center.add_child(mode_card)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	mode_card.add_child(box)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	heading.text = "Choose a mode"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiFonts.style_label(heading, 22, 800, UiPalette.color(false, "ink"))
	header.add_child(heading)
	btn_mode_close = IconButton.new(IconButton.Kind.CLOSE)
	btn_mode_close.name = "BtnModeClose"
	btn_mode_close.pressed.connect(close_mode_sheet)
	header.add_child(btn_mode_close)
	box.add_child(header)
	btn_mode_living = _make_mode_button("BtnModeLiving", MODE_LIVING_TITLE, MODE_LIVING_TEXT, PillButton.Variant.PRIMARY)
	btn_mode_living.pressed.connect(choose_mode.bind(Session.Mode.LIVING_BASE))
	box.add_child(btn_mode_living)
	btn_mode_lab = _make_mode_button("BtnModeLab", MODE_LAB_TITLE, MODE_LAB_TEXT, PillButton.Variant.SECONDARY)
	btn_mode_lab.pressed.connect(choose_mode.bind(Session.Mode.LAB))
	box.add_child(btn_mode_lab)


func _make_mode_button(node_name: String, label: String, description: String, v: PillButton.Variant) -> PillButton:
	var b := PillButton.new(label, v)
	b.name = node_name
	b.subtitle = description
	b.custom_minimum_size = MODE_CARD_SIZE
	b.font_px = 20
	return b


func _push_screen(id: String) -> void:
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push(id)
