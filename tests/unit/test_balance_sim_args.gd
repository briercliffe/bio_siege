extends GutTest

## Unit tests for BalanceSimArgs parser, parameter sweeps, stat overrides and deploy jitter.


func test_set_with_nested_path_changes_exactly_that_value() -> void:
	var json_roots: Dictionary = {
		"rules": {
			"tick_rate": 20,
			"battle_timeout_s": 180,
		},
		"structures": {
			"mucous_wall": {
				"hp": 300,
				"path_weight": 10.0,
			},
			"macrophage": {
				"attack": {
					"damage": 40,
					"interval_s": 1.0,
				}
			}
		},
		"pathogens": {
			"rhinovirus": {
				"hp": 30,
				"speed_tiles_s": 2.5,
			}
		}
	}

	# 1. Test overriding nested structure path_weight
	var err1: String = BalanceSimArgs.apply_override(json_roots, "structures.mucous_wall.path_weight", "25")
	assert_eq(err1, "", "apply_override should succeed")
	assert_eq(json_roots["structures"]["mucous_wall"]["path_weight"], 25)
	# Verify other values are unaffected
	assert_eq(json_roots["structures"]["mucous_wall"]["hp"], 300)
	assert_eq(json_roots["rules"]["tick_rate"], 20)
	assert_eq(json_roots["pathogens"]["rhinovirus"]["hp"], 30)

	# 2. Test deeply nested attack property
	var err2: String = BalanceSimArgs.apply_override(json_roots, "structures.macrophage.attack.interval_s", "0.5")
	assert_eq(err2, "", "Deeply nested override should succeed")
	assert_eq(json_roots["structures"]["macrophage"]["attack"]["interval_s"], 0.5)
	assert_eq(json_roots["structures"]["macrophage"]["attack"]["damage"], 40)

	# 3. Test rules override
	var err3: String = BalanceSimArgs.apply_override(json_roots, "rules.battle_timeout_s", "60")
	assert_eq(err3, "", "Rules override should succeed")
	assert_eq(json_roots["rules"]["battle_timeout_s"], 60)


func test_nonexistent_path_is_error() -> void:
	var json_roots: Dictionary = {
		"rules": {"tick_rate": 20},
		"structures": {
			"mucous_wall": {"hp": 300}
		},
		"pathogens": {
			"rhinovirus": {"hp": 30}
		}
	}

	# Nonexistent root
	var err1: String = BalanceSimArgs.apply_override(json_roots, "invalid_root.foo", "10")
	assert_ne(err1, "", "Nonexistent root should return error string")

	# Nonexistent intermediate key
	var err2: String = BalanceSimArgs.apply_override(json_roots, "structures.unknown_structure.hp", "100")
	assert_ne(err2, "", "Nonexistent intermediate key should return error string")

	# Nonexistent leaf key
	var err3: String = BalanceSimArgs.apply_override(json_roots, "pathogens.rhinovirus.magic_stat", "50")
	assert_ne(err3, "", "Nonexistent leaf key should return error string")

	# Empty path
	var err4: String = BalanceSimArgs.apply_override(json_roots, "", "10")
	assert_ne(err4, "", "Empty path should return error string")


func test_sweep_value_generation_inclusive() -> void:
	# Integer sweep: 2:20:6 -> [2, 8, 14, 20] inclusive
	var sweep_int: Dictionary = BalanceSimArgs.parse_sweep("structures.mucous_wall.hp:2:20:6")
	assert_true(sweep_int.get("ok", false), "Sweep parse should succeed")
	assert_eq(sweep_int.get("path"), "structures.mucous_wall.hp")
	var expected_int: Array = [2, 8, 14, 20]
	assert_eq(sweep_int.get("values"), expected_int, "Values must include end bound")

	# Float sweep
	var sweep_float: Dictionary = BalanceSimArgs.parse_sweep("pathogens.rhinovirus.speed_tiles_s:1.0:2.0:0.5")
	assert_true(sweep_float.get("ok", false))
	assert_eq(sweep_float.get("path"), "pathogens.rhinovirus.speed_tiles_s")
	var vals_float: Array = sweep_float.get("values", [])
	assert_eq(vals_float.size(), 3)
	assert_almost_eq(vals_float[0], 1.0, 0.001)
	assert_almost_eq(vals_float[1], 1.5, 0.001)
	assert_almost_eq(vals_float[2], 2.0, 0.001)

	# Invalid step = 0
	var invalid_step: Dictionary = BalanceSimArgs.parse_sweep("rules.tick_rate:10:20:0")
	assert_false(invalid_step.get("ok", false), "Step 0 should fail")

	# Invalid format
	var invalid_format: Dictionary = BalanceSimArgs.parse_sweep("foo:bar")
	assert_false(invalid_format.get("ok", false), "Malformed sweep string should fail")


func test_jitter_wraps_around_ring() -> void:
	# Ring of 4 cells: index 0 -> index 1 -> index 2 -> index 3 -> wraps back to 0
	var ring: Array[Vector2i] = [
		Vector2i(0, 0), # idx 0
		Vector2i(1, 0), # idx 1
		Vector2i(1, 1), # idx 2
		Vector2i(0, 1), # idx 3
	]

	var units: Array = [
		{"type": "rhinovirus", "cell": ring[0]}
	]

	# Find a seed where rng.next_range(-1, 1) returns -1
	var target_seed: int = 0
	while target_seed < 1000:
		var r := Rng.new(target_seed)
		if r.next_range(-1, 1) == -1:
			break
		target_seed += 1

	var jittered: Array = BalanceSimArgs.apply_jitter(units, 1, target_seed, ring)
	assert_eq(jittered.size(), 1)
	# Index 0 with offset -1 in 4-element ring must wrap to index 3 (last ring cell)
	assert_eq(jittered[0]["cell"], ring[3], "Index 0 with offset -1 should wrap to last ring cell")

	# Also verify on full scenario ring
	var scenario_ring: Array[Vector2i] = Scenarios.ring_cells(20, 20)
	var units2: Array = [
		{"type": "rhinovirus", "cell": scenario_ring[0]}
	]
	var jittered2: Array = BalanceSimArgs.apply_jitter(units2, 1, target_seed, scenario_ring)
	assert_eq(jittered2[0]["cell"], scenario_ring[scenario_ring.size() - 1], "Scenario ring index 0 with offset -1 should wrap to last cell")


func test_apply_jitter_zero_is_noop() -> void:
	var ring: Array[Vector2i] = Scenarios.ring_cells(20, 20)
	var units: Array = [
		{"type": "rhinovirus", "cell": ring[0]},
		{"type": "bacteriophage", "cell": ring[5]}
	]
	var jittered: Array = BalanceSimArgs.apply_jitter(units, 0, 12345, ring)
	assert_eq(jittered[0]["cell"], ring[0])
	assert_eq(jittered[1]["cell"], ring[5])
	# Verify deep copy (modifying jittered does not mutate original)
	jittered[0]["cell"] = Vector2i(99, 99)
	assert_eq(units[0]["cell"], ring[0], "Original units array should remain unaffected")


func test_parse_args_scenarios_and_defaults() -> void:
	var args: Array[String] = ["--scenario=mixed"]
	var parsed: Dictionary = BalanceSimArgs.parse_args(args)
	assert_true(parsed.get("ok", false))
	assert_eq(parsed.get("exit_code"), 0)
	assert_eq(parsed.get("inputs", {}).get("scenario"), "mixed")
	var opts: Dictionary = parsed.get("options", {})
	assert_eq(opts.get("runs"), 100)
	assert_eq(opts.get("seed"), -1)
	assert_eq(opts.get("jitter"), 2)
	assert_eq(opts.get("sweep"), "")
	assert_eq(opts.get("out"), "")
	assert_eq(opts.get("set", []), [])


func test_parse_args_all_options() -> void:
	var args: Array[String] = [
		"--scenario=stress",
		"--runs=25",
		"--seed=999",
		"--jitter=4",
		"--set=pathogens.rhinovirus.hp=45",
		"--set=structures.mucous_wall.hp=400",
		"--sweep=structures.mucous_wall.hp:100:500:50",
		"--out=res://output.csv"
	]
	var parsed: Dictionary = BalanceSimArgs.parse_args(args)
	assert_true(parsed.get("ok", false))
	var opts: Dictionary = parsed.get("options", {})
	assert_eq(opts.get("runs"), 25)
	assert_eq(opts.get("seed"), 999)
	assert_eq(opts.get("jitter"), 4)
	assert_eq(opts.get("sweep"), "structures.mucous_wall.hp:100:500:50")
	assert_eq(opts.get("out"), "res://output.csv")
	var sets: Array = opts.get("set", [])
	assert_eq(sets.size(), 2)
	assert_eq(sets[0], "pathogens.rhinovirus.hp=45")
	assert_eq(sets[1], "structures.mucous_wall.hp=400")


func test_parse_args_validation_errors() -> void:
	# No inputs
	var res1: Dictionary = BalanceSimArgs.parse_args(["--runs=10"])
	assert_false(res1.get("ok", false))
	assert_eq(res1.get("exit_code"), 1)

	# Multiple inputs
	var res2: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed", "--battle=battle.json"])
	assert_false(res2.get("ok", false))

	# Invalid scenario name
	var res3: Dictionary = BalanceSimArgs.parse_args(["--scenario=nonexistent_scenario"])
	assert_false(res3.get("ok", false))

	# Base without army
	var res4: Dictionary = BalanceSimArgs.parse_args(["--base=base.json"])
	assert_false(res4.get("ok", false))

	# Army without base
	var res5: Dictionary = BalanceSimArgs.parse_args(["--army=army.json"])
	assert_false(res5.get("ok", false))

	# Invalid runs
	var res6: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed", "--runs=-5"])
	assert_false(res6.get("ok", false))

	# Invalid jitter
	var res7: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed", "--jitter=-1"])
	assert_false(res7.get("ok", false))
