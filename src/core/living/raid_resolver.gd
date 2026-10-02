class_name RaidResolver
extends RefCounted

## One place for the rules that follow a finished raid (#159): loot, Amino Acids, DNA, the defender's
## memory update and population breeding. The player raiding an AI base, an AI raiding the player and
## (later) the server worker all call this, so the two sides cannot drift apart.
## Pure: no Node, Time, OS or file access.


const BCELL_ID: String = "b_cell"


## Turns a finished battle into rewards, losses, memory and breeding.
##   setup: the BattleSetup that was simulated
##   sim: the finished BattleSim
##   defender_stored_atp: uncollected ATP in the defender's Mitochondria before the raid
##   defender_memory: the defender's ImmuneMemory (mutated in place)
##   pools: type_id -> BreedPool for every breeding type in the battle (mutated in place)
##   slots_override, decay_override: the defender's memory slots and decay (Living Base upgrades); -1 = config
## Returns {outcome, atp_looted, amino_attacker, amino_defender, dna_attacker, memory_changes, evolution}.
static func resolve(cfg: GameConfig, setup: BattleSetup, sim: BattleSim, defender_stored_atp: int,
		defender_memory: ImmuneMemory, pools: Dictionary, slots_override: int = -1, decay_override: int = -1) -> Dictionary:
	var memory_changes: Array[Dictionary] = []
	if cfg.memory_enabled() and defender_memory != null:
		memory_changes = defender_memory.update_after_raid(sim.seen_strain_keys(), sim.analyzed_strain_keys(), cfg, slots_override, decay_override)
	var evolution: Array[Dictionary] = []
	if cfg.coevolution_enabled():
		evolution = breed_after_battle(cfg, setup, sim, pools)
	var dna: int = 0
	# debug_dna is for Phase 2 AI raids only: online, DNA comes from PvP wins alone (RaidJobs awards it).
	if cfg.flag("debug_dna") and not cfg.flag("online") and sim.outcome == "attacker":
		dna = cfg.loot_dna_per_win
	return {
		"outcome": sim.outcome,
		"atp_looted": _atp_looted(cfg, setup, sim, defender_stored_atp),
		"amino_attacker": _amino_attacker(cfg, sim),
		"amino_defender": _amino_defender(cfg, sim),
		"dna_attacker": dna,
		"memory_changes": memory_changes,
		"evolution": evolution,
	}


## Scores the finished raid onto `pools`, then breeds every pool. One Rng for all types, in sorted type
## order, seeded setup.seed + pre-breed generation * 100003. A missing pool is treated as wild.
## Returns one entry per type: the BreedPool.breed() result plus "type_id".
static func breed_after_battle(cfg: GameConfig, setup: BattleSetup, sim: BattleSim, pools: Dictionary) -> Array[Dictionary]:
	sim.grant_survival_bonus()
	var fitness: Dictionary = sim.fitness_by_type()
	var type_ids: Array[String] = cfg.coevo_types.duplicate()
	type_ids.sort()
	var base_generation: int = -1
	for type_id: String in type_ids:
		var pool: BreedPool = pools.get(type_id, null) as BreedPool
		if pool == null:
			pool = BreedPool.wild_pool(type_id, cfg)
			pools[type_id] = pool
		var scores: Variant = fitness.get(type_id, null)
		if scores is Array and (scores as Array).size() == pool.fitness.size():
			for i: int in range(pool.fitness.size()):
				pool.fitness[i] = int((scores as Array)[i])
		if base_generation < 0 or pool.generation < base_generation:
			base_generation = pool.generation
	var rng := Rng.new(setup.seed + maxi(0, base_generation) * 100003)
	var presented: Array[String] = []
	if cfg.flag("dendritic_cell"):
		presented = sim.presented_antigen_ids()
	var bias: Array[String] = _receptor_bias(cfg, presented)
	var evolution: Array[Dictionary] = []
	for type_id: String in type_ids:
		var pool: BreedPool = pools[type_id]
		var is_bcell: bool = type_id == BCELL_ID
		var pool_bias: Array[String] = []
		if is_bcell:
			pool_bias = bias
		var res: Dictionary = pool.breed(rng, cfg, pool_bias)
		res["type_id"] = type_id
		if is_bcell and not bias.is_empty():
			res["presented"] = presented
		evolution.append(res)
	return evolution


## Every receptor that binds one of the presented antigens, in catalog order.
static func _receptor_bias(cfg: GameConfig, presented: Array[String]) -> Array[String]:
	var bias: Array[String] = []
	if presented.is_empty():
		return bias
	for receptor_id: Variant in cfg.coevo_receptor_name.keys():
		if presented.has(str(cfg.coevo_receptor_binds.get(receptor_id, ""))):
			bias.append(str(receptor_id))
	return bias


## ATP the raider takes: for each destroyed generator, its share of the stored ATP times loot_atp_pct.
static func _atp_looted(cfg: GameConfig, setup: BattleSetup, sim: BattleSim, defender_stored_atp: int) -> int:
	var shares: Array[int] = AtpGenerator.split_stored(cfg, setup.structures, defender_stored_atp)
	var looted: int = 0
	for i: int in range(mini(shares.size(), sim.structures.size())):
		if shares[i] > 0 and not sim.structures[i].alive:
			looted += shares[i] * cfg.loot_atp_pct / 100
	return looted


## Amino Acids the raider earns: a share of the ATP cost of every destroyed non-core structure.
static func _amino_attacker(cfg: GameConfig, sim: BattleSim) -> int:
	var total: int = 0
	for s: StructureState in sim.structures:
		if not s.alive and s.def != null and not s.def.has_tag("core"):
			total += int(s.def.cost.get("atp", 0))
	return total * cfg.loot_amino_structure_pct / 100


## Amino Acids the defender earns: a share of the base ATP cost of every pathogen it killed.
## Units consumed by a hijack are not kills, and strain cost modifiers are ignored.
static func _amino_defender(cfg: GameConfig, sim: BattleSim) -> int:
	var total: int = 0
	for p: PathogenState in sim.pathogens:
		if not p.alive and p.cause_of_death == "killed" and p.def != null:
			total += int(p.def.cost.get("atp", 0))
	return total * cfg.loot_amino_kill_pct / 100
