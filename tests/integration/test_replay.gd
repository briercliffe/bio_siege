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
