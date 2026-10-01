class_name BattleSnapshotBuffer
extends RefCounted

## Previous and current tick positions of every live pathogen and projectile, so the view can
## interpolate between sim ticks. Read-only with respect to the sim.

const MT_PER_TILE: float = 1000.0

## Pathogen id -> Vector2i pos_mt. Projectiles are keyed by the negated id, so the two id spaces never collide.
var prev: Dictionary = {}
var curr: Dictionary = {}


func reset() -> void:
	prev.clear()
	curr.clear()


## Call once after every sim.step(). Swaps the two dictionaries instead of allocating new ones.
func capture(sim: BattleSim) -> void:
	if sim == null:
		return
	var old: Dictionary = prev
	prev = curr
	curr = old
	curr.clear()
	for p: PathogenState in sim.pathogens:
		if p != null and p.alive:
			curr[p.id] = p.pos
	for j: ProjectileState in sim.projectiles:
		if j != null and j.alive:
			curr[-j.id] = j.pos


func has_unit(id: int) -> bool:
	return curr.has(id)


func has_projectile(id: int) -> bool:
	return curr.has(-id)


## True when the projectile was also captured on the tick before, so its motion can be extrapolated.
func has_previous_projectile(id: int) -> bool:
	return prev.has(-id)


## Ground position in tiles. `alpha` is the fraction between the previous and current tick; a value
## outside 0..1 extrapolates. A unit with no previous capture returns its current position.
func unit_ground(id: int, alpha: float) -> Vector2:
	return _ground(id, alpha)


func projectile_ground(id: int, alpha: float) -> Vector2:
	return _ground(-id, alpha)


## Distance travelled during the last tick, in tiles.
func moved_tiles(id: int) -> float:
	if not curr.has(id) or not prev.has(id):
		return 0.0
	var c: Vector2i = curr[id]
	var p: Vector2i = prev[id]
	return Vector2(c - p).length() / MT_PER_TILE


func _ground(key: int, alpha: float) -> Vector2:
	if not curr.has(key):
		return Vector2.ZERO
	var c: Vector2i = curr[key]
	if not prev.has(key):
		return Vector2(c) / MT_PER_TILE
	var p: Vector2i = prev[key]
	return Vector2(p).lerp(Vector2(c), alpha) / MT_PER_TILE
