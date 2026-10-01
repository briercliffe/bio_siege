class_name StaphPainter
extends ModelPainter

## The Staphylococcus: eight shaded cocci stacked like grapes on a glossy biofilm base, ported from
## docs/mockups/canvas/Field.dc.html (issue #68, docs/MODEL_PIPELINE_PLAN.md section 5). Units are tiles (T),
## the anchor is the ground centre and negative y is up. Nothing is allocated in paint() or in
## paint_ground() once a unit has been seen: colours are cached in a preallocated array, polygons go through
## PaintKit, and each unit's biofilm trail is a fixed six-slot ring buffer taken from a pool.
##
## The cluster is left/right symmetric, so facing never mirrors the transform: it only signs the lean and the
## gather, which keeps the light on the upper left for both facings.

const HEIGHT_T: float = 2.35

# Geometry in tiles, straight from the canvas.
const SHADOW_RECT: Rect2 = Rect2(-1.4, -0.62, 2.8, 1.0)
const BASE_RECT: Rect2 = Rect2(-1.3, -0.7, 2.6, 0.95)
const BASE_LIGHT_RECT: Rect2 = Rect2(-0.95, -0.62, 1.5, 0.6)
## x, y, diameter of each coccus in draw order (back row first).
const COCCI: Array[Vector3] = [
	Vector3(0.0, -1.8, 1.0), Vector3(-0.55, -1.45, 1.0), Vector3(0.55, -1.45, 1.0),
	Vector3(-0.9, -0.9, 1.05), Vector3(0.9, -0.9, 1.05), Vector3(0.0, -1.1, 1.12),
	Vector3(-0.45, -0.5, 1.0), Vector3(0.45, -0.5, 1.0),
]
## Cocci from this index on are the front row (lighter shading).
const FRONT_FROM: int = 3
const GLOSS_OFFSET: Vector2 = Vector2(-0.3, -0.36)
const GLOSS_SIZE: Vector2 = Vector2(0.28, 0.16)

## Below this tile size the gloss dots are skipped (issue: detail cutoff).
const LOW_DETAIL_T_PX: float = 10.0
## Below this tile size a coccus is one flat circle (back row) or two (front row) instead of a four-layer
## sphere, the gloss is skipped and the biofilm is one oval. Every draw command costs around 10 to 15
## microseconds (docs/PERF_BASELINE.md), and the 200-unit bench runs at 23 px per tile.
const FLAT_T_PX: float = 28.0

const C_SHADOW: int = 0
const C_BASE_M: int = 1
const C_BASE_D: int = 2
const C_BASE_L: int = 3
const C_BACK_L: int = 4
const C_BACK_M: int = 5
const C_BACK_D: int = 6
const C_FRONT_L: int = 7
const C_FRONT_M: int = 8
const C_FRONT_D: int = 9
const C_GLOSS: int = 10
const BASE: Array[Color] = [
	Color(0.0, 0.0, 0.0, 0.35), Color(0.75, 0.6, 0.15, 0.7), Color(0.59, 0.43, 0.04, 0.6), Color(0.94, 0.8, 0.35, 0.75),
	Color("#f6dd7a"), Color("#d4a90c"), Color("#7d5f00"),
	Color("#fff3a6"), Color("#f1c40f"), Color("#a87f00"),
	Color(1.0, 1.0, 1.0, 0.55),
]

# Presentation constants, from the animation table in the issue.
const IDLE_PERIOD_S: float = 1.6
const IDLE_BREATH: float = 0.04
const MOVE_SQUASH: Vector2 = Vector2(0.08, -0.06)
const MOVE_LEAN: float = 0.1
const GATHER_BACK: float = 0.2
const GATHER_SCALE_Y: float = 0.92
const WINDUP_END: float = 0.4
const HEAVE_FROM: float = 0.3
## The heave peaks here rather than at WINDUP_END: the last windup frame AnimDriver produces has
## attack_t = WINDUP_END * (1 - 1 / windup ticks), about 0.367 for the capped 12-tick windup, and
## WINDUP_END itself is only reached on the strike tick.
const HEAVE_TO: float = 0.36
const HEAVE_T: float = 0.3
const RECOVER_START: float = 0.6
const SLAM_SQUASH: Vector2 = Vector2(1.14, 0.86)
const RING_T0: float = 0.5
const RING_T1: float = 1.6
const RING_ALPHA: float = 0.6
const RING_COLOR: Color = Color("#f1c40f")
const RING_WIDTH_T: float = 0.08
const RING_SEGMENTS: int = 32
const SCATTER_DEG: float = 45.0
const SCATTER_T: float = 1.2
const SCATTER_DEPTH: float = 0.5
const SCATTER_ARC_T: float = 0.8
const POP_FROM_T: float = 0.8
const POP_STEP: float = 0.02
const HIT_WHITE: float = 0.7
const SHAKE_RAD_PER_S: float = 60.0
const SHAKE_T: float = 0.08
const SIZE_VARIANCE: float = 0.08
const LIGHT_VARIANCE: float = 0.08

# Biofilm trail: the unit's last TRAIL_MAX ground positions, spaced TRAIL_SPACING_T tiles apart.
const TRAIL_MAX: int = 6
const TRAIL_SPACING_T: float = 0.5
const TRAIL_ALPHA: float = 0.25
const TRAIL_SIZE: Vector2 = Vector2(1.2, 0.5)
const TRAIL_COLOR: Color = Color(0.94, 0.8, 0.35, 1.0)
## Seconds for a trail to fade out once the unit stops laying it.
const TRAIL_FADE_S: float = 1.5


## Fixed-size ring of past positions, in tiles of screen space (anchor / t, projection origin included).
## UnitLayer resets the painter when the tile size or origin changes, so a stale trail is never drawn.
class Trail extends RefCounted:
	var pts: PackedVector2Array = PackedVector2Array()
	var head: int = 0       # next slot to write
	var count: int = 0
	var last: Vector2 = Vector2.ZERO
	var stamp: float = 0.0  # pose.time of the last push

	func _init() -> void:
		pts.resize(StaphPainter.TRAIL_MAX)

	func reset(at: Vector2, time: float) -> void:
		head = 0
		count = 0
		last = at
		stamp = time

	func push(p: Vector2) -> void:
		pts[head] = p
		head = (head + 1) % StaphPainter.TRAIL_MAX
		count = mini(count + 1, StaphPainter.TRAIL_MAX)


# Per-paint scratch. Painters are shared and painting is single threaded, so plain members are safe.
var _lum: float = 1.0
var _white: float = 0.0
var _cols: Array[Color] = []
var _trails: Dictionary = {}          # pose.seed -> Trail
var _pool: Array[Trail] = []          # released trails, reused so paint_ground() does not allocate


func _init() -> void:
	_cols.resize(BASE.size())
	_prepare()


func height_tiles() -> float:
	return HEIGHT_T


func has_custom_death() -> bool:
	return true


## Number of trail positions currently held for the unit with this seed (0 when it has none).
func trail_count(seed_id: int) -> int:
	var tr: Trail = _trails.get(seed_id)
	return tr.count if tr != null else 0


## Ground decals: the fading biofilm trail while moving, the shockwave ring on the slam.
func paint_ground(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	if pose.anim == ModelPose.Anim.DEAD:
		_release(pose.seed)
		return
	var here: Vector2 = anchor / t
	var tr: Trail = _trails.get(pose.seed)
	if tr == null:
		tr = _pool.pop_back() if not _pool.is_empty() else Trail.new()
		tr.reset(here, pose.time)
		_trails[pose.seed] = tr
	if here.distance_to(tr.last) >= TRAIL_SPACING_T:
		tr.push(tr.last)
		tr.last = here
		tr.stamp = pose.time

	var fade: float = 1.0 - clampf((pose.time - tr.stamp) / TRAIL_FADE_S, 0.0, 1.0)
	if tr.count > 0 and fade > 0.0:
		var ry: float = TRAIL_SIZE.y / TRAIL_SIZE.x
		var r: float = TRAIL_SIZE.x * 0.5 * t
		for i: int in range(tr.count):
			var idx: int = posmod(tr.head - 1 - i, TRAIL_MAX)
			var a: float = TRAIL_ALPHA * (1.0 - float(i) / float(TRAIL_MAX)) * fade
			ci.draw_set_transform(tr.pts[idx] * t, 0.0, Vector2(1.0, ry))
			ci.draw_circle(Vector2.ZERO, r, Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, a))

	if pose.anim == ModelPose.Anim.STRIKE or pose.anim == ModelPose.Anim.RECOVER:
		var u: float = clampf((pose.attack_t - RING_T0) / (1.0 - RING_T0), 0.0, 1.0)
		ci.draw_set_transform(anchor, 0.0, Vector2(1.0, 0.5))
		ci.draw_arc(Vector2.ZERO, lerpf(RING_T0, RING_T1, u) * t, 0.0, TAU, RING_SEGMENTS,
			Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_ALPHA * (1.0 - u)), maxf(1.0, RING_WIDTH_T * t))
	ci.draw_set_transform(Vector2.ZERO)


## Returns every trail to the pool. Trails are keyed by seed and stored in screen tiles, so they are stale
## once a battle ends or the projection moves.
func reset() -> void:
	for tr_var: Variant in _trails.values():
		var tr: Trail = tr_var
		_pool.append(tr)
	_trails.clear()


func _release(seed_id: int) -> void:
	var tr: Trail = _trails.get(seed_id)
	if tr != null:
		_trails.erase(seed_id)
		_pool.append(tr)


func idle_period_s() -> float:
	return IDLE_PERIOD_S


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t: float) -> void:
	var size_k: float = 1.0 + (ViewRng.hash01(pose.seed, 2) - 0.5) * SIZE_VARIANCE
	_lum = 1.0 + (ViewRng.hash01(pose.seed, 3) - 0.5) * LIGHT_VARIANCE
	_white = HIT_WHITE * clampf(pose.hit_t, 0.0, 1.0)
	_prepare()
	var dir: float = 1.0 if pose.facing_right else -1.0
	var shake_px: float = sin(pose.time * SHAKE_RAD_PER_S) * SHAKE_T * t * pose.shake
	var dead: bool = pose.anim == ModelPose.Anim.DEAD

	# Pose-driven values: squash, lean (x shear of the vertical axis), shift (tiles, x toward facing) and
	# lift (tiles, y down).
	var sq: Vector2 = Vector2.ONE
	var lean: float = 0.0
	var shift: float = 0.0
	var lift: float = 0.0
	var breathe: bool = false
	match pose.anim:
		ModelPose.Anim.MOVE:
			var s: float = 0.5 + 0.5 * sin(TAU * pose.gait_phase)
			sq = Vector2(1.0 + MOVE_SQUASH.x * s, 1.0 + MOVE_SQUASH.y * s)
			lean = MOVE_LEAN * s
		ModelPose.Anim.WINDUP:
			var k: float = clampf(pose.attack_t / WINDUP_END, 0.0, 1.0)
			shift = -GATHER_BACK * k
			sq.y = lerpf(1.0, GATHER_SCALE_Y, k)
			# The heave: the cluster jumps at the end of the windup and lands on the strike tick.
			lift = -HEAVE_T * Easing.ease_in_out(clampf((pose.attack_t - HEAVE_FROM) / (HEAVE_TO - HEAVE_FROM), 0.0, 1.0))
		ModelPose.Anim.STRIKE:
			sq = SLAM_SQUASH
		ModelPose.Anim.RECOVER:
			var back: float = 1.0 - Easing.ease_out_quad((pose.attack_t - RECOVER_START) / (1.0 - RECOVER_START))
			sq = Vector2.ONE.lerp(SLAM_SQUASH, back)
		ModelPose.Anim.DEAD:
			pass
		_:
			breathe = true

	var origin: Vector2 = anchor + Vector2(shake_px, 0.0)
	var flat: Transform2D = Transform2D(0.0, origin).scaled_local(Vector2(size_k, size_k))
	# The group: squashed about the ground centre, leaning toward the facing, shifted and lifted.
	var group: Transform2D = flat * Transform2D(Vector2(sq.x, 0.0), Vector2(-dir * lean, sq.y), Vector2(shift * dir * t, lift * t))

	var fade: float = 1.0 - pose.death_t if dead else 1.0
	# The shadow stays on the ground: it follows the shake but never squashes, hops or gathers.
	_oval(ci, flat, SHADOW_RECT.get_center(), SHADOW_RECT.size, t, _ca(C_SHADOW, fade))
	if t < FLAT_T_PX:
		_oval(ci, group, BASE_RECT.get_center(), BASE_RECT.size, t, _ca(C_BASE_M, fade))
	else:
		_oval(ci, group, BASE_RECT.get_center(), BASE_RECT.size, t, _ca(C_BASE_D, fade))
		_oval(ci, group, BASE_LIGHT_RECT.get_center(), BASE_LIGHT_RECT.size, t, _ca(C_BASE_L, fade))

	ci.draw_set_transform_matrix(group if not dead else flat)
	for i: int in range(COCCI.size()):
		var q: Vector3 = COCCI[i]
		if dead:
			_paint_scattering(ci, t, i, q, pose.death_t)
		else:
			var d: float = q.z
			if breathe:
				d *= 1.0 + IDLE_BREATH * sin(TAU * pose.time / IDLE_PERIOD_S + float(i))
			_coccus(ci, t, i, Vector2(q.x, q.y), d)
	ci.draw_set_transform(Vector2.ZERO)


## One coccus of diameter `d` (tiles) centred at `c`.
func _coccus(ci: CanvasItem, t: float, i: int, c: Vector2, d: float) -> void:
	var front: bool = i >= FRONT_FROM
	var light: Color = _cols[C_FRONT_L] if front else _cols[C_BACK_L]
	var mid: Color = _cols[C_FRONT_M] if front else _cols[C_BACK_M]
	var dark: Color = _cols[C_FRONT_D] if front else _cols[C_BACK_D]
	if t < FLAT_T_PX:
		if front:
			ci.draw_circle(c * t, d * 0.5 * t, dark)
			ci.draw_circle((c + Vector2(-0.04, -0.05) * d) * t, d * 0.43 * t, mid)
		else:
			ci.draw_circle(c * t, d * 0.5 * t, mid)
		return
	PaintKit.sphere(ci, PaintKit.part_rect(Vector2.ZERO, t, c.x - d * 0.5, c.y - d * 0.5, d, d), light, mid, dark)
	if t >= LOW_DETAIL_T_PX:
		PaintKit.ellipse(ci, PaintKit.part_rect(Vector2.ZERO, t, c.x + GLOSS_OFFSET.x * d, c.y + GLOSS_OFFSET.y * d, GLOSS_SIZE.x * d, GLOSS_SIZE.y * d), _cols[C_GLOSS])


## Death: coccus i flies along i * 45 degrees on a ground-plane arc with a hop, shrinks and pops.
func _paint_scattering(ci: CanvasItem, t: float, i: int, q: Vector3, death_t: float) -> void:
	if death_t > POP_FROM_T + POP_STEP * float(i):
		return
	var a: float = deg_to_rad(SCATTER_DEG) * float(i)
	var dist: float = death_t * SCATTER_T
	var c: Vector2 = Vector2(q.x + cos(a) * dist, q.y + sin(a) * dist * SCATTER_DEPTH - sin(PI * death_t) * SCATTER_ARC_T)
	_coccus(ci, t, i, c, q.z * (1.0 - death_t))


## A filled ellipse as a circle under a squashed transform, so it takes the engine's circle fast path.
## `centre` and `size` are in tiles; `xf` maps tiles-as-pixels to the canvas. It is left set on return.
func _oval(ci: CanvasItem, xf: Transform2D, centre: Vector2, size: Vector2, t: float, col: Color) -> void:
	ci.draw_set_transform_matrix(xf * Transform2D(Vector2(1.0, 0.0), Vector2(0.0, size.y / size.x), centre * t))
	ci.draw_circle(Vector2.ZERO, size.x * 0.5 * t, col)


func _ca(slot: int, alpha: float) -> Color:
	var c: Color = _cols[slot]
	return Color(c.r, c.g, c.b, c.a * alpha)


## Fills the per-paint colours: swarm lightness shift and hit flash toward white.
func _prepare() -> void:
	for i: int in range(BASE.size()):
		var c: Color = BASE[i]
		var w: float = 0.0 if i == C_SHADOW else _white
		_cols[i] = Color(
			lerpf(minf(c.r * _lum, 1.0), 1.0, w),
			lerpf(minf(c.g * _lum, 1.0), 1.0, w),
			lerpf(minf(c.b * _lum, 1.0), 1.0, w),
			c.a)
