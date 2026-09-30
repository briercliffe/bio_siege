class_name SimFixtures
extends RefCounted

static func make_sim(structures: Array, units: Array, seed: int = 1, config: GameConfig = null) -> BattleSim:
	var cfg: GameConfig = config
	if cfg == null:
		var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
		cfg = res.config

	var structs: Array = structures.duplicate(true)
	var has_core: bool = false
	for s_val: Variant in structs:
		if s_val is Dictionary:
			var s_dict: Dictionary = s_val
			var type_id: String = str(s_dict.get("type", ""))
			if type_id == "nucleus":
				has_core = true
				break
			if cfg != null and cfg.structures.has(type_id):
				var sdef: StructureDef = cfg.structures[type_id]
				if sdef != null and sdef.has_tag("core"):
					has_core = true
					break

	if not has_core:
		structs.append({
			"type": "nucleus",
			"origin": Vector2i(18, 18)
		})

	var setup := BattleSetup.create(structs, units, seed)
	return BattleSim.new(cfg, setup)
