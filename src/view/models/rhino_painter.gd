class_name RhinoPainter
extends ModelPainter

## The Rhinovirus: an icosahedral capsid with surface spikes, ported from docs/mockups/canvas/Field.dc.html
## (issue #67, docs/MODEL_PIPELINE_PLAN.md section 5). Units are tiles (T), the anchor is the ground centre
## and negative y is up. Nothing is allocated in paint(): every colour is a const and the shared polygon
## scratch arrays live in PaintKit.
##
## The capsid is nearly round, so facing only moves the lunge and the roll direction. The transform is never
## mirrored, which keeps the light on the upper left for both facings.

const HEIGHT_T: float = 1.25
const BODY_CY: float = -0.62
const SHADOW_RECT: Rect2 = Rect2(-0.62, -0.14, 1.24, 0.5)
const BODY_RADIUS: float = 0.48
const SPIKE_COUNT: int = 8
const SPIKE_SIZE: float = 0.22
const SPIKE_RING: float = 0.6
const SPIKE_BACK_SIN_MAX: float = 0.2
const KNOB_RING: float = 0.4
const KNOB_SIZE: float = 0.17
const KNOB_ANGLES_DEG: Array[float] = [40.0, 90.0, 140.0]
const FACET_RECT: Rect2 = Rect2(-0.3, -1.02, 0.6, 0.66)
const GLOSS_RECT: Rect2 = Rect2(-0.3, -1.06, 0.3, 0.17)
const RIM_WIDTH_PX: float = 1.5
const RIM_SEGMENTS: int = 24

## Below this tile size the facet, knobs, rim and highlight are skipped: the silhouette carries the read.
const LOW_DETAIL_T_PX: float = 10.0
## Below this tile size spikes and knobs are one flat circle instead of a four-layer sphere. At this size a
## knob is under 5 px and the shading is not visible, but each layer is a draw command (docs/PERF_BASELINE.md).
const FLAT_BALL_T_PX: float = 28.0

const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.35)
const SPIKE_LIGHT: Color = Color("#d9ffe9")
const SPIKE_MID: Color = Color("#3ee08a")
const SPIKE_DARK: Color = Color("#127a40")
const BODY_LIGHT: Color = Color("#d0fae2")
const BODY_MID: Color = Color("#2ecc71")
const BODY_DARK: Color = Color("#0f6e39")
const RIM: Color = Color(1.0, 1.0, 1.0, 0.16)
const FACET: Color = Color(1.0, 1.0, 1.0, 0.17)
const KNOB_LIGHT: Color = Color("#eafff2")
const KNOB_MID: Color = Color("#57e69a")
const KNOB_DARK: Color = Color("#178a4b")
const GLOSS: Color = Color(1.0, 1.0, 1.0, 0.6)
const PUFF: Color = Color(1.0, 1.0, 1.0, 0.5)

# Presentation constants, from the animation table in the issue.
const IDLE_PERIOD_S: float = 1.2
const IDLE_SQUASH: float = 0.05
const IDLE_RING_PULSE: float = 0.06
const IDLE_RING_PHASE: float = 1.3
const HOP_T: float = 0.25
const LAND_ZONE: float = 0.1
const LAND_SQUASH: Vector2 = Vector2(1.12, 0.88)
const CROUCH_SQUASH: Vector2 = Vector2(1.12, 0.84)
const WINDUP_END: float = 0.4
const RECOVER_START: float = 0.6
const LUNGE_T: float = 0.35
const STRIKE_RING: float = 0.72
const STRIKE_KNOB_SCALE: float = 1.3
const HIT_WHITE: float = 0.7
const SHAKE_RAD_PER_S: float = 60.0
const SHAKE_T: float = 0.08
const DEATH_BODY_HIDDEN_T: float = 0.15
const FRAGMENTS: int = 6
const FRAGMENT_SIZE: float = 0.18
const FRAGMENT_DIST_T: float = 0.9
const PUFF_R0: float = 0.3
const PUFF_R1: float = 1.0
const SIZE_VARIANCE: float = 0.08
const LIGHT_VARIANCE: float = 0.08

# Per-paint scratch. Painters are shared and painting is single threaded, so plain members are safe.
var _lum: float = 1.0
var _white: float = 0.0
var _c_shadow: Color = SHADOW
var _c_spike_l: Color = SPIKE_LIGHT
var _c_spike_m: Color = SPIKE_MID
var _c_spike_d: Color = SPIKE_DARK
var _c_body_l: Color = BODY_LIGHT
var _c_body_m: Color = BODY_MID
var _c_body_d: Color = BODY_DARK
var _c_rim: Color = RIM
var _c_facet: Color = FACET
var _c_knob_l: Color = KNOB_LIGHT
var _c_knob_m: Color = KNOB_MID
var _c_knob_d: Color = KNOB_DARK
var _c_gloss: Color = GLOSS
var _c_puff: Color = PUFF


func height_tiles() -> float:
	return HEIGHT_T


func has_custom_death() -> bool:
	return true


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	var size_k: float = 1.0 + (ViewRng.hash01(pose.seed, 2) - 0.5) * SIZE_VARIANCE
	_lum = 1.0 + (ViewRng.hash01(pose.seed, 3) - 0.5) * LIGHT_VARIANCE
	_white = HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0)
	_prepare(1.0)
	var dir: float = 1.0 if pose.facing_right else -1.0
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake
	var dead: bool = pose.anim == ModelPose.Anim.DEAD

	# Pose-driven values: lunge (tiles), ring radius (tiles), knob scale, squash, hop (px), roll angle.
	var lunge: float = 0.0
	var ring: float = SPIKE_RING
	var knob_k: float = 1.0
	var sq: Vector2 = Vector2.ONE
	var lift: float = 0.0
	var roll: float = 0.0
	match pose.anim:
		ModelPose.Anim.MOVE:
			var g: float = pose.gait_phase
			lift = -HOP_T * absf(sin(PI * g)) * t
			if g < LAND_ZONE or g > 1.0 - LAND_ZONE:
				sq = LAND_SQUASH
			roll = g * PI * dir
		ModelPose.Anim.WINDUP:
			sq = Vector2.ONE.lerp(CROUCH_SQUASH, clampf(pose.attack_t / WINDUP_END, 0.0, 1.0))
		ModelPose.Anim.STRIKE:
			lunge = LUNGE_T
			ring = STRIKE_RING
			knob_k = STRIKE_KNOB_SCALE
		ModelPose.Anim.RECOVER:
			var back: float = 1.0 - Easing.ease_out_quad((pose.attack_t - RECOVER_START) / (1.0 - RECOVER_START))
			lunge = LUNGE_T * back
			ring = lerpf(SPIKE_RING, STRIKE_RING, back)
			knob_k = lerpf(1.0, STRIKE_KNOB_SCALE, back)
		ModelPose.Anim.DEAD:
			pass
		_:
			var w: float = TAU * pose.time / IDLE_PERIOD_S
			var sy: float = 1.0 + IDLE_SQUASH * sin(w)
			sq = Vector2(1.0 / sy, sy)
			ring = SPIKE_RING * (1.0 + IDLE_RING_PULSE * sin(w + IDLE_RING_PHASE))

	var origin: Vector2 = anchor + Vector2(lunge * t * dir + shake_px, 0.0)

	# Ground shadow: follows the lunge and shake, never squashes or hops.
	if dead:
		_prepare(1.0 - pose.death_t)
	# A circle under a squashed transform, so the shadow takes the engine's circle fast path.
	ci.draw_set_transform(origin, 0.0, Vector2(size_k, size_k * SHADOW_RECT.size.y / SHADOW_RECT.size.x))
	ci.draw_circle(SHADOW_RECT.get_center() * Vector2(t, t / (SHADOW_RECT.size.y / SHADOW_RECT.size.x)), SHADOW_RECT.size.x * 0.5 * t, _c_shadow)

	if dead:
		_paint_death(ci, pose.death_t, t, ring)
	else:
		ci.draw_set_transform(origin + Vector2(0.0, lift * size_k), 0.0, Vector2(sq.x * size_k, sq.y * size_k))
		_paint_body(ci, t, ring, knob_k, roll)
	ci.draw_set_transform(Vector2.ZERO)


func _paint_body(ci: CanvasItem, t: float, ring: float, knob_k: float, roll: float) -> void:
	# Back spikes, upper half only. The index filter is fixed so spikes never pop while the ring rolls.
	for i: int in range(SPIKE_COUNT):
		var a: float = float(i) * PI / 4.0
		if sin(a) > SPIKE_BACK_SIN_MAX:
			continue
		a += roll
		_spike(ci, t, Vector2(cos(a), sin(a)) * ring, SPIKE_SIZE)

	var body: Rect2 = PaintKit.part_rect(Vector2.ZERO, t, -BODY_RADIUS, BODY_CY - BODY_RADIUS, BODY_RADIUS * 2.0, BODY_RADIUS * 2.0)
	if t < FLAT_BALL_T_PX:
		# Two layers: the dark limb and a lit disc offset toward the light.
		ci.draw_circle(Vector2(0.0, BODY_CY * t), BODY_RADIUS * t, _c_body_d)
		ci.draw_circle(Vector2(-0.03 * BODY_RADIUS * 2.0 * t, (BODY_CY - 0.04 * BODY_RADIUS * 2.0) * t), BODY_RADIUS * 0.88 * t, _c_body_m)
	else:
		PaintKit.sphere(ci, body, _c_body_l, _c_body_m, _c_body_d)
	if t < LOW_DETAIL_T_PX:
		return
	if t < FLAT_BALL_T_PX:
		# 10 to 28 px: keep the gloss; the knobs, rim and facet are skipped (perf, see docs/PERF_BASELINE.md).
		ci.draw_circle(GLOSS_RECT.get_center() * t, GLOSS_RECT.size.y * 0.5 * t, _c_gloss)
		return

	ci.draw_arc(Vector2(0.0, BODY_CY * t), BODY_RADIUS * t - RIM_WIDTH_PX * 0.5, 0.0, TAU, RIM_SEGMENTS, _c_rim, RIM_WIDTH_PX)
	PaintKit.hex(ci, PaintKit.part_rect(Vector2.ZERO, t, FACET_RECT.position.x, FACET_RECT.position.y, FACET_RECT.size.x, FACET_RECT.size.y), _c_facet)
	var size: float = KNOB_SIZE * knob_k
	for d: float in KNOB_ANGLES_DEG:
		var a: float = deg_to_rad(d) + roll
		PaintKit.sphere(ci, PaintKit.part_rect(Vector2.ZERO, t, cos(a) * KNOB_RING - size * 0.5, BODY_CY + sin(a) * KNOB_RING - size * 0.5, size, size),
			_c_knob_l, _c_knob_m, _c_knob_d)
	PaintKit.ellipse(ci, PaintKit.part_rect(Vector2.ZERO, t, GLOSS_RECT.position.x, GLOSS_RECT.position.y, GLOSS_RECT.size.x, GLOSS_RECT.size.y), _c_gloss)


func _spike(ci: CanvasItem, t: float, offset: Vector2, size: float) -> void:
	if t < FLAT_BALL_T_PX:
		ci.draw_circle(Vector2(offset.x, BODY_CY + offset.y) * t, size * 0.5 * t, _c_spike_m)
	else:
		PaintKit.sphere(ci, PaintKit.part_rect(Vector2.ZERO, t, offset.x - size * 0.5, BODY_CY + offset.y - size * 0.5, size, size),
			_c_spike_l, _c_spike_m, _c_spike_d)


## Pop: six fragments fly out along i * 60 degrees while a white puff grows and fades.
func _paint_death(ci: CanvasItem, death_t: float, t: float, ring: float) -> void:
	if death_t <= DEATH_BODY_HIDDEN_T:
		_prepare(1.0)
		_paint_body(ci, t, ring, 1.0, 0.0)
	_prepare(1.0 - death_t)
	var dist: float = death_t * FRAGMENT_DIST_T
	for i: int in range(FRAGMENTS):
		var a: float = float(i) * PI / 3.0
		_spike(ci, t, Vector2(cos(a), sin(a)) * dist, FRAGMENT_SIZE)
	var r: float = lerpf(PUFF_R0, PUFF_R1, death_t)
	PaintKit.ellipse(ci, PaintKit.part_rect(Vector2.ZERO, t, -r, BODY_CY - r, r * 2.0, r * 2.0), _c_puff)


## Fills the per-paint colours: swarm lightness shift, hit flash toward white and an alpha multiplier.
func _prepare(alpha: float) -> void:
	_c_shadow = _shade(SHADOW, alpha, false)
	_c_spike_l = _shade(SPIKE_LIGHT, alpha)
	_c_spike_m = _shade(SPIKE_MID, alpha)
	_c_spike_d = _shade(SPIKE_DARK, alpha)
	_c_body_l = _shade(BODY_LIGHT, alpha)
	_c_body_m = _shade(BODY_MID, alpha)
	_c_body_d = _shade(BODY_DARK, alpha)
	_c_rim = _shade(RIM, alpha)
	_c_facet = _shade(FACET, alpha)
	_c_knob_l = _shade(KNOB_LIGHT, alpha)
	_c_knob_m = _shade(KNOB_MID, alpha)
	_c_knob_d = _shade(KNOB_DARK, alpha)
	_c_gloss = _shade(GLOSS, alpha)
	_c_puff = _shade(PUFF, alpha)


func _shade(c: Color, alpha: float, flash: bool = true) -> Color:
	var w: float = _white if flash else 0.0
	return Color(
		lerpf(minf(c.r * _lum, 1.0), 1.0, w),
		lerpf(minf(c.g * _lum, 1.0), 1.0, w),
		lerpf(minf(c.b * _lum, 1.0), 1.0, w),
		c.a * alpha)
