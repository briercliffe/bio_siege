class_name ProfileJobs
extends RefCounted

## Pure worker rules for the server-owned Living Base profile (AM-05, docs/SERVER_PLAN.md). Every job payload
## carries `profile` (the server copy) and `now_unix` (the server clock at enqueue). Each returns
## {"ok", "result", "error"}; on success `result.profile` is the new profile dict and `result.snapshot` the
## public defended snapshot to store next to it. Nothing here touches the network, files or Time.

const PROFILE_NEW: String = "profile_new"
const PROFILE_TICK: String = "profile_tick"
const BASE_COMMIT: String = "base_commit"
const COLLECT: String = "collect"
const UPGRADE_BUY: String = "upgrade_buy"
const PROFILE_IMPORT: String = "profile_import"

const TYPES: Array[String] = [PROFILE_NEW, PROFILE_TICK, BASE_COMMIT, COLLECT, UPGRADE_BUY, PROFILE_IMPORT]


static func handles(type: String) -> bool:
	return TYPES.has(type)


static func process(cfg: GameConfig, type: String, payload: Dictionary, created_unix: int) -> Dictionary:
	var now: int = _int_of(payload, "now_unix", created_unix)
	if type == PROFILE_NEW:
		return _profile_new(cfg, payload, now)
	var original: Dictionary = payload.get("profile", {}) as Dictionary if payload.get("profile", {}) is Dictionary else {}
	var loaded: Dictionary = LivingBaseProfile.from_dict(original, cfg)
	if not bool(loaded["ok"]):
		return _fail("invalid_profile")
	var profile: LivingBaseProfile = loaded["profile"]
	profile.advance_clock(cfg, now)
	match type:
		PROFILE_TICK:
			return _done(cfg, original, profile, {})
		BASE_COMMIT:
			return _base_commit(cfg, original, profile, payload)
		COLLECT:
			var amount: int = profile.collect()
			return _done(cfg, original, profile, {"collected": amount})
		UPGRADE_BUY:
			return _upgrade_buy(cfg, original, profile, payload)
		PROFILE_IMPORT:
			return _profile_import(cfg, original, profile, payload)
		_:
			return _fail("unknown_job_type")


## The server-side extras a new profile starts with (the keys docs/SERVER_PLAN.md lists next to LivingBaseProfile).
static func new_profile_extras(cfg: GameConfig) -> Dictionary:
	return {
		"trophies": 0,
		"unlocked_strains": [],
		"shield_until_unix": 0,
		"under_attack_until_unix": 0,
		"config_hash": cfg.content_hash,
	}


## What other players see and raid: layout, memory, structure-type pools, stored ATP and trophies.
static func snapshot_of(cfg: GameConfig, profile_dict: Dictionary, now_unix: int) -> Dictionary:
	var pools: Dictionary = {}
	var all_pools: Dictionary = profile_dict.get("populations", {}) as Dictionary if profile_dict.get("populations", {}) is Dictionary else {}
	for type_id: Variant in all_pools.keys():
		if cfg.structures.has(str(type_id)):
			pools[str(type_id)] = all_pools[type_id]
	return {
		"layout": profile_dict.get("layout", []),
		"memory": profile_dict.get("memory", {}),
		"populations": pools,
		"stored_atp": int(profile_dict.get("stored_atp", 0)),
		"trophies": int(profile_dict.get("trophies", 0)),
		"updated_unix": now_unix,
	}


static func _profile_new(cfg: GameConfig, payload: Dictionary, now: int) -> Dictionary:
	var profile: LivingBaseProfile = LivingBaseProfile.create_new(cfg, _int_of(payload, "seed", 0), now)
	return _done(cfg, new_profile_extras(cfg), profile, {})


static func _base_commit(cfg: GameConfig, original: Dictionary, profile: LivingBaseProfile, payload: Dictionary) -> Dictionary:
	var layout_val: Variant = payload.get("layout", null)
	if not layout_val is Array:
		return _fail("invalid_layout")
	var old_grid := GridModel.new(cfg)
	if old_grid.load_layout(profile.layout, LivingBaseProfile.unlimited_wallet()) != GridModel.PlaceError.OK:
		return _fail("invalid_layout")
	var new_grid := GridModel.new(cfg)
	if new_grid.load_layout(layout_val as Array, LivingBaseProfile.unlimited_wallet()) != GridModel.PlaceError.OK:
		return _fail("invalid_layout")
	if not cfg.move_nucleus_enabled():
		var old_core: GridModel.PlacedStructure = old_grid.find_core()
		var new_core: GridModel.PlacedStructure = new_grid.find_core()
		if old_core == null or new_core == null or old_core.origin != new_core.origin:
			return _fail("invalid_layout")
	var old_cost: Dictionary = old_grid.total_cost()
	var new_cost: Dictionary = new_grid.total_cost()
	var spend: Dictionary = {}
	var refund: Dictionary = {}
	for cur_var: Variant in _union_keys(old_cost, new_cost):
		var cur: String = str(cur_var)
		var diff: int = int(new_cost.get(cur, 0)) - int(old_cost.get(cur, 0))
		if diff > 0:
			spend[cur] = diff
		elif diff < 0:
			refund[cur] = -diff
	var wallet := Wallet.new(profile.wallet)
	if not wallet.spend(spend):
		return _fail("insufficient_funds")
	for cur_var: Variant in refund.keys():
		wallet.set_amount(str(cur_var), wallet.get_amount(str(cur_var)) + int(refund[cur_var]))
	profile.wallet = wallet.to_dict()
	profile.layout = new_grid.to_layout()
	return _done(cfg, original, profile, {"spent": spend, "refunded": refund})


static func _upgrade_buy(cfg: GameConfig, original: Dictionary, profile: LivingBaseProfile, payload: Dictionary) -> Dictionary:
	var id: String = str(payload.get("id", ""))
	if not cfg.flag("amino_upgrades") or not cfg.upgrade_defs.has(id):
		return _fail("unknown_upgrade")
	var cost: Dictionary = BaseUpgrades.next_cost(cfg, profile.upgrades, id)
	if cost.is_empty():
		return _fail("maxed")
	var wallet := Wallet.new(profile.wallet)
	if not BaseUpgrades.buy(cfg, profile.upgrades, id, wallet):
		return _fail("insufficient_funds")
	profile.wallet = wallet.to_dict()
	if id == "receptor_slot":
		var pools: Dictionary = {}
		for type_id: Variant in profile.populations.keys():
			if profile.populations[type_id] is Dictionary:
				pools[str(type_id)] = BreedPool.from_dict(profile.populations[type_id], str(type_id), cfg)
		BaseUpgrades.widen_receptor_pools(cfg, pools)
		for type_id: Variant in pools.keys():
			profile.populations[str(type_id)] = (pools[type_id] as BreedPool).to_dict()
	return _done(cfg, original, profile, {"id": id, "level": BaseUpgrades.level(profile.upgrades, id), "cost": cost})


## One-time import of an offline base. Only the layout and the memory are taken from `local_profile`.
static func _profile_import(cfg: GameConfig, original: Dictionary, profile: LivingBaseProfile, payload: Dictionary) -> Dictionary:
	if profile.raid_counter != 0 or profile.ai_raid_counter != 0:
		return _fail("profile_not_fresh")
	var local_val: Variant = payload.get("local_profile", null)
	if not local_val is Dictionary:
		return _fail("invalid_profile")
	var loaded: Dictionary = LivingBaseProfile.from_dict(local_val as Dictionary, cfg)
	if not bool(loaded["ok"]):
		return _fail("invalid_profile")
	var local: LivingBaseProfile = loaded["profile"]
	var grid := GridModel.new(cfg)
	if grid.load_layout(local.layout, LivingBaseProfile.unlimited_wallet()) != GridModel.PlaceError.OK:
		return _fail("invalid_layout")
	var cost: Dictionary = grid.total_cost()
	var wallet := Wallet.new(cfg.lb_start_wallet)
	if not wallet.spend(cost):
		return _fail("layout_too_expensive")
	profile.wallet = wallet.to_dict()
	profile.layout = grid.to_layout()
	profile.memory = ImmuneMemory.from_dict(local.memory, cfg, BaseUpgrades.memory_slots(cfg, profile.upgrades)).to_dict()
	return _done(cfg, original, profile, {})


## Builds the success result: the profile dict is the original (so server-side extras survive) with the
## LivingBaseProfile fields laid over it.
static func _done(cfg: GameConfig, original: Dictionary, profile: LivingBaseProfile, extra: Dictionary) -> Dictionary:
	var out: Dictionary = original.duplicate(true)
	var fresh: Dictionary = profile.to_dict()
	for key: Variant in fresh.keys():
		out[key] = fresh[key]
	var result: Dictionary = extra.duplicate(true)
	result["profile"] = out
	result["snapshot"] = snapshot_of(cfg, out, profile.last_clock_unix)
	return {"ok": true, "result": result, "error": ""}


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "result": {}, "error": error}


static func _union_keys(a: Dictionary, b: Dictionary) -> Array:
	var keys: Array = a.keys()
	for k: Variant in b.keys():
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	return keys


static func _int_of(d: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT and is_finite(float(v)):
		return int(v)
	return fallback
