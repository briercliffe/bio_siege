class_name NucleusPainter
extends ModelPainter

## The Nucleus: a shaded dome with a bright nucleolus and surface pores, circled by a tilted envelope ring
## whose back half passes behind the dome and front half in front of it. Ported from
## docs/mockups/canvas/Field.dc.html (issue #70, docs/MODEL_PIPELINE_PLAN.md section 5). The JSON placeholder
## shape (rounded_square) is ignored: the Nucleus is always this dome (plan section 10, question 5). Units are
## tiles (T), the anchor is the ground centre of the footprint and negative y is up. Nothing is allocated in
## paint(): colours are cached per call in a preallocated array and the ring halves are written into
## preallocated point arrays. The plinth under the dome is the ground plate GridView and UnitLayer draw.
##
## The model is symmetric and never mirrors.

const HEIGHT_T: float = 4.1

# Geometry in tiles, straight from the canvas.
const RING_C: Vector2 = Vector2(0.0, -1.9)
const RING_R: Vector2 = Vector2(2.6, 0.85)
const RING_PX_AT_14: float = 3.0
## Points per ring half, ends included.
const RING_HALF_POINTS: int = 17
const DOME_C: Vector2 = Vector2(0.0, -1.95)
const DOME_R: float = 2.05
const DOME_RIM_PX_AT_14: float = 2.5
## The dome is over 2 tiles in radius, so its outline needs more points than PaintKit's 24.
const DOME_POINTS: int = 48
## x1, y1, x2, y2 of each surface streak, and its thickness and alpha.
const STREAKS: Array[Vector4] = [Vector4(-0.95, -2.95, -0.2, -3.35), Vector4(0.3, -3.5, 1.15, -2.95), Vector4(-1.3, -1.95, -0.55, -1.65)]
const STREAK_THICK: Array[float] = [0.14, 0.12, 0.12]
const STREAK_ALPHA: Array[float] = [0.22, 0.2, 0.2]
const NUCLEOLUS_C: Vector2 = Vector2(-0.3, -2.4)
const NUCLEOLUS_R: float = 0.75
## The canvas nucleolus glow is a 10k px box-shadow: two rings of rising radius and falling alpha.
const NUCLEOLUS_GLOW_T: Array[float] = [0.45, 0.3, 0.15]
const NUCLEOLUS_GLOW_SHARE: Array[float] = [0.15, 0.25, 0.35]
const PORES: Array[Vector2] = [Vector2(-1.3, -1.25), Vector2(-0.5, -0.85), Vector2(0.4, -0.75), Vector2(1.2, -1.15), Vector2(1.6, -1.85), Vector2(-1.65, -1.95)]
const PORE_R: float = 0.12
const PORE_RING_PX_AT_14: float = 1.2
const HIGHLIGHT_RECT: Rect2 = Rect2(-1.45, -3.65, 1.2, 0.7)
## Three crack lines across the dome on death, as offsets from the dome centre.
const CRACKS: Array[Vector4] = [Vector4(-0.2, -1.2, -1.1, -0.1), Vector4(0.3, -0.9, 1.3, 0.2), Vector4(0.0, -0.1, 0.4, 1.3)]
const CRACK_PX_AT_14: float = 2.0

## Below this tile size the pores and streaks are skipped (issue: detail cutoff).
const LOW_DETAIL_T_PX: float = 10.0
## Below this tile size the dome and nucleolus are two circles each instead of a radial-gradient mesh, the dome rim, pore rings
## and the outer glow ring are skipped. Every draw command costs around 10 to 15 microseconds
## (docs/PERF_BASELINE.md), and the battle runs at 23 px per tile.
const FLAT_T_PX: float = 28.0

const C_RING: int = 0
const C_DOME_L: int = 1
const C_DOME_M: int = 2
const C_DOME_D: int = 3
const C_DOME_RIM: int = 4
const C_STREAK: int = 5
const C_NUC_L: int = 6
const C_NUC_M: int = 7
const C_NUC_D: int = 8
const C_NUC_GLOW: int = 9
const C_PORE: int = 10
const C_PORE_RING: int = 11
const C_HIGHLIGHT: int = 12
const C_CRACK: int = 13
const C_FRAGMENT_L: int = 14
const C_FRAGMENT_D: int = 15
const C_PUFF: int = 16
const BASE: Array[Color] = [
	Color(236.0 / 255.0, 208.0 / 255.0, 248.0 / 255.0, 0.8),
	Color("#e6c6f2"), Color("#8e44ad"), Color("#4b2263"), Color(1.0, 1.0, 1.0, 0.2),
	Color(1.0, 1.0, 1.0, 1.0),
	Color("#fbeefe"), Color("#c88be0"), Color("#8e44ad"), Color(236.0 / 255.0, 208.0 / 255.0, 248.0 / 255.0, 0.55),
	Color(40.0 / 255.0, 10.0 / 255.0, 60.0 / 255.0, 0.55), Color(236.0 / 255.0, 208.0 / 255.0, 248.0 / 255.0, 0.4),
	Color(1.0, 1.0, 1.0, 0.45),
	Color("#2a0d3a"),
	Color("#b36ad0"), Color("#5e2a7e"),
	Color(200.0 / 255.0, 140.0 / 255.0, 230.0 / 255.0, 0.6),
]

# Presentation constants, from the animation table in the issue.
const RING_PERIOD_S: float = 3.0
const RING_WOBBLE: float = 0.08
const PULSE_AMOUNT: float = 0.05
const PULSE_RATE_FULL_HZ: float = 0.5
const PULSE_RATE_EMPTY_HZ: float = 2.0
const HIT_RING_ALPHA: float = 0.3
## hit_t decays from 1 over AnimDriver.HIT_DECAY_TICKS (4); above this it is the first two ticks.
const HIT_FLICKER_ABOVE: float = 0.5
const RING_DETACH_END: float = 0.5
const RING_RISE_T: float = 1.5
const CRACK_FROM: float = 0.2
const CRACK_TO: float = 0.6
const BURST_FROM: float = 0.7
const FRAGMENTS: int = 10
const FRAGMENT_SIZE: float = 0.4
const FRAGMENT_DIST_T: float = 3.0
const FRAGMENT_DEPTH: float = 0.55
const FRAGMENT_ARC_T: float = 1.0
const PUFF_R0: float = 1.2
const PUFF_R1: float = 3.0
const HIT_WHITE: float = 0.4
const SHAKE_RAD_PER_S: float = 60.0
const SHAKE_T: float = 0.06

# Per-paint scratch. Painters are shared and painting is single threaded, so plain members are safe.
var _white: float = 0.0
var _base: Transform2D = Transform2D.IDENTITY
var _cols: Array[Color] = []
var _half: PackedVector2Array = PackedVector2Array()
var _sphere: PaintKit.RadialMesh = PaintKit.RadialMesh.new(PackedVector2Array(), DOME_POINTS)
var _nucleolus: PaintKit.RadialMesh = PaintKit.RadialMesh.new()
## Unit points of the back (upper) half of the ring, left to right over the top; the front half is the
## same points with y negated.
var _unit_back: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_cols.resize(BASE.size())
	_half.resize(RING_HALF_POINTS)
	_unit_back.resize(RING_HALF_POINTS)
	for i: int in range(RING_HALF_POINTS):
		var a: float = PI + PI * float(i) / float(RING_HALF_POINTS - 1)
		_unit_back[i] = Vector2(cos(a), sin(a))
	_prepare()


func height_tiles() -> float:
	return HEIGHT_T


## Nucleolus pulse rate in Hz: 0.5 at full health rising to 2.0 at 0 HP, so the pulse quickens as it is hurt.
static func pulse_rate(hp_frac: float) -> float:
	return PULSE_RATE_FULL_HZ + (PULSE_RATE_EMPTY_HZ - PULSE_RATE_FULL_HZ) * (1.0 - clampf(hp_frac, 0.0, 1.0))


## Ring height (the full vertical diameter) in tiles at a view time: the tilted ring appears to orbit.
static func ring_height(time_s: float) -> float:
	return RING_R.y * 2.0 * (1.0 + RING_WOBBLE * sin(TAU * time_s / RING_PERIOD_S))


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	_white = HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0)
	_prepare()
	var dead: bool = pose.anim == ModelPose.Anim.DEAD
	var d: float = pose.death_t if dead else 0.0
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake
	_base = Transform2D(0.0, anchor + Vector2(shake_px, 0.0))
	var flat: bool = t < FLAT_T_PX
	ci.draw_set_transform_matrix(_base)

	# The ring detaches on death: it rises and fades over the first half.
	var ring_alpha: float = HIT_RING_ALPHA if pose.hit_t > HIT_FLICKER_ABOVE else 1.0
	var ring_c: Vector2 = RING_C
	if dead:
		var u: float = clampf(d / RING_DETACH_END, 0.0, 1.0)
		ring_alpha = 1.0 - u
		ring_c.y -= RING_RISE_T * Easing.ease_out_quad(u)
	var ring_r: Vector2 = Vector2(RING_R.x, ring_height(pose.time) * 0.5)
	var ring_w: float = maxf(1.0, RING_PX_AT_14 * t / 14.0)
	var ring_col: Color = _ca(C_RING, ring_alpha)
	if ring_alpha > 0.0:
		_paint_ring_half(ci, ring_c * t, ring_r * t, 1.0, ring_w, ring_col)

	if d < BURST_FROM:
		_paint_dome(ci, t, pose, d, flat)
	else:
		_paint_burst(ci, t, (d - BURST_FROM) / (1.0 - BURST_FROM), flat)

	if ring_alpha > 0.0:
		_paint_ring_half(ci, ring_c * t, ring_r * t, -1.0, ring_w, ring_col)
	ci.draw_set_transform(Vector2.ZERO)


## Half the ring as one polyline: the back (upper) half for `side` 1, the front (lower) half for -1.
func _paint_ring_half(ci: CanvasItem, c: Vector2, r: Vector2, side: float, w: float, col: Color) -> void:
	for i: int in range(RING_HALF_POINTS):
		var u: Vector2 = _unit_back[i]
		_half[i] = c + Vector2(u.x * r.x, u.y * r.y * side)
	ci.draw_polyline(_half, col, w)


func _paint_dome(ci: CanvasItem, t: float, pose: ModelPose, d: float, flat: bool) -> void:
	var dc: Vector2 = DOME_C * t
	var r: float = DOME_R * t
	if flat:
		ci.draw_circle(dc, r, _cols[C_DOME_D])
		ci.draw_circle(dc + Vector2(-0.04, -0.05) * r * 2.0, r * 0.86, _cols[C_DOME_M])
	else:
		_sphere.draw(ci, dc, Vector2(r, r), _cols[C_DOME_L], _cols[C_DOME_M], _cols[C_DOME_D])
		var rim_w: float = maxf(1.0, DOME_RIM_PX_AT_14 * t / 14.0)
		ci.draw_arc(dc, r - rim_w * 0.5, 0.0, TAU, 48, _cols[C_DOME_RIM], rim_w)
	var detail: bool = t >= LOW_DETAIL_T_PX
	if detail:
		for i: int in range(STREAKS.size()):
			var s: Vector4 = STREAKS[i]
			ci.draw_line(Vector2(s.x, s.y) * t, Vector2(s.z, s.w) * t, _ca(C_STREAK, STREAK_ALPHA[i]), maxf(1.0, STREAK_THICK[i] * t))

	# The nucleolus pulses faster as the Nucleus loses health.
	var nr: float = NUCLEOLUS_R * t * (1.0 + PULSE_AMOUNT * sin(TAU * pose.time * pulse_rate(pose.hp_frac)))
	var nc: Vector2 = NUCLEOLUS_C * t
	var glow: Color = _cols[C_NUC_GLOW]
	for i: int in range(NUCLEOLUS_GLOW_T.size()):
		if flat and i < NUCLEOLUS_GLOW_T.size() - 1:
			continue
		ci.draw_circle(nc, nr + NUCLEOLUS_GLOW_T[i] * t, Color(glow.r, glow.g, glow.b, glow.a * NUCLEOLUS_GLOW_SHARE[i]))
	if flat:
		ci.draw_circle(nc, nr, _cols[C_NUC_D])
		ci.draw_circle(nc + Vector2(-0.08, -0.1) * nr, nr * 0.8, _cols[C_NUC_M].lerp(_cols[C_NUC_L], 0.3))
	else:
		_nucleolus.draw(ci, nc, Vector2(nr, nr), _cols[C_NUC_L], _cols[C_NUC_M], _cols[C_NUC_D])

	if detail:
		var ring_w: float = maxf(1.0, PORE_RING_PX_AT_14 * t / 14.0)
		for q: Vector2 in PORES:
			ci.draw_circle(q * t, PORE_R * t, _cols[C_PORE])
			if not flat:
				ci.draw_arc(q * t, PORE_R * t - ring_w * 0.5, 0.0, TAU, 12, _cols[C_PORE_RING], ring_w)
	PaintKit.oval(ci, _base, HIGHLIGHT_RECT.get_center(), HIGHLIGHT_RECT.size, t, _cols[C_HIGHLIGHT])

	# Cracks grow across the dome before it bursts.
	if d > CRACK_FROM:
		var k: float = clampf((d - CRACK_FROM) / (CRACK_TO - CRACK_FROM), 0.0, 1.0)
		var w: float = maxf(1.0, CRACK_PX_AT_14 * t / 14.0)
		for c: Vector4 in CRACKS:
			var a: Vector2 = DOME_C + Vector2(c.x, c.y)
			var b: Vector2 = DOME_C + Vector2(c.z, c.w)
			ci.draw_line(a * t, a.lerp(b, k) * t, _cols[C_CRACK], w)


## The burst, `u` 0 to 1: fragments fly out on low arcs, shrinking and fading, over an expanding puff.
func _paint_burst(ci: CanvasItem, t: float, u: float, flat: bool) -> void:
	var fade: float = 1.0 - u
	var puff: Color = _cols[C_PUFF]
	ci.draw_circle(DOME_C * t, lerpf(PUFF_R0, PUFF_R1, Easing.ease_out_quad(u)) * t, Color(puff.r, puff.g, puff.b, puff.a * fade))
	var dist: float = FRAGMENT_DIST_T * Easing.ease_out_quad(u)
	var size: float = FRAGMENT_SIZE * (1.0 - 0.6 * u) * t
	for i: int in range(FRAGMENTS):
		var a: float = TAU * float(i) / float(FRAGMENTS)
		var p: Vector2 = DOME_C + Vector2(cos(a) * dist, sin(a) * dist * FRAGMENT_DEPTH - sin(PI * u) * FRAGMENT_ARC_T)
		var col: Color = _ca(C_FRAGMENT_L if i % 2 == 0 else C_FRAGMENT_D, fade)
		ci.draw_circle(p * t, size * (0.5 if flat else 0.6), col)


func _ca(slot: int, alpha: float) -> Color:
	var c: Color = _cols[slot]
	return Color(c.r, c.g, c.b, c.a * alpha)


## Fills the per-paint colours with the hit flash toward white.
func _prepare() -> void:
	for i: int in range(BASE.size()):
		var c: Color = BASE[i]
		var w: float = 0.0 if i == C_CRACK else _white
		_cols[i] = Color(lerpf(c.r, 1.0, w), lerpf(c.g, 1.0, w), lerpf(c.b, 1.0, w), c.a)
