class_name UnitLayer
extends Node2D

## One depth-sorted isometric draw pass for every structure and pathogen (docs/MODEL_PIPELINE_PLAN.md
## section 6). No node per unit. Reads sim state through BattleSnapshotBuffer and never modifies it.

const KIND_STRUCTURE: int = 0
const KIND_PATHOGEN: int = 1
## A wall's post and its cracks are separate draw items just after the segment, so a unit standing on the
## same depth key sorts between them the way the canvas does.
const KIND_WALL_POST: int = 2
const KIND_WALL_CRACKS: int = 3
const WALL_POST_BIAS: float = 0.001
const WALL_CRACKS_BIAS: float = 0.002

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

const WALL_TYPE_ID: String = "mucous_wall"
## Draw pathogens from the baked atlas (SpriteBaker) instead of painting them every frame. On because the
## measurements in docs/PERF_BASELINE.md ("After M6") show the live painters miss the frame budget.
const USE_BAKED_SPRITES: bool = true
const CRACK_PULSE_LO: float = 0.6
const CRACK_PULSE_HI: float = 1.0


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
var _breached: Dictionary = {}
var _expired: Array[int] = []

var driver: AnimDriver = AnimDriver.new()
var baker: SpriteBaker = null
var _baked_key: Vector2 = Vector2(-1.0, -1.0)
## Its ground decals are painted in this layer's ground pass, under the sprites: scorch before the plates,
## splash rings after them.
var effects: EffectLayer = null
## Softer hit flashes and shake (Settings: Reduce screen flashes). Set by the phase; kept across setup().
var reduce_flashes: bool = false:
	set = set_reduce_flashes
## View clock in seconds for idle loops. Advances only while the battle runs and is not paused.
var view_time: float = 0.0
## Set by the phase while the Pause menu is open; freezes the view clock (and so every idle loop).
var paused: bool = false

## Connected wall segments for the live wall cells. Rebuilt when a wall is destroyed or the projection changes.
var walls: WallRenderer = WallRenderer.new()
var _wall_cells: Dictionary = {}
var _walls_dirty: bool = true
## Destroyed walls, by structure id, whose goo decal stays on the ground for the rest of the battle.
var _goo: Array[int] = []
var _proj_key: Vector4 = Vector4(-1.0, 0.0, 0.0, 0.0)
## Projection of the last pass, so a resize while paused still redraws once.
var _drawn_key: Vector4 = Vector4(-1.0, 0.0, 0.0, 0.0)


func setup(p_sim: BattleSim, p_config: GameConfig, p_projection: IsoProjection, p_snapshots: BattleSnapshotBuffer, p_runner: BattleRunner) -> void:
	sim = p_sim
	config = p_config
	projection = p_projection
	snapshots = p_snapshots
	runner = p_runner
	driver = AnimDriver.new(reduce_flashes)
	view_time = 0.0
	ModelRegistry.configure(config, projection.scale if projection != null else IsoProjection.DEFAULT_SCALE)
	ModelRegistry.reset_painters()
	_bake_sprites()
	_dying_p.clear()
	_dying_s.clear()
	_goo.clear()
	_walls_dirty = true
	_proj_key = Vector4(-1.0, 0.0, 0.0, 0.0)
	queue_redraw()


func set_reduce_flashes(value: bool) -> void:
	reduce_flashes = value
	if driver != null:
		driver.reduce_flashes = value
	queue_redraw()


func _process(delta: float) -> void:
	if sim == null:
		return
	if baker != null and projection != null and _bake_key() != _baked_key:
		_bake_sprites()
	if is_live():
		view_time += delta
		queue_redraw()
	elif projection != null and _projection_key() != _drawn_key:
		queue_redraw()


## True while the battle runs and is not paused: only then does the layer redraw every frame. Without a
## runner (tests and tools) there is no battle clock, so it keeps redrawing.
func is_live() -> bool:
	return runner == null or (runner.is_running and not runner.paused and not paused)


func _projection_key() -> Vector4:
	return Vector4(projection.tile_px, projection.origin.x, projection.origin.y, projection.scale)


# --- sizing, shared with the overlay ---------------------------------------

static func pathogen_size_t(type_id: String) -> Vector2:
	return PATHOGEN_SIZE_T.get(type_id, DEFAULT_PATHOGEN_SIZE_T)


## Sprite (width, height) in screen px for a structure.
static func structure_size_px(s: StructureState, proj: IsoProjection) -> Vector2:
	var t: float = proj.tile_px
	if s.def != null and s.def.has_tag("wall"):
		return Vector2(2.0 * t * proj.scale, WallRenderer.height_tiles(s.hp, s.max_hp) * t)
	var h_t: float = ModelRegistry.painter_for(s.type_id).height_tiles()
	return Vector2(float(s.footprint.x) * t * proj.scale * STRUCTURE_WIDTH_SCALE, h_t * t)


## The live unit a tower is aiming at, or null. After a kill the sim keeps target_id on the dead unit until
## its next tick, so a set target_id alone does not mean there is something to aim at.
static func live_target(p_sim: BattleSim, s: StructureState) -> PathogenState:
	if p_sim == null or s == null or s.target_id == 0:
		return null
	var tp: PathogenState = p_sim.pathogen(s.target_id)
	return tp if tp != null and tp.alive else null


static func structure_anchor(s: StructureState) -> Vector2:
	return Vector2(s.origin) + Vector2(s.footprint) * 0.5


## Crack colour alpha while a pathogen is breaking the wall: 0.6 to 1.0 on a 0.8 s cycle of the view clock.
static func crack_pulse_alpha(time_s: float) -> float:
	var phase: float = fposmod(time_s, CRACK_PULSE_PERIOD_S) / CRACK_PULSE_PERIOD_S
	return lerpf(CRACK_PULSE_LO, CRACK_PULSE_HI, 0.5 + 0.5 * sin(phase * TAU))


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
			if s.def != null and s.def.has_tag("wall"):
				# The segment and its neighbours' bridges go at once, leaving the gap; chunks and goo play there.
				_walls_dirty = true
				if not _goo.has(sid):
					_goo.append(sid)


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


func _collect() -> void:
	_pool_used = 0
	_breached.clear()
	if sim == null or projection == null:
		_sorted.resize(0)
		return
	# A wall that died without an event reaching the view still leaves its gap, before any post is read.
	if not _wall_cache_matches_sim():
		_walls_dirty = true
	_refresh_wall_cache()
	for p: PathogenState in sim.pathogens:
		if p.alive:
			_take_item(KIND_PATHOGEN, p.id, IsoProjection.depth_key(pathogen_anchor(p)), -1.0)
			if p.blocker_id != 0:
				_breached[p.blocker_id] = true
	for s: StructureState in sim.structures:
		if not s.alive:
			continue
		var key: float = IsoProjection.depth_key(structure_anchor(s))
		_take_item(KIND_STRUCTURE, s.id, key, -1.0)
		if s.def == null or not s.def.has_tag("wall"):
			continue
		var hurt: bool = s.hp * 2 < s.max_hp
		if not hurt and walls.has_post(s.origin):
			_take_item(KIND_WALL_POST, s.id, key + WALL_POST_BIAS, -1.0)
		if hurt or _breached.has(s.id):
			_take_item(KIND_WALL_CRACKS, s.id, key + WALL_CRACKS_BIAS, -1.0)

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

	# The sort array keeps its size from frame to frame, so it is refilled in place rather than regrown.
	if _sorted.size() != _pool_used:
		_sorted.resize(_pool_used)
	for i: int in range(_pool_used):
		_sorted[i] = _pool[i]
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
	_drawn_key = _projection_key()
	_draw_ground_decals()
	var n: int = _sorted.size()
	var i: int = 0
	while i < n:
		var item: UnitDrawItem = _sorted[i]
		i += 1
		match item.kind:
			KIND_STRUCTURE:
				var s: StructureState = sim.structure(item.id)
				# A post right behind its own segment in the order joins the segment's command.
				if i < n and _sorted[i].kind == KIND_WALL_POST and _sorted[i].id == item.id and item.age < 0.0:
					walls.paint_body_and_post(self, s.origin, _wall_pose(s))
					i += 1
				else:
					_draw_structure(s)
			KIND_PATHOGEN:
				_draw_pathogen(sim.pathogen(item.id))
			KIND_WALL_POST:
				var ps: StructureState = sim.structure(item.id)
				walls.paint_post(self, ps.origin, _wall_part_pose(ps))
			KIND_WALL_CRACKS:
				var cs: StructureState = sim.structure(item.id)
				var alpha: float = crack_pulse_alpha(view_time) if _breached.has(cs.id) else WallRenderer.CRACK_ALPHA
				walls.paint_cracks(self, cs.origin, cs.hp * 2 < cs.max_hp, alpha, _wall_part_pose(cs))


## True when the cached wall cells are exactly the live wall cells of the sim.
func _wall_cache_matches_sim() -> bool:
	var live: int = 0
	for s: StructureState in sim.structures:
		if s.alive and s.def != null and s.def.has_tag("wall"):
			live += 1
			if not _wall_cells.has(s.origin):
				return false
	return live == _wall_cells.size()


func _refresh_wall_cache() -> void:
	var key := Vector4(projection.tile_px, projection.origin.x, projection.origin.y, projection.scale)
	if key != _proj_key:
		_proj_key = key
		_walls_dirty = true
		# Painter state such as the staph trails is stored in screen space.
		ModelRegistry.reset_painters()
	if not _walls_dirty:
		return
	_walls_dirty = false
	_wall_cells.clear()
	for s: StructureState in sim.structures:
		if s.alive and s.def != null and s.def.has_tag("wall"):
			_wall_cells[s.origin] = true
	walls.rebuild(_wall_cells, projection)


## Bakes (or rebakes, when T or the screen scale changed) the pathogen atlas. Until it is ready the
## pathogens are painted live.
func _bake_sprites() -> void:
	if not USE_BAKED_SPRITES or config == null or projection == null or not is_inside_tree():
		return
	_baked_key = _bake_key()
	if baker == null:
		baker = SpriteBaker.new()
		baker.name = "SpriteBaker"
		add_child(baker, false, Node.INTERNAL_MODE_FRONT)
	var ids: Array[String] = []
	for id_var: Variant in config.pathogens:
		ids.append(str(id_var))
	ids.sort()
	baker.bake(ids, projection.tile_px, _bake_key().y)


## (tile px, screen scale): what an atlas depends on besides the types.
func _bake_key() -> Vector2:
	var xf: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	return Vector2(projection.tile_px, xf.get_scale().x)


func _wall_pose(s: StructureState) -> ModelPose:
	return driver.pose_for_structure(s, sim.tick, Vector2.ZERO, view_time)


## Posts and cracks sort after their segment, so the segment's pose from this frame is already built.
func _wall_part_pose(s: StructureState) -> ModelPose:
	var pose: ModelPose = driver.last_structure_pose(s.id)
	return pose if pose != null else _wall_pose(s)


func _draw_ground_decals() -> void:
	if effects != null:
		effects.draw_scorch(self)
	draw_set_transform_matrix(projection.ground_transform())
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
	if effects != null:
		effects.draw_splashes(self)
	var goo_ticks: float = float(AnimDriver.death_ticks_for(WALL_TYPE_ID))
	for sid: int in _goo:
		var gs: StructureState = sim.structure(sid)
		if gs == null:
			continue
		var age: int = driver.structure_death_age(sid, sim.tick)
		walls.paint_goo(self, gs.origin, clampf(float(age) / goo_ticks, 0.0, 1.0) if age >= 0 else 1.0)
	walls.paint_shadows(self)


func _draw_structure(s: StructureState) -> void:
	if s == null:
		return
	if s.def != null and s.def.has_tag("wall"):
		var wp: ModelPose = _wall_pose(s)
		if wp.anim == ModelPose.Anim.DEAD:
			walls.paint_break(self, s.origin, wp.death_t)
		else:
			walls.paint_body(self, s.origin, s.hp * 2 < s.max_hp, wp)
		return
	var tp: PathogenState = live_target(sim, s)
	var aim_ground: Vector2 = pathogen_anchor(tp) if tp != null else Vector2.ZERO
	var pose: ModelPose = driver.pose_for_structure(s, sim.tick, aim_ground, view_time, tp != null)
	var foot: Vector2 = projection.ground_to_screen(structure_anchor(s))
	ModelRegistry.painter_for(s.type_id).paint(self, foot, pose, projection.tile_px)


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
	var painter: ModelPainter = ModelRegistry.painter_for(p.type_id)
	var foot: Vector2 = projection.ground_to_screen(ground)
	# A painter's ground decals (trail, shockwave) go down just before the unit, so they sort with it.
	painter.paint_ground(self, foot, pose, projection.tile_px)
	if USE_BAKED_SPRITES and baker != null and baker.draw(self, p.type_id, pose, foot):
		return
	painter.paint(self, foot, pose, projection.tile_px)
