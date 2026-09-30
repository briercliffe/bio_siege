class_name IconPainter
extends RefCounted

## Flat HUD icons drawn in code. Colours come from the JSON `placeholder.color` when a
## GameConfig is supplied, otherwise from the mockup values.

const ICON_IDS: Array[String] = [
	"mucous_wall", "macrophage", "b_cell", "nucleus", "rhinovirus", "bacteriophage", "staphylococcus", "atp",
]

const WALL_FILL: Color = Color("#dccf9f")
const WALL_RING: Color = Color("#7d6f48")
const STAPH: Color = Color("#f1c40f")

const LANDER: Array[Vector2] = [
	Vector2(0.28, 0.06), Vector2(0.72, 0.06), Vector2(0.88, 0.46), Vector2(0.72, 0.58),
	Vector2(0.92, 0.94), Vector2(0.80, 0.94), Vector2(0.60, 0.66), Vector2(0.40, 0.66),
	Vector2(0.20, 0.94), Vector2(0.08, 0.94), Vector2(0.28, 0.58), Vector2(0.12, 0.46),
]
const HEXAGON: Array[Vector2] = [
	Vector2(0.5, 0.0), Vector2(1.0, 0.25), Vector2(1.0, 0.75), Vector2(0.5, 1.0), Vector2(0.0, 0.75), Vector2(0.0, 0.25),
]
const TRIANGLE: Array[Vector2] = [Vector2(0.5, 0.0), Vector2(1.0, 0.92), Vector2(0.0, 0.92)]


static func draw_icon(ci: CanvasItem, id: String, rect: Rect2, config: GameConfig = null) -> void:
	match id:
		"mucous_wall":
			_wall(ci, rect, _json_color(config, id, WALL_FILL))
		"macrophage":
			_sphere(ci, rect, Color("#b4d8fb"), _json_color(config, id, Color("#2e86de")), Color("#18508f"))
		"b_cell":
			_poly(ci, TRIANGLE, rect, Color("#d9f9ff"), _json_color(config, id, Color("#48dbfb")), Color("#1391b8"))
		"nucleus":
			_sphere(ci, rect, Color("#d9b8e8"), _json_color(config, id, Color("#8e44ad")), Color("#5a2874"))
		"rhinovirus":
			_sphere(ci, rect, Color("#c4f7db"), _json_color(config, id, Color("#2ecc71")), Color("#178a4b"))
		"bacteriophage":
			_poly(ci, LANDER, rect, Color("#f8b878"), _json_color(config, id, Color("#e67e22")), Color("#b0600f"))
		"staphylococcus":
			_staph(ci, rect, _json_color(config, id, STAPH))
		"atp":
			_poly(ci, HEXAGON, rect, Color("#ffe680"), Color("#f1c40f"), Color("#f1c40f"))


static func _json_color(config: GameConfig, id: String, fallback: Color) -> Color:
	if config == null:
		return fallback
	if config.structures.has(id):
		return (config.structures[id] as StructureDef).placeholder_color
	if config.pathogens.has(id):
		return (config.pathogens[id] as PathogenDef).placeholder_color
	return fallback


static func _wall(ci: CanvasItem, rect: Rect2, fill: Color) -> void:
	var w: float = minf(rect.size.x, 34.0)
	var h: float = w * (14.0 / 34.0)
	var r := Rect2(rect.get_center() - Vector2(w, h) * 0.5, Vector2(w, h))
	KitDraw.draw_box(ci, r, WALL_RING, -1.0)
	KitDraw.draw_box(ci, r.grow(-2.0), fill, -1.0)


## Four-circle radial-gradient trick: dark base, then smaller lighter discs toward the highlight.
static func _sphere(ci: CanvasItem, rect: Rect2, light: Color, mid: Color, dark: Color) -> void:
	var r: float = minf(rect.size.x, rect.size.y) * 0.5
	var c: Vector2 = rect.get_center()
	ci.draw_circle(c, r, dark)
	ci.draw_circle(c + Vector2(-0.06, -0.08) * r, r * 0.88, dark.lerp(mid, 0.6))
	ci.draw_circle(c + Vector2(-0.14, -0.18) * r, r * 0.68, mid)
	ci.draw_circle(c + Vector2(-0.24, -0.3) * r, r * 0.36, mid.lerp(light, 0.65))


static func _poly(ci: CanvasItem, unit: Array[Vector2], rect: Rect2, light: Color, mid: Color, dark: Color) -> void:
	var pts := PackedVector2Array()
	for u: Vector2 in unit:
		pts.append(rect.position + u * rect.size)
	var stops: Array[Color] = [light, mid, dark]
	KitDraw.draw_banded_polygon(ci, pts, rect, stops)


static func _staph(ci: CanvasItem, rect: Rect2, col: Color) -> void:
	var r: float = minf(rect.size.x, rect.size.y) * 0.27
	var c: Vector2 = rect.get_center()
	var centers: Array[Vector2] = [
		c + Vector2(0.0, -0.65) * r,
		c + Vector2(-0.95, 0.75) * r,
		c + Vector2(0.95, 0.75) * r,
	]
	for p: Vector2 in centers:
		ci.draw_circle(p, r, col.darkened(0.35))
		ci.draw_circle(p, r - 1.5, col)
