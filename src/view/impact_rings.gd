class_name ImpactRings
extends Node2D

## Debug layer (issue #72): a small white ring on the ground wherever STRUCTURE_DAMAGED or PATHOGEN_DAMAGED
## fires, so the strike frames of the painters can be checked against the sim's impact ticks.
## Off unless `enabled` is set (the "Show impact ticks" toggle in the debug overlay). Read-only with respect
## to the sim. The ring buffer is fixed, so nothing is allocated per frame.

## Global switch, shared by every battle view; the debug overlay flips it.
static var enabled: bool = false

const CAPACITY: int = 128
## Ticks a ring stays on screen after the event.
const LIFE_TICKS: int = 8
const RADIUS_TILES: float = 0.45
const WIDTH_TILES: float = 0.08
const POINTS: int = 24
const RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)

var sim: BattleSim = null
var projection: IsoProjection = null
var runner: BattleRunner = null

var _tick: PackedInt32Array = PackedInt32Array()
var _pos: PackedVector2Array = PackedVector2Array()
var _head: int = 0
var _count: int = 0


func _init() -> void:
	_tick.resize(CAPACITY)
	_pos.resize(CAPACITY)


func setup(p_sim: BattleSim, p_projection: IsoProjection, p_runner: BattleRunner) -> void:
	sim = p_sim
	projection = p_projection
	runner = p_runner
	_head = 0
	_count = 0
	queue_redraw()


## Rings alive at `tick`.
func active_count(tick: int) -> int:
	var n: int = 0
	for i: int in range(_count):
		if tick - _tick[(_head + i) % CAPACITY] <= LIFE_TICKS:
			n += 1
	return n


func on_event(ev: Dictionary) -> void:
	if not enabled or sim == null:
		return
	var at: Vector2 = Vector2.ZERO
	match str(ev.get("type", "")):
		SimEvents.PATHOGEN_DAMAGED:
			var p: PathogenState = sim.pathogen(int(ev.get("unit_id", 0)))
			if p == null:
				return
			at = Vector2(p.pos) / 1000.0
		SimEvents.STRUCTURE_DAMAGED:
			var s: StructureState = sim.structure(int(ev.get("structure_id", 0)))
			if s == null:
				return
			at = Vector2(s.center) / 1000.0
		_:
			return
	_push(AnimDriver.event_tick(ev, sim.tick), at)


func _push(t: int, at: Vector2) -> void:
	if _count == CAPACITY:
		_head = (_head + 1) % CAPACITY
		_count -= 1
	var s: int = (_head + _count) % CAPACITY
	_tick[s] = t
	_pos[s] = at
	_count += 1


func _process(_delta: float) -> void:
	if sim == null:
		return
	while _count > 0 and sim.tick - _tick[_head] > LIFE_TICKS:
		_head = (_head + 1) % CAPACITY
		_count -= 1
	# A redraw while paused is harmless, and one more after the switch goes off clears the last rings.
	if enabled or _count > 0:
		queue_redraw()


func _draw() -> void:
	if not enabled or sim == null or projection == null or _count == 0:
		return
	draw_set_transform_matrix(projection.ground_transform())
	for i: int in range(_count):
		var s: int = (_head + i) % CAPACITY
		var age: int = sim.tick - _tick[s]
		var a: float = 1.0 - float(maxi(age, 0)) / float(LIFE_TICKS + 1)
		draw_arc(_pos[s], RADIUS_TILES, 0.0, TAU, POINTS, Color(RING_COLOR, RING_COLOR.a * a), WIDTH_TILES)
	draw_set_transform_matrix(Transform2D.IDENTITY)
