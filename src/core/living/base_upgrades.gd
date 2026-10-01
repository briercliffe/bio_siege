class_name BaseUpgrades
extends RefCounted

## Amino Acid base upgrades (#168, decision D3): breadth, never flat HP or damage. Pure maths over the
## profile's `upgrades` dictionary (upgrade id -> level) and the `upgrades` block of the config. Everything
## here returns the plain config value while the amino_upgrades flag is off or nothing was bought.


## Levels bought of `id` (0 when none).
static func level(profile_upgrades: Dictionary, id: String) -> int:
	return maxi(0, int(profile_upgrades.get(id, 0)))


## Highest level of `id`: one per cost entry. 0 for an unknown upgrade.
static func max_level(cfg: GameConfig, id: String) -> int:
	var def: Dictionary = cfg.upgrade_defs.get(id, {})
	return (def.get("costs", []) as Array).size()


## The cost of the next level, or {} when maxed or unknown.
static func next_cost(cfg: GameConfig, profile_upgrades: Dictionary, id: String) -> Dictionary:
	var def: Dictionary = cfg.upgrade_defs.get(id, {})
	var costs: Array = def.get("costs", [])
	var lv: int = level(profile_upgrades, id)
	if lv >= costs.size():
		return {}
	return (costs[lv] as Dictionary).duplicate()


## Buys the next level: all or nothing on the wallet. Returns whether it was bought.
static func buy(cfg: GameConfig, profile_upgrades: Dictionary, id: String, wallet: Wallet) -> bool:
	if not cfg.flag("amino_upgrades"):
		return false
	var cost: Dictionary = next_cost(cfg, profile_upgrades, id)
	if cost.is_empty() or not wallet.spend(cost):
		return false
	profile_upgrades[id] = level(profile_upgrades, id) + 1
	return true


## Receptor slots a player tower pool gets on top of the config's (receptor_slot upgrade).
static func receptor_slot_bonus(cfg: GameConfig, profile_upgrades: Dictionary) -> int:
	return _bonus(cfg, profile_upgrades, "receptor_slot")


## Applies one level of the receptor_slot upgrade to the player's tower (structure-type) pools: each gets
## `per_level` more receptor slots. A missing pool is created wild first. `pools` is type_id -> BreedPool.
static func widen_receptor_pools(cfg: GameConfig, pools: Dictionary) -> void:
	var per_level: int = int((cfg.upgrade_defs.get("receptor_slot", {}) as Dictionary).get("per_level", 0))
	for type_id: String in cfg.coevo_types:
		if not cfg.structures.has(type_id):
			continue
		var pool: BreedPool = pools.get(type_id, null) as BreedPool
		if pool == null:
			pool = BreedPool.wild_pool(type_id, cfg)
			pools[type_id] = pool
		pool.widen_receptors(per_level)


## Immune-memory slots for this base: the config value plus `per_level` for each memory_slot level.
static func memory_slots(cfg: GameConfig, profile_upgrades: Dictionary) -> int:
	return cfg.memory_slots + _bonus(cfg, profile_upgrades, "memory_slot")


## Raids a strain can go unseen before it wanes: the config value plus `per_level` for each memory_retention level.
static func memory_decay_raids(cfg: GameConfig, profile_upgrades: Dictionary) -> int:
	return cfg.memory_decay_raids + _bonus(cfg, profile_upgrades, "memory_retention")


## Percent of the B-Cell analysis time this base needs: 100, then `per_level` percent applied once per level
## (90, 81, 72 with 90). Integer maths, so 81 * 90 / 100 is 72.
static func analysis_threshold_pct(cfg: GameConfig, profile_upgrades: Dictionary) -> int:
	var pct: int = 100
	if not cfg.flag("amino_upgrades") or not cfg.upgrade_defs.has("analysis_speed"):
		return pct
	var per_level: int = int((cfg.upgrade_defs["analysis_speed"] as Dictionary).get("per_level", 100))
	for i: int in range(mini(level(profile_upgrades, "analysis_speed"), max_level(cfg, "analysis_speed"))):
		pct = pct * per_level / 100
	return maxi(1, pct)


static func _bonus(cfg: GameConfig, profile_upgrades: Dictionary, id: String) -> int:
	if not cfg.flag("amino_upgrades") or not cfg.upgrade_defs.has(id):
		return 0
	var per_level: int = int((cfg.upgrade_defs[id] as Dictionary).get("per_level", 0))
	return mini(level(profile_upgrades, id), max_level(cfg, id)) * per_level
