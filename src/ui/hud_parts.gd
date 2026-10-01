class_name HudParts
extends RefCounted

## Small builders for the labels and boxes the floating-card HUDs are made of.

const KICKER_SPACING: int = 2


static func label(text: String, px: int, weight: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiFonts.style_label(l, px, weight, color)
	return l


## The default font runs a little wider than the canvas font, so card text wraps rather than widening the card.
static func wrapping(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func kicker(text: String, color: Color) -> Label:
	var l: Label = label(text, 12, 700, color)
	var v := FontVariation.new()
	v.base_font = UiFonts.weight(700)
	v.spacing_glyph = KICKER_SPACING
	l.add_theme_font_override("font", v)
	return l


static func hbox(sep: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b
