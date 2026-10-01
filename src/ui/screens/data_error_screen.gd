class_name DataErrorScreen
extends Control

## Screen 15 (Data error): shown instead of the game when data/*.json fails validation at startup.
## Errors are grouped one per row with a file and entity chip. Copy report puts a plain text report on
## the clipboard and Reload data retries loading without a restart. Positions come from the mockup
## canvas source ConfigError.dc.html at 1280x720; a larger viewport keeps the card centred.

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const CARD_WIDTH: float = 700.0
const CARD_TOP: float = 80.0
const CARD_RADIUS: int = 40
const CARD_PAD: float = 36.0
const CARD_ALPHA: float = 0.95
const CARD_GAP: int = 16
const CARD_SHADOW: Color = Color(0.0706, 0.1882, 0.3098, 0.25)

const BADGE_SIZE: float = 60.0
const BADGE_FILL: Color = Color("#fde3df")
const BADGE_ICON_PX: float = 30.0
const BADGE_STROKE: float = 2.6
const HEADER_GAP: int = 16
const KICKER_TEXT: String = "DATA ERROR"
const KICKER_PX: int = 12
const KICKER_SPACING: int = 2
const TITLE_TEXT: String = "Game data could not load"
const TITLE_PX: int = 30
const INTRO_TEXT: String = "Bio Siege never guesses at missing stats. Fix the values below, then reload."
const INTRO_PX: int = 16

const LIST_MAX_HEIGHT: float = 300.0
const ITEM_GAP: int = 10
const ITEM_RADIUS: int = 22
const ITEM_PAD_X: float = 18.0
const ITEM_PAD_Y: float = 14.0
const ITEM_INNER_GAP: int = 6
const ITEM_BODY_PX: int = 15
const ITEM_LINE_HEIGHT: float = 1.4
const SCROLLBAR_ROOM: float = 12.0
const CHIP_HEIGHT: float = 26.0
const CHIP_PAD_X: float = 12.0
const CHIP_PX: int = 13

const BUTTON_HEIGHT: float = 58.0
const BUTTON_GAP: int = 12
const BUTTON_PX: int = 17
const COPY_TEXT: String = "Copy report"
const COPIED_TEXT: String = "Copied"
const COPIED_SECONDS: float = 2.0
const RELOAD_TEXT: String = "Reload data"

var errors: PackedStringArray = PackedStringArray()
## Text most recently handed to the clipboard (tests read it; the headless clipboard is a no-op).
var last_report: String = ""
## Node with reload_config() and the config_reload_failed signal. Defaults to the GameData autoload.
var data_source: Node = null

var background: AmbientBackground = null
var card: PanelContainer = null
var list: VBoxContainer = null
var scroll: ScrollContainer = null
var items: Array[PanelContainer] = []
var chips: Array[ErrorChip] = []
var copy_button: PillButton = null
var reload_button: PillButton = null

var _copy_timer: Timer = null


## A 26 px white capsule with the file and entity.
class ErrorChip extends Control:
	var text: String = ""

	func _init(p_text: String) -> void:
		text = p_text
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var w: float = UiFonts.text_size(text, CHIP_PX, 700).x + CHIP_PAD_X * 2.0
		custom_minimum_size = Vector2(ceilf(w), CHIP_HEIGHT)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		KitDraw.draw_box(self, rect, Color.WHITE, -1.0)
		KitDraw.draw_text_centered(self, text, rect, CHIP_PX, 700, UiPalette.color(false, "danger"))


## The 60 px pink circle with a warning triangle and exclamation mark drawn in code.
class WarningBadge extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		draw_circle(center, minf(size.x, size.y) * 0.5, BADGE_FILL)
		# The icon is a 24-unit viewBox drawn at BADGE_ICON_PX.
		var unit: float = BADGE_ICON_PX / 24.0
		var origin: Vector2 = center - Vector2(12.0, 12.0) * unit
		var col: Color = UiPalette.color(false, "danger")
		var tri := PackedVector2Array([
			origin + Vector2(12.0, 4.0) * unit, origin + Vector2(21.0, 20.0) * unit,
			origin + Vector2(3.0, 20.0) * unit, origin + Vector2(12.0, 4.0) * unit])
		draw_polyline(tri, col, BADGE_STROKE, true)
		for corner: Vector2 in tri:
			draw_circle(corner, BADGE_STROKE * 0.5, col)
		draw_line(origin + Vector2(12.0, 10.0) * unit, origin + Vector2(12.0, 14.0) * unit, col, BADGE_STROKE, true)
		draw_circle(origin + Vector2(12.0, 10.0) * unit, BADGE_STROKE * 0.5, col)
		draw_circle(origin + Vector2(12.0, 14.0) * unit, BADGE_STROKE * 0.5, col)
		draw_circle(origin + Vector2(12.0, 17.2) * unit, BADGE_STROKE * 0.5, col)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout)


func _ready() -> void:
	if data_source == null:
		data_source = GameData
	connect_data_source()
	_layout()


## Listens for failed reloads on `data_source`. Tests that swap the source call this again.
func connect_data_source() -> void:
	if data_source != null and not data_source.config_reload_failed.is_connected(_on_reload_failed):
		data_source.config_reload_failed.connect(_on_reload_failed)


## Shows the screen with one row per error.
func show_errors(new_errors: PackedStringArray) -> void:
	errors = new_errors
	for item: PanelContainer in items:
		list.remove_child(item)
		item.queue_free()
	items.clear()
	chips.clear()
	for error: String in errors:
		_add_item(DataErrorFormat.parse(error))
	scroll.scroll_vertical = 0
	_fit_scroll()
	visible = true
	_layout()


## Every control the player can tap, for the 48x48 minimum check.
func tappable_controls() -> Array[Control]:
	return [copy_button, reload_button]


## Puts the report on the clipboard, then shows "Copied" for two seconds.
func copy_report() -> void:
	last_report = DataErrorFormat.report(errors)
	DisplayServer.clipboard_set(last_report)
	# Browsers can refuse the native clipboard silently, so also ask the page for it.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText(%s)" % JSON.stringify(last_report))
	copy_button.text = COPIED_TEXT
	_copy_timer.start(COPIED_SECONDS)


## Retries loading. Hides the screen on success; a failure refreshes the list with the new errors.
func reload_data() -> void:
	if data_source == null:
		return
	if data_source.reload_config():
		visible = false


func _on_reload_failed(new_errors: PackedStringArray) -> void:
	if visible:
		show_errors(new_errors)


func _on_copy_timeout() -> void:
	copy_button.text = COPY_TEXT


func _add_item(parsed: Dictionary) -> void:
	var pal: Dictionary = UiPalette.for_theme(false)
	var item := PanelContainer.new()
	item.name = "Item%d" % (items.size() + 1)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = KitDraw.make_box(pal["danger_tint"] as Color, float(ITEM_RADIUS))
	sb.content_margin_left = ITEM_PAD_X
	sb.content_margin_right = ITEM_PAD_X
	sb.content_margin_top = ITEM_PAD_Y
	sb.content_margin_bottom = ITEM_PAD_Y
	item.add_theme_stylebox_override("panel", sb)
	list.add_child(item)
	items.append(item)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", ITEM_INNER_GAP)
	item.add_child(box)

	var chip := ErrorChip.new(DataErrorFormat.chip_text(parsed))
	chip.name = "Chip"
	box.add_child(chip)
	chips.append(chip)

	var body := Label.new()
	body.name = "Body"
	body.text = DataErrorFormat.body_text(parsed)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(CARD_WIDTH - CARD_PAD * 2.0 - SCROLLBAR_ROOM - ITEM_PAD_X * 2.0, 0.0)
	UiFonts.style_label(body, ITEM_BODY_PX, 400, pal["ink"] as Color)
	body.add_theme_constant_override("line_spacing",
			roundi(float(ITEM_BODY_PX) * ITEM_LINE_HEIGHT - UiFonts.weight(400).get_height(ITEM_BODY_PX)))
	box.add_child(body)


func _build() -> void:
	var pal: Dictionary = UiPalette.for_theme(false)
	background = AmbientBackground.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	card = PanelContainer.new()
	card.name = "Card"
	var panel: Color = Color.WHITE
	panel.a = CARD_ALPHA
	var sb: StyleBoxFlat = KitDraw.make_box(panel, float(CARD_RADIUS), 2, pal["panel_border"] as Color,
			CARD_SHADOW, 44, Vector2(0.0, 16.0))
	sb.set_content_margin_all(CARD_PAD)
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", CARD_GAP)
	card.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", HEADER_GAP)
	column.add_child(header)
	header.add_child(WarningBadge.new())
	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.text = KICKER_TEXT
	UiFonts.style_label(kicker, KICKER_PX, 700, pal["danger"] as Color)
	var kicker_font := FontVariation.new()
	kicker_font.base_font = UiFonts.weight(700)
	kicker_font.spacing_glyph = KICKER_SPACING
	kicker.add_theme_font_override("font", kicker_font)
	titles.add_child(kicker)
	var title := Label.new()
	title.name = "Title"
	title.text = TITLE_TEXT
	UiFonts.style_label(title, TITLE_PX, 800, pal["ink"] as Color)
	titles.add_child(title)

	var intro := Label.new()
	intro.name = "Intro"
	intro.text = INTRO_TEXT
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(CARD_WIDTH - CARD_PAD * 2.0, 0.0)
	UiFonts.style_label(intro, INTRO_PX, 400, pal["muted"] as Color)
	column.add_child(intro)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", ITEM_GAP)
	list.minimum_size_changed.connect(_fit_scroll)
	scroll.add_child(list)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", BUTTON_GAP)
	column.add_child(buttons)
	copy_button = _make_button("BtnCopy", COPY_TEXT, PillButton.Variant.SECONDARY, 700)
	copy_button.pressed.connect(copy_report)
	buttons.add_child(copy_button)
	reload_button = _make_button("BtnReload", RELOAD_TEXT, PillButton.Variant.PRIMARY, 800)
	reload_button.pressed.connect(reload_data)
	buttons.add_child(reload_button)

	_copy_timer = Timer.new()
	_copy_timer.name = "CopiedTimer"
	_copy_timer.one_shot = true
	_copy_timer.timeout.connect(_on_copy_timeout)
	add_child(_copy_timer)


static func _make_button(node_name: String, text: String, variant: PillButton.Variant, w: int) -> PillButton:
	var button := PillButton.new(text, variant)
	button.name = node_name
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.font_px = BUTTON_PX
	button.font_weight = w
	return button


## The list grows with its rows up to LIST_MAX_HEIGHT, then scrolls.
func _fit_scroll() -> void:
	if scroll == null or list == null:
		return
	scroll.custom_minimum_size = Vector2(0.0, minf(list.get_combined_minimum_size().y, LIST_MAX_HEIGHT))


func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = DESIGN_SIZE
	var dy: float = roundf(maxf(view.y - DESIGN_SIZE.y, 0.0) * 0.5)
	card.size = Vector2(CARD_WIDTH, 0.0)
	card.size = Vector2(CARD_WIDTH, card.get_combined_minimum_size().y)
	card.position = Vector2(roundf((view.x - CARD_WIDTH) * 0.5), CARD_TOP + dy)
