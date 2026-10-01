class_name AnimDriver
extends RefCounted

## Turns sim state and events into a ModelPose (docs/MODEL_PIPELINE_PLAN.md sections 3.2, 4 and 5).
## Read-only: it never writes to the sim, so animation cannot change a battle's outcome.
##
## Tick convention: the sim stamps an event with the tick it happened in, then increments its tick at the
## end of step(). The view sees the state after that step, so every recorded tick is event tick + 1
## (the tick the view first sees it). A strike therefore reads as ticks_since_strike == 0 on the step
## that applied the damage.

const WINDUP_CAP_TICKS: int = 12
const HIT_DECAY_TICKS: int = 4
const WALL_SHAKE_TICKS: int = 3
const DEATH_TICKS: Dictionary = {"rhinovirus": 8, "bacteriophage": 14, "staphylococcus": 18,
	"macrophage": 16, "b_cell": 20, "nucleus": 40, "mucous_wall": 10, "mitochondria": 18, "dendritic_cell": 14}
const STRIDE_TILES: Dictionary = {"rhinovirus": 1.6, "bacteriophage": 2.0, "staphylococcus": 1.2}
const TOWER_CHARGE_TICKS: int = 6      # B-Cell charge glow before a shot
const TOWER_RECOIL_TICKS: int = 6      # B-Cell recoil after a shot

const DEFAULT_DEATH_TICKS: int = 10
const DEFAULT_STRIDE_TILES: float = 1.5
const NEVER: int = -1000000
const FACING_DEADZONE: float = 0.01
const IDLE_DESYNC_SECONDS: float = 10.0
const STRIKE_T: float = 0.5
const B_CELL_ID: String = "b_cell"
const NUCLEUS_ID: String = "nucleus"
## Mitochondria idle pulse rate, and how long a Dendritic Cell's "present" pulse lasts after ANALYSIS_SHARED.
const MITO_PULSE_HZ: float = 0.35
const PRESENT_TICKS: int = 8
## Seconds for a tower's aim_lock to go from 0 to 1 (or back) as it gains or loses a target.
const AIM_LOCK_S: float = 0.2
## Longest view-clock step fed to the time-integrated pose fields, so a hitch does not jump them.
const MAX_VIEW_STEP_S: float = 0.1

var reduce_flashes: bool = false

var _strike_p: Dictionary = {}     # unit id -> tick of its last strike
var _hit_p: Dictionary = {}        # unit id -> tick of its last hit
var _death_p: Dictionary = {}      # unit id -> death tick
var _hit_s: Dictionary = {}        # structure id -> tick of its last hit
var _death_s: Dictionary = {}      # structure id -> death tick
var _fire_s: Dictionary = {}       # structure id -> tick of its last shot
var _present_s: Dictionary = {}    # Dendritic Cell id -> tick it last shared an analysis
var _poses_p: Dictionary = {}      # unit id -> reused ModelPose
var _poses_s: Dictionary = {}      # structure id -> reused ModelPose
var _last_ground_p: Dictionary = {}    # unit id -> ground position at the previous pose call
var _last_time_s: Dictionary = {}      # structure id -> view_time at the previous pose call
var _latest_tick: int = 0


func _init(p_reduce_flashes: bool = false) -> void:
	reduce_flashes = p_reduce_flashes


# --- pure functions ---------------------------------------------------------

static func windup_ticks(interval_ticks: int) -> int:
	return mini(WINDUP_CAP_TICKS, interval_ticks * 2 / 5)


static func recover_ticks(interval_ticks: int) -> int:
	return mini(interval_ticks - windup_ticks(interval_ticks), maxi(2, interval_ticks * 2 / 5))


static func advance_gait(phase: float, moved_tiles: float, stride_tiles: float) -> float:
	if moved_tiles == 0.0 or stride_tiles <= 0.0:
		return phase
	return fposmod(phase + moved_tiles / stride_tiles, 1.0)


## A 0..1 phase advanced by `dt_s` seconds at `rate_hz`. Integrating the rate (instead of sin(time * rate))
## keeps the phase continuous when the rate changes.
static func advance_pulse(phase: float, dt_s: float, rate_hz: float) -> float:
	return fposmod(phase + maxf(dt_s, 0.0) * rate_hz, 1.0)


## A tower's aim_lock moved `dt_s` seconds toward 1 while it has a target, toward 0 otherwise.
static func ease_lock(lock: float, has_target: bool, dt_s: float) -> float:
	return move_toward(lock, 1.0 if has_target else 0.0, maxf(dt_s, 0.0) / AIM_LOCK_S)


static func facing_right(from_ground: Vector2, to_ground: Vector2, current: bool) -> bool:
	var dx: float = (to_ground.x - to_ground.y) - (from_ground.x - from_ground.y)
	if absf(dx) < FACING_DEADZONE:
		return current
	return dx > 0.0


static func flash_amount(ticks_since_hit: int, reduce: bool) -> float:
	if reduce:
		return 0.0
	return clampf(1.0 - float(ticks_since_hit) / float(HIT_DECAY_TICKS), 0.0, 1.0)


static func shake_amount(ticks_since_hit: int, reduce: bool, decay_ticks: int = HIT_DECAY_TICKS) -> float:
	var s: float = clampf(1.0 - float(ticks_since_hit) / float(maxi(decay_ticks, 1)), 0.0, 1.0)
	return s * 0.5 if reduce else s


static func death_t(ticks_since_death: int, death_ticks: int) -> float:
	if death_ticks <= 0:
		return 1.0
	return clampf(float(ticks_since_death) / float(death_ticks), 0.0, 1.0)


## Returns Vector2(anim, attack_t). See the table in the issue (#65) for the rules.
static func pathogen_attack(state: PathogenState.State, cooldown: int, interval_ticks: int, ticks_since_strike: int) -> Vector2:
	var recover: int = recover_ticks(interval_ticks)
	var windup: int = windup_ticks(interval_ticks)
	if ticks_since_strike == 0:
		return Vector2(float(ModelPose.Anim.STRIKE), STRIKE_T)
	if ticks_since_strike > 0 and ticks_since_strike <= recover:
		return Vector2(float(ModelPose.Anim.RECOVER), 0.6 + 0.4 * float(ticks_since_strike) / float(recover))
	if state == PathogenState.State.ATTACKING and windup > 0 and cooldown <= windup:
		return Vector2(float(ModelPose.Anim.WINDUP), 0.4 * (1.0 - float(cooldown) / float(windup)))
	if state == PathogenState.State.MOVING:
		return Vector2(float(ModelPose.Anim.MOVE), 0.0)
	return Vector2(float(ModelPose.Anim.IDLE), 0.0)


## The tick the view first sees an event's effect (event tick + 1). `fallback` is the view's current
## tick, used when an event carries no tick.
static func event_tick(ev: Dictionary, fallback: int) -> int:
	return int(ev.get("tick", fallback - 1)) + 1


static func death_ticks_for(type_id: String) -> int:
	return int(DEATH_TICKS.get(type_id, DEFAULT_DEATH_TICKS))


# --- events -----------------------------------------------------------------

## Feed every drained SimEvents dictionary.
func on_event(ev: Dictionary) -> void:
	var t: int = event_tick(ev, _latest_tick)
	match str(ev.get("type", "")):
		SimEvents.STRUCTURE_DAMAGED:
			var src: int = int(ev.get("source_unit_id", 0))
			if src != 0:
				_strike_p[src] = t
			_hit_s[int(ev.get("structure_id", 0))] = t
		SimEvents.PATHOGEN_DAMAGED:
			_hit_p[int(ev.get("unit_id", 0))] = t
		SimEvents.PATHOGEN_KILLED:
			var uid: int = int(ev.get("unit_id", 0))
			if not _death_p.has(uid):
				_death_p[uid] = t
		SimEvents.STRUCTURE_DESTROYED:
			var sid: int = int(ev.get("structure_id", 0))
			if not _death_s.has(sid):
				_death_s[sid] = t
		SimEvents.TOWER_FIRED:
			_fire_s[int(ev.get("structure_id", 0))] = t
		SimEvents.ANALYSIS_SHARED:
			_present_s[int(ev.get("presenter_id", 0))] = t


## Ticks since a pathogen died, or -1 while it is alive.
func pathogen_death_age(id: int, sim_tick: int) -> int:
	return sim_tick - int(_death_p[id]) if _death_p.has(id) else -1


## Ticks since a structure was destroyed, or -1 while it stands.
func structure_death_age(id: int, sim_tick: int) -> int:
	return sim_tick - int(_death_s[id]) if _death_s.has(id) else -1


## Distance in tiles a pathogen moved since the last pose_for_pathogen call for it.
func moved_since_last(id: int, ground: Vector2) -> float:
	if not _last_ground_p.has(id):
		return 0.0
	var last: Vector2 = _last_ground_p[id]
	return last.distance_to(ground)


# --- poses ------------------------------------------------------------------

func pose_for_pathogen(p: PathogenState, sim_tick: int, ground: Vector2, target_ground: Vector2, moved_tiles: float, view_time: float) -> ModelPose:
	_latest_tick = sim_tick
	var pose: ModelPose = _pose(_poses_p, p.id)
	pose.seed = p.id
	pose.time = view_time + ViewRng.hash01(p.id, 1) * IDLE_DESYNC_SECONDS
	pose.hp_frac = _hp_frac(p.hp, p.max_hp)
	pose.aim = Vector2.ZERO
	var last: Vector2 = _last_ground_p.get(p.id, ground)
	_last_ground_p[p.id] = ground

	if _death_p.has(p.id):
		_apply_death(pose, sim_tick - int(_death_p[p.id]), death_ticks_for(p.type_id))
		return pose

	if p.state == PathogenState.State.ATTACKING and p.attacking_id() != 0:
		pose.facing_right = facing_right(ground, target_ground, pose.facing_right)
	elif moved_tiles > 0.0:
		pose.facing_right = facing_right(last, ground, pose.facing_right)
	pose.gait_phase = advance_gait(pose.gait_phase, moved_tiles, float(STRIDE_TILES.get(p.type_id, DEFAULT_STRIDE_TILES)))

	var interval: int = p.def.attack_interval_ticks if p.def != null else 0
	var since_strike: int = sim_tick - int(_strike_p.get(p.id, NEVER))
	var res: Vector2 = pathogen_attack(p.state, p.attack_cooldown, interval, since_strike)
	pose.anim = int(res.x) as ModelPose.Anim
	pose.attack_t = res.y
	pose.death_t = 0.0
	_apply_hit(pose, sim_tick - int(_hit_p.get(p.id, NEVER)))
	return pose


## The pose pose_for_structure last built for a structure, or null. Lets a second draw item of the same
## structure in one frame (a wall's post or cracks) reuse it instead of building it again.
func last_structure_pose(id: int) -> ModelPose:
	return _poses_s.get(id)


## `has_aim` is false when the tower still holds a target id that no longer resolves to a live unit (the sim
## clears it on its next tick); the tower then keeps its previous aim and facing instead of turning to
## `aim_ground`.
func pose_for_structure(s: StructureState, sim_tick: int, aim_ground: Vector2, view_time: float, has_aim: bool = true) -> ModelPose:
	_latest_tick = sim_tick
	var fresh: bool = not _poses_s.has(s.id)
	var pose: ModelPose = _pose(_poses_s, s.id)
	pose.seed = s.id
	pose.time = view_time + ViewRng.hash01(s.id, 1) * IDLE_DESYNC_SECONDS
	pose.hp_frac = _hp_frac(s.hp, s.max_hp)
	if fresh:
		pose.pulse_phase = ViewRng.hash01(s.id, 2)
	var dt: float = clampf(view_time - float(_last_time_s.get(s.id, view_time)), 0.0, MAX_VIEW_STEP_S)
	_last_time_s[s.id] = view_time

	if _death_s.has(s.id):
		_apply_death(pose, sim_tick - int(_death_s[s.id]), death_ticks_for(s.type_id))
		return pose

	if s.type_id == NUCLEUS_ID:
		pose.pulse_phase = advance_pulse(pose.pulse_phase, dt, NucleusPainter.pulse_rate(pose.hp_frac))
	elif s.def != null and s.def.has_generator and not reduce_flashes:
		# The Mitochondria pulse; Reduce flashes holds the clock still.
		pose.pulse_phase = advance_pulse(pose.pulse_phase, dt, MITO_PULSE_HZ)
	pose.death_t = 0.0
	pose.anim = ModelPose.Anim.IDLE
	pose.attack_t = 0.0
	if s.def != null and s.def.has_attack:
		_tower_attack(pose, s, sim_tick, aim_ground, has_aim)
		pose.aim_lock = ease_lock(pose.aim_lock, s.target_id != 0, dt)
	else:
		pose.aim = Vector2.ZERO
		pose.aim_lock = 0.0
	if s.def != null and s.def.has_presenter and not reduce_flashes:
		var since_present: int = sim_tick - int(_present_s.get(s.id, NEVER))
		if since_present >= 0 and since_present < PRESENT_TICKS:
			pose.anim = ModelPose.Anim.STRIKE
			pose.attack_t = float(since_present) / float(PRESENT_TICKS)
	var since_hit: int = sim_tick - int(_hit_s.get(s.id, NEVER))
	_apply_hit(pose, since_hit)
	if s.def != null and s.def.has_tag("wall"):
		pose.shake = shake_amount(since_hit, reduce_flashes, WALL_SHAKE_TICKS)
	return pose


func _tower_attack(pose: ModelPose, s: StructureState, sim_tick: int, aim_ground: Vector2, has_aim: bool) -> void:
	var anchor: Vector2 = Vector2(s.origin) + Vector2(s.footprint) * 0.5
	if s.target_id == 0:
		pose.aim = Vector2.ZERO
	elif has_aim:
		var d: Vector2 = aim_ground - anchor
		var screen: Vector2 = Vector2(d.x - d.y, (d.x + d.y) * 0.5)
		if screen.length_squared() > 0.000001:
			pose.aim = screen.normalized()
		pose.facing_right = facing_right(anchor, aim_ground, pose.facing_right)
	var since_fire: int = sim_tick - int(_fire_s.get(s.id, NEVER))
	var res: Vector2 = tower_attack(s.type_id, s.target_id != 0, s.attack_cooldown, s.def.attack_interval_ticks, since_fire)
	pose.anim = int(res.x) as ModelPose.Anim
	pose.attack_t = res.y


## Returns Vector2(anim, attack_t) for a tower. The B-Cell charges over the last TOWER_CHARGE_TICKS of its
## cooldown (WINDUP, attack_t 0 to 1), fires (STRIKE, 1) and recoils for TOWER_RECOIL_TICKS (RECOVER, 0 to
## 1). Other towers use the pathogen windup, strike and recover timing.
static func tower_attack(type_id: String, has_target: bool, cooldown: int, interval_ticks: int, since_fire: int) -> Vector2:
	if type_id == B_CELL_ID:
		if since_fire == 0:
			return Vector2(float(ModelPose.Anim.STRIKE), 1.0)
		if since_fire > 0 and since_fire <= TOWER_RECOIL_TICKS:
			return Vector2(float(ModelPose.Anim.RECOVER), float(since_fire) / float(TOWER_RECOIL_TICKS))
		if has_target and cooldown <= TOWER_CHARGE_TICKS:
			return Vector2(float(ModelPose.Anim.WINDUP), 1.0 - float(cooldown) / float(TOWER_CHARGE_TICKS))
		return Vector2(float(ModelPose.Anim.IDLE), 0.0)
	var windup: int = windup_ticks(interval_ticks)
	var recover: int = recover_ticks(interval_ticks)
	if since_fire == 0:
		return Vector2(float(ModelPose.Anim.STRIKE), STRIKE_T)
	if since_fire > 0 and since_fire <= recover:
		return Vector2(float(ModelPose.Anim.RECOVER), 0.6 + 0.4 * float(since_fire) / float(recover))
	if has_target and windup > 0 and cooldown <= windup:
		return Vector2(float(ModelPose.Anim.WINDUP), 0.4 * (1.0 - float(cooldown) / float(windup)))
	return Vector2(float(ModelPose.Anim.IDLE), 0.0)


func _apply_hit(pose: ModelPose, ticks_since_hit: int) -> void:
	pose.hit_t = flash_amount(ticks_since_hit, reduce_flashes)
	pose.shake = shake_amount(ticks_since_hit, reduce_flashes)


func _apply_death(pose: ModelPose, ticks_since_death: int, death_ticks: int) -> void:
	pose.anim = ModelPose.Anim.DEAD
	pose.death_t = death_t(ticks_since_death, death_ticks)
	pose.attack_t = 0.0
	pose.hit_t = 0.0
	pose.shake = 0.0


static func _hp_frac(hp: int, max_hp: int) -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


static func _pose(pool: Dictionary, id: int) -> ModelPose:
	if not pool.has(id):
		pool[id] = ModelPose.new()
	return pool[id]
