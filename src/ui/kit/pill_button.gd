class_name PillButton
extends Button

## Capsule button: PRIMARY (gradient accent), SECONDARY (outlined) or DANGER_OUTLINE.
## Everything is drawn in _draw(); the native Button only supplies input and the `text` property.
## A disabled button stays visible with a flat muted fill.

enum Variant { PRIMARY, SECONDARY, DANGER_OUTLINE }

const MIN_HEIGHT: float = 52.0
const MIN_HEIGHT_WITH_SUBTITLE: float = 64.0
const MIN_WIDTH: float = 120.0

var night: bool = false:
	set = set_night
var variant: Variant = Variant.PRIMARY:
	set = set_variant
var subtitle: String = "":
	set = set_subtitle
var font_px: int = 17:
	set = set_font_px


func _init(label: String = "", v: Variant = Variant.PRIMARY) -> void:
	text = label
	variant = v
	KitDraw.make_button_blank(self)
	_refresh_min_size()


func set_night(value: bool) -> void:
	night = value
	queue_redraw()


func set_variant(value: Variant) -> void:
	variant = value
	queue_redraw()


func set_subtitle(value: String) -> void:
	subtitle = value
	_refresh_min_size()
	queue_redraw()


func set_font_px(value: int) -> void:
	font_px = clampi(value, 17, 23)
	queue_redraw()


func _refresh_min_size() -> void:
	var h: float = MIN_HEIGHT_WITH_SUBTITLE if subtitle != "" else MIN_HEIGHT
	custom_minimum_size = Vector2(MIN_WIDTH, h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		queue_redraw()


func _draw() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var rect := Rect2(Vector2.ZERO, size)
	var pressed_now: bool = get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	if pressed_now:
		rect = Rect2(rect.position + Vector2(0.0, 1.0), rect.size - Vector2(0.0, 1.0))
	var text_col: Color
	if disabled:
		KitDraw.draw_box(self, rect, pal["disabled_fill"] as Color, -1.0)
		text_col = pal["disabled_text"] as Color
	else:
		match variant:
			Variant.PRIMARY:
				KitDraw.draw_box(self, rect, pal["accent"] as Color, -1.0, 0, Color.TRANSPARENT,
						pal["accent_shadow"] as Color, 18, Vector2(0.0, 8.0))
				if night:
					KitDraw.draw_box(self, rect, pal["accent"] as Color, -1.0, 0, Color.TRANSPARENT,
							pal["accent_glow"] as Color, 24, Vector2.ZERO)
				var top: Color = pal["accent_top"] as Color
				var bottom: Color = pal["accent"] as Color
				if pressed_now:
					top = top.darkened(0.12)
					bottom = bottom.darkened(0.12)
				KitDraw.draw_gradient_rounded(self, rect, -1.0, top, bottom)
				text_col = pal["on_accent"] as Color
			Variant.SECONDARY:
				KitDraw.draw_box(self, rect, pal["secondary_btn_bg"] as Color, -1.0, 2, pal["secondary_btn_border"] as Color)
				text_col = pal["ink"] as Color
			_:
				KitDraw.draw_box(self, rect, pal["danger_tint"] as Color, -1.0, 2, pal["danger_border"] as Color)
				text_col = pal["danger"] as Color
	if subtitle == "":
		KitDraw.draw_text_centered(self, text, rect, font_px, 800, text_col)
	else:
		var sub_col: Color = text_col if variant == Variant.PRIMARY or disabled else (pal["muted"] as Color)
		var title_rect := Rect2(rect.position + Vector2(0.0, -7.0), rect.size)
		var sub_rect := Rect2(rect.position + Vector2(0.0, 12.0), rect.size)
		KitDraw.draw_text_centered(self, text, title_rect, font_px, 800, text_col)
		KitDraw.draw_text_centered(self, subtitle, sub_rect, 12, 600, sub_col)
