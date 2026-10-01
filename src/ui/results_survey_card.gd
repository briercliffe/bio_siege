class_name ResultsSurveyCard
extends FloatingCard

## The one optional question on the Results screen (screens 13 and 14). One tap answers it, Skip hides it.
## The card only reports what was tapped; ResultsPhase writes the telemetry.

signal answered(key: String, value: Variant)
signal skipped(key: String)

const KICKER_TEXT: String = "QUICK QUESTION · OPTIONAL"
const THANKS_TEXT: String = "Thanks!"
const CARD_WIDTH: float = 396.0
const ROUND_SIZE: Vector2 = Vector2(58.0, 50.0)
const PILL_SIZE: Vector2 = Vector2(110.0, 52.0)
const SKIP_HEIGHT: float = 48.0
const SELECTED_BORDER: Color = Color("#2ecc71")

## Rotation order, indexed by battle_count % 4. Each entry is one question; `pills` ones answer with a word.
const QUESTIONS: Array[Dictionary] = [
	{
		"key": "pivot",
		"text": "How did switching from builder to attacker feel?",
		"low": "Jarring",
		"high": "Smooth",
	},
	{
		"key": "map_feel",
		"text": "The island felt…",
		"pills": [
			{"label": "Empty", "value": "empty"},
			{"label": "Just right", "value": "just_right"},
			{"label": "Cramped", "value": "cramped"},
		],
	},
	{
		"key": "predictability",
		"text": "Could you predict where pathogens would go?",
		"low": "Not at all",
		"high": "Every time",
	},
	{
		"key": "economy",
		"text": "Did sharing ATP between base and army force interesting choices?",
		"low": "No",
		"high": "Yes, a lot",
	},
]


## A round or pill answer button. It draws itself; the native Button only supplies input.
class AnswerButton:
	extends Button

	var value: Variant = null
	var chosen: bool = false:
		set(v):
			chosen = v
			queue_redraw()

	func _init(label: String, p_value: Variant, p_size: Vector2) -> void:
		text = label
		value = p_value
		custom_minimum_size = p_size
		KitDraw.make_button_blank(self)

	func _draw() -> void:
		var pal: Dictionary = UiPalette.for_theme(true)
		var rect := Rect2(Vector2.ZERO, size)
		var pressed_now: bool = get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
		var fill: Color = Color(1.0, 1.0, 1.0, 0.1) if pressed_now else (pal["secondary_btn_bg"] as Color)
		if chosen:
			KitDraw.draw_box(self, rect, fill, -1.0, 2, SELECTED_BORDER)
		else:
			KitDraw.draw_box(self, rect, fill, -1.0, 2, pal["secondary_btn_border"] as Color)
		KitDraw.draw_text_centered(self, text, rect, 17, 800, pal["ink"] as Color)


## Underlined muted text on a 48 px tall button (Skip, Export playtest logs).
class TextLink:
	extends Button

	var font_px: int = 14:
		set(v):
			font_px = v
			_fit()

	func _init(label: String = "") -> void:
		text = label
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		KitDraw.make_button_blank(self)
		_fit()

	## Wide enough for the text plus 16 px each side, and never under 48 px either way.
	func _fit() -> void:
		var w: float = maxf(UiFonts.text_size(text, font_px, 700).x + 32.0, 48.0)
		custom_minimum_size = Vector2(w, SKIP_HEIGHT)
		queue_redraw()

	func _draw() -> void:
		var col: Color = UiPalette.color(true, "muted")
		var font: Font = UiFonts.weight(700)
		var tw: float = UiFonts.text_size(text, font_px, 700).x
		var left: float = 16.0
		var base_y: float = size.y * 0.5 + font.get_ascent(font_px) * 0.5 - font.get_descent(font_px) * 0.5
		draw_string(font, Vector2(left, base_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, col)
		draw_line(Vector2(left, base_y + 2.0), Vector2(left + tw, base_y + 2.0), col, 1.5)


var question_key: String = ""
var kicker_label: Label = null
var question_label: Label = null
var answer_row: HBoxContainer = null
var legend_row: HBoxContainer = null
var low_label: Label = null
var high_label: Label = null
var skip_button: TextLink = null
## Answer buttons in display order.
var answer_buttons: Array[AnswerButton] = []
var is_answered: bool = false


## battle_count 0 is pivot, 1 map_feel, 2 predictability, 3 economy, then it repeats.
static func question_for(battle_count: int) -> Dictionary:
	return QUESTIONS[posmod(battle_count, QUESTIONS.size())]


func _init() -> void:
	night = true
	custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	kicker_label = HudParts.kicker(KICKER_TEXT, UiPalette.color(true, "muted"))
	box.add_child(kicker_label)

	question_label = HudParts.wrapping(HudParts.label("", 17, 700, UiPalette.color(true, "ink")))
	box.add_child(question_label)

	answer_row = HudParts.hbox(12)
	answer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(answer_row)

	legend_row = HudParts.hbox(8)
	box.add_child(legend_row)
	low_label = HudParts.label("", 12, 400, UiPalette.color(true, "muted"))
	low_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend_row.add_child(low_label)
	high_label = HudParts.label("", 12, 400, UiPalette.color(true, "muted"))
	high_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	legend_row.add_child(high_label)

	skip_button = TextLink.new("Skip")
	skip_button.name = "BtnSkipSurvey"
	skip_button.pressed.connect(_on_skip_pressed)
	box.add_child(skip_button)


## Shows the question for `battle_count`, clearing any earlier answer.
func setup(battle_count: int) -> void:
	var q: Dictionary = question_for(battle_count)
	question_key = str(q["key"])
	is_answered = false
	visible = true
	for b: AnswerButton in answer_buttons:
		answer_row.remove_child(b)
		b.queue_free()
	answer_buttons.clear()
	question_label.text = str(q["text"])
	skip_button.visible = true

	var pills: Array = q.get("pills", [])
	if pills.is_empty():
		for i: int in range(1, 6):
			_add_answer(str(i), i, ROUND_SIZE)
		low_label.text = str(q.get("low", ""))
		high_label.text = str(q.get("high", ""))
		legend_row.visible = true
	else:
		for p_val: Variant in pills:
			var p: Dictionary = p_val
			_add_answer(str(p["label"]), str(p["value"]), PILL_SIZE)
		legend_row.visible = false


func _add_answer(label: String, value: Variant, btn_size: Vector2) -> void:
	var b := AnswerButton.new(label, value, btn_size)
	b.name = "Answer%s" % str(value)
	b.pressed.connect(_on_answer_pressed.bind(b))
	answer_row.add_child(b)
	answer_buttons.append(b)


## The answer button holding `value`, or null.
func answer_button(value: Variant) -> AnswerButton:
	for b: AnswerButton in answer_buttons:
		if b.value == value:
			return b
	return null


func _on_answer_pressed(btn: AnswerButton) -> void:
	if is_answered:
		return
	is_answered = true
	for b: AnswerButton in answer_buttons:
		b.chosen = b == btn
		b.disabled = true
	question_label.text = THANKS_TEXT
	skip_button.visible = false
	legend_row.visible = false
	answered.emit(question_key, btn.value)


func _on_skip_pressed() -> void:
	if is_answered:
		return
	visible = false
	skipped.emit(question_key)
