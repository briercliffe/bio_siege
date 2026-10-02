extends GutTest

const T0: int = 1800000000

var _cfg: GameConfig


func before_each() -> void:
	_cfg = _load({})


func _load(overrides: Dictionary) -> GameConfig:
	var flags: Dictionary = {"living_base": true}
	for k: Variant in overrides.keys():
		flags[k] = overrides[k]
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data", flags)
	assert_true(res.is_ok())
	return res.config


func _profile(cfg: GameConfig, seed: int, layout_entries: Array = []) -> Dictionary:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(cfg, seed, T0)
	var grid := GridModel.new(cfg)
	var layout: Array = [{"type": "nucleus", "origin": [18, 18]}]
	layout.append_array(layout_entries)
	assert_eq(grid.load_layout(layout, LivingBaseProfile.unlimited_wallet()), GridModel.PlaceError.OK)
	p.layout = grid.to_layout()
	p.stored_atp = 400
	var d: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict())) as Dictionary
	d["trophies"] = 0
	d["unlocked_strains"] = []
	return d


func _ring(cfg: GameConfig) -> Array[Vector2i]:
	var g := GridModel.new(cfg)
	return g.ring_cells()


func _unit(type: String, cell: Vector2i, strain: String = "wild") -> Dictionary:
	return {"type": type, "cell": [cell.x, cell.y], "strain": strain}


func _payload(cfg: GameConfig, army: Variant, attacker: Dictionary = {}, defender: Dictionary = {}) -> Dictionary:
	var d: Dictionary = defender if not defender.is_empty() else _profile(cfg, 2, [
		{"type": "mitochondria", "origin": [10, 10]}, {"type": "macrophage", "origin": [14, 10]}])
	var a: Dictionary = attacker if not attacker.is_empty() else _profile(cfg, 1)
	return {
		"raid": {
			"raid_id": "r1", "attacker_id": "a", "defender_id": "d", "seed": 4242, "config_hash": cfg.content_hash,
			"defender_snapshot": ProfileJobs.snapshot_of(cfg, d, T0), "attacker_pools": {},
			"submission": {"army": army, "client_final_hash": "x"},
		},
		"attacker_profile": a, "defender_profile": d, "now_unix": T0,
	}


func _validate(cfg: GameConfig, payload: Dictionary) -> Dictionary:
	return JobRules.process(cfg, {"job_id": "j", "type": "raid_validate", "created_unix": T0, "config_hash": cfg.content_hash, "payload": payload})


func _army(n: int = 4, type: String = "rhinovirus") -> Array:
	var ring: Array[Vector2i] = _ring(_cfg)
	var out: Array = []
	for i: int in range(n):
		out.append(_unit(type, ring[i * 7]))
	return out


func test_a_legal_army_matches_running_the_sim_directly() -> void:
	var payload: Dictionary = _payload(_cfg, _army())
	var res: Dictionary = _validate(_cfg, payload)
	assert_true(res["ok"], str(res))
	var result: Dictionary = res["result"] as Dictionary

	var snapshot: Dictionary = (payload["raid"] as Dictionary)["defender_snapshot"] as Dictionary
	var grid := GridModel.new(_cfg)
	grid.load_layout(snapshot["layout"] as Array, LivingBaseProfile.unlimited_wallet())
	var units: Array[Dictionary] = []
	for u: Variant in _army():
		var d: Dictionary = u as Dictionary
		var c: Array = d["cell"] as Array
		units.append({"type": d["type"], "cell": Vector2i(int(c[0]), int(c[1])), "strain": "wild"})
	var setup: BattleSetup = BattleSetup.create(grid.to_layout(), units, 4242)
	var sim := BattleSim.new(_cfg, setup)
	sim.run_to_end()
	assert_eq(result["server_final_hash"], sim.state_hash())
	assert_eq((result["res"] as Dictionary)["outcome"], sim.outcome)
	assert_false(result["hash_match"], "the client sent a different hash")
	var matched: Dictionary = payload.duplicate(true)
	((matched["raid"] as Dictionary)["submission"] as Dictionary)["client_final_hash"] = sim.state_hash()
	assert_true((_validate(_cfg, matched)["result"] as Dictionary)["hash_match"])
	assert_true((result["battle"] as Dictionary).has("result") or (result["battle"] as Dictionary).size() > 0)


func test_an_illegal_cell_is_rejected() -> void:
	var res: Dictionary = _validate(_cfg, _payload(_cfg, [_unit("rhinovirus", Vector2i(20, 20))]))
	assert_false(res["ok"])
	assert_eq(res["error"], "invalid_army")
	assert_eq(_validate(_cfg, _payload(_cfg, [{"type": "rhinovirus", "cell": [0.5, 1], "strain": "wild"}]))["error"], "invalid_army")
	assert_eq(_validate(_cfg, _payload(_cfg, [{"type": "rhinovirus", "strain": "wild"}]))["error"], "invalid_army")


func test_an_unaffordable_army_is_rejected() -> void:
	var poor: Dictionary = _profile(_cfg, 1)
	(poor["wallet"] as Dictionary)["atp"] = 35
	var res: Dictionary = _validate(_cfg, _payload(_cfg, _army(4), poor))
	assert_eq(res["error"], "invalid_army")
	var exact: Dictionary = _profile(_cfg, 1)
	(exact["wallet"] as Dictionary)["atp"] = 40
	assert_true(_validate(_cfg, _payload(_cfg, _army(4), exact))["ok"])


func test_an_unknown_type_is_rejected() -> void:
	var ring: Array[Vector2i] = _ring(_cfg)
	assert_eq(_validate(_cfg, _payload(_cfg, [_unit("macrophage", ring[0])]))["error"], "invalid_army", "a tower is not a pathogen")
	assert_eq(_validate(_cfg, _payload(_cfg, [_unit("dragon", ring[0])]))["error"], "invalid_army")
	assert_eq(_validate(_cfg, _payload(_cfg, [_unit("rhinovirus", ring[0], "bogus")]))["error"], "invalid_army")
	assert_eq(_validate(_cfg, _payload(_cfg, "nope"))["error"], "invalid_army")


func test_strain_cost_modifiers_are_charged() -> void:
	var cfg: GameConfig = _load({"strains": true})
	var ring: Array[Vector2i] = _ring(cfg)
	var army: Array = [_unit("rhinovirus", ring[0], "rapid_replication"), _unit("rhinovirus", ring[5], "rapid_replication")]
	var res: Dictionary = _validate(cfg, _payload(cfg, army))
	assert_true(res["ok"], str(res))
	var cost: int = int(((res["result"] as Dictionary)["army_cost"] as Dictionary)["atp"])
	var a := Army.new(cfg)
	a.set_strain("rhinovirus", "rapid_replication")
	assert_eq(cost, 2 * int(a.unit_cost("rhinovirus")["atp"]))
	assert_lt(cost, 20)


func test_the_attacker_pays_the_army_and_gets_the_loot() -> void:
	var res: Dictionary = _validate(_cfg, _payload(_cfg, _army(6)))
	var result: Dictionary = res["result"] as Dictionary
	var loot: Dictionary = result["res"] as Dictionary
	var cost: int = int((result["army_cost"] as Dictionary)["atp"])
	assert_eq(cost, 60)
	var patch: Dictionary = result["attacker_patch"] as Dictionary
	assert_eq(int((patch["wallet_delta"] as Dictionary)["atp"]), -cost + int(loot["atp_looted"]))
	assert_eq(int(patch["raid_counter_inc"]), 1)
	var after: Dictionary = result["attacker_profile"] as Dictionary
	assert_eq(int((after["wallet"] as Dictionary)["atp"]), 1000 - cost + int(loot["atp_looted"]))
	assert_eq(int(after["raid_counter"]), 1)


func test_the_defender_patch_matches_the_resolver() -> void:
	var result: Dictionary = _validate(_cfg, _payload(_cfg, _army(8)))["result"] as Dictionary
	var loot: Dictionary = result["res"] as Dictionary
	var patch: Dictionary = result["defender_patch"] as Dictionary
	assert_eq(int(patch["atp_lost"]), int(loot["atp_looted"]))
	assert_eq(int(patch["amino_gained"]), int(loot["amino_defender"]))
	assert_true(patch.has("memory"))
	assert_true(patch.has("structure_pools"))
	assert_lte(int(patch["atp_lost"]), 400, "never more than the snapshot held")


func test_coevolution_breeds_both_sides_pools() -> void:
	var cfg: GameConfig = _load({"coevolution": true, "bcell_analysis": true, "immune_memory": true})
	var result: Dictionary = _validate(cfg, _payload(cfg, _army(8)))["result"] as Dictionary
	var d_pools: Dictionary = (result["defender_patch"] as Dictionary)["structure_pools"] as Dictionary
	var a_pools: Dictionary = (result["attacker_patch"] as Dictionary)["pathogen_pools"] as Dictionary
	assert_false(d_pools.is_empty())
	assert_false(a_pools.is_empty())
	for t: Variant in d_pools.keys():
		assert_true(cfg.structures.has(str(t)))
		assert_true((d_pools[t] as Dictionary).has("genomes"))
	for t: Variant in a_pools.keys():
		assert_true(cfg.pathogens.has(str(t)))
	assert_false(((result["res"] as Dictionary)["evolution"] as Array).is_empty())
	var attacker_after: Dictionary = (result["attacker_profile"] as Dictionary)["populations"] as Dictionary
	for t: Variant in a_pools.keys():
		assert_eq(attacker_after[t], a_pools[t])


func test_army_spend_charges_the_army_and_never_goes_negative() -> void:
	var attacker: Dictionary = _profile(_cfg, 1)
	(attacker["wallet"] as Dictionary)["atp"] = 25
	var job: Dictionary = {"job_id": "j", "type": "army_spend", "created_unix": T0, "config_hash": _cfg.content_hash,
			"payload": {"attacker_profile": attacker, "army": _army(3), "now_unix": T0}}
	var res: Dictionary = JobRules.process(_cfg, job)
	assert_true(res["ok"])
	var after: Dictionary = (res["result"] as Dictionary)["attacker_profile"] as Dictionary
	assert_eq(int((after["wallet"] as Dictionary)["atp"]), 0, "30 ATP army, 25 ATP wallet")
	assert_eq(int(after["raid_counter"]), 0)
	var none: Dictionary = JobRules.process(_cfg, {"job_id": "j", "type": "army_spend", "created_unix": T0, "config_hash": _cfg.content_hash,
			"payload": {"attacker_profile": attacker, "now_unix": T0}})
	assert_eq(int((((none["result"] as Dictionary)["attacker_profile"] as Dictionary)["wallet"] as Dictionary)["atp"]), 25)


func test_server_extras_survive() -> void:
	var attacker: Dictionary = _profile(_cfg, 1)
	attacker["trophies"] = 77
	attacker["unlocked_strains"] = ["rhinovirus/capsid_hardening"]
	var res: Dictionary = _validate(_cfg, _payload(_cfg, _army(), attacker))
	var after: Dictionary = (res["result"] as Dictionary)["attacker_profile"] as Dictionary
	assert_eq(int(after["trophies"]), 77)
	assert_eq(after["unlocked_strains"], ["rhinovirus/capsid_hardening"])


func test_a_bad_snapshot_or_profile_is_rejected() -> void:
	var p: Dictionary = _payload(_cfg, _army())
	((p["raid"] as Dictionary))["defender_snapshot"] = {}
	assert_eq(_validate(_cfg, p)["error"], "invalid_profile")
	var q: Dictionary = _payload(_cfg, _army())
	q["attacker_profile"] = {"format": "x"}
	assert_eq(_validate(_cfg, q)["error"], "invalid_profile")
	var r: Dictionary = _payload(_cfg, _army())
	((r["raid"] as Dictionary)["defender_snapshot"] as Dictionary)["layout"] = [{"type": "nucleus", "origin": [99, 99]}]
	assert_eq(_validate(_cfg, r)["error"], "invalid_layout")
