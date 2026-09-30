class_name MacrophagePainter
extends ModelPainter

## The Macrophage: an amoeboid body with two pseudopod arms on a cylinder pedestal, translucent nucleus
## lobes, granules and a dark feeding cup on the front. Ported from docs/mockups/canvas/Field.dc.html
## (issue #70, docs/MODEL_PIPELINE_PLAN.md section 5). Units are tiles (T), the anchor is the ground centre
## of the footprint and negative y is up. Nothing is allocated in paint(): colours are cached per call in a
## preallocated array and the lumpy outline is written into preallocated point arrays.
##
## Facing mirrors the placement of the arms, lobes, granules and cup, never the lighting, so the highlight
## stays on the upper left for both facings.

const HEIGHT_T: float = 3.0

# Geometry in tiles, straight from the canvas.
const PED_HALF: float = 1.0
const PED_H: float = 0.75
const ARM_ROOT: Vector2 = Vector2(0.75, -1.5)
## Arm ends (the hand centres) for the left and right arm, facing right.
const ARM_END_L: Vector2 = Vector2(-1.35, -2.15)
const ARM_END_R: Vector2 = Vector2(1.35, -2.05)
const ARM_THICK: float = 0.3
const HAND_R: float = 0.2
const BODY_C: Vector2 = Vector2(0.0, -2.025)
const BODY_R: Vector2 = Vector2(1.0, 0.925)
const BODY_POINTS: int = 24
const BODY_LUMP: float = 0.04
const BODY_LUMP_FREQ: float = 3.0
const BODY_LUMP_PHASE: float = 0.7
const RIM_PX_AT_14: float = 1.5
## The body deflates about its bottom, where it sits on the pedestal.
const BODY_BASE_Y: float = -1.1
## x, y, radius of the two nucleus lobes.
const LOBES: Array[Vector3] = [Vector3(-0.2, -2.2, 0.35), Vector3(0.21, -2.09, 0.31)]
const GRANULES: Array[Vector2] = [Vector2(-0.7, -1.95), Vector2(0.6, -2.05), Vector2(0.78, -2.55), Vector2(-0.72, -2.5), Vector2(0.05, -1.8)]
const GRANULE_R: float = 0.08
const CUP_C: Vector2 = Vector2(0.0, -1.6)
const CUP_W: float = 0.92
const HIGHLIGHT_RECT: Rect2 = Rect2(-0.8, -2.8, 0.7, 0.42)

## Below this tile size the granules and lobes are skipped (issue: detail cutoff).
const LOW_DETAIL_T_PX: float = 10.0
## Below this tile size the body is a smooth two-layer oval without the lumpy outline or rim, the arms are
## plain lines, the hands and cup are one circle each and the pedestal is one quad and one top oval. At
## 23 px (the battle) the 4% lumps are under a pixel. Every draw command costs around 10 to 15 microseconds
## (docs/PERF_BASELINE.md).
const FLAT_T_PX: float = 28.0

const C_PED_BOTTOM: int = 0
const C_PED_L: int = 1
const C_PED_M: int = 2
const C_PED_R: int = 3
const C_PED_TOP: int = 4
const C_PED_TOP_L: int = 5
const C_ARM_L: int = 6
const C_ARM_D: int = 7
const C_HAND_L: int = 8
const C_HAND_M: int = 9
const C_HAND_D: int = 10
const C_BODY_L: int = 11
const C_BODY_M: int = 12
const C_BODY_D: int = 13
const C_RIM: int = 14
const C_LOBE_1: int = 15
const C_LOBE_2: int = 16
const C_GRANULE: int = 17
const C_CUP: int = 18
const C_CUP_INNER: int = 19
const C_HIGHLIGHT: int = 20
const BASE: Array[Color] = [
	Color("#17447a"), Color("#4b7fb8"), Color("#2f5f96"), Color("#1d436f"), Color("#5d93cc"), Color("#a9cdf0"),
	Color("#5aa5f2"), Color("#2a78d0"),
	Color("#cbe4ff"), Color("#3b8fe6"), Color("#153f74"),
	Color("#cbe4ff"), Color("#2e86de"), Color("#153f74"), Color(1.0, 1.0, 1.0, 0.2),
	Color(15.0 / 255.0, 55.0 / 255.0, 120.0 / 255.0, 0.5), Color(15.0 / 255.0, 55.0 / 255.0, 120.0 / 255.0, 0.42),
	Color(1.0, 1.0, 1.0, 0.6),
	Color(8.0 / 255.0, 35.0 / 255.0, 80.0 / 255.0, 0.68), Color(4.0 / 255.0, 18.0 / 255.0, 45.0 / 255.0, 0.6),
	Color(1.0, 1.0, 1.0, 0.5),
]

# Presentation constants, from the animation table in the issue.
const ARM_SWAY_T: float = 0.08
const ARM_SWAY_PERIOD_S: float = 2.0
const GRANULE_DRIFT_T: float = 0.05
const GRANULE_DRIFT_PERIOD_S: float = 2.6
const CUP_H_MIN: float = 0.36
const CUP_H_MAX: float = 0.44
const CUP_PERIOD_S: float = 3.0
const CUP_H_OPEN: float = 0.55
## The cup leans this far toward the target along the aim.
const CUP_AIM_SHIFT_T: float = 0.08
const WINDUP_END: float = 0.4
const RECOVER_START: float = 0.6
const ARM_RAISE_T: float = 0.3
const ARM_SNAP_T: float = 0.15
const DEFLATE_END: float = 0.7
const DEFLATE_SCALE: Vector2 = Vector2(1.2, 0.3)
const DROOP_DEG: float = 70.0
const FADE_FROM_T: float = 0.7
const HIT_WHITE: float = 0.5
const SHAKE_RAD_PER_S: float = 60.0
const SHAKE_T: float = 0.06

# Per-paint scratch. Painters are shared and painting is single threaded, so plain members are safe.
var _white: float = 0.0
var _cols: Array[Color] = []
var _ped_cols: Array[Color] = []
var _body_mesh: PaintKit.RadialMesh = null
var _rim: PackedVector2Array = PackedVector2Array()
## The lumpy outline as unit offsets: cos and sin times the lump factor, built once.
var _lumpy: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_cols.resize(BASE.size())
	_ped_cols.resize(6)
	_rim.resize(BODY_POINTS + 1)
	_lumpy.resize(BODY_POINTS)
	for i: int in range(BODY_POINTS):
		var a: float = TAU * float(i) / float(BODY_POINTS)
		_lumpy[i] = Vector2(cos(a), sin(a)) * (1.0 + BODY_LUMP * sin(BODY_LUMP_FREQ * a + BODY_LUMP_PHASE))
	_body_mesh = PaintKit.RadialMesh.new(_lumpy)
	_prepare(1.0)


func height_tiles() -> float:
	return HEIGHT_T


## Points of the lumpy body outline in tiles, relative to the body centre (for tests and bounds).
func body_outline_tiles() -> PackedVector2Array:
	var out := PackedVector2Array()
	for u: Vector2 in _lumpy:
		out.append(u * BODY_R)
	return out


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	_white = HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0)
	var dead: bool = pose.anim == ModelPose.Anim.DEAD
	_prepare((1.0 - smoothstep(FADE_FROM_T, 1.0, pose.death_t)) if dead else 1.0)
	var aiming: bool = pose.aim.length_squared() > 0.000001
	var right: bool = pose.aim.x >= 0.0 if aiming and absf(pose.aim.x) > 0.000001 else pose.facing_right
	var dir: float = 1.0 if right else -1.0
	var forward: Vector2 = pose.aim if aiming else Vector2(dir, 0.0)
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake

	# Pose-driven values in tiles (y down): arm raise, arm snap along the aim, cup height, droop and deflation.
	var sway: float = ARM_SWAY_T * sin(TAU * pose.time / ARM_SWAY_PERIOD_S)
	var cup_idle: float = lerpf(CUP_H_MIN, CUP_H_MAX, 0.5 + 0.5 * sin(TAU * pose.time / CUP_PERIOD_S))
	var raise: float = 0.0
	var snap: float = 0.0
	var open: float = 0.0
	var droop: float = 0.0
	var deflate: float = 0.0
	match pose.anim:
		ModelPose.Anim.WINDUP:
			open = clampf(pose.attack_t / WINDUP_END, 0.0, 1.0)
			raise = ARM_RAISE_T * open
		ModelPose.Anim.STRIKE:
			open = 1.0
			raise = ARM_RAISE_T
			snap = ARM_SNAP_T
		ModelPose.Anim.RECOVER:
			open = 1.0 - Easing.ease_out_quad((pose.attack_t - RECOVER_START) / (1.0 - RECOVER_START))
			raise = ARM_RAISE_T * open
			snap = ARM_SNAP_T * open
		ModelPose.Anim.DEAD:
			sway = 0.0
			droop = deg_to_rad(DROOP_DEG) * Easing.ease_out_quad(pose.death_t / DEFLATE_END)
			deflate = Easing.ease_out_quad(pose.death_t / DEFLATE_END)
	var cup_h: float = lerpf(cup_idle, CUP_H_OPEN, open)

	var base: Transform2D = Transform2D(0.0, anchor + Vector2(shake_px, 0.0))
	var flat: bool = t < FLAT_T_PX
	ci.draw_set_transform_matrix(base)
	for i: int in range(6):
		_ped_cols[i] = _cols[C_PED_BOTTOM + i]
	PaintKit.pedestal(ci, base, t, PED_HALF, PED_H, _ped_cols, flat)

	# Arms first, so the body covers their roots. The sway is out of phase between the two arms.
	for side: int in range(2):
		var end0: Vector2 = ARM_END_L if side == 0 else ARM_END_R
		var sg: float = -1.0 if side == 0 else 1.0
		var root: Vector2 = Vector2(ARM_ROOT.x * sg * dir, ARM_ROOT.y)
		var end: Vector2 = Vector2(end0.x * dir, end0.y + sway * sg - raise) + forward * snap
		if droop != 0.0:
			end = root + (end - root).rotated(droop * signf(end.x - root.x))
		_paint_arm(ci, t, root, end, flat)

	# The body group deflates about its bottom: wider and flatter.
	var s: Vector2 = Vector2.ONE.lerp(DEFLATE_SCALE, deflate)
	var body_xf: Transform2D = base * Transform2D(Vector2(s.x, 0.0), Vector2(0.0, s.y), Vector2(0.0, BODY_BASE_Y * t * (1.0 - s.y)))
	ci.draw_set_transform_matrix(body_xf)
	_paint_body(ci, body_xf, t, flat)
	if t >= LOW_DETAIL_T_PX:
		for lobe_i: int in range(LOBES.size()):
			var q: Vector3 = LOBES[lobe_i]
			ci.draw_circle(Vector2(q.x * dir, q.y) * t, q.z * t, _cols[C_LOBE_1 + lobe_i])
		for g_i: int in range(GRANULES.size()):
			var g: Vector2 = GRANULES[g_i]
			var a: float = TAU * pose.time / GRANULE_DRIFT_PERIOD_S + float(g_i) * 1.3
			var c: Vector2 = Vector2(g.x * dir, g.y) + Vector2(cos(a), sin(a)) * GRANULE_DRIFT_T
			ci.draw_circle(c * t, GRANULE_R * t, _cols[C_GRANULE])
	var cup_c: Vector2 = CUP_C + Vector2(forward.x * CUP_AIM_SHIFT_T, 0.0)
	PaintKit.oval(ci, body_xf, cup_c, Vector2(CUP_W, cup_h), t, _cols[C_CUP])
	if not flat:
		PaintKit.oval(ci, body_xf, cup_c + Vector2(0.0, cup_h * 0.18), Vector2(CUP_W * 0.7, cup_h * 0.55), t, _cols[C_CUP_INNER])
	PaintKit.oval(ci, body_xf, HIGHLIGHT_RECT.get_center(), HIGHLIGHT_RECT.size, t, _cols[C_HIGHLIGHT])
	ci.draw_set_transform(Vector2.ZERO)


## One pseudopod: a bar from the root to the hand, lighter along its top, and the hand blob.
func _paint_arm(ci: CanvasItem, t: float, root: Vector2, end: Vector2, flat: bool) -> void:
	var w: float = maxf(1.0, ARM_THICK * t)
	if flat:
		ci.draw_line(root * t, end * t, _cols[C_ARM_D].lerp(_cols[C_ARM_L], 0.4), w)
		ci.draw_circle(end * t, HAND_R * t, _cols[C_HAND_M])
		return
	PaintKit.bar(ci, root * t, end * t, w, _cols[C_ARM_D])
	var lift: Vector2 = Vector2(0.0, -ARM_THICK * 0.18) * t
	ci.draw_line(root * t + lift, end * t + lift, _cols[C_ARM_L], w * 0.5)
	PaintKit.sphere(ci, PaintKit.part_rect(Vector2.ZERO, t, end.x - HAND_R, end.y - HAND_R, HAND_R * 2.0, HAND_R * 2.0), _cols[C_HAND_L], _cols[C_HAND_M], _cols[C_HAND_D])


## The amoeboid body: the lumpy outline shaded as one radial-gradient mesh, with an inset rim.
func _paint_body(ci: CanvasItem, xf: Transform2D, t: float, flat: bool) -> void:
	var size: Vector2 = BODY_R * 2.0
	if flat:
		PaintKit.oval(ci, xf, BODY_C, size, t, _cols[C_BODY_D])
		PaintKit.oval(ci, xf, BODY_C + Vector2(-0.04, -0.05) * size, size * 0.86, t, _cols[C_BODY_M])
		return
	var c: Vector2 = BODY_C * t
	var r: Vector2 = BODY_R * t
	var inset: float = maxf(0.5, RIM_PX_AT_14 * t / 14.0 * 0.5)
	var r_rim: Vector2 = r - Vector2(inset, inset)
	for i: int in range(BODY_POINTS):
		_rim[i] = c + _lumpy[i] * r_rim
	_rim[BODY_POINTS] = _rim[0]
	_body_mesh.draw(ci, c, r, _cols[C_BODY_L], _cols[C_BODY_M], _cols[C_BODY_D])
	ci.draw_polyline(_rim, _cols[C_RIM], maxf(1.0, RIM_PX_AT_14 * t / 14.0))


## Fills the per-paint colours: hit flash toward white and an alpha multiplier.
func _prepare(alpha: float) -> void:
	for i: int in range(BASE.size()):
		var c: Color = BASE[i]
		_cols[i] = Color(lerpf(c.r, 1.0, _white), lerpf(c.g, 1.0, _white), lerpf(c.b, 1.0, _white), c.a * alpha)
