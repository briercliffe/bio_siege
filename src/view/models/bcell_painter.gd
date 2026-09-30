class_name BCellPainter
extends ModelPainter

## The B-Cell: three stepped two-tone pyramid tiers on a cylinder pedestal, topped by a glowing Y-shaped
## antibody inside a halo. The tallest defense. Ported from docs/mockups/canvas/Field.dc.html (issue #70,
## docs/MODEL_PIPELINE_PLAN.md section 5). Units are tiles (T), the anchor is the ground centre of the
## footprint and negative y is up. Nothing is allocated in paint(): colours are cached per call in a
## preallocated array and the tier triangles are written into preallocated point arrays.
##
## Pose timing is the B-Cell's own (AnimDriver): WINDUP is the charge (attack_t 0 to 1 over the last
## TOWER_CHARGE_TICKS of cooldown), STRIKE is the shot and RECOVER the recoil (attack_t 0 to 1). The model is
## symmetric: facing never mirrors it, the aim only tilts the antibody.

const HEIGHT_T: float = 4.3

# Geometry in tiles, straight from the canvas.
const PED_HALF: float = 0.95
const PED_H: float = 0.7
## Width, height and base y of each tier, bottom first.
const TIERS: Array[Vector3] = [Vector3(1.7, 1.0, -1.1), Vector3(1.25, 0.9, -1.9), Vector3(0.85, 0.8, -2.6)]
## The tier's outer corners sit at this fraction of its height (clip-path 0 86% and 100% 86%).
const TIER_SHOULDER: float = 0.86
## The tiers compress about the pedestal top.
const TIER_BASE_Y: float = -1.1
const HALO_C: Vector2 = Vector2(0.0, -3.9)
const HALO_D: float = 1.4
const HALO_D_CHARGED: float = 1.8
## The canvas halo is a radial gradient that is transparent from 70% of its radius.
const HALO_FILL: float = 0.7
const Y_PIVOT: Vector2 = Vector2(0.0, -3.35)
const Y_FORK: Vector2 = Vector2(0.0, -3.75)
const Y_ARM: Vector2 = Vector2(0.4, -4.15)
const STEM_THICK: float = 0.16
const ARM_THICK: float = 0.15
const TIP_R: float = 0.13
const JOINT_C: Vector2 = Vector2(0.0, -3.54)
const JOINT_R: float = 0.14
## The canvas glow is an 8k px box-shadow: two rings of rising radius and falling alpha.
const GLOW_GROW_T: Array[float] = [0.3, 0.2, 0.1]
const GLOW_SHARE: Array[float] = [0.2, 0.3, 0.45]
const HALO_RINGS: int = 5
const HALO_RING_SHARE: float = 0.3

## Below this tile size the halo and the Y glow are skipped (issue: detail cutoff).
const LOW_DETAIL_T_PX: float = 10.0
## Below this tile size the pedestal is one quad and one top oval, the Y is plain lines without round caps
## and each glow is one circle. Every draw command costs around 10 to 15 microseconds
## (docs/PERF_BASELINE.md), and the battle runs at 23 px per tile.
const FLAT_T_PX: float = 28.0

const C_PED_BOTTOM: int = 0
const C_TIER_L1_TOP: int = 6
const C_TIER_L1_BOT: int = 7
const C_TIER_R1_TOP: int = 8
const C_TIER_R1_BOT: int = 9
const C_TIER_L2_TOP: int = 10
const C_TIER_L2_BOT: int = 11
const C_TIER_R2_TOP: int = 12
const C_TIER_R2_BOT: int = 13
const C_HALO: int = 14
const C_Y: int = 15
const C_JOINT: int = 16
const C_GLOW: int = 17
const BASE: Array[Color] = [
	Color("#1d6b80"), Color("#5fb8cc"), Color("#3a95ab"), Color("#25748a"), Color("#7cc8dc"), Color("#c3f0fa"),
	Color("#e4fbff"), Color("#7ee7ff"), Color("#3fc9ea"), Color("#178faf"),
	Color("#f2feff"), Color("#93eeff"), Color("#55d6f3"), Color("#1ba0c4"),
	Color("#48dbfb"), Color("#e8fcff"), Color("#ffffff"), Color("#48dbfb"),
]

# Presentation constants, from the animation table in the issue.
const SPIN_PERIOD_S: float = 3.0
const HALO_PERIOD_S: float = 1.5
const HALO_ALPHA_LO: float = 0.3
const HALO_ALPHA_HI: float = 0.5
const GLOW_ALPHA: float = 0.45
const CHARGED_ALPHA: float = 0.9
const AIM_MAX_DEG: float = 25.0
const RECOIL_SCALE_Y: float = 0.9
## Death: each tier's collapse window starts this far after the one above it and lasts TIER_FALL_SPAN.
const TIER_FALL_STEP: float = 0.25
const TIER_FALL_SPAN: float = 0.4
const TIER_DROP_T: float = 0.6
const Y_FALL_END: float = 0.45
const Y_FALL_DEG: float = 80.0
const Y_FALL_T: float = 2.2
const PED_FADE_FROM: float = 0.7
const HIT_WHITE: float = 0.5
const SHAKE_RAD_PER_S: float = 60.0
const SHAKE_T: float = 0.06

# Per-paint scratch. Painters are shared and painting is single threaded, so plain members are safe.
var _white: float = 0.0
var _cols: Array[Color] = []
var _ped_cols: Array[Color] = []
var _tri: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _tri_cols: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
var _glow: PaintKit.GlowMesh = PaintKit.GlowMesh.new()
var _halo: PaintKit.GlowMesh = PaintKit.GlowMesh.new()
## Peak alpha factors: what the canvas's stacked rings add up to where they all overlap.
var _glow_peak: float = 0.0
var _halo_peak: float = 0.0


func _init() -> void:
	_cols.resize(BASE.size())
	_ped_cols.resize(6)
	_glow_peak = PaintKit.stacked_alpha(GLOW_SHARE)
	var halo_shares: Array[float] = []
	halo_shares.resize(HALO_RINGS)
	halo_shares.fill(HALO_RING_SHARE)
	_halo_peak = PaintKit.stacked_alpha(halo_shares)
	_prepare(1.0)


func height_tiles() -> float:
	return HEIGHT_T


## Tilt of the antibody toward a screen-space aim direction, in radians: the angle of the aim from the
## vertical, folded so a target in front or behind leans the same side, clamped to +-AIM_MAX_DEG. Positive
## leans right. Zero for no target.
static func aim_angle(aim: Vector2) -> float:
	if aim.length_squared() < 0.000001:
		return 0.0
	var lim: float = deg_to_rad(AIM_MAX_DEG)
	return clampf(atan2(aim.x, absf(aim.y)), -lim, lim)


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	_white = HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0)
	_prepare(1.0)
	var dead: bool = pose.anim == ModelPose.Anim.DEAD
	var d: float = pose.death_t if dead else 0.0
	var dir: float = 1.0 if pose.facing_right else -1.0
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake

	var charge: float = 0.0
	var squash_y: float = 1.0
	match pose.anim:
		ModelPose.Anim.WINDUP:
			charge = clampf(pose.attack_t, 0.0, 1.0)
		ModelPose.Anim.STRIKE:
			charge = 1.0
			squash_y = RECOIL_SCALE_Y
		ModelPose.Anim.RECOVER:
			var k: float = clampf(pose.attack_t, 0.0, 1.0)
			charge = 1.0 - Easing.ease_out_quad(k)
			squash_y = lerpf(RECOIL_SCALE_Y, 1.0, Easing.ease_out_back(k))

	var base: Transform2D = Transform2D(0.0, anchor + Vector2(shake_px, 0.0))
	var flat: bool = t < FLAT_T_PX
	ci.draw_set_transform_matrix(base)
	var ped_alpha: float = 1.0 - smoothstep(PED_FADE_FROM, 1.0, d)
	for i: int in range(6):
		_ped_cols[i] = _ca(C_PED_BOTTOM + i, ped_alpha)
	PaintKit.pedestal(ci, base, t, PED_HALF, PED_H, _ped_cols, flat)

	# Tiers, bottom first, compressed about the pedestal top on the recoil. On death they drop and fade from
	# the top down.
	var tiers_xf: Transform2D = base * Transform2D(Vector2(1.0, 0.0), Vector2(0.0, squash_y), Vector2(0.0, TIER_BASE_Y * t * (1.0 - squash_y)))
	ci.draw_set_transform_matrix(tiers_xf)
	for i: int in range(TIERS.size()):
		var drop: float = 0.0
		var alpha: float = 1.0
		if dead:
			var u: float = tier_fall(i, d)
			drop = TIER_DROP_T * Easing.ease_in_quad(u)
			alpha = 1.0 - u
		if alpha > 0.0:
			var light: int = C_TIER_L2_TOP if i == 1 else C_TIER_L1_TOP
			var dark: int = C_TIER_R2_TOP if i == 1 else C_TIER_R1_TOP
			_paint_tier(ci, t, TIERS[i], drop, light, dark, alpha)

	# Halo, then the antibody: rotated toward the target about the stem base, arms spinning while idle.
	var halo_a: float = lerpf(HALO_ALPHA_LO, HALO_ALPHA_HI, 0.5 + 0.5 * sin(TAU * pose.time / HALO_PERIOD_S))
	halo_a = lerpf(halo_a, CHARGED_ALPHA, charge)
	var glow_a: float = lerpf(GLOW_ALPHA, CHARGED_ALPHA, charge)
	var y_alpha: float = 1.0
	# aim_lock eases the tilt in and the spinning arms shut as a target is acquired, and back as it is lost.
	var lock: float = Easing.ease_out_quad(clampf(pose.aim_lock, 0.0, 1.0))
	var tilt: float = aim_angle(pose.aim) * lock
	var fall: Vector2 = Vector2.ZERO
	if dead:
		var u: float = clampf(d / Y_FALL_END, 0.0, 1.0)
		tilt = deg_to_rad(Y_FALL_DEG) * Easing.ease_in_quad(u) * dir
		fall = Vector2(0.0, Y_FALL_T * Easing.ease_in_quad(u))
		y_alpha = 1.0 - u
		halo_a *= 1.0 - u
		glow_a *= 1.0 - u
	if y_alpha <= 0.0:
		ci.draw_set_transform(Vector2.ZERO)
		return
	var top_drop: float = TIER_DROP_T * Easing.ease_in_quad(tier_fall(TIERS.size() - 1, d)) if dead else 0.0
	var pivot: Vector2 = (Y_PIVOT + fall + Vector2(0.0, top_drop)) * t
	var y_xf: Transform2D = tiers_xf * Transform2D(tilt, pivot - pivot.rotated(tilt))
	ci.draw_set_transform_matrix(y_xf)
	var off: Vector2 = (fall + Vector2(0.0, top_drop)) * t
	var detail: bool = t >= LOW_DETAIL_T_PX
	if detail:
		var hd: float = lerpf(HALO_D, HALO_D_CHARGED, charge)
		_paint_halo(ci, HALO_C * t + off, hd * 0.5 * HALO_FILL * t, _ca(C_HALO, halo_a), flat)
	var spin: float = 1.0 if dead else lerpf(cos(TAU * pose.time / SPIN_PERIOD_S), 1.0, lock)
	var y_col: Color = _ca(C_Y, y_alpha)
	var fork: Vector2 = Y_FORK * t + off
	var tip_l: Vector2 = Vector2(-Y_ARM.x * spin, Y_ARM.y) * t + off
	var tip_r: Vector2 = Vector2(Y_ARM.x * spin, Y_ARM.y) * t + off
	var stem_w: float = maxf(1.0, STEM_THICK * t)
	var arm_w: float = maxf(1.0, ARM_THICK * t)
	if flat:
		ci.draw_line(Y_PIVOT * t + off, fork, y_col, stem_w)
		ci.draw_line(fork, tip_l, y_col, arm_w)
		ci.draw_line(fork, tip_r, y_col, arm_w)
	else:
		PaintKit.bar(ci, Y_PIVOT * t + off, fork, stem_w, y_col)
		PaintKit.bar(ci, fork, tip_l, arm_w, y_col)
		PaintKit.bar(ci, fork, tip_r, arm_w, y_col)
	var glow: Color = _ca(C_GLOW, glow_a)
	if detail:
		_paint_glow(ci, tip_l, TIP_R * t, t, glow, flat)
		_paint_glow(ci, tip_r, TIP_R * t, t, glow, flat)
		_paint_glow(ci, JOINT_C * t + off, JOINT_R * t, t, glow, flat)
	ci.draw_circle(tip_l, TIP_R * t, y_col)
	ci.draw_circle(tip_r, TIP_R * t, y_col)
	ci.draw_circle(JOINT_C * t + off, JOINT_R * t, _ca(C_JOINT, y_alpha))
	ci.draw_set_transform(Vector2.ZERO)


## 0..1 progress of tier i's collapse at death_t `d`: the top tier (i = 2) goes first.
static func tier_fall(i: int, d: float) -> float:
	var start: float = float(TIERS.size() - 1 - i) * TIER_FALL_STEP
	return clampf((d - start) / TIER_FALL_SPAN, 0.0, 1.0)


## One tier: the light left half and the dark right half, each a vertical gradient triangle.
func _paint_tier(ci: CanvasItem, t: float, tier: Vector3, drop: float, light: int, dark: int, alpha: float) -> void:
	var w: float = tier.x * t
	var h: float = tier.y * t
	var bottom: float = (tier.z + drop) * t
	var top: float = bottom - h
	var shoulder: float = top + h * TIER_SHOULDER
	_tri[0] = Vector2(0.0, top)
	_tri[1] = Vector2(0.0, bottom)
	_tri[2] = Vector2(-w * 0.5, shoulder)
	_tri_cols[0] = _ca(light, alpha)
	_tri_cols[1] = _ca(light + 1, alpha)
	_tri_cols[2] = _tri_cols[0].lerp(_tri_cols[1], TIER_SHOULDER)
	ci.draw_polygon(_tri, _tri_cols)
	_tri[2] = Vector2(w * 0.5, shoulder)
	_tri_cols[0] = _ca(dark, alpha)
	_tri_cols[1] = _ca(dark + 1, alpha)
	_tri_cols[2] = _tri_cols[0].lerp(_tri_cols[1], TIER_SHOULDER)
	ci.draw_polygon(_tri, _tri_cols)


## The box-shadow glow around a core of radius `r` px: a smooth mesh fading to 0 (one circle when flat).
func _paint_glow(ci: CanvasItem, c: Vector2, r: float, t: float, col: Color, flat: bool) -> void:
	if col.a <= 0.0:
		return
	if flat:
		ci.draw_circle(c, r + GLOW_GROW_T[2] * t, Color(col.r, col.g, col.b, col.a * 0.5))
		return
	_glow.draw(ci, c, r, r + GLOW_GROW_T[0] * t, Color(col.r, col.g, col.b, col.a * _glow_peak))


## The radial halo: a smooth mesh from the centre fading to 0 at `r` px (one circle when flat).
func _paint_halo(ci: CanvasItem, c: Vector2, r: float, col: Color, flat: bool) -> void:
	if col.a <= 0.0:
		return
	if flat:
		ci.draw_circle(c, r * 0.75, Color(col.r, col.g, col.b, col.a * 0.6))
		return
	_halo.draw(ci, c, 0.0, r, Color(col.r, col.g, col.b, col.a * _halo_peak))


func _ca(slot: int, alpha: float) -> Color:
	var c: Color = _cols[slot]
	return Color(c.r, c.g, c.b, c.a * alpha)


## Fills the per-paint colours: hit flash toward white and an alpha multiplier.
func _prepare(alpha: float) -> void:
	for i: int in range(BASE.size()):
		var c: Color = BASE[i]
		_cols[i] = Color(lerpf(c.r, 1.0, _white), lerpf(c.g, 1.0, _white), lerpf(c.b, 1.0, _white), c.a * alpha)
