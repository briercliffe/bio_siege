class_name PauseMenu
extends Control

## Screen 12 (Infection: paused), from the mockup canvas source Pause.dc.html. A night scrim that
## blocks input to the board and a centred card with Resume, Restart raid, Settings and Quit to menu.
## UI only: it emits a signal per button and the Infection phase acts on it.

signal resume_requested
signal restart_requested
signal settings_requested
signal quit_requested

const CARD_WIDTH: float = 400.0
const CARD_RADIUS: float = 36.0
const CARD_PADDING: float = 36.0
const CARD_FILL: Color = Color("#2a0b10")
const CARD_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.6)
const CARD_SHADOW_SIZE: int = 60
const CARD_SHADOW_OFFSET: Vector2 = Vector2(0.0, 20.0)
const GAP: int = 12
const TITLE_GAP: int = 8
const RESUME_HEIGHT: float = 60.0
const BUTTON_HEIGHT: float = 56.0
const KICKER_SPACING: int = 2
const NOTE_TEXT: String = "Restarting returns you to Incubation with the same base and army budget."

var dim: DimOverlay = null
var card: PanelContainer = null
var kicker_label: Label = null
var title_label: Label = null
var resume_button: PillButton = null
var restart_button: PillButton = null
var settings_button: PillButton = null
var quit_button: PillButton = null
var note_label: Label = null


func _init() -> void:
	name = "PauseMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func buttons() -> Array[PillButton]:
	return [resume_button, restart_button, settings_button, quit_button]


func _build() -> void:
	var pal: Dictionary = UiPalette.for_theme(true)
	dim = DimOverlay.new()
	dim.name = "Dim"
	dim.night = true
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	var sb: StyleBoxFlat = KitDraw.make_box(CARD_FILL, CARD_RADIUS, 2, pal["panel_border"] as Color,
			CARD_SHADOW, CARD_SHADOW_SIZE, CARD_SHADOW_OFFSET)
	sb.set_content_margin_all(CARD_PADDING)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	kicker_label = Label.new()
	kicker_label.text = "BATTLE PAUSED"
	UiFonts.style_label(kicker_label, 13, 700, pal["muted"] as Color)
	var spaced := FontVariation.new()
	spaced.base_font = UiFonts.weight(700)
	spaced.spacing_glyph = KICKER_SPACING
	kicker_label.add_theme_font_override("font", spaced)
	box.add_child(kicker_label)

	var title_wrap := MarginContainer.new()
	title_wrap.add_theme_constant_override("margin_bottom", TITLE_GAP)
	title_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = Label.new()
	title_label.text = "Take a breath"
	UiFonts.style_label(title_label, 32, 800, pal["ink"] as Color)
	title_wrap.add_child(title_label)
	box.add_child(title_wrap)

	resume_button = _button("BtnResume", "Resume", PillButton.Variant.PRIMARY, RESUME_HEIGHT, 19, 800)
	restart_button = _button("BtnRestart", "Restart raid", PillButton.Variant.SECONDARY, BUTTON_HEIGHT, 17, 600)
	settings_button = _button("BtnSettings", "Settings", PillButton.Variant.SECONDARY, BUTTON_HEIGHT, 17, 600)
	quit_button = _button("BtnQuit", "Quit to menu", PillButton.Variant.DANGER_OUTLINE, BUTTON_HEIGHT, 17, 700)
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	for b: PillButton in buttons():
		box.add_child(b)

	note_label = Label.new()
	note_label.text = NOTE_TEXT
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.custom_minimum_size = Vector2(CARD_WIDTH - CARD_PADDING * 2.0, 0.0)
	UiFonts.style_label(note_label, 14, 400, pal["muted"] as Color)
	box.add_child(note_label)


func _button(node_name: String, label: String, variant: PillButton.Variant, height: float, px: int, weight: int) -> PillButton:
	var b := PillButton.new(label, variant)
	b.name = node_name
	b.night = true
	b.font_px = px
	b.font_weight = weight
	b.custom_minimum_size = Vector2(0.0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b
