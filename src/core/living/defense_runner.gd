class_name DefenseRunner
extends RefCounted

## AI raids on the player's base (#163): builds the raid, runs it headless, and applies the result to the
## profile. The persistent layout is never damaged: the base is repaired free after every raid.
## Pure: the caller passes the profile, the config and (for scheduling) timestamps.

const SEED_STEP: int = 104729
const SALT_STEP: int = 7919


## The BattleSetup for AI raid number `raid_index` against the profile's base. `salt` varies the seed of a
## live raid that was started again before the previous one finished.
static func build_setup(cfg: GameConfig, profile: LivingBaseProfile, raid_index: int, salt: int = 0) -> BattleSetup:
	var raid_seed: int = profile.seed + SEED_STEP * raid_index + SALT_STEP * salt
	var army: Dictionary = AiArmyGenerator.generate(cfg, profile.layout, raid_seed)
	var units: Array = army["units"]
	var memory_seed: Dictionary = {}
	if cfg.memory_enabled():
		var keys: Array[String] = []
		for u: Dictionary in units:
			var key: String = "%s/%s" % [str(u.get("type", "")), str(u.get("strain", "wild"))]
			if not keys.has(key):
				keys.append(key)
		memory_seed = ImmuneMemory.from_dict(profile.memory, cfg, BaseUpgrades.memory_slots(cfg, profile.upgrades)).seed_map(keys, cfg)
	var populations: Dictionary = {}
	if cfg.coevolution_enabled():
		var pools: Dictionary = pools_for(cfg, profile)
		for type_id: Variant in pools.keys():
			populations[type_id] = (pools[type_id] as BreedPool).to_dict()
	# The player's base defends with its upgrades; AI bases never get mods.
	var mods: Dictionary = {}
	var analysis_pct: int = BaseUpgrades.analysis_threshold_pct(cfg, profile.upgrades)
	if analysis_pct != 100:
		mods["analysis_threshold_pct"] = analysis_pct
	return BattleSetup.create(profile.layout, units, raid_seed, memory_seed, populations, mods)


## Runs raid `raid_index` headless to the end, applies it to the profile and returns the defense-log entry.
static func resolve_offline(cfg: GameConfig, profile: LivingBaseProfile, raid_index: int) -> Dictionary:
	var setup: BattleSetup = build_setup(cfg, profile, raid_index)
	var sim := BattleSim.new(cfg, setup)
	sim.run_to_end()
	return apply_result(cfg, profile, setup, sim, raid_index)


## Applies a finished AI raid to the profile: ATP lost from the Mitochondria, Amino Acids for kills, the
## base's memory and tower pools, the AI army's pools, and the raid counter. Returns the defense-log entry.
static func apply_result(cfg: GameConfig, profile: LivingBaseProfile, setup: BattleSetup, sim: BattleSim, raid_index: int) -> Dictionary:
	var slots: int = BaseUpgrades.memory_slots(cfg, profile.upgrades)
	var memory: ImmuneMemory = ImmuneMemory.from_dict(profile.memory, cfg, slots)
	var pools: Dictionary = pools_for(cfg, profile)
	var res: Dictionary = RaidResolver.resolve(cfg, setup, sim, profile.stored_atp, memory, pools, slots, BaseUpgrades.memory_decay_raids(cfg, profile.upgrades))
	profile.apply_defense_result(res)
	profile.memory = memory.to_dict()
	if cfg.coevolution_enabled():
		for type_id: Variant in pools.keys():
			var tid: String = str(type_id)
			var pool_dict: Dictionary = (pools[type_id] as BreedPool).to_dict()
			if cfg.structures.has(tid):
				profile.populations[tid] = pool_dict
			else:
				profile.ai_army_populations[tid] = pool_dict
	profile.ai_raid_counter += 1
	var army: Dictionary = {}
	for u: Dictionary in setup.units:
		var t: String = str(u.get("type", ""))
		army[t] = int(army.get(t, 0)) + 1
	return {
		"raid_index": raid_index,
		"outcome": str(res["outcome"]),
		"ticks": sim.tick,
		"atp_lost": int(res["atp_looted"]),
		"amino_gained": int(res["amino_defender"]),
		"memory_changes": res["memory_changes"],
		"evolution": res["evolution"],
		"army": army,
		"battle": SnapshotIO.battle_to_dict(cfg, setup, sim),
	}


## Every breeding type's pool: the player's own for structure types, the AI army's for pathogen types.
## A missing pool is wild. Empty unless coevolution is on.
static func pools_for(cfg: GameConfig, profile: LivingBaseProfile) -> Dictionary:
	var pools: Dictionary = {}
	if not cfg.coevolution_enabled():
		return pools
	for type_id: String in cfg.coevo_types:
		var source: Dictionary = profile.populations if cfg.structures.has(type_id) else profile.ai_army_populations
		var stored: Variant = source.get(type_id, null)
		if stored is Dictionary:
			pools[type_id] = BreedPool.from_dict(stored, type_id, cfg)
		else:
			pools[type_id] = BreedPool.wild_pool(type_id, cfg)
	return pools
