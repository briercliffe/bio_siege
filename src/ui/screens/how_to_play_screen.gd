class_name HowToPlayScreen
extends Control

## Screen 02 (How to play): the four-step loop on static mini islands, three rules and Start building.
## Shown on first launch over the Title and reopened from the Build and Spawn HUD "?" buttons. Positions
## come from the mockup canvas source HowToPlay.dc.html at 1280x720; a wider or taller viewport keeps
## the content centred. The numbers in the copy come from the config, never from literals.

signal back_requested

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const MIN_BUTTON_SIZE: Vector2 = Vector2(48.0, 48.0)
const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const HEADER_TOP: float = 26.0
const KICKER_TEXT: String = "ONE LOOP, FOUR STEPS"
const KICKER_PX: int = 12
const KICKER_SPACING: int = 2
const TITLE_TEXT: String = "How to play"
const TITLE_PX: int = 40
const TITLE_GAP: int = 2

const CONTENT_WIDTH: float = 1184.0
const CARD_TOP: float = 112.0
const CARD_SIZE: Vector2 = Vector2(281.0, 368.0)
const CARD_GAP: int = 20
const CARD_RADIUS: int = 36
const CARD_PAD: float = 20.0
const CARD_ALPHA: float = 0.92
const CARD_INNER_GAP: int = 12
const CHIP_HEIGHT: float = 30.0
const CHIP_PAD_X: float = 14.0
const CHIP_PX: int = 12
const ISLAND_SIZE: Vector2 = Vector2(230.0, 140.0)
const STEP_TITLE_PX: int = 24
const STEP_BODY_PX: int = 15
const STEP_BODY_LINE_HEIGHT: float = 1.45

const RULE_TOP: float = 560.0
const RULE_SIZE: Vector2 = Vector2(384.0, 88.0)
const RULE_GAP: int = 16
const RULE_RADIUS: int = 28
const RULE_ALPHA: float = 0.85
const RULE_PAD_X: float = 20.0
const RULE_PAD_Y: float = 14.0
const RULE_PX: int = 14
const RULE_LINE_HEIGHT: float = 1.45
const RULE_TEXT: Color = Color("#3f5670")

const START_TEXT: String = "Start building"
const START_SIZE: Vector2 = Vector2(240.0, 60.0)
const START_TOP: float = 640.0
const START_PX: int = 18

const CHIP_BLUE: Color = Color("#1e5aa8")
const CHIP_GREEN: Color = Color("#178a4b")
const CHIP_GREY: Color = Color("#576574")
const BODY_TEXT: Color = Color("#576574")

enum Scene { BUILD, DEPLOY, SIEGE, ITERATE }

const MINUTE_WORDS: Array[String] = ["one", "two", "three", "four", "five"]
const MULTIPLIER_WORDS: Dictionary = {2: "Double", 3: "Triple"}
const PHAGE_ID: String = "bacteriophage"
const DEFENSE_TAG: String = "defense"

## Deploy markers on card 2, on the front-right edge of the band toward the front corner. Each spot is a
## fraction of the grid's (width - 1, height - 1), so it stays on the band whatever the grid size. Listed
## back to front; the deployed units are also painted over their markers so they read at this size.
const DEPLOY_TYPES: Array[String] = ["rhinovirus", "bacteriophage", "staphylococcus"]
const DEPLOY_SPOTS: Array[Vector2] = [Vector2(1.0, 0.55), Vector2(1.0, 0.7), Vector2(1.0, 0.85)]
## Card 3: a trail of pathogens running from the gap on the right of the demo wall ring
## (TitleScreen.DEMO_GAP_X) out toward the island's right corner, which on screen is roughly level.
## Listed back to front (ascending x + y), the island's depth order.
const SIEGE_UNITS: Array[Dictionary] = [
	{"type": "bacteriophage", "cell": Vector2i(29, 20)},
	{"type": "rhinovirus", "cell": Vector2i(30, 21)},
	{"type": "staphylococcus", "cell": Vector2i(32, 20)},
	{"type": "rhinovirus", "cell": Vector2i(34, 19)},
	{"type": "rhinovirus", "cell": Vector2i(36, 18)},
	{"type": "rhinovirus", "cell": Vector2i(38, 17)},
	{"type": "rhinovirus", "cell": Vector2i(35, 21)},
]
## Card 4: wall cells on the front edge of the demo ring that are knocked out.
const BREACH_CELLS: Array[Vector2i] = [Vector2i(18, 27), Vector2i(19, 27), Vector2i(20, 27)]

var settings_path: String = GameSettings.DEFAULT_PATH
var fsm: GameStateMachine = null
var config: GameConfig = null

var background: AmbientBackground = null
var back_button: IconButton = null
var header: VBoxContainer = null
var kicker_label: Label = null
var title_label: Label = null
var cards: Array[FloatingCard] = []
var chips: Array[StepChip] = []
var islands: Array[Control] = []
var grid_views: Array[GridView] = []
var step_titles: Array[Label] = []
var step_bodies: Array[Label] = []
var rule_cards: Array[FloatingCard] = []
var rule_labels: Array[RichTextLabel] = []
var start_button: PillButton = null


## A 30 px capsule with the step number and phase name.
class StepChip extends Control:
	var text: String = ""
	var fill: Color = Color.BLACK

	func _init(p_text: String, p_fill: Color) -> void:
		text = p_text
		fill = p_fill
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var w: float = UiFonts.text_size(text, CHIP_PX, 800).x + CHIP_PAD_X * 2.0
		custom_minimum_size = Vector2(ceilf(w), CHIP_HEIGHT)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		KitDraw.draw_box(self, rect, fill, -1.0)
		KitDraw.draw_text_centered(self, text, rect, CHIP_PX, 800, Color.WHITE)


## Static pathogens drawn over a mini island with their model painters.
class PathogenSprites extends Node2D:
	var grid_view: GridView = null
	var units: Array[Dictionary] = []

	func _draw() -> void:
		if grid_view == null:
			return
		var pose := ModelPose.new()
		pose.facing_right = false
		var t: float = grid_view.projection.tile_px
		for i: int in range(units.size()):
			var entry: Dictionary = units[i]
			pose.seed = i + 1
			var anchor: Vector2 = grid_view.cell_to_local_center(entry["cell"] as Vector2i)
			ModelRegistry.painter_for(entry["type"] as String).paint(self, anchor, pose, t)


static func should_show_on_launch(path: String = GameSettings.DEFAULT_PATH) -> bool:
	return not GameSettings.get_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, false, path)


## The "?" button used by the Build and Spawn HUD top bars.
static func create_help_button() -> Button:
	var button := Button.new()
	button.name = "BtnHelp"
	button.text = "?"
	button.custom_minimum_size = MIN_BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button


## "Triple" for 3x, "Double" for 2x, otherwise "Nx". `pct` is a percentage (300 = 3x).
static func multiplier_word(pct: int) -> String:
	if pct % 100 == 0 and MULTIPLIER_WORDS.has(pct / 100):
		return str(MULTIPLIER_WORDS[pct / 100])
	if pct % 100 == 0:
		return "%dx" % (pct / 100)
	return "%sx" % String.num(float(pct) / 100.0, 2)


## A countdown clock, "3:00".
static func clock_text(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


## "three minutes"; whole minutes 1 to 5 as words, others as digits, and seconds when not whole minutes.
static func duration_text(seconds: int) -> String:
	if seconds <= 0 or seconds % 60 != 0:
		return "%d seconds" % seconds
	var minutes: int = seconds / 60
	var count: String = MINUTE_WORDS[minutes - 1] if minutes <= MINUTE_WORDS.size() else str(minutes)
	return "%s minute%s" % [count, "" if minutes == 1 else "s"]


static func timeout_seconds(cfg: GameConfig) -> int:
	if cfg == null or cfg.tick_rate <= 0:
		return 0
	return cfg.battle_timeout_ticks / cfg.tick_rate


static func phage_defense_pct(cfg: GameConfig) -> int:
	var pdef: PathogenDef = cfg.pathogens.get(PHAGE_ID) as PathogenDef if cfg != null else null
	if pdef == null:
		return 100
	return int(pdef.damage_multipliers_pct.get(DEFENSE_TAG, 100))


## Chip, chip colour, title and body of each step card.
static func step_texts(cfg: GameConfig) -> Array[Dictionary]:
	return [
		{"chip": "1 · SYNTHESIS", "color": CHIP_BLUE, "title": "Build",
			"body": "Spend ATP on walls, Macrophages and B-Cells around your Nucleus. Sell anything for a full refund."},
		{"chip": "2 · INCUBATION", "color": CHIP_GREEN, "title": "Deploy",
			"body": "Switch sides. Buy pathogens with the ATP you kept, then tap the glowing band to send them in."},
		{"chip": "3 · INFECTION", "color": CHIP_GREEN, "title": "Siege",
			"body": "Launch and watch the battle play out. Destroy the Nucleus to win. You have %s." % duration_text(timeout_seconds(cfg))},
		{"chip": "4 · RESULTS", "color": CHIP_GREY, "title": "Iterate",
			"body": "Re-raid the same base, edit your defenses or start over. ATP spent on defense is missing from your army."},
	]


## Bold lead and the rest of each rule chip.
static func rule_texts(cfg: GameConfig) -> Array[Dictionary]:
	return [
		{"lead": "Walls block paths.",
			"rest": "Pathogens walk around when the detour is short and break through when it is long."},
		{"lead": "Bacteriophages hit defenses hard.",
			"rest": "%s damage against Macrophages and B-Cells." % multiplier_word(phage_defense_pct(cfg))},
		{"lead": "Out of time means the defense wins.",
			"rest": "The timer stops the battle at %s." % clock_text(timeout_seconds(cfg))},
	]


## Local demo base for one card. The player's own base is never touched.
static func build_scene_grid(cfg: GameConfig, scene: Scene) -> GridModel:
	var grid: GridModel = TitleScreen.build_demo_grid(cfg)
	if scene == Scene.ITERATE:
		for cell: Vector2i in BREACH_CELLS:
			var id: int = grid.structure_id_at(cell)
			if id > 0:
				grid.sell(id)
	return grid


## A throwaway army with one of each pathogen deployed on the front-right edge of the band.
static func build_deploy_army(cfg: GameConfig, grid: GridModel) -> Army:
	var army := Army.new(cfg)
	var costs: Array[Dictionary] = []
	for type_id: String in DEPLOY_TYPES:
		costs.append(army.unit_cost(type_id))
	var wallet := Wallet.new(Wallet.sum_costs(costs))
	for i: int in range(DEPLOY_TYPES.size()):
		var spot: Vector2 = DEPLOY_SPOTS[i]
		var cell := Vector2i(roundi(float(grid.width - 1) * spot.x), roundi(float(grid.height - 1) * spot.y))
		if army.buy(DEPLOY_TYPES[i], wallet):
			army.deploy(DEPLOY_TYPES[i], cell)
	return army


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout)


func _ready() -> void:
	# GridView turns input and idle animation on at ready; the mini islands are static and display-only.
	for view: GridView in grid_views:
		view.set_process_unhandled_input(false)
		view.set_process(false)
	if config == null:
		_apply_config(GameData.config if GameData != null else null)
	_layout()


## Main calls this when the screen opens: the settings file, the FSM (for Start building on the Title)
## and the session's config.
func setup(path: String = GameSettings.DEFAULT_PATH, p_fsm: GameStateMachine = null, cfg: GameConfig = null) -> void:
	settings_path = path
	fsm = p_fsm
	if cfg == null and fsm != null and fsm.session != null:
		cfg = fsm.session.config
	if cfg != null and cfg != config:
		_apply_config(cfg)


## Every control the player can tap, for the 48x48 minimum check.
func tappable_controls() -> Array[Control]:
	return [back_button, start_button]


## Remembers the screen was seen and closes it; on the Title it also starts building.
func start_building() -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, settings_path)
	back_requested.emit()
	if fsm != null and fsm.phase == GameStateMachine.Phase.TITLE:
		fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)


func _apply_config(cfg: GameConfig) -> void:
	config = cfg
	var steps: Array[Dictionary] = step_texts(cfg)
	for i: int in range(steps.size()):
		step_bodies[i].text = str(steps[i]["body"])
	var rules: Array[Dictionary] = rule_texts(cfg)
	for i: int in range(rules.size()):
		rule_labels[i].text = "[color=#%s][b]%s[/b][/color] %s" % [
			UiPalette.color(false, "ink").to_html(false), rules[i]["lead"], rules[i]["rest"]]
	if cfg == null:
		return
	for i: int in range(grid_views.size()):
		var scene: Scene = i as Scene
		var view: GridView = grid_views[i]
		var grid: GridModel = build_scene_grid(cfg, scene)
		var army: Army = build_deploy_army(cfg, grid) if scene == Scene.DEPLOY else null
		view.setup(grid, cfg, army)
		view.set_night(scene != Scene.BUILD)
		view.deploy_mode = scene == Scene.DEPLOY
		view.fit_to_rect(Rect2(Vector2.ZERO, ISLAND_SIZE))
		var overlay: PathogenSprites = view.get_node_or_null("DeployUnits") as PathogenSprites
		if overlay != null and army != null:
			overlay.units.clear()
			for dep: Dictionary in army.deployments:
				overlay.units.append({"type": dep["type"], "cell": dep["cell"]})
		overlay = view.get_node_or_null("SiegeUnits") as PathogenSprites
		if overlay != null:
			overlay.queue_redraw()


func _build() -> void:
	background = AmbientBackground.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	back_button = IconButton.new(IconButton.Kind.BACK)
	back_button.name = "BtnBack"
	back_button.pressed.connect(back_requested.emit)
	add_child(back_button)

	var pal: Dictionary = UiPalette.for_theme(false)
	header = VBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", TITLE_GAP)
	add_child(header)
	kicker_label = _make_label("Kicker", KICKER_TEXT, KICKER_PX, 700, pal["accent"] as Color)
	var kicker_font := FontVariation.new()
	kicker_font.base_font = UiFonts.weight(700)
	kicker_font.spacing_glyph = KICKER_SPACING
	kicker_label.add_theme_font_override("font", kicker_font)
	kicker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(kicker_label)
	title_label = _make_label("Title", TITLE_TEXT, TITLE_PX, 800, pal["ink"] as Color)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	var steps: Array[Dictionary] = step_texts(null)
	for i: int in range(steps.size()):
		_build_card(i, steps[i], pal)

	for i: int in range(3):
		var rule := FloatingCard.new()
		rule.name = "Rule%d" % (i + 1)
		rule.custom_minimum_size = RULE_SIZE
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb: StyleBoxFlat = KitDraw.make_box(Color(1.0, 1.0, 1.0, RULE_ALPHA), float(RULE_RADIUS))
		sb.content_margin_left = RULE_PAD_X
		sb.content_margin_right = RULE_PAD_X
		sb.content_margin_top = RULE_PAD_Y
		sb.content_margin_bottom = RULE_PAD_Y
		rule.add_theme_stylebox_override("panel", sb)
		var label := RichTextLabel.new()
		label.name = "Text"
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label.custom_minimum_size = Vector2(RULE_SIZE.x - RULE_PAD_X * 2.0, 0.0)
		label.add_theme_font_override("normal_font", UiFonts.weight(400))
		label.add_theme_font_override("bold_font", UiFonts.weight(700))
		label.add_theme_font_size_override("normal_font_size", RULE_PX)
		label.add_theme_font_size_override("bold_font_size", RULE_PX)
		label.add_theme_color_override("default_color", RULE_TEXT)
		label.add_theme_constant_override("line_separation",
				roundi(float(RULE_PX) * RULE_LINE_HEIGHT - UiFonts.weight(400).get_height(RULE_PX)))
		rule.add_child(label)
		add_child(rule)
		rule_cards.append(rule)
		rule_labels.append(label)

	start_button = PillButton.new(START_TEXT, PillButton.Variant.PRIMARY)
	start_button.name = "BtnStart"
	start_button.custom_minimum_size = START_SIZE
	start_button.font_px = START_PX
	start_button.font_weight = 800
	start_button.pressed.connect(start_building)
	add_child(start_button)


func _build_card(index: int, info: Dictionary, pal: Dictionary) -> void:
	var card := FloatingCard.new()
	card.name = "Step%d" % (index + 1)
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: Color = pal["panel"] as Color
	panel.a = CARD_ALPHA
	var sb: StyleBoxFlat = KitDraw.make_box(panel, float(CARD_RADIUS), 2, pal["panel_border"] as Color,
			Color(0.0706, 0.1882, 0.3098, 0.18), 30, Vector2(0.0, 12.0))
	sb.set_content_margin_all(CARD_PAD)
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	cards.append(card)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", CARD_INNER_GAP)
	card.add_child(box)

	var chip := StepChip.new(str(info["chip"]), info["color"] as Color)
	chip.name = "Chip"
	box.add_child(chip)
	chips.append(chip)

	var island := Control.new()
	island.name = "Island"
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	island.custom_minimum_size = ISLAND_SIZE
	island.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(island)
	islands.append(island)
	var view: GridView = (load("res://src/view/grid_view.tscn") as PackedScene).instantiate() as GridView
	island.add_child(view)
	grid_views.append(view)
	if index == Scene.DEPLOY or index == Scene.SIEGE:
		var overlay := PathogenSprites.new()
		overlay.name = "SiegeUnits" if index == Scene.SIEGE else "DeployUnits"
		overlay.grid_view = view
		if index == Scene.SIEGE:
			overlay.units = SIEGE_UNITS.duplicate()
		view.add_child(overlay)

	var title := _make_label("Title", str(info["title"]), STEP_TITLE_PX, 800, pal["ink"] as Color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	step_titles.append(title)

	var body := _make_label("Body", str(info["body"]), STEP_BODY_PX, 400, BODY_TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PAD * 2.0, 0.0)
	body.add_theme_constant_override("line_spacing",
			roundi(float(STEP_BODY_PX) * STEP_BODY_LINE_HEIGHT - UiFonts.weight(400).get_height(STEP_BODY_PX)))
	box.add_child(body)
	step_bodies.append(body)


static func _make_label(node_name: String, text: String, px: int, w: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.style_label(label, px, w, color)
	return label


func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = DESIGN_SIZE
	var left: float = roundf((view.x - CONTENT_WIDTH) * 0.5)
	var dy: float = roundf(maxf(view.y - DESIGN_SIZE.y, 0.0) * 0.5)
	back_button.position = BACK_POS
	back_button.size = back_button.get_combined_minimum_size()
	header.position = Vector2(0.0, HEADER_TOP + dy)
	header.size = Vector2(view.x, 0.0)
	for i: int in range(cards.size()):
		cards[i].position = Vector2(left + float(i) * (CARD_SIZE.x + float(CARD_GAP)), CARD_TOP + dy)
		cards[i].size = CARD_SIZE
	for i: int in range(rule_cards.size()):
		rule_cards[i].position = Vector2(left + float(i) * (RULE_SIZE.x + float(RULE_GAP)), RULE_TOP + dy)
		rule_cards[i].size = RULE_SIZE
	start_button.size = START_SIZE
	start_button.position = Vector2(roundf((view.x - START_SIZE.x) * 0.5), START_TOP + dy)
