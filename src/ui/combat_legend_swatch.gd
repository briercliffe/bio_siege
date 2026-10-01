class_name CombatLegendSwatch
extends Control

## One 28 px swatch of the "Reading the battle" legend on the Infection HUD (mockup 11), drawn in code.

enum Kind { INTENT_LINE, WALL_CRACKS, HEALTH_BAR, ANTIBODY }

const SWATCH_SIZE: Vector2 = Vector2(28.0, 16.0)
const LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.7)
const DASH: float = 4.0
const DASH_GAP: float = 3.0
const CAPSULE_H: float = 12.0
const RING_W: float = 2.0
const BAR_H: float = 6.0
const BAR_TRACK: Color = Color(0.0, 0.0, 0.0, 0.6)
const DOT_RADIUS: float = 5.0
const DOT_FILL: Color = Color("#e8fcff")
const GLOW_RINGS: int = 5
const GLOW_SPREAD: float = 8.0

var kind: Kind = Kind.INTENT_LINE


func _init(k: Kind = Kind.INTENT_LINE) -> void:
	kind = k
	custom_minimum_size = SWATCH_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var w: float = SWATCH_SIZE.x
	var left: float = c.x - w * 0.5
	match kind:
		Kind.INTENT_LINE:
			var x: float = left
			while x < left + w:
				draw_line(Vector2(x, c.y), Vector2(minf(x + DASH, left + w), c.y), LINE_COLOR, 2.0, true)
				x += DASH + DASH_GAP
		Kind.WALL_CRACKS:
			var r := Rect2(left, c.y - CAPSULE_H * 0.5, w, CAPSULE_H)
			KitDraw.draw_box(self, r.grow(RING_W), IconPainter.WALL_RING, -1.0)
			KitDraw.draw_box(self, r, IconPainter.WALL_FILL, -1.0)
			var crack := PackedVector2Array([
				c + Vector2(-6.0, -3.0), c + Vector2(-2.0, 1.0), c + Vector2(1.0, -2.0), c + Vector2(5.0, 3.0),
			])
			draw_polyline(crack, IconPainter.WALL_RING, 1.5, true)
		Kind.HEALTH_BAR:
			var r := Rect2(left, c.y - BAR_H * 0.5, w, BAR_H)
			KitDraw.draw_box(self, r, BAR_TRACK, -1.0)
			KitDraw.draw_box(self, Rect2(r.position, Vector2(w * 0.5, BAR_H)), BattleOverlay.BAR_AMBER, -1.0)
		Kind.ANTIBODY:
			for i: int in range(GLOW_RINGS, 0, -1):
				var t: float = float(i) / float(GLOW_RINGS)
				draw_circle(c, DOT_RADIUS + GLOW_SPREAD * t, Color(BattleOverlay.ANALYSIS_COLOR, 0.22 * (1.0 - t) + 0.04))
			draw_circle(c, DOT_RADIUS, DOT_FILL)
