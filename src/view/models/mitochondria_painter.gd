class_name MitochondriaPainter
extends ModelPainter

## The Mitochondria (#171): a bean-shaped organelle in the #e74c3c family with a dark outline, a light rim
## highlight on the upper left and four wavy cristae (the inner folds). Units are tiles (T), the anchor is the
## ground centre of the 3x3 footprint and negative y is up. The model is symmetric and never mirrors.
##
## Idle is a slow pulse. Its scale and a soft glow follow how full the stored-ATP buffer is: the HUD sets
## `stored_fraction` (read-only data for the view). In a battle it stays 0, so the pulse is small. The pulse
## clock is pose.pulse_phase, which AnimDriver holds still under Settings > Reduce flashes. A hit flashes the
## body white; death shrinks the body and bursts it into a ring and short shards.

const HEIGHT_T: float = 2.0

const BODY_C: Vector2 = Vector2(0.0, -0.95)
const BODY_R: Vector2 = Vector2(1.45, 0.82)
const BODY_POINTS: int = 32
## How far the top of the bean dips toward its middle, in unit radii, and how wide the dent is.
const DENT_DEPTH: float = 0.3
const DENT_WIDTH: float = 0.16
const OUTLINE_GROW: float = 1.07
const CRISTAE: int = 4
const CRISTA_POINTS: int = 7
const CRISTA_SPAN: float = 0.62
const CRISTA_WAVE: float = 0.1
const RIM_POINTS: int = 9
const SHADOW_ALPHA: float = 0.22

## Pulse: the scale swing is PULSE_BASE plus PULSE_STORED times the stored fraction.
const PULSE_BASE: float = 0.012
const PULSE_STORED: float = 0.04
const GLOW_ALPHA_MAX: float = 0.4
const HIT_WHITE: float = 0.6
const SHAKE_T: float = 0.04
const SHAKE_RAD_PER_S: float = 90.0

## Death: the body is gone by BURST_FROM, the burst runs from there to 1.
const BURST_FROM: float = 0.45
const BURST_SHARDS: int = 7
const BURST_REACH_T: float = 2.0

const C_BODY: Color = Color("#e74c3c")
const C_DARK: Color = Color("#8e2a20")
const C_LIGHT: Color = Color("#f5b7b1")
const C_CRISTA: Color = Color("#a93226")
const C_GLOW: Color = Color("#ff9d8f")
const C_SHADOW: Color = Color(0.0, 0.0, 0.0, 1.0)

## 0..1: how full the base's Mitochondria are. Set by the HUD in Living Base; reset to 0 for a battle.
var stored_fraction: float = 0.0

var _unit: PackedVector2Array = PackedVector2Array()
var _pts: PackedVector2Array = PackedVector2Array()
var _crista: PackedVector2Array = PackedVector2Array()
var _rim: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_unit.resize(BODY_POINTS)
	_pts.resize(BODY_POINTS)
	for i: int in range(BODY_POINTS):
		var a: float = TAU * float(i) / float(BODY_POINTS)
		var x: float = cos(a)
		var y: float = sin(a)
		if y < 0.0:
			y += DENT_DEPTH * exp(-x * x / DENT_WIDTH) * -y
		_unit[i] = Vector2(x, y)
	_crista.resize(CRISTA_POINTS)
	_rim.resize(RIM_POINTS)


func height_tiles() -> float:
	return HEIGHT_T


func has_custom_death() -> bool:
	return true


func idle_period_s() -> float:
	return 3.0


func reset() -> void:
	stored_fraction = 0.0


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	var dead: bool = pose.anim == ModelPose.Anim.DEAD
	var d: float = pose.death_t if dead else 0.0
	var f: float = clampf(stored_fraction, 0.0, 1.0)
	var pulse: float = sin(TAU * pose.pulse_phase)
	var scale: float = 1.0 + (PULSE_BASE + PULSE_STORED * f) * pulse
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake
	ci.draw_set_transform_matrix(Transform2D(0.0, anchor + Vector2(shake_px, 0.0)))

	if d < BURST_FROM:
		var u: float = d / BURST_FROM
		var body_scale: float = scale * (1.0 - 0.5 * Easing.ease_out_quad(u))
		var alpha: float = 1.0 - u * 0.6
		_paint_body(ci, t, pose, body_scale, alpha, f, pulse)
	else:
		_paint_burst(ci, t, (d - BURST_FROM) / (1.0 - BURST_FROM))
	ci.draw_set_transform(Vector2.ZERO)


func _paint_body(ci: CanvasItem, t: float, pose: ModelPose, scale: float, alpha: float, f: float, pulse: float) -> void:
	var c: Vector2 = BODY_C * t
	var r: Vector2 = BODY_R * t * scale
	# Ground shadow.
	PaintKit.ellipse(ci, Rect2(Vector2(-r.x * 0.95, -r.y * 0.25 + 0.05 * t), Vector2(r.x * 1.9, r.y * 0.5)), Color(C_SHADOW, SHADOW_ALPHA * alpha))
	# Outline, then the body on top.
	for i: int in range(BODY_POINTS):
		_pts[i] = c + _unit[i] * r * OUTLINE_GROW
	ci.draw_colored_polygon(_pts, Color(C_DARK, alpha))
	for i: int in range(BODY_POINTS):
		_pts[i] = c + _unit[i] * r
	var body: Color = C_BODY.lerp(Color.WHITE, HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0))
	body.a = alpha
	ci.draw_colored_polygon(_pts, body)
	# A soft inner glow that follows the stored ATP.
	var glow: float = GLOW_ALPHA_MAX * f * (0.55 + 0.45 * pulse) * alpha
	if glow > 0.01:
		PaintKit.ellipse(ci, Rect2(c - r * 0.55, r * 1.1), Color(C_GLOW, glow))
	# Cristae: wavy folds across the body, kept inside its outline.
	var line_w: float = maxf(1.0, 0.07 * t)
	var crista_col: Color = Color(C_CRISTA, 0.7 * alpha)
	for k: int in range(CRISTAE):
		var x: float = lerpf(-CRISTA_SPAN, CRISTA_SPAN, float(k) / float(CRISTAE - 1)) * r.x
		var half: float = r.y * 0.62 * (1.0 - 0.35 * absf(x) / r.x)
		for j: int in range(CRISTA_POINTS):
			var v: float = float(j) / float(CRISTA_POINTS - 1)
			var wave: float = sin(v * TAU * 1.5 + float(k) * 1.3) * CRISTA_WAVE * t
			_crista[j] = Vector2(x + wave, c.y - half + 2.0 * half * v + 0.08 * r.y)
		ci.draw_polyline(_crista, crista_col, line_w, true)
	# Light rim highlight on the upper left.
	for j: int in range(RIM_POINTS):
		var a: float = lerpf(PI * 1.08, PI * 1.62, float(j) / float(RIM_POINTS - 1))
		var p: Vector2 = Vector2(cos(a), sin(a))
		if p.y < 0.0:
			p.y += DENT_DEPTH * exp(-p.x * p.x / DENT_WIDTH) * -p.y
		_rim[j] = c + p * r * 0.9
	ci.draw_polyline(_rim, Color(C_LIGHT, 0.55 * alpha), maxf(1.0, 0.09 * t), true)


## A ring and short shards flying outward, fading as u goes 0 to 1.
func _paint_burst(ci: CanvasItem, t: float, u: float) -> void:
	var e: float = Easing.ease_out_quad(u)
	var fade: float = 1.0 - u
	var c: Vector2 = BODY_C * t
	ci.draw_arc(c, BURST_REACH_T * 0.6 * t * e + 0.2 * t, 0.0, TAU, 28, Color(C_BODY, 0.8 * fade), maxf(1.0, 0.14 * t * fade), true)
	for k: int in range(BURST_SHARDS):
		var a: float = TAU * float(k) / float(BURST_SHARDS) + 0.4
		var dir: Vector2 = Vector2(cos(a), sin(a) * 0.55)
		var from: Vector2 = c + dir * (0.4 + 0.5 * e) * t
		var to: Vector2 = c + dir * (0.7 + BURST_REACH_T * 0.5 * e) * t
		ci.draw_line(from, to, Color(C_CRISTA, fade), maxf(1.0, 0.1 * t * fade), true)
