class_name AiArmyGenerator
extends RefCounted

## Builds the army of an AI raid on the player's base, deterministically from a seed (#162).
## Ints only; one Rng that is never reseeded.


## Returns {"units": Array[Dictionary], "spent": int}. Units are in BattleSetup format:
## {"type", "cell": [x, y], "strain"}. Costs are the pathogens' base ATP costs (strain modifiers are ignored).
static func generate(cfg: GameConfig, defender_layout: Array, seed: int) -> Dictionary:
	var units: Array[Dictionary] = []
	var types: Array[String] = []
	for k: Variant in cfg.ai_pathogen_weights.keys():
		if cfg.pathogens.has(str(k)):
			types.append(str(k))
	types.sort()
	if types.is_empty():
		return {"units": units, "spent": 0}
	var budget: int = maxi(cfg.ai_min_army_atp, RaidScore.base_value(cfg, defender_layout) * cfg.ai_army_budget_pct / 100)
	var rng := Rng.new(seed)

	var total_weight: int = 0
	var cheapest: String = types[0]
	for t: String in types:
		total_weight += int(cfg.ai_pathogen_weights[t])
		if _cost(cfg, t) < _cost(cfg, cheapest):
			cheapest = t

	var picked: Array[String] = []
	var remaining: int = budget
	var spent: int = 0
	while _cost(cfg, cheapest) > 0 and remaining >= _cost(cfg, cheapest):
		var roll: int = rng.next_int(total_weight)
		var pick: String = types[types.size() - 1]
		for t: String in types:
			roll -= int(cfg.ai_pathogen_weights[t])
			if roll < 0:
				pick = t
				break
		if _cost(cfg, pick) > remaining:
			pick = cheapest
		picked.append(pick)
		remaining -= _cost(cfg, pick)
		spent += _cost(cfg, pick)

	# Strains: one variant per type (0 = wild, otherwise the variant at index n - 1 in JSON order).
	var strain_of: Dictionary = {}
	for t: String in types:
		strain_of[t] = "wild"
		if cfg.flag("strains"):
			var ids: Array[String] = (cfg.pathogens[t] as PathogenDef).strain_ids()
			strain_of[t] = ids[rng.next_int(ids.size())]

	var grid := GridModel.new(cfg)
	var cells: Array[Vector2i] = _side_cells(grid, rng.next_int(4))
	for i: int in range(picked.size()):
		var c: Vector2i = cells[i % cells.size()]
		units.append({"type": picked[i], "cell": [c.x, c.y], "strain": strain_of[picked[i]]})
	return {"units": units, "spent": spent}


## Deploy-ring cells nearest one edge (0 N, 1 E, 2 S, 3 W), in ring order. A cell nearer a corner goes
## to the first of N, E, S, W that ties for closest.
static func _side_cells(grid: GridModel, side: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c: Vector2i in grid.ring_cells():
		var dists: Array[int] = [c.y, grid.width - 1 - c.x, grid.height - 1 - c.y, c.x]
		var best: int = 0
		for i: int in range(1, 4):
			if dists[i] < dists[best]:
				best = i
		if best == side:
			cells.append(c)
	return cells


static func _cost(cfg: GameConfig, type_id: String) -> int:
	var def: PathogenDef = cfg.pathogens.get(type_id)
	return int(def.cost.get("atp", 0)) if def != null else 0
