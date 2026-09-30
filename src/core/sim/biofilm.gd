class_name Biofilm
extends RefCounted

## Staphylococcus collective behaviour: nearby same-type units link into groups.
## Ints only; deterministic (ascending id order everywhere).

var group_of: Dictionary = {}   # unit id -> root id (lowest id in its group); only units in groups of size >= 2
var groups: Dictionary = {}     # root id -> Array[int] of member ids, ascending


## Recomputes groups from scratch. Returns true if any membership changed.
func regroup(pathogens: Array[PathogenState]) -> bool:
	var cands: Array[PathogenState] = []
	for p: PathogenState in pathogens:
		if p != null and p.alive and p.def != null and p.def.has_biofilm:
			cands.append(p)
	cands.sort_custom(func(a: PathogenState, b: PathogenState) -> bool: return a.id < b.id)

	var parent: Dictionary = {}
	for p: PathogenState in cands:
		parent[p.id] = p.id

	# Candidate count is small (ATP budget / unit cost), so O(n^2) pairs is fine.
	for i: int in range(cands.size()):
		var a: PathogenState = cands[i]
		for j: int in range(i + 1, cands.size()):
			var b: PathogenState = cands[j]
			if a.type_id != b.type_id:
				continue
			var was_grouped: bool = group_of.has(a.id) and group_of.has(b.id) and group_of[a.id] == group_of[b.id]
			var radius: int = a.def.biofilm_break_mt if was_grouped else a.def.biofilm_link_mt
			if FixedMath.dist_sq(a.pos, b.pos) <= radius * radius:
				_union(parent, a.id, b.id)

	var sets: Dictionary = {}
	for p: PathogenState in cands:
		var root: int = _find(parent, p.id)
		if not sets.has(root):
			sets[root] = [] as Array[int]
		(sets[root] as Array[int]).append(p.id)

	var new_group_of: Dictionary = {}
	var new_groups: Dictionary = {}
	for root_var: Variant in sets.keys():
		var ids: Array[int] = sets[root_var]
		if ids.size() < 2:
			continue
		var root_id: int = ids[0]  # lowest id: candidates were visited ascending
		new_groups[root_id] = ids
		for id: int in ids:
			new_group_of[id] = root_id

	var changed: bool = new_group_of != group_of
	group_of = new_group_of
	groups = new_groups
	return changed


func members(unit_id: int) -> Array[int]:
	if group_of.has(unit_id):
		var root: int = int(group_of[unit_id])
		var out: Array[int] = []
		out.assign(groups[root])
		return out
	return [unit_id]


func remove(unit_id: int) -> void:
	if not group_of.has(unit_id):
		return
	var root: int = int(group_of[unit_id])
	var ids: Array[int] = []
	ids.assign(groups[root])
	ids.erase(unit_id)
	group_of.erase(unit_id)
	groups.erase(root)
	if ids.size() < 2:
		for id: int in ids:
			group_of.erase(id)
		return
	var new_root: int = ids[0]
	groups[new_root] = ids
	for id: int in ids:
		group_of[id] = new_root


func _find(parent: Dictionary, x: int) -> int:
	var r: int = x
	while int(parent[r]) != r:
		r = int(parent[r])
	return r


func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra == rb:
		return
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb
