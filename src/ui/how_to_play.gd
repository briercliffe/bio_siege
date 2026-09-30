class_name HowToPlay
extends Control

## Four-panel "How to play" overlay. Shown on first launch and reopened from the "?" buttons.

signal dismissed

const PAGE_COUNT: int = HowToPlayDiagram.PAGE_COUNT
const SWIPE_THRESHOLD_PX: float = 60.0
const MIN_BUTTON_SIZE: Vector2 = Vector2(48.0, 48.0)
const DOT_RADIUS: float = 6.0
const DOT_SPACING: float = 22.0
const DOT_ACTIVE_COLOR: Color = Color("#1e5aa8")
const DOT_IDLE_COLOR: Color = Color("#c3ccd6")

const PAGES: Array[Dictionary] = [
	{
		"title": "1. Synthesis",
		"body": "Build your immune system. Walls block paths, Macrophages splash nearby pathogens, B-Cells snipe from range. Everything costs ATP.",
	},
	{
		"title": "2. Switching sides",
		"body": "When you finalize, you become the Pathogen. Whatever ATP you didn't spend on your base is your army budget.",
	},
	{
		"title": "3. Incubation",
		"body": "Buy pathogens and tap the green ring to deploy them. Rhinoviruses swarm, Bacteriophages hunt defenses, Staphylococcus tanks damage.",
	},
	{
		"title": "4. Infection",
		"body": "Watch the attack. Destroy the Nucleus to win. Faint lines show where each pathogen is heading.",
	},
]

const OUTBREAK_LINE: String = "Outbreak: keep breaking your own base. It remembers every strain that hits it. The run ends when your defense holds."

var page: int = 0
var settings_path: String = GameSettings.DEFAULT_PATH

var _swipe_start_x: float = 0.0
var _swipe_tracking: bool = false

@onready var title_label: Label = $Center/Panel/Margin/VBox/TitleLabel
@onready var diagram: HowToPlayDiagram = $Center/Panel/Margin/VBox/Diagram
@onready var body_label: Label = $Center/Panel/Margin/VBox/BodyLabel
@onready var dots: Control = $Center/Panel/Margin/VBox/Dots
@onready var btn_back: Button = $Center/Panel/Margin/VBox/Buttons/BtnBack
@onready var btn_next: Button = $Center/Panel/Margin/VBox/Buttons/BtnNext
@onready var btn_got_it: Button = $Center/Panel/Margin/VBox/Buttons/BtnGotIt


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


func _ready() -> void:
	visible = false
	btn_back.pressed.connect(previous_page)
	btn_next.pressed.connect(next_page)
	btn_got_it.pressed.connect(got_it)
	dots.draw.connect(_on_dots_draw)
	for button: Button in [btn_back, btn_next, btn_got_it]:
		button.custom_minimum_size = MIN_BUTTON_SIZE
	_refresh()


func open(start_page: int = 0) -> void:
	page = clampi(start_page, 0, PAGE_COUNT - 1)
	_swipe_tracking = false
	if GameData.config != null:
		diagram.config = GameData.config
	visible = true
	_refresh()


func is_open() -> bool:
	return visible


func next_page() -> void:
	go_to(page + 1)


func previous_page() -> void:
	go_to(page - 1)


func go_to(index: int) -> void:
	page = clampi(index, 0, PAGE_COUNT - 1)
	_refresh()


## Closes the overlay and remembers that the player has seen it.
func got_it() -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, settings_path)
	visible = false
	dismissed.emit()


func _refresh() -> void:
	if title_label == null:
		return
	var info: Dictionary = PAGES[page]
	title_label.text = str(info["title"])
	body_label.text = str(info["body"])
	if page == PAGE_COUNT - 1 and GameData.config != null and GameData.config.flag("outbreak_mode"):
		body_label.text += "
" + OUTBREAK_LINE
	diagram.page = page
	btn_back.disabled = page == 0
	btn_next.disabled = page == PAGE_COUNT - 1
	dots.queue_redraw()


func _on_dots_draw() -> void:
	var total_w: float = DOT_SPACING * float(PAGE_COUNT - 1)
	var start: Vector2 = Vector2((dots.size.x - total_w) * 0.5, dots.size.y * 0.5)
	for i in range(PAGE_COUNT):
		dots.draw_circle(start + Vector2(DOT_SPACING * float(i), 0.0), DOT_RADIUS, DOT_ACTIVE_COLOR if i == page else DOT_IDLE_COLOR)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		_swipe_tracking = event.pressed
		_swipe_start_x = event.position.x
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index != 0 or not _swipe_tracking:
			return
		var dx: float = event.position.x - _swipe_start_x
		if absf(dx) >= SWIPE_THRESHOLD_PX:
			_swipe_tracking = false
			if dx < 0.0:
				next_page()
			else:
				previous_page()
		accept_event()
