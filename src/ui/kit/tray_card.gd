class_name TrayCard
extends Button

## Bottom-tray card: icon, name and ATP cost (214x72), or the dashed SELL variant (150x72).
## Selected: 3 px accent border plus a 4 px outer ring. Unaffordable: muted and not tappable (still visible).

enum Variant { ITEM, SELL }

const ITEM_SIZE: Vector2 = Vector2(214.0, 72.0)
const SELL_SIZE: Vector2 = Vector2(150.0, 72.0)
const RADIUS: float = 24.0
const ICON_PX: float = 34.0
const RING_PX: int = 4

var night: bool = false:
	set = set_night
var variant: Variant = Variant.ITEM:
	set = set_variant
var icon_id: String = "":
	set = set_icon_id
var title: String = "":
	set = set_title
var cost_text: String = "":
	set = set_cost_text
## Second line of the SELL variant ("100% refund" or "Nothing to sell").
var subtitle: String = "":
	set = set_subtitle
var selected: bool = false
var affordable: bool = true:
	set = set_affordable
var config: GameConfig = null

var _style: StyleBoxFlat = null


func _init(v: Variant = Variant.ITEM) -> void:
	variant = v
	KitDraw.make_button_blank(self)
	_refresh_size()
	_refresh_style()


func set_night(value: bool) -> void:
	night = value
	_refresh_style()


func set_variant(value: Variant) -> void:
	variant = value
	_refresh_size()
	_refresh_style()


func set_icon_id(value: String) -> void:
	icon_id = value
	queue_redraw()


func set_title(value: String) -> void:
	title = value
	queue_redraw()


func set_cost_text(value: String) -> void:
	cost_text = value
	queue_redraw()


func set_subtitle(value: String) -> void:
	subtitle = value
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	_refresh_style()


func set_affordable(value: bool) -> void:
	affordable = value
	disabled = not value
	self_modulate = Color(1.0, 1.0, 1.0, 1.0 if value else 0.55)
	queue_redraw()


## Current border width in pixels (3 when selected, 2 otherwise).
func border_width() -> int:
	return _style.border_width_left


func _refresh_size() -> void:
	custom_minimum_size = SELL_SIZE if variant == Variant.SELL else ITEM_SIZE


func _refresh_style() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var accent: Color = pal["accent"] as Color
	var border_w: int = 3 if selected else 2
	var border_col: Color = accent if selected else (pal["panel_border"] as Color)
	var fill: Color = pal["panel"] as Color
	if selected:
		fill = Color(1.0, 1.0, 1.0, 1.0) if not night else (pal["stepper_card"] as Color)
	var shadow: Color = pal["panel_shadow"] as Color
	if variant == Variant.SELL:
		fill = pal["dashed_fill"] as Color
		border_w = 0
		shadow = Color.TRANSPARENT
	_style = KitDraw.make_box(fill, RADIUS, border_w, border_col, shadow, 20, Vector2(0.0, 8.0))
	queue_redraw()


func _draw() -> void:
	var pal: Dictionary = UiPalette.for_theme(night)
	var rect := Rect2(Vector2.ZERO, size)
	_style.draw(get_canvas_item(), rect)
	if variant == Variant.SELL:
		KitDraw.draw_dashed_rounded(self, rect.grow(-1.0), RADIUS, pal["dashed_border"] as Color, 2.0)
		var muted: Color = pal["muted"] as Color
		var ink: Color = pal["ink"] as Color if not disabled else muted
		KitDraw.draw_text_centered(self, title, Rect2(rect.position + Vector2(0.0, -10.0), rect.size), 16, 700, ink)
		KitDraw.draw_text_centered(self, subtitle, Rect2(rect.position + Vector2(0.0, 11.0), rect.size), 12, 400, muted)
		return
	if selected:
		var ring_style: StyleBoxFlat = KitDraw.make_box(Color.TRANSPARENT, RADIUS + float(RING_PX), RING_PX, pal["accent_ring"] as Color)
		ring_style.draw_center = false
		ring_style.draw(get_canvas_item(), rect.grow(float(RING_PX)))
	var pad: float = 13.0 if selected else 14.0
	var icon_rect := Rect2(Vector2(pad, (size.y - ICON_PX) * 0.5), Vector2(ICON_PX, ICON_PX))
	IconPainter.draw_icon(self, icon_id, icon_rect, config)
	var text_left: float = pad + ICON_PX + 12.0
	var name_col: Color = pal["ink"] as Color if affordable else (pal["muted"] as Color)
	var cost_col: Color = pal["accent"] as Color if affordable else (pal["muted"] as Color)
	KitDraw.draw_text_at(self, title, text_left, size.y * 0.5 - 12.0, 16, 700, name_col)
	KitDraw.draw_text_at(self, cost_text, text_left, size.y * 0.5 + 11.0, 14, 800, cost_col)
