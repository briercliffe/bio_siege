class_name UnitLayer
extends Node2D

## One depth-sorted isometric draw pass for every structure and pathogen (docs/MODEL_PIPELINE_PLAN.md
## section 6). No node per unit. Reads sim state through BattleSnapshotBuffer and never modifies it.

const KIND_STRUCTURE: int = 0
const KIND_PATHOGEN: int = 1

const SCORCH_DIAMETER_T: float = 3.6
const SCORCH_RINGS: int = 5
const SCORCH_ALPHA: float = 0.5
const PLATE_TOWER_RADIUS: float = 1.9
const PLATE_CORE_RADIUS: float = 2.8
const STRUCTURE_WIDTH_SCALE: float = 1.4
const CRACK_PULSE_PERIOD_S: float = 0.8
const PLATE_FILL: Color = Color(0.0, 0.0, 0.0, 0.3)
const NUCLEUS_GLOW: Color = Color(195.0 / 255.0, 155.0 / 255.0, 211.0 / 255.0, 0.12)
const NUCLEUS_PLATE: Color = Color(74.0 / 255.0, 28.0 / 255.0, 102.0 / 255.0, 0.38)

## Pathogen sprite size in tiles (width, height), from docs/MVP_UI_SPEC.md section 4.
const PATHOGEN_SIZE_T: Dictionary = {
	"rhinovirus": Vector2(1.2, 1.25),
	"bacteriophage": Vector2(1.9, 3.0),
	"staphylococcus": Vector2(2.8, 2.35),
}
const DEFAULT_PATHOGEN_SIZE_T: Vector2 = Vector2(1.2, 1.25)

## Crack polylines in face-local (u, v) space, the same marks the old StructureView drew.
const CRACKS: Array = [
	[Vector2(0.2, 0.0), Vector2(0.38, 0.28), Vector2(0.28, 0.52), Vector2(0.52, 0.78), Vector2(0.45, 1.0)],
	[Vector2(0.75, 0.0), Vector2(0.58, 0.32), Vector2(0.78, 0.64), Vector2(0.68, 1.0)],
	[Vector2(0.0, 0.5), Vector2(0.32, 0.38), Vector2(0.58, 0.62), Vector2(0.82, 0.44), Vector2(1.0, 0.52)],
]


class UnitDrawItem extends RefCounted:
	var key: float = 0.0
	var kind: int = 0
	var id: int = 0
	## Age in ticks of a dying entity's fading copy; negative for a live entity.
	var age: float = -1.0


var sim: BattleSim = null
var config: GameConfig = null
var projection: IsoProjection = null
var snapshots: BattleSnapshotBuffer = null
var runner: BattleRunner = null

## Number of items painted last pass, for the stress scene readout.
var last_item_count: int = 0

var _pool: Array[UnitDrawItem] = []
var _sorted: Array[UnitDrawItem] = []
var _pool_used: int = 0
var _sort_cmp: Callable = UnitLayer._item_before

# Per-id death ticks, in reused dictionaries of ints. Hit flashes, strikes and poses live in the AnimDriver.
var _dying_p: Dictionary = {}
var _dying_s: Dictionary = {}
var _scorch: Array[int] = []
var _breached: Dictionary = {}
var _expired: Array[int] = []

var driver: AnimDriver = AnimDriver.new()
## View clock in seconds for idle loops. Advances only while the battle runs.
var view_time: float = 0.0

var _wall_faces: Dictionary = {}
var _faces_key: Vector3 = Vector3(-1.0, 0.0, 0.0)


func setup(p_sim: BattleSim, p_config: GameConfig, p_projection: IsoProjection, p_snapshots: BattleSnapshotBuffer, p_runner: BattleRunner) -> void:
	sim = p_sim
	config = p_config
	projection = p_projection
	snapshots = p_snapshots
	runner = p_runner
	driver = AnimDriver.new()
	view_time = 0.0
	ModelRegistry.configure(config, projection.scale if projection != null else IsoProjection.DEFAULT_SCALE)
	_dying_p.clear()
	_dying_s.clear()
	_scorch.clear()
	_wall_faces.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if sim == null:
		return
	if runner != null and runner.is_running:
		view_time += delta
	queue_redraw()


# --- sizing, shared with the overlay ---------------------------------------

static func pathogen_size_t(type_id: String) -> Vector2:
	return PATHOGEN_SIZE_T.get(type_id, DEFAULT_PATHOGEN_SIZE_T)


## Sprite (width, height) in screen px for a structure.
static func structure_size_px(s: StructureState, proj: IsoProjection) -> Vector2:
	var t: float = proj.tile_px
	if s.def != null and s.def.has_tag("wall"):
		return Vector2(2.0 * t * proj.scale, PlaceholderBillboard.WALL_HEIGHT_T * t)
	var h_t: float = float(GridView.MODEL_HEIGHT_T.get(s.type_id, GridView.DEFAULT_MODEL_HEIGHT_T))
	return Vector2(float(s.footprint.x) * t * proj.scale * STRUCTURE_WIDTH_SCALE, h_t * t)


static func structure_anchor(s: StructureState) -> Vector2:
	return Vector2(s.origin) + Vector2(s.footprint) * 0.5


static func crack_count(hp: int, max_hp: int) -> int:
	if max_hp <= 0:
		return 1
	if hp <= max_hp / 3:
		return 3
	if hp <= (max_hp * 2) / 3:
		return 2
	return 1


## Ground anchor of a live pathogen, interpolated between ticks.
func pathogen_anchor(p: PathogenState) -> Vector2:
	var alpha: float = runner.alpha if runner != null else 1.0
	if snapshots != null and snapshots.has_unit(p.id):
		return snapshots.unit_ground(p.id, alpha)
	return Vector2(p.pos) / 1000.0


# --- events -----------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	if sim == null:
		return
	driver.on_event(ev)
	match str(ev.get("type", "")):
		SimEvents.PATHOGEN_KILLED:
			var uid: int = int(ev.get("unit_id", 0))
			if sim.pathogen(uid) != null:
				_dying_p[uid] = AnimDriver.event_tick(ev, sim.tick)
		SimEvents.STRUCTURE_DESTROYED:
			var sid: int = int(ev.get("structure_id", 0))
			var s: StructureState = sim.structure(sid)
			if s == null:
				return
			_dying_s[sid] = AnimDriver.event_tick(ev, sim.tick)
			if s.def != null and not s.def.has_tag("wall") and not _scorch.has(sid):
				_scorch.append(sid)


# --- draw order -------------------------------------------------------------

static func _item_before(a: UnitDrawItem, b: UnitDrawItem) -> bool:
	if a.key != b.key:
		return a.key < b.key
	if a.kind != b.kind:
		return a.kind < b.kind
	return a.id < b.id


func _take_item(kind: int, id: int, key: float, age: float) -> void:
	var item: UnitDrawItem
	if _pool_used < _pool.size():
		item = _pool[_pool_used]
	else:
		item = UnitDrawItem.new()
		_pool.append(item)
	_pool_used += 1
	item.kind = kind
	item.id = id
	item.key = key
	item.age = age
	_sorted.append(item)


func _collect() -> void:
	_pool_used = 0
	_sorted.clear()
	_breached.clear()
	if sim == null or projection == null:
		return
	for s: StructureState in sim.structures:
		if s.alive:
			_take_item(KIND_STRUCTURE, s.id, IsoProjection.depth_key(structure_anchor(s)), -1.0)
	for p: PathogenState in sim.pathogens:
		if p.alive:
			_take_item(KIND_PATHOGEN, p.id, IsoProjection.depth_key(pathogen_anchor(p)), -1.0)
			if p.blocker_id != 0:
				_breached[p.blocker_id] = true

	_expired.clear()
	for sid_var: Variant in _dying_s:
		var sid: int = sid_var
		var age: float = float(sim.tick - int(_dying_s[sid]))
		var ds: StructureState = sim.structure(sid)
		if ds == null or age >= float(AnimDriver.death_ticks_for(ds.type_id)):
			_expired.append(sid)
		else:
			_take_item(KIND_STRUCTURE, sid, IsoProjection.depth_key(structure_anchor(ds)), age)
	for sid: int in _expired:
		_dying_s.erase(sid)
	_expired.clear()
	for uid_var: Variant in _dying_p:
		var uid: int = uid_var
		var age: float = float(sim.tick - int(_dying_p[uid]))
		var dp: PathogenState = sim.pathogen(uid)
		if dp == null or age >= float(AnimDriver.death_ticks_for(dp.type_id)):
			_expired.append(uid)
		else:
			_take_item(KIND_PATHOGEN, uid, IsoProjection.depth_key(Vector2(dp.pos) / 1000.0), age)
	for uid: int in _expired:
		_dying_p.erase(uid)
	_expired.clear()

	_sorted.sort_custom(_sort_cmp)


## (kind, id) of every item in paint order, so tests can check the sort without rendering.
func build_draw_order() -> Array[Vector2i]:
	_collect()
	var out: Array[Vector2i] = []
	for item: UnitDrawItem in _sorted:
		out.append(Vector2i(item.kind, item.id))
	return out


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	_collect()
	last_item_count = _sorted.size()
	if sim == null or projection == null:
		return
	_refresh_wall_cache()
	_draw_ground_decals()
	for item: UnitDrawItem in _sorted:
		if item.kind == KIND_STRUCTURE:
			_draw_structure(sim.structure(item.id))
		else:
			_draw_pathogen(sim.pathogen(item.id))


func _refresh_wall_cache() -> void:
	var key := Vector3(projection.tile_px, projection.origin.x, projection.origin.y)
	if key != _faces_key:
		_faces_key = key
		_wall_faces.clear()


func _faces_for(s: StructureState) -> Array[PackedVector2Array]:
	if not _wall_faces.has(s.id):
		_wall_faces[s.id] = PlaceholderBillboard.wall_faces(projection, s.origin)
	return _wall_faces[s.id]


func _draw_ground_decals() -> void:
	draw_set_transform_matrix(projection.ground_transform())
	var ring_alpha: float = SCORCH_ALPHA / float(SCORCH_RINGS) * 1.4
	for sid: int in _scorch:
		var dead: StructureState = sim.structure(sid)
		if dead == null:
			continue
		var dc: Vector2 = structure_anchor(dead)
		for i: int in range(SCORCH_RINGS):
			var r: float = SCORCH_DIAMETER_T * 0.5 * (1.0 - float(i) / float(SCORCH_RINGS))
			draw_circle(dc, r, Color(0.0, 0.0, 0.0, ring_alpha))
	for s: StructureState in sim.structures:
		if not s.alive or s.def == null or s.def.has_tag("wall"):
			continue
		var c: Vector2 = structure_anchor(s)
		if s.def.has_tag("core"):
			for i: int in range(GridView.BLOB_RINGS):
				draw_circle(c, PLATE_CORE_RADIUS * 1.3 * (1.0 - float(i) / float(GridView.BLOB_RINGS)), NUCLEUS_GLOW)
			draw_circle(c, PLATE_CORE_RADIUS, NUCLEUS_PLATE)
		else:
			draw_circle(c, PLATE_TOWER_RADIUS, PLATE_FILL)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_structure(s: StructureState) -> void:
	if s == null:
		return
	var aim_ground: Vector2 = Vector2.ZERO
	if s.target_id != 0:
		var tp: PathogenState = sim.pathogen(s.target_id)
		if tp != null and tp.alive:
			aim_ground = pathogen_anchor(tp)
	var pose: ModelPose = driver.pose_for_structure(s, sim.tick, aim_ground, view_time)
	if s.def != null and s.def.has_tag("wall"):
		PlaceholderBillboard.draw_wall_faces(self, _faces_for(s), false, PlaceholderPainter.HIT_WHITE * pose.hit_t, 1.0 - pose.death_t)
		if pose.anim != ModelPose.Anim.DEAD and _breached.has(s.id) and s.hp > 0:
			_draw_cracks(_faces_for(s), crack_count(s.hp, s.max_hp))
		return
	var foot: Vector2 = projection.ground_to_screen(structure_anchor(s))
	ModelRegistry.painter_for(s.type_id).paint(self, foot, pose, projection.tile_px)


func _draw_cracks(faces: Array[PackedVector2Array], count: int) -> void:
	var pulse: float = fmod(float(Time.get_ticks_msec()) / 1000.0, CRACK_PULSE_PERIOD_S)
	var a: float = lerpf(0.6, 1.0, 0.5 + 0.5 * sin(pulse / CRACK_PULSE_PERIOD_S * TAU))
	var col := Color(0.23, 0.18, 0.18, a)
	var width: float = maxf(1.0, projection.tile_px / 14.0 * 1.5)
	for f: int in range(2):
		var q: PackedVector2Array = faces[f]
		for i: int in range(count):
			var uv: Array = CRACKS[i]
			var pts := PackedVector2Array()
			for pt_var: Variant in uv:
				var pt: Vector2 = pt_var
				var top: Vector2 = q[0].lerp(q[1], pt.x)
				var bottom: Vector2 = q[3].lerp(q[2], pt.x)
				pts.append(top.lerp(bottom, pt.y))
			draw_polyline(pts, col, width)


func _draw_pathogen(p: PathogenState) -> void:
	if p == null:
		return
	var ground: Vector2 = pathogen_anchor(p) if p.alive else Vector2(p.pos) / 1000.0
	var target_ground: Vector2 = ground
	var tid: int = p.attacking_id()
	if tid != 0:
		var ts: StructureState = sim.structure(tid)
		if ts != null:
			target_ground = structure_anchor(ts)
	var moved: float = driver.moved_since_last(p.id, ground) if p.alive else 0.0
	var pose: ModelPose = driver.pose_for_pathogen(p, sim.tick, ground, target_ground, moved, view_time)
	ModelRegistry.painter_for(p.type_id).paint(self, projection.ground_to_screen(ground), pose, projection.tile_px)
