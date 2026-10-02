extends GutTest

var _cfg: GameConfig


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "coevolution": true}).config


func _wild(type_id: String = "macrophage") -> Dictionary:
	return JSON.parse_string(JSON.stringify(BreedPool.wild_pool(type_id, _cfg).to_dict())) as Dictionary


func test_a_wild_pool_passes() -> void:
	assert_eq(PoolAudit.check(_cfg, "macrophage", _wild(), 0), "")
	assert_eq(PoolAudit.check(_cfg, "rhinovirus", _wild("rhinovirus"), 0), "")


func test_a_bred_pool_within_the_raid_count_passes() -> void:
	var pool: Dictionary = _wild()
	pool["generation"] = 3
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 3), "")
	pool["generation"] = 4
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 3), PoolAudit.BAD_GENERATION, "one generation per raid at most")


func test_a_generation_that_is_too_high_or_negative_is_rejected() -> void:
	var pool: Dictionary = _wild()
	pool["generation"] = 99
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 5), PoolAudit.BAD_GENERATION)
	pool["generation"] = -1
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 5), PoolAudit.BAD_GENERATION)
	pool["generation"] = 1.5
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 5), PoolAudit.BAD_GENERATION)
	pool["generation"] = "3"
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 5), PoolAudit.BAD_GENERATION)


func test_an_unknown_allele_is_rejected() -> void:
	var pool: Dictionary = _wild()
	((pool["genomes"] as Array)[2] as Dictionary)["receptors"][0] = "godmode"
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 9), PoolAudit.UNKNOWN_ALLELE)
	var pool2: Dictionary = _wild("rhinovirus")
	((pool2["genomes"] as Array)[0] as Dictionary)["antigens"][1] = "binder_a"
	assert_eq(PoolAudit.check(_cfg, "rhinovirus", pool2, 9), PoolAudit.UNKNOWN_ALLELE, "a receptor id is not an antigen")
	var pool3: Dictionary = _wild()
	((pool3["genomes"] as Array)[0] as Dictionary)["antigens"][0] = 5
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool3, 9), PoolAudit.UNKNOWN_ALLELE)


func test_known_alleles_pass() -> void:
	var pool: Dictionary = _wild()
	((pool["genomes"] as Array)[0] as Dictionary)["antigens"][0] = "capsule_a"
	((pool["genomes"] as Array)[0] as Dictionary)["receptors"][0] = "binder_a"
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 0), "")


func test_a_wrong_length_is_rejected() -> void:
	var short: Dictionary = _wild()
	(short["genomes"] as Array).pop_back()
	assert_eq(PoolAudit.check(_cfg, "macrophage", short, 9), PoolAudit.WRONG_LENGTH, "pool_size genomes")
	var long: Dictionary = _wild()
	(long["genomes"] as Array).append((long["genomes"] as Array)[0])
	assert_eq(PoolAudit.check(_cfg, "macrophage", long, 9), PoolAudit.WRONG_LENGTH)
	var wide_genome: Dictionary = _wild()
	((wide_genome["genomes"] as Array)[1] as Dictionary)["receptors"].append("binder_a")
	assert_eq(PoolAudit.check(_cfg, "macrophage", wide_genome, 9), PoolAudit.WRONG_LENGTH, "too many receptors for the declared slots")
	var few_antigens: Dictionary = _wild()
	((few_antigens["genomes"] as Array)[1] as Dictionary)["antigens"].pop_back()
	assert_eq(PoolAudit.check(_cfg, "macrophage", few_antigens, 9), PoolAudit.WRONG_LENGTH)


func test_a_widened_pool_is_valid_only_with_matching_slots() -> void:
	var pool: BreedPool = BreedPool.wild_pool("macrophage", _cfg)
	pool.widen_receptors(1)
	var d: Dictionary = JSON.parse_string(JSON.stringify(pool.to_dict())) as Dictionary
	assert_eq(int(d["receptor_slots"]), _cfg.coevo_receptor_slots + 1)
	assert_eq(PoolAudit.check(_cfg, "macrophage", d, 0), "")
	d["receptor_slots"] = _cfg.coevo_receptor_slots + BreedPool.MAX_EXTRA_RECEPTORS + 1
	assert_eq(PoolAudit.check(_cfg, "macrophage", d, 0), PoolAudit.WRONG_LENGTH)
	var lying: Dictionary = _wild()
	lying["receptor_slots"] = _cfg.coevo_receptor_slots + 1
	assert_eq(PoolAudit.check(_cfg, "macrophage", lying, 0), PoolAudit.WRONG_LENGTH, "declared slots do not match the genomes")


func test_a_non_pool_or_unknown_type_is_rejected() -> void:
	assert_eq(PoolAudit.check(_cfg, "macrophage", "x", 5), PoolAudit.BAD_POOL)
	assert_eq(PoolAudit.check(_cfg, "macrophage", {"generation": 0, "genomes": "x"}, 5), PoolAudit.WRONG_LENGTH)
	var pool: Dictionary = _wild()
	(pool["genomes"] as Array)[0] = 7
	assert_eq(PoolAudit.check(_cfg, "macrophage", pool, 5), PoolAudit.BAD_POOL)
	assert_eq(PoolAudit.check(_cfg, "mucous_wall", _wild(), 5), PoolAudit.UNKNOWN_TYPE)


func test_audit_resets_bad_pools_to_wild_and_keeps_good_ones() -> void:
	var good: Dictionary = _wild("b_cell")
	good["generation"] = 2
	var bad: Dictionary = _wild("macrophage")
	bad["generation"] = 40
	var res: Dictionary = PoolAudit.audit(_cfg, {"b_cell": good, "macrophage": bad, "mucous_wall": _wild()}, 3)
	var pools: Dictionary = res["pools"] as Dictionary
	assert_eq(pools["b_cell"], good)
	assert_eq(JSON.stringify(pools["macrophage"]), JSON.stringify(BreedPool.wild_pool("macrophage", _cfg).to_dict()), "reset to wild")
	assert_false(pools.has("mucous_wall"), "an unknown type is dropped")
	assert_eq(res["resets"], [
		{"type_id": "macrophage", "reason": "bad_generation"},
		{"type_id": "mucous_wall", "reason": "unknown_type"}])


func test_participation_counts_raids_launched_and_defended() -> void:
	assert_eq(PoolAudit.participation({"raid_counter": 3.0, "ai_raid_counter": 1, "defense_counter": 4}), 8)
	assert_eq(PoolAudit.participation({}), 0)
	assert_eq(PoolAudit.participation({"raid_counter": -5}), 0)


func test_the_raid_job_resets_a_tampered_pool_and_records_it() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true, "coevolution": true}).config
	var t0: int = 1800000000
	var attacker: Dictionary = JSON.parse_string(JSON.stringify(LivingBaseProfile.create_new(cfg, 1, t0).to_dict())) as Dictionary
	var defender: Dictionary = JSON.parse_string(JSON.stringify(LivingBaseProfile.create_new(cfg, 2, t0).to_dict())) as Dictionary
	var cheat: Dictionary = _wild("rhinovirus")
	cheat["generation"] = 50
	((cheat["genomes"] as Array)[0] as Dictionary)["receptors"][0] = "godmode"
	var tampered_defender: Dictionary = _wild("macrophage")
	tampered_defender["generation"] = 30
	var ring: Array[Vector2i] = GridModel.new(cfg).ring_cells()
	var job: Dictionary = {"job_id": "j", "type": "raid_validate", "created_unix": t0, "config_hash": cfg.content_hash, "payload": {
		"raid": {"raid_id": "r", "seed": 5, "attacker_pools": {"rhinovirus": cheat},
				"defender_snapshot": {"layout": [{"type": "nucleus", "origin": [18, 18]}, {"type": "macrophage", "origin": [14, 10]}],
						"memory": {}, "populations": {"macrophage": tampered_defender}, "stored_atp": 0},
				"submission": {"army": [{"type": "rhinovirus", "cell": [ring[0].x, ring[0].y], "strain": "wild"}], "client_final_hash": ""}},
		"attacker_profile": attacker, "defender_profile": defender, "now_unix": t0}}
	var res: Dictionary = JobRules.process(cfg, job)
	assert_true(res["ok"], str(res))
	var result: Dictionary = res["result"] as Dictionary
	var resets: Array = result["pool_resets"] as Array
	assert_eq(resets.size(), 2)
	var owners: Array = []
	for r: Variant in resets:
		owners.append("%s:%s" % [(r as Dictionary)["owner"], (r as Dictionary)["reason"]])
	owners.sort()
	assert_eq(owners, ["attacker:bad_generation", "defender:bad_generation"])
	for pool: Variant in ((result["attacker_patch"] as Dictionary)["pathogen_pools"] as Dictionary).values():
		assert_lte(int((pool as Dictionary)["generation"]), 1, "bred from wild, not from the forged pool")
	for pool: Variant in ((result["defender_patch"] as Dictionary)["structure_pools"] as Dictionary).values():
		assert_lte(int((pool as Dictionary)["generation"]), 1)


func test_the_raid_job_returns_stats_and_counts_the_defense() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true, "coevolution": true}).config
	var t0: int = 1800000000
	var attacker: Dictionary = JSON.parse_string(JSON.stringify(LivingBaseProfile.create_new(cfg, 1, t0).to_dict())) as Dictionary
	var defender: Dictionary = JSON.parse_string(JSON.stringify(LivingBaseProfile.create_new(cfg, 2, t0).to_dict())) as Dictionary
	defender["stats"] = {"raids": 2, "receptor_hits": 4, "receptor_checks": 8, "max_generation": {"macrophage": 2}, "flagged": false}
	var ring: Array[Vector2i] = GridModel.new(cfg).ring_cells()
	var job: Dictionary = {"job_id": "j", "type": "raid_validate", "created_unix": t0, "config_hash": cfg.content_hash, "payload": {
		"raid": {"raid_id": "r", "seed": 5, "attacker_pools": {},
				"defender_snapshot": {"layout": [{"type": "nucleus", "origin": [18, 18]}, {"type": "macrophage", "origin": [14, 10]}],
						"memory": {}, "populations": {}, "stored_atp": 0},
				"submission": {"army": [{"type": "rhinovirus", "cell": [ring[0].x, ring[0].y], "strain": "wild"}], "client_final_hash": ""}},
		"attacker_profile": attacker, "defender_profile": defender, "now_unix": t0}}
	var result: Dictionary = JobRules.process(cfg, job)["result"] as Dictionary
	var d_patch: Dictionary = result["defender_patch"] as Dictionary
	assert_eq(int(d_patch["defense_counter_inc"]), 1)
	var d_stats: Dictionary = d_patch["stats"] as Dictionary
	assert_eq(int(d_stats["raids"]), 3)
	assert_gte(int(d_stats["receptor_checks"]), 8)
	assert_gte(int(d_stats["receptor_hits"]), 4)
	assert_eq(int((d_stats["max_generation"] as Dictionary)["macrophage"]) >= 2, true)
	var a_stats: Dictionary = (result["attacker_patch"] as Dictionary)["stats"] as Dictionary
	assert_eq(int(a_stats["raids"]), 1)
	assert_eq(int(a_stats["receptor_checks"]), 0)
	assert_eq(result["pool_resets"], [])
