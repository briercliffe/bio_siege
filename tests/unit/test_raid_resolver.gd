extends GutTest

## RaidResolver (#159): loot, Amino Acids, DNA, memory and breeding after a finished raid.

var _cfg: GameConfig = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true


func _setup(structs: Array, units: Array) -> BattleSetup:
	var all: Array = structs.duplicate(true)
	all.append({"type": "nucleus", "origin": Vector2i(18, 18)})
	return BattleSetup.create(all, units, 1)


func _finished_sim(setup: BattleSetup, outcome: String = "defender") -> BattleSim:
	var sim := BattleSim.new(_cfg, setup)
	sim.finished = true
	sim.outcome = outcome
	return sim


func _resolve(setup: BattleSetup, sim: BattleSim, stored: int = 0) -> Dictionary:
	return RaidResolver.resolve(_cfg, setup, sim, stored, ImmuneMemory.new(), {})


func test_loot_from_a_destroyed_mitochondria() -> void:
	var setup: BattleSetup = _setup([{"type": "mitochondria", "origin": Vector2i(5, 5)}], [])
	var sim: BattleSim = _finished_sim(setup)
	assert_eq(_resolve(setup, sim, 200)["atp_looted"], 0, "not destroyed")
	sim.structures[0].alive = false
	assert_eq(_resolve(setup, sim, 200)["atp_looted"], 100)


func test_loot_splits_by_storage_share() -> void:
	var setup: BattleSetup = _setup([
		{"type": "mitochondria", "origin": Vector2i(5, 5)},
		{"type": "mitochondria", "origin": Vector2i(10, 5)},
	], [])
	var sim: BattleSim = _finished_sim(setup)
	sim.structures[1].alive = false
	# 101 stored: the first gets 51 (remainder), the second 50; 50% of 50 is 25.
	assert_eq(_resolve(setup, sim, 101)["atp_looted"], 25)


func test_amino_attacker_from_destroyed_structures_excludes_the_core() -> void:
	var setup: BattleSetup = _setup([
		{"type": "macrophage", "origin": Vector2i(5, 5)},
		{"type": "b_cell", "origin": Vector2i(10, 5)},
	], [])
	var sim: BattleSim = _finished_sim(setup, "attacker")
	sim.structures[0].alive = false
	sim.structures[1].alive = false
	sim.structures[2].alive = false
	assert_eq(_resolve(setup, sim)["amino_attacker"], 50, "(100 + 150) x 20%")


func test_amino_defender_counts_kills_not_hijacked_units() -> void:
	var units: Array = []
	for i: int in range(10):
		units.append({"type": "rhinovirus", "cell": Vector2i(0, 20 + i)})
	units.append({"type": "bacteriophage", "cell": Vector2i(1, 20)})
	var setup: BattleSetup = _setup([], units)
	var sim: BattleSim = _finished_sim(setup)
	for i: int in range(10):
		sim.pathogens[i].alive = false
		sim.pathogens[i].cause_of_death = "killed"
	sim.pathogens[10].alive = false
	sim.pathogens[10].cause_of_death = "hijack"
	assert_eq(_resolve(setup, sim)["amino_defender"], 10, "10 x 10 ATP x 10%")


func test_pathogens_record_how_they_died() -> void:
	var setup: BattleSetup = _setup([], [{"type": "rhinovirus", "cell": Vector2i(0, 20)}])
	var sim: BattleSim = BattleSim.new(_cfg, setup)
	var before: String = sim.state_hash()
	assert_eq(sim.pathogen(1).cause_of_death, "")
	sim.damage_pathogen(sim.pathogen(1), 100000, 0)
	assert_false(sim.pathogen(1).alive)
	assert_eq(sim.pathogen(1).cause_of_death, "killed")
	assert_ne(sim.state_hash(), before)


func test_cause_of_death_is_not_in_the_state_hash() -> void:
	var setup: BattleSetup = _setup([], [{"type": "rhinovirus", "cell": Vector2i(0, 20)}])
	var a := BattleSim.new(_cfg, setup)
	var b := BattleSim.new(_cfg, setup)
	a.pathogen(1).cause_of_death = "killed"
	assert_eq(a.state_hash(), b.state_hash())


func test_dna_needs_the_debug_flag_and_an_attacker_win() -> void:
	var setup: BattleSetup = _setup([], [])
	var win: BattleSim = _finished_sim(setup, "attacker")
	assert_eq(_resolve(setup, win)["dna_attacker"], 0, "debug_dna off")
	_cfg.feature_flags["debug_dna"] = true
	assert_eq(_resolve(setup, win)["dna_attacker"], 5)
	assert_eq(_resolve(setup, _finished_sim(setup, "defender"))["dna_attacker"], 0)


func test_memory_changes_match_a_direct_update() -> void:
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	var setup: BattleSetup = _setup([{"type": "b_cell", "origin": Vector2i(5, 5)}], [{"type": "rhinovirus", "cell": Vector2i(0, 20)}])
	var sim: BattleSim = _finished_sim(setup)
	sim.pathogen(1).alive = false
	var direct := ImmuneMemory.new()
	var expected: Array[Dictionary] = direct.update_after_raid(sim.seen_strain_keys(), sim.analyzed_strain_keys(), _cfg)
	var via := ImmuneMemory.new()
	var res: Dictionary = RaidResolver.resolve(_cfg, setup, sim, 0, via, {})
	assert_eq(res["memory_changes"], expected)
	assert_eq(via.to_dict(), direct.to_dict())
	_cfg.feature_flags["immune_memory"] = false
	assert_eq(RaidResolver.resolve(_cfg, setup, sim, 0, ImmuneMemory.new(), {})["memory_changes"], [])


func test_breed_after_battle_matches_the_ce03_expectation() -> void:
	_cfg.feature_flags["coevolution"] = true
	var structs: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "macrophage", "origin": Vector2i(5, 5)},
	]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 20)}]
	var setup: BattleSetup = BattleSetup.create(structs, units, 1)
	var sim: BattleSim = SimFixtures.make_sim(structs, units, 1, _cfg)
	sim.finished = true
	sim.outcome = "defender"
	sim._pools["rhinovirus"].fitness[1] = 10
	sim._survival_granted = true
	var pools: Dictionary = {}
	var evolution: Array[Dictionary] = RaidResolver.breed_after_battle(_cfg, setup, sim, pools)
	assert_eq((pools["rhinovirus"] as BreedPool).generation, 1)
	assert_eq((pools["macrophage"] as BreedPool).generation, 0)
	assert_eq(evolution.size(), _cfg.coevo_types.size())
	var by_type: Dictionary = {}
	for e: Dictionary in evolution:
		by_type[e["type_id"]] = e
	assert_true(by_type["rhinovirus"]["bred"])
	assert_false(by_type["macrophage"]["bred"])
	assert_eq(by_type["rhinovirus"]["top_parent"], 1)


func test_resolve_breeds_only_with_coevolution_on() -> void:
	var setup: BattleSetup = _setup([], [])
	var sim: BattleSim = _finished_sim(setup)
	assert_eq(_resolve(setup, sim)["evolution"], [])
	_cfg.feature_flags["coevolution"] = true
	var sim2: BattleSim = BattleSim.new(_cfg, setup)
	sim2.finished = true
	sim2.outcome = "defender"
	var res: Dictionary = RaidResolver.resolve(_cfg, setup, sim2, 0, ImmuneMemory.new(), {})
	assert_eq((res["evolution"] as Array).size(), _cfg.coevo_types.size())


func test_apply_raid_and_defense_results() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 1, 0)
	p.apply_raid_result({"atp_looted": 40, "amino_attacker": 7, "dna_attacker": 5})
	assert_eq(p.wallet["atp"], 1040)
	assert_eq(p.wallet["amino_acids"], 7)
	assert_eq(p.wallet["dna"], 5)
	p.stored_atp = 30
	p.apply_defense_result({"atp_looted": 100, "amino_defender": 4})
	assert_eq(p.stored_atp, 0, "never negative")
	assert_eq(p.wallet["amino_acids"], 11)


func test_loot_block_loads_and_validates() -> void:
	assert_eq(_cfg.loot_atp_pct, 50)
	assert_eq(_cfg.loot_amino_structure_pct, 20)
	assert_eq(_cfg.loot_amino_kill_pct, 10)
	assert_eq(_cfg.loot_dna_per_win, 5)
	assert_false(_cfg.flag("debug_dna"))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_rules.json"))
	rules["loot"]["amino_per_kill_pct"] = 101
	var r1: ConfigLoadResult = _load_rules(rules)
	assert_true(_has_error(r1, "game_rules.json: loot.amino_per_kill_pct: must be <= 100"))
	rules["loot"]["amino_per_kill_pct"] = 10
	rules["loot"]["dna_per_win"] = -1
	assert_true(_has_error(_load_rules(rules), "game_rules.json: loot.dna_per_win: must be >= 0 (got -1)"))
	rules["loot"]["dna_per_win"] = 5
	rules["loot"]["bogus"] = 1
	assert_true(_has_error(_load_rules(rules), "game_rules.json: loot.bogus: unknown key"))
	rules["loot"].erase("bogus")
	rules["loot"].erase("dna_per_win")
	assert_true(_has_error(_load_rules(rules), "game_rules.json: loot.dna_per_win: missing required field"))
	rules.erase("loot")
	rules["feature_flags"]["living_base"] = true
	assert_true(_has_error(_load_rules(rules), "game_rules.json: loot: required when feature_flags.living_base is true"))


func _load_rules(rules: Dictionary) -> ConfigLoadResult:
	return GameConfig.load_from_strings(JSON.stringify(rules),
		FileAccess.get_file_as_string("res://data/structures.json"),
		FileAccess.get_file_as_string("res://data/pathogens.json"))


func _has_error(res: ConfigLoadResult, fragment: String) -> bool:
	for e: String in res.errors:
		if e.find(fragment) != -1:
			return true
	return false
