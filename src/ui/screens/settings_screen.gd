class_name SettingsScreen
extends Control

## Screen 04 (Settings). Every row saves to GameSettings and takes effect immediately. Positions come
## from the mockup canvas source Settings.dc.html at 1280x720; a wider or taller viewport keeps the
## card centred horizontally. Opened from the Title (day) and from the Pause menu (`night = true`).

signal back_requested

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const HEADER_TOP: float = 26.0
const KICKER_TEXT: String = "PREFERENCES"
const KICKER_PX: int = 12
const KICKER_SPACING: int = 2
const TITLE_TEXT: String = "Settings"
const TITLE_PX: int = 40
const TITLE_GAP: int = 2

const CARD_WIDTH: float = 640.0
const CARD_TOP: float = 112.0
const CARD_RADIUS: int = 36
const CARD_PAD_X: float = 30.0
const CARD_PAD_Y: float = 12.0
const CARD_ALPHA: float = 0.92
const ROW_MIN_HEIGHT: float = 72.0
const ROW_GAP: int = 20
const DIVIDER_PX: float = 1.0
const DIVIDER_DAY: Color = Color("#dbe9f6")
const DIVIDER_NIGHT: Color = Color(1.0, 1.0, 1.0, 0.1)
const ROW_TITLE_PX: int = 17
const ROW_SUBTITLE_PX: int = 14

const SLIDER_SIZE: Vector2 = Vector2(220.0, 48.0)
const RESET_SIZE: Vector2 = Vector2(92.0, 48.0)
const RESET_PX: int = 17

const FOOTER_TOP: float = 672.0
const FOOTER_PX: int = 13
const FOOTER_DAY: Color = Color("#3f5670")
const FOOTER_TEXT: String = "Telemetry is anonymous session logs: phase timings, spending split and battle outcomes."
const RESET_TOAST: String = "Tips will show again"

const ROWS: Array[Dictionary] = [
	{"id": "volume", "title": "Master volume", "subtitle": "Placeholder sounds only for now"},
	{"id": "sfx", "title": "Sound effects", "subtitle": "Hits, deaths and button taps"},
	{"id": "intent", "title": "Intent lines by default", "subtitle": "Show each pathogen’s target in battle"},
	{"id": "flashes", "title": "Reduce screen flashes", "subtitle": "Softer hit flashes and death puffs"},
	{"id": "telemetry", "title": "Share playtest telemetry", "subtitle": "Helps balance the game"},
	{"id": "debug", "title": "Debug overlay", "subtitle": "Frame time and sim tick, dev builds only"},
	{"id": "reset", "title": "Reset tutorial hints", "subtitle": "Show the first-time tips again"},
]

var night: bool = false:
	set = set_night
var settings_path: String = GameSettings.DEFAULT_PATH
## False in release builds: the Debug overlay switch stays visible but disabled (spec section 5).
var is_debug: bool = OS.is_debug_build()
## The Sfx and SessionLogger autoloads; tests may swap in their own instances.
var sfx: Node = null
var logger: Node = null

var background: AmbientBackground = null
var back_button: IconButton = null
var header: VBoxContainer = null
var kicker_label: Label = null
var title_label: Label = null
var card: FloatingCard = null
var rows_box: VBoxContainer = null
var volume_slider: VolumeSlider = null
var sfx_switch: ToggleSwitch = null
var intent_switch: ToggleSwitch = null
var flashes_switch: ToggleSwitch = null
var telemetry_switch: ToggleSwitch = null
var debug_switch: ToggleSwitch = null
var reset_button: PillButton = null
var footer_label: Label = null
var toast: Toast = null

var _row_titles: Array[Label] = []
var _row_subtitles: Array[Label] = []
var _dividers: Array[ColorRect] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sfx = Sfx
	logger = SessionLogger
	_build()
	_apply_theme()
	resized.connect(_layout)


func _ready() -> void:
	load_values()
	_layout()


## Points the screen at another settings file (tests) and, optionally, simulates a release build.
func setup(path: String = GameSettings.DEFAULT_PATH, p_is_debug: bool = OS.is_debug_build()) -> void:
	settings_path = path
	is_debug = p_is_debug
	load_values()


func set_night(value: bool) -> void:
	night = value
	if background != null:
		_apply_theme()


## Shows the saved values without re-saving them.
func load_values() -> void:
	volume_slider.set_value_no_signal(SettingsApply.master_volume(settings_path))
	var muted: bool = bool(sfx.get("muted")) if sfx != null else GameSettings.get_bool(
			GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, GameSettings.DEFAULT_MUTED, settings_path)
	_show_switch(sfx_switch, not muted)
	var cfg: GameConfig = GameData.config if GameData != null else null
	_show_switch(intent_switch, SettingsApply.intent_lines_default(cfg, settings_path))
	_show_switch(flashes_switch, SettingsApply.reduce_flashes(settings_path))
	_show_switch(telemetry_switch, SettingsApply.telemetry_consent(settings_path))
	_show_switch(debug_switch, GameSettings.get_bool(GameSettings.SECTION_DEBUG, GameSettings.KEY_DEBUG_OVERLAY,
			GameSettings.DEFAULT_DEBUG_OVERLAY, settings_path))
	debug_switch.disabled = not is_debug
	debug_switch.visible = true


## Every control the player can tap, for the 48x48 minimum check.
func tappable_controls() -> Array[Control]:
	return [back_button, volume_slider, sfx_switch, intent_switch, flashes_switch, telemetry_switch,
			debug_switch, reset_button]


static func _show_switch(sw: ToggleSwitch, on: bool) -> void:
	sw.set_pressed_no_signal(on)
	sw.queue_redraw()


func _on_volume_changed(v: float) -> void:
	SettingsApply.apply_master_volume(v)
	GameSettings.set_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME, v, settings_path)


func _on_sfx_toggled(on: bool) -> void:
	if sfx != null:
		sfx.call("set_muted", not on)
	else:
		GameSettings.set_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, not on, settings_path)


func _on_intent_toggled(on: bool) -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAMEPLAY, GameSettings.KEY_INTENT_LINES_DEFAULT, on, settings_path)


func _on_flashes_toggled(on: bool) -> void:
	GameSettings.set_bool(GameSettings.SECTION_ACCESSIBILITY, GameSettings.KEY_REDUCE_FLASHES, on, settings_path)
	SettingsApply.notify_changed(get_tree())


func _on_telemetry_toggled(on: bool) -> void:
	GameSettings.set_bool(GameSettings.SECTION_PRIVACY, GameSettings.KEY_TELEMETRY_CONSENT, on, settings_path)
	if logger != null:
		logger.call("set_consent", on)


func _on_debug_toggled(on: bool) -> void:
	GameSettings.set_bool(GameSettings.SECTION_DEBUG, GameSettings.KEY_DEBUG_OVERLAY, on, settings_path)
	SettingsApply.notify_changed(get_tree())


func _on_reset_pressed() -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, false, settings_path)
	toast.show_message(RESET_TOAST)


func _build() -> void:
	background = AmbientBackground.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	back_button = IconButton.new(IconButton.Kind.BACK)
	back_button.name = "BtnBack"
	back_button.pressed.connect(back_requested.emit)
	add_child(back_button)

	header = VBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", TITLE_GAP)
	add_child(header)
	kicker_label = _make_label("Kicker", KICKER_TEXT)
	kicker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(kicker_label)
	title_label = _make_label("Title", TITLE_TEXT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	card = FloatingCard.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows_box.add_theme_constant_override("separation", 0)
	card.add_child(rows_box)

	volume_slider = VolumeSlider.new()
	volume_slider.name = "VolumeSlider"
	volume_slider.custom_minimum_size = SLIDER_SIZE
	volume_slider.value = GameSettings.DEFAULT_MASTER_VOLUME
	volume_slider.value_changed.connect(_on_volume_changed)
	sfx_switch = _make_switch("SfxSwitch", _on_sfx_toggled)
	intent_switch = _make_switch("IntentSwitch", _on_intent_toggled)
	flashes_switch = _make_switch("FlashesSwitch", _on_flashes_toggled)
	telemetry_switch = _make_switch("TelemetrySwitch", _on_telemetry_toggled)
	debug_switch = _make_switch("DebugSwitch", _on_debug_toggled)
	reset_button = PillButton.new("Reset", PillButton.Variant.SECONDARY)
	reset_button.name = "BtnReset"
	reset_button.custom_minimum_size = RESET_SIZE
	reset_button.font_px = RESET_PX
	reset_button.font_weight = 700
	reset_button.pressed.connect(_on_reset_pressed)

	var controls: Array[Control] = [volume_slider, sfx_switch, intent_switch, flashes_switch,
			telemetry_switch, debug_switch, reset_button]
	for i: int in range(ROWS.size()):
		var info: Dictionary = ROWS[i]
		rows_box.add_child(_make_row(info, controls[i]))
		if i < ROWS.size() - 1:
			var divider := ColorRect.new()
			divider.name = "Divider%d" % i
			divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
			divider.custom_minimum_size = Vector2(0.0, DIVIDER_PX)
			rows_box.add_child(divider)
			_dividers.append(divider)

	footer_label = _make_label("Footer", FOOTER_TEXT)
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer_label)

	toast = Toast.new()
	toast.name = "Toast"
	toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(toast)


func _make_row(info: Dictionary, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % str(info["id"])
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	row.add_theme_constant_override("separation", ROW_GAP)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	var title := _make_label("Title", str(info["title"]))
	var subtitle := _make_label("Subtitle", str(info["subtitle"]))
	text.add_child(title)
	text.add_child(subtitle)
	_row_titles.append(title)
	_row_subtitles.append(subtitle)
	row.add_child(text)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(control)
	return row


func _make_switch(node_name: String, handler: Callable) -> ToggleSwitch:
	var sw := ToggleSwitch.new()
	sw.name = node_name
	sw.toggled.connect(handler)
	return sw


static func _make_label(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _apply_theme() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var ink: Color = pal["ink"] as Color
	var muted: Color = pal["muted"] as Color
	background.night = night
	back_button.night = night
	UiFonts.style_label(kicker_label, KICKER_PX, 700, pal["accent"] as Color)
	var kicker_font := FontVariation.new()
	kicker_font.base_font = UiFonts.weight(700)
	kicker_font.spacing_glyph = KICKER_SPACING
	kicker_label.add_theme_font_override("font", kicker_font)
	UiFonts.style_label(title_label, TITLE_PX, 800, ink)
	card.night = night
	var panel: Color = pal["panel"] as Color
	panel.a = CARD_ALPHA
	var sb: StyleBoxFlat = KitDraw.make_box(panel, float(CARD_RADIUS), 2, pal["panel_border"] as Color,
			pal["panel_shadow"] as Color, 30, Vector2(0.0, 12.0))
	sb.content_margin_left = CARD_PAD_X
	sb.content_margin_right = CARD_PAD_X
	sb.content_margin_top = CARD_PAD_Y
	sb.content_margin_bottom = CARD_PAD_Y
	card.add_theme_stylebox_override("panel", sb)
	for label: Label in _row_titles:
		UiFonts.style_label(label, ROW_TITLE_PX, 700, ink)
	for label: Label in _row_subtitles:
		UiFonts.style_label(label, ROW_SUBTITLE_PX, 400, muted)
	for divider: ColorRect in _dividers:
		divider.color = DIVIDER_NIGHT if night else DIVIDER_DAY
	volume_slider.night = night
	for sw: ToggleSwitch in [sfx_switch, intent_switch, flashes_switch, telemetry_switch, debug_switch]:
		sw.night = night
	reset_button.night = night
	UiFonts.style_label(footer_label, FOOTER_PX, 400, muted if night else FOOTER_DAY)


func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = DESIGN_SIZE
	var dy: float = maxf(view.y - DESIGN_SIZE.y, 0.0)
	back_button.position = BACK_POS
	back_button.size = back_button.get_combined_minimum_size()
	header.position = Vector2(0.0, HEADER_TOP)
	header.size = Vector2(view.x, 0.0)
	card.size = Vector2(CARD_WIDTH, 0.0)
	card.position = Vector2(roundf((view.x - CARD_WIDTH) * 0.5), CARD_TOP + roundf(dy * 0.5))
	var footer_h: float = footer_label.get_combined_minimum_size().y
	footer_label.position = Vector2(0.0, FOOTER_TOP + dy)
	footer_label.size = Vector2(view.x, footer_h)
