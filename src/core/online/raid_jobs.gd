class_name RaidJobs
extends RefCounted

## Pure worker rules for PvP raids (AM-06, docs/SERVER_PLAN.md). The client plays the battle for show; the worker
## re-simulates it here and decides everything: army legality, the outcome, loot and what both sides learn.
## The server only applies the returned patches. Nothing here touches the network, files or Time.

const RAID_VALIDATE: String = "raid_validate"
const ARMY_SPEND: String = "army_spend"
const TYPES: Array[String] = [RAID_VALIDATE, ARMY_SPEND]


static func handles(type: String) -> bool:
	return TYPES.has(type)


static func process(cfg: GameConfig, type: String, payload: Dictionary, _created_unix: int) -> Dictionary:
	match type:
		RAID_VALIDATE:
			return _raid_validate(cfg, payload)
		ARMY_SPEND:
			return _army_spend(cfg, payload)
		_:
			return _fail("unknown_job_type")


## Normalises the submitted army ([{type, cell: [x, y], strain}]) into BattleSetup units. Returns
## {"ok": bool, "units": Array[Dictionary], "error": String}. Legal means: a pathogen type, a known strain
## (wild, or unlocked), a deploy-ring cell, and (when `wallet` is given) a total cost the wallet affords.
static func check_army(cfg: GameConfig, army_val: Variant, ring: Array[Vector2i], unlocked: Variant, wallet: Wallet) -> Dictionary:
	var units: Array[Dictionary] = []
	if not army_val is Array:
		return {"ok": false, "units": units, "error": "invalid_army"}
	var ring_set: Dictionary = {}
	for c: Vector2i in ring:
		ring_set[c] = true
	for item: Variant in army_val as Array:
		if not item is Dictionary:
			return {"ok": false, "units": units, "error": "invalid_army"}
		var d: Dictionary = item as Dictionary
		var type_id: String = str(d.get("type", ""))
		var pdef: PathogenDef = cfg.pathogens.get(type_id) as PathogenDef
		if pdef == null:
			return {"ok": false, "units": units, "error": "invalid_army"}
		var strain_id: String = str(d.get("strain", "wild"))
		if pdef.strain(strain_id) == null or not _strain_allowed(type_id, strain_id, unlocked):
			return {"ok": false, "units": units, "error": "invalid_army"}
		var cell: Variant = _cell_of(d.get("cell", null))
		if cell == null or not ring_set.has(cell):
			return {"ok": false, "units": units, "error": "invalid_army"}
		units.append({"type": type_id, "cell": cell as Vector2i, "strain": strain_id})
	if wallet != null and not wallet.can_afford(army_cost(cfg, units)):
		return {"ok": false, "units": units, "error": "invalid_army"}
	return {"ok": true, "units": units, "error": ""}


## What the army costs, strain cost modifiers included (the same maths as Army.unit_cost).
static func army_cost(cfg: GameConfig, units: Array) -> Dictionary:
	var total: Dictionary = {}
	var army := Army.new(cfg)
	for u: Variant in units:
		var d: Dictionary = u as Dictionary
		var type_id: String = str(d.get("type", ""))
		if not cfg.pathogens.has(type_id):
			continue
		army.strain_by_type = {}
		var strain_id: String = str(d.get("strain", "wild"))
		if strain_id != "wild":
			army.strain_by_type[type_id] = strain_id
		var unit: Dictionary = army.unit_cost(type_id)
		for cur: Variant in unit.keys():
			total[str(cur)] = int(total.get(str(cur), 0)) + int(unit[cur])
	return total


static func _raid_validate(cfg: GameConfig, payload: Dictionary) -> Dictionary:
	var raid: Dictionary = _dict(payload.get("raid"))
	var attacker_dict: Dictionary = _dict(payload.get("attacker_profile"))
	var defender_dict: Dictionary = _dict(payload.get("defender_profile"))
	var snapshot: Dictionary = _dict(raid.get("defender_snapshot"))
	var submission: Dictionary = _dict(raid.get("submission"))
	var attacker_loaded: Dictionary = LivingBaseProfile.from_dict(attacker_dict, cfg)
	if not bool(attacker_loaded["ok"]) or snapshot.is_empty():
		return _fail("invalid_profile")
	var attacker: LivingBaseProfile = attacker_loaded["profile"]
	var defender_upgrades: Dictionary = {}
	var defender_loaded: Dictionary = LivingBaseProfile.from_dict(defender_dict, cfg)
	if bool(defender_loaded["ok"]):
		defender_upgrades = (defender_loaded["profile"] as LivingBaseProfile).upgrades

	var grid := GridModel.new(cfg)
	if grid.load_layout(snapshot.get("layout", []) as Array, LivingBaseProfile.unlimited_wallet()) != GridModel.PlaceError.OK:
		return _fail("invalid_layout")
	var checked: Dictionary = check_army(cfg, submission.get("army", null), grid.ring_cells(),
			attacker_dict.get("unlocked_strains", null), Wallet.new(attacker.wallet))
	if not bool(checked["ok"]):
		return _fail(str(checked["error"]))
	var units: Array[Dictionary] = checked["units"]
	var cost: Dictionary = army_cost(cfg, units)

	var slots: int = BaseUpgrades.memory_slots(cfg, defender_upgrades)
	var memory: ImmuneMemory = ImmuneMemory.from_dict(_dict(snapshot.get("memory")), cfg, slots)
	var memory_seed: Dictionary = {}
	if cfg.memory_enabled():
		var keys: Array[String] = []
		for u: Dictionary in units:
			var key: String = "%s/%s" % [str(u["type"]), str(u["strain"])]
			if not keys.has(key):
				keys.append(key)
		memory_seed = memory.seed_map(keys, cfg)
	var pools: Dictionary = _pools(cfg, _dict(snapshot.get("populations")), _dict(raid.get("attacker_pools")))
	var populations: Dictionary = {}
	for type_id: Variant in pools.keys():
		populations[type_id] = (pools[type_id] as BreedPool).to_dict()
	var mods: Dictionary = {}
	var analysis_pct: int = BaseUpgrades.analysis_threshold_pct(cfg, defender_upgrades)
	if analysis_pct != 100:
		mods["analysis_threshold_pct"] = analysis_pct
	var setup: BattleSetup = BattleSetup.create(grid.to_layout(), units, _int_of(raid, "seed", 0), memory_seed, populations, mods)
	var sim := BattleSim.new(cfg, setup)
	sim.run_to_end()
	var res: Dictionary = RaidResolver.resolve(cfg, setup, sim, _int_of(snapshot, "stored_atp", 0), memory, pools,
			slots, BaseUpgrades.memory_decay_raids(cfg, defender_upgrades))

	var structure_pools: Dictionary = {}
	var pathogen_pools: Dictionary = {}
	for type_id: Variant in pools.keys():
		var pool_dict: Dictionary = (pools[type_id] as BreedPool).to_dict()
		if cfg.structures.has(str(type_id)):
			structure_pools[str(type_id)] = pool_dict
		else:
			pathogen_pools[str(type_id)] = pool_dict

	# The attacker as a whole profile (for tests and replays) and as the additive patch the server applies.
	var wallet_delta: Dictionary = {}
	for cur: Variant in cost.keys():
		wallet_delta[str(cur)] = -int(cost[cur])
	_add(wallet_delta, "atp", int(res.get("atp_looted", 0)))
	_add(wallet_delta, "amino_acids", int(res.get("amino_attacker", 0)))
	_add(wallet_delta, "dna", int(res.get("dna_attacker", 0)))
	var attacker_after: Dictionary = _attacker_after(cfg, attacker_dict, attacker, wallet_delta, pathogen_pools, 1)
	var server_hash: String = sim.state_hash()
	var client_hash: String = str(submission.get("client_final_hash", ""))
	return {"ok": true, "error": "", "result": {
		"attacker_profile": attacker_after,
		"attacker_patch": {"wallet_delta": wallet_delta, "pathogen_pools": pathogen_pools, "raid_counter_inc": 1},
		"defender_patch": {
			"atp_lost": int(res.get("atp_looted", 0)),
			"amino_gained": int(res.get("amino_defender", 0)),
			"memory": memory.to_dict(),
			"structure_pools": structure_pools,
		},
		"res": res,
		"army_cost": cost,
		"server_final_hash": server_hash,
		"hash_match": server_hash == client_hash,
		"battle": SnapshotIO.battle_to_dict(cfg, setup, sim),
	}}


## Charges an army without a battle: a cancelled, rejected or expired raid still costs its army.
## payload: {attacker_profile, army (optional), now_unix}. The wallet never goes below 0.
static func _army_spend(cfg: GameConfig, payload: Dictionary) -> Dictionary:
	var attacker_dict: Dictionary = _dict(payload.get("attacker_profile"))
	var loaded: Dictionary = LivingBaseProfile.from_dict(attacker_dict, cfg)
	if not bool(loaded["ok"]):
		return _fail("invalid_profile")
	var attacker: LivingBaseProfile = loaded["profile"]
	var units: Array[Dictionary] = []
	var army_val: Variant = payload.get("army", [])
	if army_val is Array:
		for item: Variant in army_val as Array:
			if item is Dictionary and cfg.pathogens.has(str((item as Dictionary).get("type", ""))):
				var d: Dictionary = item as Dictionary
				var pdef: PathogenDef = cfg.pathogens[str(d["type"])] as PathogenDef
				var strain_id: String = str(d.get("strain", "wild"))
				units.append({"type": str(d["type"]), "strain": strain_id if pdef.strain(strain_id) != null else "wild"})
	var cost: Dictionary = army_cost(cfg, units)
	var wallet_delta: Dictionary = {}
	for cur: Variant in cost.keys():
		wallet_delta[str(cur)] = -int(cost[cur])
	return {"ok": true, "error": "", "result": {
		"attacker_profile": _attacker_after(cfg, attacker_dict, attacker, wallet_delta, {}, 0),
		"attacker_patch": {"wallet_delta": wallet_delta, "pathogen_pools": {}, "raid_counter_inc": 0},
		"army_cost": cost,
	}}


static func _attacker_after(_cfg: GameConfig, original: Dictionary, attacker: LivingBaseProfile, wallet_delta: Dictionary,
		pathogen_pools: Dictionary, raid_inc: int) -> Dictionary:
	for cur: Variant in wallet_delta.keys():
		attacker.wallet[str(cur)] = maxi(0, int(attacker.wallet.get(str(cur), 0)) + int(wallet_delta[cur]))
	for type_id: Variant in pathogen_pools.keys():
		attacker.populations[str(type_id)] = pathogen_pools[type_id]
	attacker.raid_counter += raid_inc
	var out: Dictionary = original.duplicate(true)
	var fresh: Dictionary = attacker.to_dict()
	for key: Variant in fresh.keys():
		out[key] = fresh[key]
	return out


## Every breeding type's pool: the defender's structure pools from the snapshot, the attacker's pathogen pools
## from the raid record. A missing pool is wild. Empty unless coevolution is on.
static func _pools(cfg: GameConfig, defender_pools: Dictionary, attacker_pools: Dictionary) -> Dictionary:
	var pools: Dictionary = {}
	if not cfg.coevolution_enabled():
		return pools
	for type_id: String in cfg.coevo_types:
		var source: Dictionary = defender_pools if cfg.structures.has(type_id) else attacker_pools
		var stored: Variant = source.get(type_id, null)
		if stored is Dictionary:
			pools[type_id] = BreedPool.from_dict(stored as Dictionary, type_id, cfg)
		else:
			pools[type_id] = BreedPool.wild_pool(type_id, cfg)
	return pools


## Until strain unlocks land (AM-10, #184) every known strain is allowed. Then `unlocked` is the attacker's
## list of "type/variant" keys and a locked strain makes the army illegal.
static func _strain_allowed(_type_id: String, _strain_id: String, _unlocked: Variant) -> bool:
	return true


static func _cell_of(val: Variant) -> Variant:
	if val is Array and (val as Array).size() == 2:
		var a: Array = val as Array
		var x: Variant = a[0]
		var y: Variant = a[1]
		if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and (typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT) \
				and floorf(float(x)) == float(x) and floorf(float(y)) == float(y):
			return Vector2i(int(x), int(y))
	if val is Vector2i:
		return val
	return null


static func _add(d: Dictionary, key: String, amount: int) -> void:
	if amount != 0:
		d[key] = int(d.get(key, 0)) + amount


static func _dict(v: Variant) -> Dictionary:
	return v as Dictionary if v is Dictionary else {}


static func _int_of(d: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(float(v))):
		return int(v)
	return fallback


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "result": {}, "error": error}
