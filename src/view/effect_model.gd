class_name EffectModel
extends RefCounted

## Transient battle effects as plain data (issue #71, docs/MODEL_PIPELINE_PLAN.md section 3.4): projectiles,
## hit sparks, Macrophage vesicles, splash rings, puffs and scorch decals. EffectLayer draws them. Read-only
## with respect to the sim.
##
## Storage is allocated once. Transient effects live in a ring of TRANSIENT_CAPACITY slots: when it is full
## the oldest effect is dropped. Scorch decals stay for the rest of the battle in their own ring of
## SCORCH_CAPACITY slots, so a burst of puffs never wipes them. Together they hold at most CAPACITY effects.
##
## Ticks follow AnimDriver.event_tick(): an effect starts on the tick the view first sees its event.

enum Kind { NONE, PROJECTILE, SPARK, VESICLE, SPLASH, PUFF }

const CAPACITY: int = 256
const SCORCH_CAPACITY: int = 64
const TRANSIENT_CAPACITY: int = CAPACITY - SCORCH_CAPACITY

const SPARK_TICKS: int = 4
const VESICLE_TICKS: int = 4
const SPLASH_TICKS: int = 6
const PUFF_TICKS: int = 8
## A projectile normally ends on its PROJECTILE_HIT or PROJECTILE_FIZZLED event; this only bounds one whose
## end event never reached the view.
const PROJECTILE_MAX_TICKS: int = 400

const MT_PER_TILE: float = 1000.0

## Hit sparks are not created at all (Settings: Reduce screen flashes).
var reduce_flashes: bool = false

# Transient ring, one entry per slot. Slot of the i-th oldest effect: (_head + i) % TRANSIENT_CAPACITY.
var kind: PackedInt32Array = PackedInt32Array()
## Projectile id (PROJECTILE), structure id (SPLASH, VESICLE), unit or structure id (SPARK, PUFF).
var ref_id: PackedInt32Array = PackedInt32Array()
var start: PackedInt32Array = PackedInt32Array()
var ticks: PackedInt32Array = PackedInt32Array()
## Ground position in tiles: the target (SPARK), the centre (SPLASH, PUFF), the launch point (VESICLE,
## PROJECTILE).
var pos_a: PackedVector2Array = PackedVector2Array()
## Ground position in tiles of a vesicle's landing point.
var pos_b: PackedVector2Array = PackedVector2Array()
## Splash radius in tiles; for a spark or puff, the model height in tiles of what it sits on.
var radius: PackedFloat32Array = PackedFloat32Array()

var scorch_pos: PackedVector2Array = PackedVector2Array()
var scorch_id: PackedInt32Array = PackedInt32Array()
## Bumped whenever the scorch list changes, so the layer rebuilds its cached decal mesh only then.
var scorch_version: int = 0

var _head: int = 0
var _count: int = 0
var _scorch_head: int = 0
var _scorch_count: int = 0
var _now: int = 0


func _init(p_reduce_flashes: bool = false) -> void:
	reduce_flashes = p_reduce_flashes
	kind.resize(TRANSIENT_CAPACITY)
	ref_id.resize(TRANSIENT_CAPACITY)
	start.resize(TRANSIENT_CAPACITY)
	ticks.resize(TRANSIENT_CAPACITY)
	pos_a.resize(TRANSIENT_CAPACITY)
	pos_b.resize(TRANSIENT_CAPACITY)
	radius.resize(TRANSIENT_CAPACITY)
	scorch_pos.resize(SCORCH_CAPACITY)
	scorch_id.resize(SCORCH_CAPACITY)


func reset() -> void:
	_head = 0
	_count = 0
	_scorch_head = 0
	_scorch_count = 0
	_now = 0
	scorch_version += 1


func active_count() -> int:
	return _count + _scorch_count


## Number of transient effects; the slots are slot(0) to slot(transient_count() - 1), oldest first.
func transient_count() -> int:
	return _count


func slot(i: int) -> int:
	return (_head + i) % TRANSIENT_CAPACITY


func scorch_count() -> int:
	return _scorch_count


func scorch_slot(i: int) -> int:
	return (_scorch_head + i) % SCORCH_CAPACITY


func count_of(k: Kind) -> int:
	var n: int = 0
	for i: int in range(_count):
		if kind[slot(i)] == k:
			n += 1
	return n


## Slot of the newest effect of `k` with this ref id, or -1.
func find(k: Kind, id: int) -> int:
	for i: int in range(_count - 1, -1, -1):
		var s: int = slot(i)
		if kind[s] == k and ref_id[s] == id:
			return s
	return -1


## Ticks since an effect started, at `tick`. Negative while it waits to start (a delayed splash ring).
func age(s: int, tick: int) -> int:
	return tick - start[s]


## 0..1 progress of an effect at the fractional view tick `now`.
func progress(s: int, now: float) -> float:
	return clampf((now - float(start[s])) / float(maxi(ticks[s], 1)), 0.0, 1.0)


# --- events -----------------------------------------------------------------

func on_event(ev: Dictionary, sim: BattleSim) -> void:
	var fallback: int = sim.tick if sim != null else _now
	var t: int = AnimDriver.event_tick(ev, fallback)
	match str(ev.get("type", "")):
		SimEvents.PROJECTILE_SPAWNED:
			var src: StructureState = sim.structure(int(ev.get("structure_id", 0))) if sim != null else null
			var from: Vector2 = Vector2(src.center) / MT_PER_TILE if src != null else Vector2.ZERO
			_push(Kind.PROJECTILE, int(ev.get("projectile_id", 0)), t, PROJECTILE_MAX_TICKS, from, from, 0.0)
		SimEvents.PROJECTILE_HIT:
			_remove(find(Kind.PROJECTILE, int(ev.get("projectile_id", 0))))
			if not reduce_flashes:
				var uid: int = int(ev.get("target_unit_id", 0))
				var p: PathogenState = sim.pathogen(uid) if sim != null else null
				var at: Vector2 = Vector2(p.pos) / MT_PER_TILE if p != null else Vector2.ZERO
				_push(Kind.SPARK, uid, t, SPARK_TICKS, at, at, _height_t(p.type_id if p != null else ""))
		SimEvents.PROJECTILE_FIZZLED:
			_remove(find(Kind.PROJECTILE, int(ev.get("projectile_id", 0))))
		SimEvents.SPLASH:
			var pos_mt: Vector2i = ev.get("pos", Vector2i.ZERO)
			var c: Vector2 = Vector2(pos_mt) / MT_PER_TILE
			_push(Kind.SPLASH, int(ev.get("structure_id", 0)), t, SPLASH_TICKS, c, c, float(int(ev.get("radius", 0))) / MT_PER_TILE)
		SimEvents.TOWER_FIRED:
			_on_tower_fired(ev, sim, t)
		SimEvents.PATHOGEN_KILLED:
			var type_id: String = str(ev.get("unit_type", ""))
			var uid: int = int(ev.get("unit_id", 0))
			var p: PathogenState = sim.pathogen(uid) if sim != null else null
			if type_id == "" and p != null:
				type_id = p.type_id
			if p != null and not ModelRegistry.painter_for(type_id).has_custom_death():
				var at: Vector2 = Vector2(p.pos) / MT_PER_TILE
				_push(Kind.PUFF, uid, t, PUFF_TICKS, at, at, _height_t(type_id))
		SimEvents.STRUCTURE_DESTROYED:
			var sid: int = int(ev.get("structure_id", 0))
			var s: StructureState = sim.structure(sid) if sim != null else null
			if s == null:
				return
			if s.def != null and s.def.has_tag("wall"):
				return
			var anchor: Vector2 = UnitLayer.structure_anchor(s)
			_add_scorch(sid, anchor)
			if not ModelRegistry.painter_for(s.type_id).has_custom_death():
				_push(Kind.PUFF, sid, t, PUFF_TICKS, anchor, anchor, _height_t(s.type_id))


## A splash tower's shot: a vesicle flies from the tower to where the splash landed, and the ring that the
## sim emitted just before this event (SPLASH comes first in the same tick) waits for it to arrive.
func _on_tower_fired(ev: Dictionary, sim: BattleSim, t: int) -> void:
	if sim == null:
		return
	var sid: int = int(ev.get("structure_id", 0))
	var s: StructureState = sim.structure(sid)
	if s == null or s.def == null or s.def.splash_radius_mt <= 0:
		return
	var to: Vector2 = Vector2.ZERO
	var ring: int = find(Kind.SPLASH, sid)
	if ring >= 0 and start[ring] == t:
		to = pos_a[ring]
		# The sim applies the splash damage on the fire tick, so hit flashes, bars and deaths lead the ring
		# by VESICLE_TICKS.
		start[ring] = t + VESICLE_TICKS
	else:
		var p: PathogenState = sim.pathogen(int(ev.get("target_unit_id", 0)))
		if p == null:
			return
		to = Vector2(p.pos) / MT_PER_TILE
	_push(Kind.VESICLE, sid, t, VESICLE_TICKS, UnitLayer.structure_anchor(s), to, 0.0)


static func _height_t(type_id: String) -> float:
	return float(ModelRegistry.HEIGHT_T.get(type_id, ModelRegistry.DEFAULT_HEIGHT_T)) if type_id != "" else 1.0


# --- time -------------------------------------------------------------------

## Drops every transient effect that has ended by `tick`, keeping the rest in order. Scorch never expires.
func advance(tick: int) -> void:
	_now = tick
	var kept: int = 0
	for i: int in range(_count):
		var s: int = slot(i)
		if kind[s] == Kind.NONE or tick >= start[s] + ticks[s]:
			continue
		if kept != i:
			_copy(s, slot(kept))
		kept += 1
	_count = kept


# --- ring -------------------------------------------------------------------

func _push(k: Kind, id: int, t: int, life: int, a: Vector2, b: Vector2, r: float) -> void:
	if _count == TRANSIENT_CAPACITY:
		_head = (_head + 1) % TRANSIENT_CAPACITY
		_count -= 1
	var s: int = slot(_count)
	_count += 1
	kind[s] = k
	ref_id[s] = id
	start[s] = t
	ticks[s] = life
	pos_a[s] = a
	pos_b[s] = b
	radius[s] = r


func _remove(s: int) -> void:
	if s < 0:
		return
	var i: int = (s - _head + TRANSIENT_CAPACITY) % TRANSIENT_CAPACITY
	for j: int in range(i, _count - 1):
		_copy(slot(j + 1), slot(j))
	_count -= 1


func _copy(from: int, to: int) -> void:
	kind[to] = kind[from]
	ref_id[to] = ref_id[from]
	start[to] = start[from]
	ticks[to] = ticks[from]
	pos_a[to] = pos_a[from]
	pos_b[to] = pos_b[from]
	radius[to] = radius[from]


func _add_scorch(sid: int, at: Vector2) -> void:
	for i: int in range(_scorch_count):
		if scorch_id[scorch_slot(i)] == sid:
			return
	if _scorch_count == SCORCH_CAPACITY:
		_scorch_head = (_scorch_head + 1) % SCORCH_CAPACITY
		_scorch_count -= 1
	var s: int = scorch_slot(_scorch_count)
	_scorch_count += 1
	scorch_id[s] = sid
	scorch_pos[s] = at
	scorch_version += 1
