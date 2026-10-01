class_name EffectLayer
extends Node2D

## Every transient and screen-space battle effect (issue #71, docs/MODEL_PIPELINE_PLAN.md section 3.4):
## antibody shots, hit sparks, Macrophage vesicles, puffs, health bars and intent lines in screen space, and
## the ground decals (scorch and splash rings) that UnitLayer paints under its sprites through draw_ground().
## Effect data lives in an EffectModel. Read-only with respect to the sim.
##
## Each pass is one triangle-array or multiline command however many effects are on screen (every draw
## command costs about 10 to 15 us, docs/PERF_BASELINE.md). The batches only grow, so drawing allocates
## nothing once they reach their peak size.

const K_PX: float = 14.0

const SHOT_CORE: Color = Color("#e8fcff")
const SHOT_GLOW: Color = Color("#48dbfb")
const SHOT_DIAMETER_T: float = 0.6
const SHOT_LIFT_T: float = 1.5
const SHOT_GLOW_SCALES: Array[float] = [2.4, 1.6]
const SHOT_GLOW_ALPHAS: Array[float] = [0.15, 0.35]
const TRAIL_POINTS: int = 4
## Spacing of the trail positions, in ticks of flight.
const TRAIL_STEP_TICKS: float = 0.5
const TRAIL_ALPHA_HI: float = 0.4
const TRAIL_ALPHA_LO: float = 0.1

const SPARK_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const SPARK_LINES: int = 6
const SPARK_IN_T: float = 0.2
const SPARK_OUT_T: float = 0.6
const SPARK_WIDTH_K: float = 1.5

const VESICLE_COLOR: Color = Color("#5aa5f2")
const VESICLE_LIGHT: Color = Color("#bfe0ff")
const VESICLE_DIAMETER_T: float = 0.35
const VESICLE_PEAK_T: float = 1.0
## The Macrophage's cup, above its ground anchor.
const CUP_LIFT_T: float = 1.8

const SPLASH_BORDER: Color = Color("#2e86de")
const SPLASH_BORDER_ALPHA: float = 0.9
const SPLASH_FILL: Color = Color(46.0 / 255.0, 134.0 / 255.0, 222.0 / 255.0, 0.15)
const SPLASH_START_FRAC: float = 0.3
const SPLASH_BORDER_K: float = 2.0

const PUFF_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)
const PUFF_FROM_T: float = 0.3
const PUFF_TO_T: float = 1.0
const PUFF_SQUASH: float = 0.7

const SCORCH_RADIUS_T: float = 1.8
## The canvas radial-gradient(circle, .5 0, .22 55%, transparent 72%) ends at the farthest corner of its
## 3.6 T box (1.8 T x sqrt 2), so the 55% stop is at about 1.4 T and the edge of the disc is near clear.
const SCORCH_MID_T: float = 1.4
const SCORCH_CENTRE: Color = Color(0.0, 0.0, 0.0, 0.5)
const SCORCH_MID: Color = Color(0.0, 0.0, 0.0, 0.22)
const SCORCH_EDGE: Color = Color(0.0, 0.0, 0.0, 0.0)
const DEBRIS_COLOR: Color = Color("#4a3a2a")
const DEBRIS_SIZE_T: float = 0.5
const DEBRIS_CORNER: float = 0.3
const DEBRIS_OFFSETS_T: Array[Vector2] = [Vector2(-0.6, -0.4), Vector2(0.7, 0.3), Vector2(-0.2, 0.8), Vector2(0.4, -0.7)]

const BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.65)
const BAR_GREEN: Color = Color("#2ecc71")
const BAR_AMBER: Color = Color("#f5b041")
const BAR_RED: Color = Color("#e74c3c")
const BAR_MIN_WIDTH_T: float = 1.4
const BAR_MODEL_WIDTH: float = 0.8
const BAR_HEIGHT_K: float = 4.0
const BAR_MIN_HEIGHT_PX: float = 2.0
const BAR_GAP_T: float = 0.2

const INTENT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.65)
const INTENT_WIDTH_K: float = 1.5
const INTENT_DASH_K: float = 4.0
const INTENT_GAP_K: float = 4.0
const INTENT_LIFT_T: float = 0.6

const REDUCED_ALPHA: float = 0.5
const DISC_POINTS: int = 16
const GROUND_POINTS: int = 32
const CAP_STEPS: int = 4


## Triangles with one colour per vertex, sent as one canvas_item_add_triangle_array command. The arrays only
## grow; the unused tail of the index list is zeroed, so it draws nothing.
class TriBatch extends RefCounted:
	var pts: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()
	var nv: int = 0
	var ni: int = 0
	var _last_ni: int = 0

	func begin() -> void:
		nv = 0
		ni = 0

	func reserve(v: int, i: int) -> void:
		if nv + v > pts.size():
			var n: int = maxi(pts.size() * 2, maxi(nv + v, 64))
			pts.resize(n)
			cols.resize(n)
		if ni + i > idx.size():
			var m: int = maxi(idx.size() * 2, maxi(ni + i, 192))
			var old: int = idx.size()
			idx.resize(m)
			for k: int in range(old, m):
				idx[k] = 0

	## A filled ellipse of `unit` points (a unit circle) as a fan.
	func disc(c: Vector2, rx: float, ry: float, col: Color, unit: PackedVector2Array) -> void:
		var n: int = unit.size()
		reserve(n + 1, n * 3)
		var base: int = nv
		pts[base] = c
		cols[base] = col
		for i: int in range(n):
			var u: Vector2 = unit[i]
			pts[base + 1 + i] = Vector2(c.x + u.x * rx, c.y + u.y * ry)
			cols[base + 1 + i] = col
			var j: int = ni + i * 3
			idx[j] = base
			idx[j + 1] = base + 1 + i
			idx[j + 2] = base + 1 + (i + 1) % n
		nv += n + 1
		ni += n * 3

	## A circular band from radius `r_in` to `r_out`.
	func ring(c: Vector2, r_in: float, r_out: float, col: Color, unit: PackedVector2Array) -> void:
		var n: int = unit.size()
		reserve(n * 2, n * 6)
		var base: int = nv
		for i: int in range(n):
			var u: Vector2 = unit[i]
			pts[base + i * 2] = c + u * r_in
			pts[base + i * 2 + 1] = c + u * r_out
			cols[base + i * 2] = col
			cols[base + i * 2 + 1] = col
			var a: int = base + i * 2
			var b: int = base + ((i + 1) % n) * 2
			var j: int = ni + i * 6
			idx[j] = a
			idx[j + 1] = a + 1
			idx[j + 2] = b + 1
			idx[j + 3] = a
			idx[j + 4] = b + 1
			idx[j + 5] = b
		nv += n * 2
		ni += n * 6

	## Concentric rings of `unit` points at `radii`, coloured `ring_cols`, joined into one shaded disc.
	## radii[0] should be 0 (the centre).
	func radial(c: Vector2, radii: PackedFloat32Array, ring_cols: PackedColorArray, unit: PackedVector2Array) -> void:
		var n: int = unit.size()
		var rings: int = radii.size()
		reserve(1 + (rings - 1) * n, n * 3 + (rings - 2) * n * 6)
		var base: int = nv
		pts[base] = c
		cols[base] = ring_cols[0]
		for k: int in range(1, rings):
			for i: int in range(n):
				pts[base + 1 + (k - 1) * n + i] = c + unit[i] * radii[k]
				cols[base + 1 + (k - 1) * n + i] = ring_cols[k]
		var j: int = ni
		for i: int in range(n):
			var i2: int = (i + 1) % n
			idx[j] = base
			idx[j + 1] = base + 1 + i
			idx[j + 2] = base + 1 + i2
			j += 3
			for k: int in range(1, rings - 1):
				var a: int = base + 1 + (k - 1) * n
				var b: int = a + n
				idx[j] = a + i
				idx[j + 1] = b + i
				idx[j + 2] = b + i2
				idx[j + 3] = a + i
				idx[j + 4] = b + i2
				idx[j + 5] = a + i2
				j += 6
		nv += 1 + (rings - 1) * n
		ni = j

	## A convex polygon given as a fan around its first point.
	func convex(points: PackedVector2Array, offset: Vector2, scale: float, col: Color) -> void:
		var n: int = points.size()
		reserve(n, (n - 2) * 3)
		var base: int = nv
		for i: int in range(n):
			pts[base + i] = offset + points[i] * scale
			cols[base + i] = col
		for i: int in range(n - 2):
			var j: int = ni + i * 3
			idx[j] = base
			idx[j + 1] = base + i + 1
			idx[j + 2] = base + i + 2
		nv += n
		ni += (n - 2) * 3

	## A straight segment `w` px wide.
	func line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
		var d: Vector2 = b - a
		var length: float = d.length()
		if length <= 0.0001:
			return
		var nrm: Vector2 = Vector2(-d.y, d.x) * (w * 0.5 / length)
		reserve(4, 6)
		var base: int = nv
		pts[base] = a + nrm
		pts[base + 1] = b + nrm
		pts[base + 2] = b - nrm
		pts[base + 3] = a - nrm
		for i: int in range(4):
			cols[base + i] = col
		var j: int = ni
		idx[j] = base
		idx[j + 1] = base + 1
		idx[j + 2] = base + 2
		idx[j + 3] = base
		idx[j + 4] = base + 2
		idx[j + 5] = base + 3
		nv += 4
		ni += 6

	## A horizontal capsule from x0 to x1 centred on y, `h` px tall (a rounded bar).
	func capsule(x0: float, x1: float, y: float, h: float, col: Color, cap: PackedVector2Array) -> void:
		var w: float = x1 - x0
		if w <= 0.0 or h <= 0.0:
			return
		var r: float = minf(h, w) * 0.5
		var ry: float = h * 0.5
		var n: int = cap.size()
		reserve(1 + n * 2, n * 2 * 3)
		var base: int = nv
		pts[base] = Vector2((x0 + x1) * 0.5, y)
		cols[base] = col
		for i: int in range(n):
			var u: Vector2 = cap[i]
			pts[base + 1 + i] = Vector2(x1 - r + u.x * r, y + u.y * ry)
			pts[base + 1 + n + i] = Vector2(x0 + r - u.x * r, y - u.y * ry)
			cols[base + 1 + i] = col
			cols[base + 1 + n + i] = col
		var m: int = n * 2
		for i: int in range(m):
			var j: int = ni + i * 3
			idx[j] = base
			idx[j + 1] = base + 1 + i
			idx[j + 2] = base + 1 + (i + 1) % m
		nv += 1 + m
		ni += m * 3

	func flush(ci: CanvasItem) -> void:
		for k: int in range(ni, _last_ni):
			idx[k] = 0
		_last_ni = ni
		if ni == 0:
			return
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


var model: EffectModel = null
var sim: BattleSim = null
var projection: IsoProjection = null
var snapshots: BattleSnapshotBuffer = null
var runner: BattleRunner = null
## Intent lines follow session.intent_lines_enabled (the HUD toggle); with no session they are on.
var session: Session = null
## Sparks off, puffs and splash rings at half alpha, no splash fill (Settings: Reduce screen flashes).
var reduce_flashes: bool = false:
	set = set_reduce_flashes

## Dash segments drawn last frame, for tests and the stress readout.
var last_intent_dashes: int = 0
## Health bars drawn last frame.
var last_bar_count: int = 0

var _fx: TriBatch = TriBatch.new()
var _bars: TriBatch = TriBatch.new()
var _splash: TriBatch = TriBatch.new()
var _scorch: TriBatch = TriBatch.new()
var _scorch_version: int = -1
var _intent: PackedVector2Array = PackedVector2Array()
var _intent_last: int = 0

var _disc: PackedVector2Array = PaintKit.unit_circle_points(DISC_POINTS)
var _ground: PackedVector2Array = PaintKit.unit_circle_points(GROUND_POINTS)
var _cap: PackedVector2Array = _cap_points()
var _debris: PackedVector2Array = _debris_points()
var _spark_dirs: PackedVector2Array = PaintKit.unit_circle_points(SPARK_LINES)
var _scorch_radii: PackedFloat32Array = PackedFloat32Array([0.0, SCORCH_MID_T, SCORCH_RADIUS_T])
var _scorch_cols: PackedColorArray = PackedColorArray([SCORCH_CENTRE, SCORCH_MID, SCORCH_EDGE])


func setup(p_model: EffectModel, p_sim: BattleSim, p_projection: IsoProjection, p_snapshots: BattleSnapshotBuffer, p_runner: BattleRunner, p_reduce_flashes: bool) -> void:
	model = p_model
	sim = p_sim
	projection = p_projection
	snapshots = p_snapshots
	runner = p_runner
	_scorch_version = -1
	reduce_flashes = p_reduce_flashes
	queue_redraw()


func set_reduce_flashes(value: bool) -> void:
	reduce_flashes = value
	if model != null:
		model.reduce_flashes = value
	queue_redraw()


func on_event(ev: Dictionary) -> void:
	if model != null:
		model.on_event(ev, sim)


func intent_lines_visible() -> bool:
	return session.intent_lines_enabled if session != null else true


func _process(_delta: float) -> void:
	if sim == null:
		return
	if model != null:
		model.advance(sim.tick)
	queue_redraw()


## Health bar fill: green above 50%, amber from 25% to 50%, red below 25%.
static func bar_color(ratio: float) -> Color:
	if ratio > 0.5:
		return BAR_GREEN
	if ratio >= 0.25:
		return BAR_AMBER
	return BAR_RED


static func _cap_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in range(CAP_STEPS + 1):
		var a: float = -PI * 0.5 + PI * float(i) / float(CAP_STEPS)
		out.append(Vector2(cos(a), sin(a)))
	return out


## A 0.5 T debris square with its corners cut at 30%, centred on the origin, in tiles.
static func _debris_points() -> PackedVector2Array:
	var h: float = DEBRIS_SIZE_T * 0.5
	var c: float = DEBRIS_SIZE_T * DEBRIS_CORNER * 0.5
	return PackedVector2Array([
		Vector2(-h + c, -h), Vector2(h - c, -h), Vector2(h, -h + c), Vector2(h, h - c),
		Vector2(h - c, h), Vector2(-h + c, h), Vector2(-h, h - c), Vector2(-h, -h + c),
	])


func _now() -> float:
	return float(sim.tick) + (runner.alpha if runner != null else 0.0)


func _alpha() -> float:
	return runner.alpha if runner != null else 1.0


# --- ground pass (called by UnitLayer before its sprites) ---------------------

func draw_ground(ci: CanvasItem) -> void:
	if not build_ground():
		return
	ci.draw_set_transform_matrix(projection.ground_transform())
	_scorch.flush(ci)
	_splash.flush(ci)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Fills the ground batches without drawing. False when there is nothing to draw from.
func build_ground() -> bool:
	if sim == null or projection == null or model == null:
		return false
	if _scorch_version != model.scorch_version:
		_rebuild_scorch()
	_build_splashes()
	return true


## Triangles in the scorch and splash batches, for tests.
func ground_triangles() -> Vector2i:
	return Vector2i(_scorch.ni / 3, _splash.ni / 3)


func _rebuild_scorch() -> void:
	_scorch_version = model.scorch_version
	_scorch.begin()
	for i: int in range(model.scorch_count()):
		var c: Vector2 = model.scorch_pos[model.scorch_slot(i)]
		_scorch.radial(c, _scorch_radii, _scorch_cols, _ground)
		for d: Vector2 in DEBRIS_OFFSETS_T:
			_scorch.convex(_debris, c + d, 1.0, DEBRIS_COLOR)


## Splash rings in ground tiles (the layer draws them under the ground transform).
func _build_splashes() -> void:
	_splash.begin()
	var now: float = _now()
	var dim: float = REDUCED_ALPHA if reduce_flashes else 1.0
	var border_t: float = SPLASH_BORDER_K / (K_PX * projection.scale)
	for i: int in range(model.transient_count()):
		var s: int = model.slot(i)
		if model.kind[s] != EffectModel.Kind.SPLASH or now < float(model.start[s]):
			continue
		var u: float = model.progress(s, now)
		var r: float = model.radius[s] * lerpf(SPLASH_START_FRAC, 1.0, u)
		var fade: float = (1.0 - u) * dim
		var c: Vector2 = model.pos_a[s]
		if not reduce_flashes:
			_splash.disc(c, r, r, Color(SPLASH_FILL, SPLASH_FILL.a * fade), _ground)
		_splash.ring(c, maxf(r - border_t, 0.0), r, Color(SPLASH_BORDER, SPLASH_BORDER_ALPHA * fade), _ground)


# --- screen pass --------------------------------------------------------------

func _draw() -> void:
	if not build_frame():
		return
	if _intent_last > 0:
		draw_multiline(_intent, INTENT_COLOR, INTENT_WIDTH_K * projection.tile_px / K_PX)
	_fx.flush(self)
	_bars.flush(self)


## Fills the screen-space batches without drawing. False when there is nothing to draw from.
func build_frame() -> bool:
	if sim == null or projection == null:
		return false
	_build_intent_lines()
	_fx.begin()
	if model != null:
		_build_fx()
	_build_bars()
	return true


## Triangles in the effect batch (shots, vesicles, puffs and sparks), for tests.
func fx_triangles() -> int:
	return _fx.ni / 3


func _build_fx() -> void:
	var t: float = projection.tile_px
	var k: float = t / K_PX
	var now: float = _now()
	var alpha: float = _alpha()
	var dim: float = REDUCED_ALPHA if reduce_flashes else 1.0
	for i: int in range(model.transient_count()):
		var s: int = model.slot(i)
		match model.kind[s]:
			EffectModel.Kind.PUFF:
				var u: float = model.progress(s, now)
				var d: float = lerpf(PUFF_FROM_T, PUFF_TO_T, u) * t * 0.5
				var c: Vector2 = projection.ground_to_screen(model.pos_a[s]) - Vector2(0.0, model.radius[s] * 0.5 * t)
				_fx.disc(c, d, d * PUFF_SQUASH, Color(PUFF_COLOR, PUFF_COLOR.a * (1.0 - u) * dim), _disc)
			EffectModel.Kind.SPARK:
				var u: float = model.progress(s, now)
				var c: Vector2 = projection.ground_to_screen(model.pos_a[s]) - Vector2(0.0, model.radius[s] * 0.5 * t)
				var col := Color(SPARK_COLOR, 1.0 - u)
				var spin: float = ViewRng.hash01(model.ref_id[s] + model.start[s], 3) * TAU
				for dir: Vector2 in _spark_dirs:
					var v: Vector2 = dir.rotated(spin)
					_fx.line(c + v * (SPARK_IN_T * t), c + v * (SPARK_OUT_T * t), SPARK_WIDTH_K * k, col)
			EffectModel.Kind.VESICLE:
				var u: float = model.progress(s, now)
				var from: Vector2 = projection.ground_to_screen(model.pos_a[s]) - Vector2(0.0, CUP_LIFT_T * t)
				var to: Vector2 = projection.ground_to_screen(model.pos_b[s])
				var c: Vector2 = from.lerp(to, u) - Vector2(0.0, 4.0 * VESICLE_PEAK_T * t * u * (1.0 - u))
				var r: float = VESICLE_DIAMETER_T * 0.5 * t
				_fx.disc(c, r, r, VESICLE_COLOR, _disc)
				_fx.disc(c + Vector2(-0.3, -0.3) * r, r * 0.4, r * 0.4, VESICLE_LIGHT, _disc)
			EffectModel.Kind.PROJECTILE:
				_add_shot(s, now, alpha, t)


func _add_shot(s: int, now: float, alpha: float, t: float) -> void:
	var id: int = model.ref_id[s]
	if snapshots == null or not snapshots.has_projectile(id):
		return
	var lift := Vector2(0.0, -SHOT_LIFT_T * t)
	var r: float = SHOT_DIAMETER_T * 0.5 * t
	if snapshots.has_previous_projectile(id):
		var flown: float = now - float(model.start[s])
		for i: int in range(TRAIL_POINTS, 0, -1):
			var back: float = float(i) * TRAIL_STEP_TICKS
			if back > flown:
				continue
			var p: Vector2 = projection.ground_to_screen(snapshots.projectile_ground(id, alpha - back)) + lift
			var f: float = float(i - 1) / float(TRAIL_POINTS - 1)
			var tr: float = r * (1.0 - 0.15 * float(i))
			_fx.disc(p, tr, tr, Color(SHOT_GLOW, lerpf(TRAIL_ALPHA_HI, TRAIL_ALPHA_LO, f)), _disc)
	var head: Vector2 = projection.ground_to_screen(snapshots.projectile_ground(id, alpha)) + lift
	for g: int in range(SHOT_GLOW_SCALES.size()):
		var gr: float = r * SHOT_GLOW_SCALES[g]
		_fx.disc(head, gr, gr, Color(SHOT_GLOW, SHOT_GLOW_ALPHAS[g]), _disc)
	_fx.disc(head, r, r, SHOT_CORE, _disc)


func _build_bars() -> void:
	_bars.begin()
	last_bar_count = 0
	var t: float = projection.tile_px
	var h: float = maxf(BAR_MIN_HEIGHT_PX, BAR_HEIGHT_K * t / K_PX)
	for s: StructureState in sim.structures:
		if not s.alive or s.hp >= s.max_hp or s.hp <= 0:
			continue
		var size: Vector2 = UnitLayer.structure_size_px(s, projection)
		var foot: Vector2 = projection.ground_to_screen(UnitLayer.structure_anchor(s))
		_add_bar(foot.x, foot.y - size.y - BAR_GAP_T * t, maxf(BAR_MIN_WIDTH_T * t, BAR_MODEL_WIDTH * size.x), h, float(s.hp) / float(s.max_hp))
	var alpha: float = _alpha()
	for p: PathogenState in sim.pathogens:
		if not p.alive or p.hp >= p.max_hp or p.hp <= 0:
			continue
		var ground: Vector2 = snapshots.unit_ground(p.id, alpha) if (snapshots != null and snapshots.has_unit(p.id)) else Vector2(p.pos) / 1000.0
		var foot: Vector2 = projection.ground_to_screen(ground)
		var w_t: float = float(ModelRegistry.PATHOGEN_WIDTH_T.get(p.type_id, ModelRegistry.DEFAULT_PATHOGEN_WIDTH_T))
		var h_t: float = ModelRegistry.painter_for(p.type_id).height_tiles()
		_add_bar(foot.x, foot.y - (h_t + BAR_GAP_T) * t, maxf(BAR_MIN_WIDTH_T, BAR_MODEL_WIDTH * w_t) * t, h, float(p.hp) / float(p.max_hp))


func _add_bar(cx: float, cy: float, w: float, h: float, ratio: float) -> void:
	var x0: float = cx - w * 0.5
	_bars.capsule(x0, x0 + w, cy, h, BAR_BG, _cap)
	_bars.capsule(x0, x0 + w * clampf(ratio, 0.0, 1.0), cy, h, bar_color(ratio), _cap)
	last_bar_count += 1


## Dashed lines from each attacking pathogen to its target, drawn as one multiline command. The point list only
## grows; unused pairs at its end collapse to zero-length segments.
func _build_intent_lines() -> void:
	var n: int = 0
	if intent_lines_visible():
		var t: float = projection.tile_px
		var k: float = t / K_PX
		var lift := Vector2(0.0, -INTENT_LIFT_T * t)
		var dash: float = INTENT_DASH_K * k
		var period: float = dash + INTENT_GAP_K * k
		var alpha: float = _alpha()
		for p: PathogenState in sim.pathogens:
			if not p.alive:
				continue
			var tid: int = p.attacking_id()
			if tid == 0:
				continue
			var target: StructureState = sim.structure(tid)
			if target == null or not target.alive:
				continue
			var ground: Vector2 = snapshots.unit_ground(p.id, alpha) if (snapshots != null and snapshots.has_unit(p.id)) else Vector2(p.pos) / 1000.0
			var a: Vector2 = projection.ground_to_screen(ground) + lift
			var b: Vector2 = projection.ground_to_screen(UnitLayer.structure_anchor(target)) + lift
			var length: float = a.distance_to(b)
			if length <= 0.001:
				continue
			var dir: Vector2 = (b - a) / length
			var need: int = n + (int(length / period) + 1) * 2
			if need > _intent.size():
				_intent.resize(maxi(_intent.size() * 2, need))
			var d: float = 0.0
			while d < length:
				_intent[n] = a + dir * d
				_intent[n + 1] = a + dir * minf(d + dash, length)
				n += 2
				d += period
	for i: int in range(n, _intent_last):
		_intent[i] = Vector2.ZERO
	_intent_last = n
	last_intent_dashes = n / 2
