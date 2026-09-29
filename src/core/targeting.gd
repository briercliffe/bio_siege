class_name Targeting
extends RefCounted

## Deterministic target selection for pathogens and towers.
## Zero Node dependencies, zero floats, fully fixed-point.

static func pick_structure_target(unit: PathogenState, structures: Array[StructureState]) -> int:
	if unit == null or unit.def == null:
		return 0

	var candidates: Array[StructureState] = []
	for s: StructureState in structures:
		if s != null and s.alive and s.def != null and s.def.is_targetable:
			candidates.append(s)

	if candidates.is_empty():
		return 0

	if unit.def.priority_tags.size() > 0:
		var priority_set: Array[StructureState] = []
		for s: StructureState in candidates:
			for tag: String in unit.def.priority_tags:
				if s.def.has_tag(tag):
					priority_set.append(s)
					break
		if not priority_set.is_empty():
			candidates = priority_set

	var best: StructureState = null
	var min_dist: int = -1

	for s: StructureState in candidates:
		var dist: int = FixedMath.dist_sq(unit.pos, s.center)
		if best == null or dist < min_dist or (dist == min_dist and s.id < best.id):
			min_dist = dist
			best = s

	return best.id if best != null else 0


static func goal_cell_for(unit: PathogenState, target: StructureState) -> Vector2i:
	if unit == null or target == null:
		return Vector2i.ZERO

	var cells: Array[Vector2i] = target.cells()
	if cells.is_empty():
		return Vector2i.ZERO

	var best_cell: Vector2i = cells[0]
	var min_dist: int = FixedMath.dist_sq(unit.pos, FixedMath.cell_center(best_cell))

	for i in range(1, cells.size()):
		var c: Vector2i = cells[i]
		var dist: int = FixedMath.dist_sq(unit.pos, FixedMath.cell_center(c))
		if dist < min_dist:
			min_dist = dist
			best_cell = c
		elif dist == min_dist:
			if c.y < best_cell.y or (c.y == best_cell.y and c.x < best_cell.x):
				min_dist = dist
				best_cell = c

	return best_cell


static func pick_unit_target(tower: StructureState, pathogens: Array[PathogenState]) -> int:
	if tower == null or tower.def == null or not tower.alive:
		return 0
	if tower.def.attack_range_mt <= 0:
		return 0

	var best: PathogenState = null
	var min_dist: int = -1

	for p: PathogenState in pathogens:
		if p == null or not p.alive:
			continue
		if not FixedMath.within(tower.center, p.pos, tower.def.attack_range_mt):
			continue
		var dist: int = FixedMath.dist_sq(tower.center, p.pos)
		if best == null or dist < min_dist or (dist == min_dist and p.id < best.id):
			min_dist = dist
			best = p

	return best.id if best != null else 0


static func tower_keeps_target(tower: StructureState, target: PathogenState) -> bool:
	if tower == null or tower.def == null or not tower.alive:
		return false
	if target == null or not target.alive:
		return false
	return FixedMath.within(tower.center, target.pos, tower.def.attack_range_mt)
