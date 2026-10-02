extends GutTest

var config: GameConfig = null

func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load cleanly")
	config = res.config


func test_base_round_trip() -> void:
	var grid := GridModel.new(config)
	grid.reset_with_nucleus()

	var wallet := Wallet.new({"atp": 1000})
	var wall_id: int = grid.place("mucous_wall", Vector2i(2, 2), wallet)
	assert_gt(wall_id, 0)
	var macro_id: int = grid.place("macrophage", Vector2i(5, 5), wallet)
	assert_gt(macro_id, 0)

	var orig_layout: Array[Dictionary] = grid.to_layout()

	var base_dict: Dictionary = SnapshotIO.base_to_dict(grid)
	assert_eq(base_dict["format"], "bio_siege.base")
	assert_eq(base_dict["version"], 1)
	assert_eq(base_dict["grid"]["width"], config.grid_width)
	assert_eq(base_dict["grid"]["height"], config.grid_height)

	var json_str: String = SnapshotIO.to_json(base_dict)
	var parsed: Dictionary = SnapshotIO.parse_base(json_str, config)
	assert_true(parsed["ok"])
	assert_eq(parsed["error"], "")
	assert_eq(parsed["layout"], orig_layout)


func test_army_round_trip() -> void:
	var army := Army.new(config)
	army.deployments.append({"type": "rhinovirus", "cell": Vector2i(0, 5)})
	army.deployments.append({"type": "bacteriophage", "cell": Vector2i(19, 10)})
	army.deployments.append({"type": "staphylococcus", "cell": Vector2i(5, 0)})

	var army_dict: Dictionary = SnapshotIO.army_to_dict(army.deployments)
	assert_eq(army_dict["format"], "bio_siege.army")
	assert_eq(army_dict["version"], 1)
	assert_eq(army_dict["units"].size(), 3)

	var json_str: String = SnapshotIO.to_json(army_dict)
	var parsed: Dictionary = SnapshotIO.parse_army(json_str, config)
	assert_true(parsed["ok"])
	assert_eq(parsed["error"], "")
	assert_eq(parsed["units"], army.deployments)


func test_parse_base_errors() -> void:
	# 1. Invalid JSON
	var err_json: Dictionary = SnapshotIO.parse_base("not valid json", config)
	assert_false(err_json["ok"])

	# 2. Wrong format
	var wrong_fmt_dict := {
		"format": "wrong.format",
		"version": 1,
		"grid": {"width": 40, "height": 40},
		"structures": [{"type": "nucleus", "origin": [18, 18]}],
	}
	var res_fmt: Dictionary = SnapshotIO.parse_base(JSON.stringify(wrong_fmt_dict), config)
	assert_false(res_fmt["ok"])
	assert_true("Not a Bio Siege base" in res_fmt["error"])

	# 3. Wrong version (version > 1)
	var wrong_ver_dict := {
		"format": "bio_siege.base",
		"version": 2,
		"grid": {"width": 40, "height": 40},
		"structures": [{"type": "nucleus", "origin": [18, 18]}],
	}
	var res_ver: Dictionary = SnapshotIO.parse_base(JSON.stringify(wrong_ver_dict), config)
	assert_false(res_ver["ok"])
	assert_true("newer version" in res_ver["error"])

	# 4. Grid size mismatch
	var wrong_grid_dict := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": 10, "height": 10},
		"structures": [{"type": "nucleus", "origin": [18, 18]}],
	}
	var res_grid: Dictionary = SnapshotIO.parse_base(JSON.stringify(wrong_grid_dict), config)
	assert_false(res_grid["ok"])
	assert_true("Grid size mismatch" in res_grid["error"])

	# 4b. Old 20x20 base files are rejected with the normal grid-size error
	var old_grid_dict := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": 20, "height": 20},
		"structures": [{"type": "nucleus", "origin": [9, 9]}],
	}
	var res_old: Dictionary = SnapshotIO.parse_base(JSON.stringify(old_grid_dict), config)
	assert_false(res_old["ok"])
	assert_true("Grid size mismatch" in res_old["error"])

	# 5. Unknown structure type
	var unknown_type_dict := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": 40, "height": 40},
		"structures": [
			{"type": "nucleus", "origin": [18, 18]},
			{"type": "nonexistent_cannon", "origin": [2, 2]},
		],
	}
	var res_type: Dictionary = SnapshotIO.parse_base(JSON.stringify(unknown_type_dict), config)
	assert_false(res_type["ok"])
	assert_true("Unknown structure type" in res_type["error"])

	# 6. Invalid origin cell
	var invalid_origin_dict := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": 40, "height": 40},
		"structures": [
			{"type": "nucleus", "origin": [18, 18]},
			{"type": "mucous_wall", "origin": "invalid"},
		],
	}
	var res_origin: Dictionary = SnapshotIO.parse_base(JSON.stringify(invalid_origin_dict), config)
	assert_false(res_origin["ok"])
	assert_true("Invalid origin cell" in res_origin["error"])

	# 7. BattleSetup.validate failure (missing core structure)
	var no_core_dict := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": 40, "height": 40},
		"structures": [
			{"type": "mucous_wall", "origin": [2, 2]},
		],
	}
	var res_core: Dictionary = SnapshotIO.parse_base(JSON.stringify(no_core_dict), config)
	assert_false(res_core["ok"])
	assert_true("core structure" in res_core["error"])


func test_parse_army_errors() -> void:
	# 1. Invalid JSON
	var err_json: Dictionary = SnapshotIO.parse_army("{invalid", config)
	assert_false(err_json["ok"])

	# 2. Wrong format
	var wrong_fmt_dict := {
		"format": "wrong.format",
		"version": 1,
		"units": [{"type": "rhinovirus", "cell": [0, 0]}],
	}
	var res_fmt: Dictionary = SnapshotIO.parse_army(JSON.stringify(wrong_fmt_dict), config)
	assert_false(res_fmt["ok"])
	assert_true("Not a Bio Siege army" in res_fmt["error"])

	# 3. Wrong version
	var wrong_ver_dict := {
		"format": "bio_siege.army",
		"version": 5,
		"units": [{"type": "rhinovirus", "cell": [0, 0]}],
	}
	var res_ver: Dictionary = SnapshotIO.parse_army(JSON.stringify(wrong_ver_dict), config)
	assert_false(res_ver["ok"])
	assert_true("newer version" in res_ver["error"])

	# 4. Unknown pathogen type
	var unknown_type_dict := {
		"format": "bio_siege.army",
		"version": 1,
		"units": [{"type": "alien_pathogen", "cell": [0, 0]}],
	}
	var res_type: Dictionary = SnapshotIO.parse_army(JSON.stringify(unknown_type_dict), config)
	assert_false(res_type["ok"])
	assert_true("Unknown pathogen type" in res_type["error"])

	# 5. Malformed cell
	var malformed_cell_dict := {
		"format": "bio_siege.army",
		"version": 1,
		"units": [{"type": "rhinovirus", "cell": "not_an_array"}],
	}
	var res_cell: Dictionary = SnapshotIO.parse_army(JSON.stringify(malformed_cell_dict), config)
	assert_false(res_cell["ok"])
	assert_true("Malformed cell" in res_cell["error"])


func test_stable_json_output() -> void:
	var d1: Dictionary = {}
	d1["z"] = 100
	d1["a"] = "first"
	d1["m"] = {"y": [1, 2], "b": 50}

	var d2: Dictionary = {}
	d2["a"] = "first"
	d2["m"] = {"b": 50, "y": [1, 2]}
	d2["z"] = 100

	var json1: String = SnapshotIO.to_json(d1)
	var json2: String = SnapshotIO.to_json(d2)

	assert_eq(json1, json2, "to_json must produce byte-identical output regardless of insertion order")


func test_battle_to_dict_and_setup_from_battle() -> void:
	var setup: BattleSetup = Scenarios.open_field(123)
	var sim := BattleSim.new(config, setup)
	for i in range(10):
		sim.step()

	var b_dict: Dictionary = SnapshotIO.battle_to_dict(config, setup, sim)
	assert_eq(b_dict["format"], "bio_siege.battle")
	assert_eq(b_dict["version"], 1)
	assert_eq(b_dict["config_hash"], config.content_hash)
	assert_eq(b_dict["seed"], 123)
	assert_eq(b_dict["result"]["ticks"], 10)
	assert_eq(b_dict["result"]["final_state_hash"], sim.state_hash())

	var json_str: String = SnapshotIO.to_json(b_dict)
	var parsed: Dictionary = SnapshotIO.parse_battle(json_str, config)
	assert_true(parsed["ok"])
	assert_eq(parsed["error"], "")
	assert_eq(parsed["config_hash"], config.content_hash)

	var recovered_setup: BattleSetup = SnapshotIO.setup_from_battle(b_dict)
	assert_eq(recovered_setup.seed, setup.seed)
	assert_eq(recovered_setup.structures.size(), setup.structures.size())
	assert_eq(recovered_setup.units.size(), setup.units.size())


func _strain_army_json(units: Array) -> String:
	return SnapshotIO.to_json({"format": "bio_siege.army", "version": 1, "units": units})

func test_army_to_dict_strain_only_when_not_wild() -> void:
	var d: Dictionary = SnapshotIO.army_to_dict([
		{"type": "rhinovirus", "cell": Vector2i(0, 0), "strain": "wild"},
		{"type": "rhinovirus", "cell": Vector2i(1, 0)},
		{"type": "bacteriophage", "cell": Vector2i(2, 0), "strain": "capsid_hardening"},
	])
	assert_false((d["units"][0] as Dictionary).has("strain"))
	assert_false((d["units"][1] as Dictionary).has("strain"))
	assert_eq(d["units"][2]["strain"], "capsid_hardening")

func test_parse_army_strain_rules() -> void:
	var ok: Dictionary = SnapshotIO.parse_army(_strain_army_json([
		{"type": "rhinovirus", "cell": [0, 0], "strain": "capsid_hardening"},
		{"type": "rhinovirus", "cell": [1, 0], "strain": "capsid_hardening"},
	]), config)
	assert_true(ok["ok"])
	assert_eq(ok["units"][0]["strain"], "capsid_hardening")
	var unknown: Dictionary = SnapshotIO.parse_army(_strain_army_json([
		{"type": "rhinovirus", "cell": [0, 0], "strain": "nope"},
	]), config)
	assert_false(unknown["ok"])
	assert_eq(unknown["error"], "Unknown strain 'nope' for rhinovirus")
	var mixed: Dictionary = SnapshotIO.parse_army(_strain_army_json([
		{"type": "rhinovirus", "cell": [0, 0], "strain": "capsid_hardening"},
		{"type": "rhinovirus", "cell": [1, 0]},
	]), config)
	assert_false(mixed["ok"])
	assert_eq(mixed["error"], "An army can use only one strain per pathogen type (rhinovirus)")

func test_setup_from_battle_keeps_strain() -> void:
	var d: Dictionary = {
		"seed": 1,
		"base": {"structures": []},
		"army": {"units": [{"type": "rhinovirus", "cell": [0, 0], "strain": "capsid_hardening"}]},
	}
	var setup: BattleSetup = SnapshotIO.setup_from_battle(d)
	assert_eq(setup.units[0]["strain"], "capsid_hardening")


func test_base_memory_round_trip() -> void:
	var grid := GridModel.new(config)
	grid.reset_with_nucleus()
	assert_false(SnapshotIO.base_to_dict(grid).has("memory"))
	assert_false(SnapshotIO.base_to_dict(grid, ImmuneMemory.new()).has("memory"))

	var mem := ImmuneMemory.new()
	mem.raids = 2
	mem.entries["rhinovirus/wild"] = {"level": 2, "absent": 0, "since": 1}
	var d: Dictionary = SnapshotIO.base_to_dict(grid, mem)
	assert_eq(d["version"], 1)
	var parsed: Dictionary = SnapshotIO.parse_base(SnapshotIO.to_json(d), config)
	assert_true(parsed["ok"])
	var back: ImmuneMemory = ImmuneMemory.from_dict(parsed["memory"], config)
	assert_eq(back.to_dict(), mem.to_dict())
	assert_eq(SnapshotIO.parse_base(SnapshotIO.to_json(SnapshotIO.base_to_dict(grid)), config)["memory"], {})

	d["memory"] = "junk"
	var bad: Dictionary = SnapshotIO.parse_base(SnapshotIO.to_json(d), config)
	assert_false(bad["ok"])
	assert_eq(bad["error"], "Invalid memory block")


func test_battle_memory_seed_round_trip() -> void:
	var base: BattleSetup = Scenarios.open_field(9)
	var setup: BattleSetup = BattleSetup.create(base.structures, base.units, 9, {"rhinovirus/wild": 75})
	var sim := BattleSim.new(config, setup)
	var b_dict: Dictionary = SnapshotIO.battle_to_dict(config, setup, sim)
	assert_eq(b_dict["memory_seed"], {"rhinovirus/wild": 75})
	assert_eq(SnapshotIO.setup_from_battle(b_dict).memory_seed, {"rhinovirus/wild": 75})
	var parsed: Dictionary = SnapshotIO.parse_battle(SnapshotIO.to_json(b_dict), config)
	assert_true(parsed["ok"])
	assert_eq((parsed["setup"] as BattleSetup).memory_seed, {"rhinovirus/wild": 75})
	var plain: Dictionary = SnapshotIO.battle_to_dict(config, base, BattleSim.new(config, base))
	assert_false(plain.has("memory_seed"))


func _two_pools() -> Dictionary:
	return {
		"rhinovirus": {"generation": 3, "genomes": [{"antigens": ["capsule_a", ""], "receptors": ["binder_a", ""]}]},
		"macrophage": {"generation": 1, "genomes": [{"antigens": ["", "wall_b"], "receptors": ["", "hook_b"]}]},
	}


func test_base_populations_round_trip() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	assert_false(SnapshotIO.base_to_dict(grid).has("populations"))
	assert_eq(SnapshotIO.parse_base(SnapshotIO.to_json(SnapshotIO.base_to_dict(grid)), cfg)["populations"], {})

	var pools: Dictionary = _two_pools()
	var d: Dictionary = SnapshotIO.base_to_dict(grid, null, pools)
	assert_eq(d["version"], 1)
	var parsed: Dictionary = SnapshotIO.parse_base(SnapshotIO.to_json(d), cfg)
	assert_true(parsed["ok"])
	for type_id: String in pools.keys():
		var back: BreedPool = BreedPool.from_dict(parsed["populations"][type_id], type_id, cfg)
		assert_eq(back.to_dict(), BreedPool.from_dict(pools[type_id], type_id, cfg).to_dict())
	assert_eq(BreedPool.from_dict(parsed["populations"]["rhinovirus"], "rhinovirus", cfg).generation, 3)

	d["populations"] = []
	var bad: Dictionary = SnapshotIO.parse_base(SnapshotIO.to_json(d), cfg)
	assert_false(bad["ok"])
	assert_eq(bad["error"], "Invalid populations block")


func test_battle_populations_round_trip() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var base: BattleSetup = Scenarios.open_field(9)
	var setup: BattleSetup = BattleSetup.create(base.structures, base.units, 9, {}, _two_pools())
	var b_dict: Dictionary = SnapshotIO.battle_to_dict(cfg, setup, BattleSim.new(cfg, setup))
	assert_eq(SnapshotIO.setup_from_battle(b_dict).populations, _two_pools())
	var parsed: Dictionary = SnapshotIO.parse_battle(SnapshotIO.to_json(b_dict), cfg)
	assert_true(parsed["ok"])
	var rhino: Dictionary = (parsed["setup"] as BattleSetup).populations["rhinovirus"]
	assert_eq(int(rhino["generation"]), 3)
	assert_false(SnapshotIO.battle_to_dict(cfg, base, BattleSim.new(cfg, base))["base"].has("populations"))


func test_a_widened_pool_survives_base_and_battle_round_trips() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["coevolution"] = true
	var pool: BreedPool = BreedPool.wild_pool("macrophage", cfg)
	pool.widen_receptors(1)
	pool.genomes[0] = Genome.from_slots(["", "wall_b"], ["binder_a", "", "hook_b"], cfg, 2, 3)
	var pools: Dictionary = {"macrophage": pool.to_dict()}
	assert_eq(pools["macrophage"]["receptor_slots"], 3)
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	var parsed_base: Dictionary = SnapshotIO.parse_base(SnapshotIO.to_json(SnapshotIO.base_to_dict(grid, null, pools)), cfg)
	assert_true(parsed_base["ok"])
	var back: BreedPool = BreedPool.from_dict(parsed_base["populations"]["macrophage"], "macrophage", cfg)
	assert_eq(back.receptor_slots, 3)
	assert_eq(back.genomes[0].receptors, ["binder_a", "", "hook_b"] as Array[String])
	var base: BattleSetup = Scenarios.open_field(9)
	var setup: BattleSetup = BattleSetup.create(base.structures, base.units, 9, {}, pools)
	var sim := BattleSim.new(cfg, setup)
	sim.run_to_end(40)
	var parsed: Dictionary = SnapshotIO.parse_battle(SnapshotIO.to_json(SnapshotIO.battle_to_dict(cfg, setup, sim)), cfg)
	assert_true(parsed["ok"])
	assert_eq((parsed["setup"] as BattleSetup).populations["macrophage"]["receptor_slots"], 3)

func test_parse_base_rejects_structure_with_flag_off() -> void:
	(config.structures["mucous_wall"] as StructureDef).requires_flag = "living_base"
	var d := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": config.grid_width, "height": config.grid_height},
		"structures": [
			{"type": "nucleus", "origin": [18, 18]},
			{"type": "mucous_wall", "origin": [2, 2]},
		],
	}
	var res: Dictionary = SnapshotIO.parse_base(JSON.stringify(d), config)
	assert_false(res["ok"])
	assert_true("Unknown structure type" in res["error"])
	config.feature_flags["living_base"] = true
	assert_true(SnapshotIO.parse_base(JSON.stringify(d), config)["ok"])
	(config.structures["mucous_wall"] as StructureDef).requires_flag = ""
	config.feature_flags.erase("living_base")
