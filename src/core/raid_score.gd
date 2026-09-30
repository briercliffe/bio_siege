class_name RaidScore
extends RefCounted
## Self-raid score: a winning attack scores the ATP value of the base it broke.


## ATP value of the non-core structures in a layout (Array of {"type": String, "origin": ...}).
## Matches GridModel.total_cost(): unknown types and the core are skipped; only "atp" counts.
static func base_value(config: GameConfig, structures: Array) -> int:
	if config == null:
		return 0
	var total: int = 0
	for entry: Variant in structures:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var type_id: String = str((entry as Dictionary).get("type", ""))
		var def: StructureDef = config.structures.get(type_id) as StructureDef
		if def == null or def.has_tag("core") or type_id == "nucleus":
			continue
		total += int(def.cost.get("atp", 0))
	return total


## base_value(...) when outcome == "attacker", else 0.
static func compute(config: GameConfig, structures: Array, outcome: String) -> int:
	if outcome != "attacker":
		return 0
	return base_value(config, structures)
