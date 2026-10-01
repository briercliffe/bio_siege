class_name PlaceholderScreen
extends Control

## Stand-in for a menu screen whose scene is not built yet: a dimmed backdrop and a card with the
## screen title and a Back button. Follows the same `back_requested` contract as a real screen.

signal back_requested

const CARD_WIDTH: float = 420.0
const TITLE_PX: int = 28
const BACK_SIZE: Vector2 = Vector2(184.0, 56.0)

var title: String = ""
var title_label: Label = null
var back_button: PillButton = null


func _init(p_title: String = "") -> void:
	title = p_title
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(DimOverlay.new())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := FloatingCard.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(title_label, TITLE_PX, 800, UiPalette.color(false, "ink"))
	box.add_child(title_label)

	back_button = PillButton.new("Back", PillButton.Variant.SECONDARY)
	back_button.name = "BtnBack"
	back_button.custom_minimum_size = BACK_SIZE
	back_button.font_px = 18
	back_button.font_weight = 700
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(back_requested.emit)
	box.add_child(back_button)
