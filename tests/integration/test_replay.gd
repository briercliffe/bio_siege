extends GutTest

var config: GameConfig = null

func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load cleanly")
	config = res.config


func test_replay_verify_mixed_scenario() -> void:
	var setup: BattleSetup = Scenarios.mixed([], 42)
	var sim := BattleSim.new(config, setup)
	while not sim.finished:
		sim.step()

	var battle_dict: Dictionary = SnapshotIO.battle_to_dict(config, setup, sim)
	var battle_json: String = SnapshotIO.to_json(battle_dict)

	var verify_res: Dictionary = Replay.verify(battle_json, config)
	assert_true(verify_res["ok"], "Verification should complete without error")
	assert_true(verify_res["match"], "Verification should match headless run")
	assert_true(verify_res["config_matches"], "Config hash should match")
	assert_eq(verify_res["expected_hash"], sim.state_hash())
	assert_eq(verify_res["actual_hash"], sim.state_hash())


func test_replay_changing_seed_fails_match() -> void:
	var setup: BattleSetup = Scenarios.mixed([], 42)
	var sim := BattleSim.new(config, setup)
	while not sim.finished:
		sim.step()

	var battle_dict: Dictionary = SnapshotIO.battle_to_dict(config, setup, sim)
	# Tamper with the seed in the log
	battle_dict["seed"] = 999

	var battle_json: String = SnapshotIO.to_json(battle_dict)
	var verify_res: Dictionary = Replay.verify(battle_json, config)
	assert_true(verify_res["ok"], "Verification process should succeed")
	assert_false(verify_res["match"], "Replay with different seed must not match original hash")
	assert_ne(verify_res["expected_hash"], verify_res["actual_hash"])


func test_replay_removing_unit_fails_match() -> void:
	var setup: BattleSetup = Scenarios.mixed([], 42)
	var sim := BattleSim.new(config, setup)
	while not sim.finished:
		sim.step()

	var battle_dict: Dictionary = SnapshotIO.battle_to_dict(config, setup, sim)
	# Remove one unit from army
	var units_arr: Array = battle_dict["army"]["units"]
	assert_gt(units_arr.size(), 1)
	units_arr.pop_back()

	var battle_json: String = SnapshotIO.to_json(battle_dict)
	var verify_res: Dictionary = Replay.verify(battle_json, config)
	assert_true(verify_res["ok"])
	assert_false(verify_res["match"], "Replay with missing unit must not match")


func test_replay_tampered_config_hash() -> void:
	var setup: BattleSetup = Scenarios.mixed([], 42)
	var sim := BattleSim.new(config, setup)
	while not sim.finished:
		sim.step()

	var battle_dict: Dictionary = SnapshotIO.battle_to_dict(config, setup, sim)
	battle_dict["config_hash"] = "0000000000000000000000000000000000000000000000000000000000000000"

	var battle_json: String = SnapshotIO.to_json(battle_dict)
	var verify_res: Dictionary = Replay.verify(battle_json, config)
	assert_true(verify_res["ok"])
	assert_false(verify_res["config_matches"], "Tampered config hash must result in config_matches: false")


func test_replay_verify_with_strains() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["strains"] = true
	var base: BattleSetup = Scenarios.walled_nucleus(7)
	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 20), "strain": "capsid_hardening"},
		{"type": "rhinovirus", "cell": Vector2i(0, 20), "strain": "capsid_hardening"},
		{"type": "staphylococcus", "cell": Vector2i(0, 9), "strain": "antigenic_masking"},
	]
	var setup: BattleSetup = BattleSetup.create(base.structures, units, 7)
	var sim := BattleSim.new(cfg, setup)
	while not sim.finished:
		sim.step()
	var json: String = SnapshotIO.to_json(SnapshotIO.battle_to_dict(cfg, setup, sim))
	var res: Dictionary = Replay.verify(json, cfg)
	assert_true(res["ok"])
	assert_true(res["match"], "strained battle must reproduce")


func test_replay_verify_with_memory_seed() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["bcell_analysis"] = true
	var structs: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "b_cell", "origin": Vector2i(10, 3)},
		{"type": "macrophage", "origin": Vector2i(6, 6)},
	]
	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "staphylococcus", "cell": Vector2i(0, 9)},
	]
	var setup: BattleSetup = BattleSetup.create(structs, units, 11, {"rhinovirus/wild": 50, "staphylococcus/wild": 100})
	var sim := BattleSim.new(cfg, setup)
	while not sim.finished:
		sim.step()
	var json: String = SnapshotIO.to_json(SnapshotIO.battle_to_dict(cfg, setup, sim))
	var res: Dictionary = Replay.verify(json, cfg)
	assert_true(res["ok"])
	assert_true(res["match"], "seeded battle must reproduce")
