class_name PhagePainter
extends ModelPainter

## The Bacteriophage, a lunar-lander shaped T4 phage: hexagonal head, ridged tail sheath, baseplate and four
## splayed legs. Ported from docs/mockups/canvas/Field.dc.html (issue #68, docs/MODEL_PIPELINE_PLAN.md
## section 5). Units are tiles (T), the anchor is the ground centre and negative y is up. Nothing is
## allocated in paint(): colours are cached per call in a preallocated array and polygons go through PaintKit.
##
## The model is left/right symmetric, so facing never mirrors the transform: it only signs the gait, the
## head dip and the sheath. That keeps the light on the upper left for both facings and the head a clean
## hexagon (the canvas's per-part flip cut dark wedges out of it).

const HEIGHT_T: float = 3.0

# Geometry in tiles, straight from the canvas.
const SHADOW_RECT: Rect2 = Rect2(-0.95, -0.2, 1.9, 0.7)
const BACK_HIP: Vector2 = Vector2(0.05, -0.9)
const BACK_KNEE: Vector2 = Vector2(0.62, -0.8)
const BACK_FOOT: Vector2 = Vector2(0.98, -0.12)
const BACK_THICK: float = 0.1
const BACK_PAD: Vector2 = Vector2(0.32, 0.14)
const FRONT_HIP: Vector2 = Vector2(0.05, -0.76)
const FRONT_KNEE: Vector2 = Vector2(0.5, -0.42)
const FRONT_FOOT: Vector2 = Vector2(0.82, 0.02)
const FRONT_THICK: float = 0.13
const FRONT_PAD: Vector2 = Vector2(0.4, 0.18)
const PAD_DROP: float = 0.03
const UNDER_RECT: Rect2 = Rect2(-0.5, -0.72, 1.0, 0.42)
const PLATE_RECT: Rect2 = Rect2(-0.5, -0.94, 1.0, 0.44)
const PLATE_LIGHT_RECT: Rect2 = Rect2(-0.36, -0.9, 0.5, 0.26)
const SHEATH_RECT: Rect2 = Rect2(-0.17, -1.6, 0.34, 0.75)
const SHEATH_MID_AT: float = 0.45
const STRIPE_AT: Array[float] = [0.2, 0.5, 0.8]
const STRIPE_PX_AT_14: float = 2.0
const COLLAR_RECT: Rect2 = Rect2(-0.32, -1.72, 0.64, 0.24)
const HEAD_RECT: Rect2 = Rect2(-0.56, -3.0, 1.12, 1.4)
const HEAD_PIVOT: Vector2 = Vector2(0.0, -1.6)
const HEAD_MID_AT: float = 0.55
const FACET_LIGHT_RECT: Rect2 = Rect2(-0.56, -3.0, 0.56, 1.4)
const FACET_DARK_RECT: Rect2 = Rect2(0.0, -3.0, 0.56, 1.4)
const FACET_LIGHT_01: PackedVector2Array = [Vector2(1.0, 0.0), Vector2(0.0, 0.25), Vector2(0.0, 0.75), Vector2(1.0, 1.0)]
const FACET_DARK_01: PackedVector2Array = [Vector2(0.0, 0.0), Vector2(1.0, 0.25), Vector2(1.0, 0.75), Vector2(0.0, 1.0)]
const HIGHLIGHT_RECT: Rect2 = Rect2(-0.2, -2.9, 0.4, 0.2)
## Two dark lines across the cracked head, as 0..1 points of the head rect.
const CRACK_A: Array[Vector2] = [Vector2(0.2, 0.2), Vector2(0.62, 0.6)]
const CRACK_B: Array[Vector2] = [Vector2(0.72, 0.12), Vector2(0.4, 0.82)]
const CRACK_WIDTH_PX_AT_14: float = 1.5

## Below this tile size the sheath stripes, facets and highlight are skipped (issue: detail cutoff).
const LOW_DETAIL_T_PX: float = 10.0
## Below this tile size the legs are plain polylines, the stripes, pads, underside, highlight and the
## baseplate shading are skipped and the sheath is one flat rect. Every draw command costs around 10 to 15
## microseconds (docs/PERF_BASELINE.md), and the 200-unit bench runs at 23 px per tile.
const FLAT_T_PX: float = 28.0

# Colour slots. BASE holds the canvas colours; _cols holds them after the swarm lightness shift, the hit
# flash and the alpha of the current call.
const C_SHADOW: int = 0
const C_BACK_LEG: int = 1
const C_BACK_PAD: int = 2
const C_UNDER: int = 3
const C_PLATE_L: int = 4
const C_PLATE_M: int = 5
const C_FRONT_LEG: int = 6
const C_FRONT_PAD: int = 7
const C_SHEATH_L: int = 8
const C_SHEATH_M: int = 9
const C_SHEATH_D: int = 10
const C_STRIPE: int = 11
const C_COLLAR: int = 12
const C_HEAD_L: int = 13
const C_HEAD_M: int = 14
const C_HEAD_D: int = 15
const C_FACET_L: int = 16
const C_FACET_D: int = 17
const C_HIGHLIGHT: int = 18
const C_GLOW: int = 19
const C_CRACK: int = 20
const BASE: Array[Color] = [
	Color(0.0, 0.0, 0.0, 0.35), Color("#7a3f08"), Color("#5a2c04"), Color("#b5590c"), Color("#ffcf99"),
	Color("#e67e22"), Color("#c9701a"), Color("#8a4a0c"), Color("#f8b878"), Color("#e67e22"), Color("#a85a10"),
	Color(0.0, 0.0, 0.0, 0.2), Color("#d9721c"), Color("#ffd6a6"), Color("#e67e22"), Color("#9d5210"),
	Color(1.0, 1.0, 1.0, 0.24), Color(0.0, 0.0, 0.0, 0.16), Color(1.0, 1.0, 1.0, 0.55), Color("#fff1d6"),
	Color("#5a2c04"),
]

# Presentation constants, from the animation table in the issue.
const IDLE_PERIOD_S: float = 1.4
const IDLE_BOB: float = 0.04
const IDLE_FOOT: float = 0.02
const IDLE_FOOT_PHASE: float = 1.0
const MOVE_FOOT: float = 0.12
const MOVE_LIFT: float = 0.1
const MOVE_BOB: float = 0.05
const CROUCH: float = 0.15
const HEAD_DIP_DEG: float = 6.0
const WINDUP_END: float = 0.4
const RECOVER_START: float = 0.6
const SHEATH_DRIVE: float = 0.25
const GLOW_RADIUS: float = 0.4
const GLOW_Y: float = -0.25
const SPLAY_DEG: float = 35.0
const CRACK_FROM_T: float = 0.3
const FADE_FROM_T: float = 0.5
const HIT_WHITE: float = 0.7
const SHAKE_RAD_PER_S: float = 60.0
const SHAKE_T: float = 0.08
const SIZE_VARIANCE: float = 0.08
const LIGHT_VARIANCE: float = 0.08

# Per-paint scratch. Painters are shared and painting is single threaded, so plain members are safe.
var _lum: float = 1.0
var _white: float = 0.0
var _cols: Array[Color] = []
var _leg: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _init() -> void:
	_cols.resize(BASE.size())
	_prepare(1.0)


func height_tiles() -> float:
	return HEIGHT_T


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	var size_k: float = 1.0 + (ViewRng.hash01(pose.seed, 2) - 0.5) * SIZE_VARIANCE
	_lum = 1.0 + (ViewRng.hash01(pose.seed, 3) - 0.5) * LIGHT_VARIANCE
	_white = HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0)
	var dir: float = 1.0 if pose.facing_right else -1.0
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake
	var dead: bool = pose.anim == ModelPose.Anim.DEAD
	_prepare((1.0 - smoothstep(FADE_FROM_T, 1.0, pose.death_t)) if dead else 1.0)

	# Pose-driven values, in tiles (y down): body drop, sheath drop, head dip, glow alpha, foot x offsets,
	# foot lift per pair and leg splay.
	var body_dy: float = 0.0
	var sheath_dy: float = 0.0
	var head_rot: float = 0.0
	var glow: float = 0.0
	var foot_b: float = 0.0
	var foot_f: float = 0.0
	var lift_b: float = 0.0
	var lift_f: float = 0.0
	var splay: float = 0.0
	match pose.anim:
		ModelPose.Anim.MOVE:
			var s: float = sin(TAU * pose.gait_phase)
			foot_f = MOVE_FOOT * s * dir
			foot_b = -foot_f
			lift_f = -MOVE_LIFT * maxf(0.0, s)
			lift_b = -MOVE_LIFT * maxf(0.0, -s)
			body_dy = -MOVE_BOB * absf(s)
		ModelPose.Anim.WINDUP:
			var k: float = clampf(pose.attack_t / WINDUP_END, 0.0, 1.0)
			body_dy = CROUCH * k
			head_rot = deg_to_rad(HEAD_DIP_DEG) * k * dir
		ModelPose.Anim.STRIKE:
			body_dy = CROUCH
			head_rot = deg_to_rad(HEAD_DIP_DEG) * dir
			sheath_dy = SHEATH_DRIVE
			glow = 1.0
		ModelPose.Anim.RECOVER:
			var back: float = 1.0 - Easing.ease_out_quad((pose.attack_t - RECOVER_START) / (1.0 - RECOVER_START))
			body_dy = CROUCH * back
			head_rot = deg_to_rad(HEAD_DIP_DEG) * back * dir
			sheath_dy = SHEATH_DRIVE * back
			glow = back
		ModelPose.Anim.DEAD:
			splay = deg_to_rad(SPLAY_DEG) * pose.death_t
		_:
			var w: float = TAU * pose.time / IDLE_PERIOD_S
			body_dy = IDLE_BOB * sin(w)
			foot_b = IDLE_FOOT * sin(w + IDLE_FOOT_PHASE)
			foot_f = -foot_b

	var origin: Vector2 = anchor + Vector2(shake_px, 0.0)
	var base: Transform2D = Transform2D(0.0, origin).scaled_local(Vector2(size_k, size_k))
	var low: bool = t < FLAT_T_PX

	ci.draw_set_transform_matrix(base)
	_oval(ci, base, SHADOW_RECT.get_center(), SHADOW_RECT.size, t, _cols[C_SHADOW])

	# Back legs (drawn first), then the injection glow and the baseplate.
	for i: int in range(2):
		var sg: float = float(i * 2 - 1)
		var back_foot: Vector2 = _paint_leg(ci, t, sg, BACK_HIP, BACK_KNEE, BACK_FOOT, BACK_THICK, body_dy, foot_b, lift_b, splay, _cols[C_BACK_LEG])
		if not low:
			_oval(ci, base, back_foot + Vector2(0.0, PAD_DROP), BACK_PAD, t, _cols[C_BACK_PAD])
	if not low:
		_oval(ci, base, UNDER_RECT.get_center() + Vector2(0.0, body_dy), UNDER_RECT.size, t, _cols[C_UNDER])
	if glow > 0.0:
		_paint_glow(ci, t, glow, low)
	_oval(ci, base, PLATE_RECT.get_center() + Vector2(0.0, body_dy), PLATE_RECT.size, t, _cols[C_PLATE_M])
	if not low:
		_oval(ci, base, PLATE_LIGHT_RECT.get_center() + Vector2(0.0, body_dy), PLATE_LIGHT_RECT.size, t, _cols[C_PLATE_L])

	for i: int in range(2):
		var sg: float = float(i * 2 - 1)
		var front_foot: Vector2 = _paint_leg(ci, t, sg, FRONT_HIP, FRONT_KNEE, FRONT_FOOT, FRONT_THICK, body_dy, foot_f, lift_f, splay, _cols[C_FRONT_LEG])
		if not low:
			_oval(ci, base, front_foot + Vector2(0.0, PAD_DROP), FRONT_PAD, t, _cols[C_FRONT_PAD])

	# Tail sheath and collar drive down together on the strike.
	var dy: float = body_dy + sheath_dy
	var sheath: Rect2 = PaintKit.part_rect(Vector2.ZERO, t, SHEATH_RECT.position.x, SHEATH_RECT.position.y + dy, SHEATH_RECT.size.x, SHEATH_RECT.size.y)
	if low:
		ci.draw_rect(sheath, _cols[C_SHEATH_M])
	else:
		var split: float = sheath.position.x + sheath.size.x * SHEATH_MID_AT
		PaintKit.horizontal_gradient_rect(ci, Rect2(sheath.position.x, sheath.position.y, split - sheath.position.x, sheath.size.y), _cols[C_SHEATH_L], _cols[C_SHEATH_M])
		PaintKit.horizontal_gradient_rect(ci, Rect2(split, sheath.position.y, sheath.end.x - split, sheath.size.y), _cols[C_SHEATH_M], _cols[C_SHEATH_D])
		var stripe_w: float = maxf(1.0, STRIPE_PX_AT_14 * t / 14.0)
		for f: float in STRIPE_AT:
			var y: float = sheath.position.y + sheath.size.y * f
			ci.draw_line(Vector2(sheath.position.x, y), Vector2(sheath.end.x, y), _cols[C_STRIPE], stripe_w)
	_oval(ci, base, COLLAR_RECT.get_center() + Vector2(0.0, dy), COLLAR_RECT.size, t, _cols[C_COLLAR])

	# Head: rotated about the top of the collar. The hex is one gradient polygon, the facets are the two
	# halves of it, light on the left and dark on the right.
	var pivot: Vector2 = (HEAD_PIVOT + Vector2(0.0, body_dy)) * t
	var head_xf: Transform2D = base * Transform2D(head_rot, pivot - pivot.rotated(head_rot))
	ci.draw_set_transform_matrix(head_xf)
	var head: Rect2 = PaintKit.part_rect(Vector2.ZERO, t, HEAD_RECT.position.x, HEAD_RECT.position.y + body_dy, HEAD_RECT.size.x, HEAD_RECT.size.y)
	PaintKit.hex_gradient(ci, head, _cols[C_HEAD_L], _cols[C_HEAD_M], _cols[C_HEAD_D], HEAD_MID_AT)
	if t >= LOW_DETAIL_T_PX:
		PaintKit.clip_poly(ci, PaintKit.part_rect(Vector2.ZERO, t, FACET_LIGHT_RECT.position.x, FACET_LIGHT_RECT.position.y + body_dy, FACET_LIGHT_RECT.size.x, FACET_LIGHT_RECT.size.y), FACET_LIGHT_01, _cols[C_FACET_L])
		PaintKit.clip_poly(ci, PaintKit.part_rect(Vector2.ZERO, t, FACET_DARK_RECT.position.x, FACET_DARK_RECT.position.y + body_dy, FACET_DARK_RECT.size.x, FACET_DARK_RECT.size.y), FACET_DARK_01, _cols[C_FACET_D])
	if not low:
		PaintKit.ellipse(ci, PaintKit.part_rect(Vector2.ZERO, t, HIGHLIGHT_RECT.position.x, HIGHLIGHT_RECT.position.y + body_dy, HIGHLIGHT_RECT.size.x, HIGHLIGHT_RECT.size.y), _cols[C_HIGHLIGHT])
	if dead and pose.death_t > CRACK_FROM_T:
		var w_px: float = maxf(1.0, CRACK_WIDTH_PX_AT_14 * t / 14.0)
		ci.draw_line(head.position + CRACK_A[0] * head.size, head.position + CRACK_A[1] * head.size, _cols[C_CRACK], w_px)
		ci.draw_line(head.position + CRACK_B[0] * head.size, head.position + CRACK_B[1] * head.size, _cols[C_CRACK], w_px)
	ci.draw_set_transform(Vector2.ZERO)


## One leg: hip to knee to foot. The feet stay on the ground while the hip drops with the body and the knee
## follows halfway. `splay` rotates knee and foot outward about the hip (death). Returns the foot in tiles,
## so the pad sits on it.
func _paint_leg(ci: CanvasItem, t: float, sg: float, hip: Vector2, knee: Vector2, foot: Vector2, thick: float, body_dy: float, foot_x: float, lift: float, splay: float, col: Color) -> Vector2:
	var h: Vector2 = Vector2(hip.x * sg, hip.y + body_dy)
	var k: Vector2 = Vector2(knee.x * sg + foot_x * 0.5, knee.y + body_dy * 0.5 + lift * 0.5)
	var f: Vector2 = Vector2(foot.x * sg + foot_x, foot.y + lift)
	if splay != 0.0:
		k = h + (k - h).rotated(-sg * splay)
		f = h + (f - h).rotated(-sg * splay)
	var width: float = maxf(1.0, thick * t)
	if t < FLAT_T_PX:
		_leg[0] = h * t
		_leg[1] = k * t
		_leg[2] = f * t
		ci.draw_polyline(_leg, col, width)
	else:
		PaintKit.bar(ci, h * t, k * t, width, col)
		PaintKit.bar(ci, k * t, f * t, width, col)
	return f


## Radial glow under the baseplate: three stacked circles, brightest at the centre.
func _paint_glow(ci: CanvasItem, t: float, amount: float, low: bool) -> void:
	var c: Vector2 = Vector2(0.0, GLOW_Y * t)
	if low:
		ci.draw_circle(c, GLOW_RADIUS * 0.75 * t, _ca(C_GLOW, 0.5 * amount))
		return
	ci.draw_circle(c, GLOW_RADIUS * t, _ca(C_GLOW, 0.22 * amount))
	ci.draw_circle(c, GLOW_RADIUS * 0.68 * t, _ca(C_GLOW, 0.4 * amount))
	ci.draw_circle(c, GLOW_RADIUS * 0.34 * t, _ca(C_GLOW, 0.85 * amount))


## A filled ellipse as a circle under a squashed transform, so it takes the engine's circle fast path.
## `centre` and `size` are in tiles. The base transform is restored afterwards.
func _oval(ci: CanvasItem, base: Transform2D, centre: Vector2, size: Vector2, t: float, col: Color) -> void:
	ci.draw_set_transform_matrix(base * Transform2D(Vector2(1.0, 0.0), Vector2(0.0, size.y / size.x), centre * t))
	ci.draw_circle(Vector2.ZERO, size.x * 0.5 * t, col)
	ci.draw_set_transform_matrix(base)


func _ca(slot: int, alpha: float) -> Color:
	var c: Color = _cols[slot]
	return Color(c.r, c.g, c.b, alpha * c.a)


## Fills the per-paint colours: swarm lightness shift, hit flash toward white and an alpha multiplier.
func _prepare(alpha: float) -> void:
	for i: int in range(BASE.size()):
		var c: Color = BASE[i]
		var w: float = 0.0 if i == C_SHADOW else _white
		_cols[i] = Color(
			lerpf(minf(c.r * _lum, 1.0), 1.0, w),
			lerpf(minf(c.g * _lum, 1.0), 1.0, w),
			lerpf(minf(c.b * _lum, 1.0), 1.0, w),
			c.a * alpha)
