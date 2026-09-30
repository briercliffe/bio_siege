class_name BalanceSimRunner
extends RefCounted

## Run loop for the balance simulator, extracted so tests can drive it without quit().
## One run is `generations` consecutive battles with immune memory carried forward.


## Seed used for one generation. A single-generation run keeps the plain run seed.
static func generation_seed(run_seed: int, gen: int, generations: int) -> int:
	if generations == 1:
		return run_seed
	return run_seed * 100 + gen


## Runs one run and returns one result Dictionary per generation.
## start_levels is {strain_key: level}; it is only used when memory is enabled in config.
static func run_run(
	config: GameConfig,
	base_setup: BattleSetup,
	run_idx: int,
	run_seed: int,
	jitter: int,
	generations: int,
	start_levels: Dictionary,
	ring_cells: Array[Vector2i]
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var memory: ImmuneMemory = BalanceSimArgs.memory_from_levels(start_levels, config)
	var memory_on: bool = config.memory_enabled()
	var analysis_on: bool = config.flag("bcell_analysis")
	var biofilm_on: bool = config.flag("biofilm")

	for gen: int in range(1, generations + 1):
		var gen_seed: int = generation_seed(run_seed, gen, generations)
		var units: Array = BalanceSimArgs.apply_jitter(base_setup.units, jitter, gen_seed, ring_cells)
		var memory_seed: Dictionary = {}
		if memory_on:
			memory_seed = memory.seed_map(BalanceSimArgs.unit_strain_keys(units), config)
		var setup: BattleSetup = BattleSetup.create(base_setup.structures, units, gen_seed, memory_seed)
		var sim: BattleSim = BattleSim.new(config, setup)

		var biofilm_max_group: int = 0
		while not sim.finished:
			sim.step()
			if biofilm_on:
				for root: Variant in sim.biofilm.groups.keys():
					biofilm_max_group = maxi(biofilm_max_group, (sim.biofilm.groups[root] as Array).size())

		var analyzed: Array[String] = []
		if analysis_on:
			analyzed = sim.analyzed_strain_keys()
		var memory_after: String = ""
		if memory_on:
			memory.update_after_raid(sim.seen_strain_keys(), analyzed, config)
			memory_after = memory_string(memory)

		var walls_damaged: int = 0
		var walls_destroyed: int = 0
		for s: StructureState in sim.structures:
			if s.def != null and s.def.has_tag("wall"):
				if s.hp < s.def.hp:
					walls_damaged += 1
				if not s.alive:
					walls_destroyed += 1

		var nuc: StructureState = sim.structure(sim.nucleus_id)
		var pathogens_alive: int = 0
		for p: PathogenState in sim.pathogens:
			if p != null and p.alive:
				pathogens_alive += 1

		var first_contact_str: String = "-1.0"
		if sim.first_contact_tick >= 0:
			first_contact_str = "%.2f" % (float(sim.first_contact_tick) / float(config.tick_rate))

		results.append({
			"run": run_idx,
			"generation": gen,
			"seed": gen_seed,
			"memory_seed": memory_seed,
			"outcome": sim.outcome,
			"end_reason": sim.end_reason,
			"ticks": sim.tick,
			"battle_s": float(sim.tick) / float(config.tick_rate),
			"nucleus_hp": nuc.hp if nuc != null else 0,
			"structures_destroyed": sim.structures_destroyed,
			"walls_destroyed": walls_destroyed,
			"walls_damaged": walls_damaged,
			"pathogens_alive": pathogens_alive,
			"first_destroyed_type": sim.first_destroyed_structure_type,
			"first_contact": first_contact_str,
			"score": RaidScore.compute(config, setup.structures, sim.outcome),
			"analyzed": analyzed,
			"memory_after": memory_after,
			"memory_levels": _levels_of(memory) if memory_on else {},
			"hijacks_completed": sim.hijacks_completed,
			"biofilm_max_group": biofilm_max_group,
		})
	return results


## Memory as `key=L` pairs sorted by key and joined with `;`.
static func memory_string(memory: ImmuneMemory) -> String:
	var parts: Array[String] = []
	var levels: Dictionary = _levels_of(memory)
	var keys: Array = levels.keys()
	keys.sort()
	for k: Variant in keys:
		parts.append("%s=%d" % [str(k), int(levels[k])])
	return ";".join(parts)


static func _levels_of(memory: ImmuneMemory) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in memory.entries.keys():
		out[str(k)] = memory.level_of(str(k))
	return out
