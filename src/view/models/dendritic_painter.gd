class_name DendriticPainter
extends ModelPainter

## The Dendritic Cell (#171): a star-shaped cell, a rounded #a29bfe body with six long tapering dendrites.
## Units are tiles (T), the anchor is the ground centre of the 2x2 footprint and negative y is up. The model is
## symmetric and never mirrors.
##
## Idle: the dendrites sway a little, each with its own phase from ViewRng so every cell moves differently but
## the same way on every run. Present (pose.anim STRIKE, attack_t 0 to 1): a quick outward pulse ring, sent
## by AnimDriver when the sim emits ANALYSIS_SHARED. A hit flashes the body white. Death shrinks the cell and
## bursts it, like the other structures.

const HEIGHT_T: float = 2.4

const BODY_C: Vector2 = Vector2(0.0, -1.05)
const BODY_R: float = 0.5
const ARMS: int = 6
const ARM_LENGTH: float = 1.15
const ARM_LENGTH_VARY: float = 0.3
const ARM_BASE_HALF: float = 0.17
const ARM_TIP_HALF: float = 0.025
## Arms and the body are squashed vertically so the star lies on the ground plane.
const SQUASH_Y: float = 0.62
const SWAY_RAD: float = 0.12
const SWAY_HZ: float = 0.45
const CURL: float = 0.22
const OUTLINE_GROW: float = 1.12
const HIT_WHITE: float = 0.6
const SHAKE_T: float = 0.04
const SHAKE_RAD_PER_S: float = 90.0
const PRESENT_REACH_T: float = 2.4
const BURST_FROM: float = 0.45

const C_BODY: Color = Color("#a29bfe")
const C_DARK: Color = Color("#5b52b8")
const C_LIGHT: Color = Color("#dcd8ff")
const C_NUCLEUS: Color = Color("#6c5ce7")
const C_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.2)

var _arm: PackedVector2Array = PackedVector2Array()
var _outline: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_arm.resize(7)
	_outline.resize(7)


func height_tiles() -> float:
	return HEIGHT_T


func has_custom_death() -> bool:
	return true


func idle_period_s() -> float:
	return 1.0 / SWAY_HZ


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	var dead: bool = pose.anim == ModelPose.Anim.DEAD
	var d: float = pose.death_t if dead else 0.0
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake
	ci.draw_set_transform_matrix(Transform2D(0.0, anchor + Vector2(shake_px, 0.0)))
	if d < BURST_FROM:
		var u: float = d / BURST_FROM
		_paint_cell(ci, t, pose, 1.0 - 0.45 * Easing.ease_out_quad(u), 1.0 - 0.6 * u)
		if pose.anim == ModelPose.Anim.STRIKE:
			_paint_pulse(ci, anchor, t, pose.attack_t)
	else:
		_paint_burst(ci, t, (d - BURST_FROM) / (1.0 - BURST_FROM))
	ci.draw_set_transform(Vector2.ZERO)


func _paint_cell(ci: CanvasItem, t: float, pose: ModelPose, scale: float, alpha: float) -> void:
	var c: Vector2 = BODY_C * t
	var white: float = HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0)
	var body: Color = C_BODY.lerp(Color.WHITE, white)
	body.a = alpha
	var dark: Color = C_DARK.lerp(Color.WHITE, white)
	dark.a = alpha
	PaintKit.ellipse(ci, Rect2(Vector2(-1.2 * t * scale, -0.3 * t), Vector2(2.4 * t * scale, 0.6 * t)), Color(C_SHADOW, C_SHADOW.a * alpha))
	for i: int in range(ARMS):
		var base_a: float = TAU * float(i) / float(ARMS) + 0.35
		var sway: float = sin(TAU * SWAY_HZ * pose.time + ViewRng.hash01(pose.seed, 10 + i) * TAU) * SWAY_RAD
		var length: float = (ARM_LENGTH + ARM_LENGTH_VARY * ViewRng.hash01(pose.seed, 30 + i)) * scale
		_build_arm(c, t, base_a + sway, length, scale, OUTLINE_GROW)
		ci.draw_colored_polygon(_outline, dark)
		_build_arm(c, t, base_a + sway, length, scale, 1.0)
		ci.draw_colored_polygon(_arm, body)
	# Body: outline, fill, a lighter highlight and the darker nucleus.
	var r: float = BODY_R * t * scale
	PaintKit.ellipse(ci, Rect2(c - Vector2(r, r * SQUASH_Y * 1.6) * OUTLINE_GROW, Vector2(r, r * SQUASH_Y * 1.6) * 2.0 * OUTLINE_GROW), dark)
	PaintKit.ellipse(ci, Rect2(c - Vector2(r, r * SQUASH_Y * 1.6), Vector2(r, r * SQUASH_Y * 1.6) * 2.0), body)
	PaintKit.ellipse(ci, Rect2(c + Vector2(-0.62, -0.78) * r, Vector2(0.7, 0.45) * r), Color(C_LIGHT, 0.7 * alpha))
	PaintKit.ellipse(ci, Rect2(c + Vector2(-0.22, -0.18) * r, Vector2(0.55, 0.4) * r), Color(C_NUCLEUS, 0.55 * alpha))


## Writes one tapering arm (a curved 7-point polygon) into _arm or, when grown, a slightly fatter one into _outline.
func _build_arm(c: Vector2, t: float, angle: float, length: float, scale: float, grow: float) -> void:
	var out: PackedVector2Array = _arm if grow == 1.0 else _outline
	var dir: Vector2 = Vector2(cos(angle), sin(angle) * SQUASH_Y)
	var side: Vector2 = Vector2(-dir.y, dir.x).normalized()
	var base_half: float = ARM_BASE_HALF * grow * t * scale
	var tip_half: float = ARM_TIP_HALF * grow * t * scale
	var start: Vector2 = c + dir * BODY_R * 0.6 * t
	var mid: Vector2 = c + dir * length * 0.55 * t + side * CURL * t * sin(angle * 2.0)
	var tip: Vector2 = c + dir * (length + BODY_R * 0.5) * t
	out[0] = start + side * base_half
	out[1] = mid + side * (base_half * 0.55)
	out[2] = tip + side * tip_half
	out[3] = tip
	out[4] = tip - side * tip_half
	out[5] = mid - side * (base_half * 0.55)
	out[6] = start - side * base_half


## A quick ring that leaves the cell when it shares an analysis. A squashed circle on the ground plane.
func _paint_pulse(ci: CanvasItem, anchor: Vector2, t: float, u: float) -> void:
	var e: float = Easing.ease_out_quad(u)
	var fade: float = 1.0 - clampf(u, 0.0, 1.0)
	ci.draw_set_transform(anchor, 0.0, Vector2(1.0, SQUASH_Y))
	ci.draw_arc(Vector2.ZERO, (0.7 + (PRESENT_REACH_T - 0.7) * e) * t, 0.0, TAU, 32, Color(C_BODY, 0.8 * fade), maxf(1.0, 0.1 * t * fade), true)


func _paint_burst(ci: CanvasItem, t: float, u: float) -> void:
	var e: float = Easing.ease_out_quad(u)
	var fade: float = 1.0 - u
	var c: Vector2 = BODY_C * t
	for k: int in range(ARMS):
		var a: float = TAU * float(k) / float(ARMS) + 0.35
		var dir: Vector2 = Vector2(cos(a), sin(a) * SQUASH_Y)
		ci.draw_line(c + dir * (0.5 + 0.4 * e) * t, c + dir * (0.9 + 1.4 * e) * t, Color(C_BODY, fade), maxf(1.0, 0.1 * t * fade), true)
	ci.draw_arc(c, (0.3 + 1.2 * e) * t, 0.0, TAU, 24, Color(C_NUCLEUS, 0.7 * fade), maxf(1.0, 0.08 * t * fade), true)
