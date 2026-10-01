class_name BalanceCampaign
extends RefCounted

## Living Base campaign for the balance simulator (#172): one player army raids the same AI base N times, with the
## base learning and breeding between raids through RaidResolver, exactly as the game does. Pure RefCounted so
## tests can drive it without quit().

const CSV_HEADER: String = "raid,outcome,ticks,atp_looted,amino_attacker,memory_levels_sum,bcell_generation"


## Returns {"ok": bool, "error": String, "rows": Array[Dictionary]}. Each row has the CSV columns as keys.
## `units` is the player's army in BattleSetup unit format. The AI base never changes: a win does not replace it.
static func run(config: GameConfig, tier_id: String, seed: int, raids: int, units: Array) -> Dictionary:
	var tier: Dictionary = {}
	for t: Dictionary in config.ai_tiers:
		if str(t["id"]) == tier_id:
			tier = t
	if tier.is_empty():
		var known: Array[String] = []
		for t: Dictionary in config.ai_tiers:
			known.append(str(t["id"]))
		return {"ok": false, "error": "Unknown AI tier '%s'. Known: %s (is the living_base flag on?)" % [tier_id, ", ".join(known)], "rows": []}
	var layout: Array = AiBaseGenerator.generate(config, tier_id, seed)["layout"]
	var memory := ImmuneMemory.new()
	var stored: int = int(tier["stored_atp"])
	var defender_pools: Dictionary = {}
	var attacker_pools: Dictionary = {}
	var rows: Array[Dictionary] = []
	for raid: int in range(1, raids + 1):
		var populations: Dictionary = {}
		var pools: Dictionary = {}
		if config.coevolution_enabled():
			for type_id: String in config.coevo_types:
				var source: Dictionary = defender_pools if config.structures.has(type_id) else attacker_pools
				var pool: BreedPool = source.get(type_id, null) as BreedPool
				if pool == null:
					pool = BreedPool.wild_pool(type_id, config)
				pools[type_id] = pool
				populations[type_id] = pool.to_dict()
		var memory_seed: Dictionary = {}
		if config.memory_enabled():
			memory_seed = memory.seed_map(BalanceSimArgs.unit_strain_keys(units), config)
		var setup: BattleSetup = BattleSetup.create(layout, units, seed + raid * 7919, memory_seed, populations)
		var errors: PackedStringArray = setup.validate(config)
		if not errors.is_empty():
			return {"ok": false, "error": "Battle setup error: %s" % errors[0], "rows": rows}
		var sim := BattleSim.new(config, setup)
		sim.run_to_end()
		var res: Dictionary = RaidResolver.resolve(config, setup, sim, stored, memory, pools)
		for type_id: Variant in pools.keys():
			var tid: String = str(type_id)
			if config.structures.has(tid):
				defender_pools[tid] = pools[type_id]
			else:
				attacker_pools[tid] = pools[type_id]
		stored = maxi(0, stored - int(res["atp_looted"]))
		var levels_sum: int = 0
		for k: Variant in memory.entries.keys():
			levels_sum += memory.level_of(str(k))
		var bcell: BreedPool = defender_pools.get("b_cell", null) as BreedPool
		rows.append({
			"raid": raid,
			"outcome": str(res["outcome"]),
			"ticks": sim.tick,
			"atp_looted": int(res["atp_looted"]),
			"amino_attacker": int(res["amino_attacker"]),
			"memory_levels_sum": levels_sum,
			"bcell_generation": bcell.generation if bcell != null else 0,
		})
	return {"ok": true, "error": "", "rows": rows}


static func csv_row(row: Dictionary) -> String:
	return "%d,%s,%d,%d,%d,%d,%d" % [
		int(row["raid"]), str(row["outcome"]), int(row["ticks"]), int(row["atp_looted"]),
		int(row["amino_attacker"]), int(row["memory_levels_sum"]), int(row["bcell_generation"])]
