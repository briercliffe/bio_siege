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
	var scenario_ring: Array[Vector2i] = Scenarios.ring_cells(40, 40, 2)
	var units2: Array = [
		{"type": "rhinovirus", "cell": scenario_ring[0]}
	]
	var jittered2: Array = BalanceSimArgs.apply_jitter(units2, 1, target_seed, scenario_ring)
	assert_eq(jittered2[0]["cell"], scenario_ring[scenario_ring.size() - 1], "Scenario ring index 0 with offset -1 should wrap to last cell")


func test_apply_jitter_zero_is_noop() -> void:
	var ring: Array[Vector2i] = Scenarios.ring_cells(40, 40, 2)
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


func _load_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load")
	return res.config


func test_flag_option_repeatable_and_validated() -> void:
	var ok: Dictionary = BalanceSimArgs.parse_args(["--scenario=repeat_swarm", "--flag=bcell_analysis", "--flag=immune_memory"])
	assert_true(ok.get("ok", false))
	assert_eq((ok["options"] as Dictionary)["flags"], ["bcell_analysis", "immune_memory"])
	var bad: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed", "--flag=Bad-Name"])
	assert_false(bad.get("ok", true))
	assert_eq(bad.get("exit_code"), 1)


func test_strain_option_validated() -> void:
	var ok: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed", "--strain=rhinovirus:capsid_hardening"])
	assert_true(ok.get("ok", false))
	assert_eq((ok["options"] as Dictionary)["strains"], {"rhinovirus": "capsid_hardening"})
	assert_false(BalanceSimArgs.parse_args(["--scenario=mixed", "--strain=rhinovirus"]).get("ok", true))
	assert_false(BalanceSimArgs.parse_args(["--scenario=mixed", "--strain=a:b:c"]).get("ok", true))
	assert_false(BalanceSimArgs.parse_args(["--scenario=mixed", "--strain=:wild"]).get("ok", true))


func test_parse_memory() -> void:
	var ok: Dictionary = BalanceSimArgs.parse_memory("rhinovirus/wild:3,staphylococcus/wild:1")
	assert_true(ok.get("ok", false))
	assert_eq(ok["levels"], {"rhinovirus/wild": 3, "staphylococcus/wild": 1})
	assert_false(BalanceSimArgs.parse_memory("rhinovirus:3").get("ok", true))
	assert_false(BalanceSimArgs.parse_memory("rhinovirus/wild:0").get("ok", true))
	assert_false(BalanceSimArgs.parse_memory("a/b/c:1").get("ok", true))
	var via_args: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed", "--memory=rhinovirus/wild:3"])
	assert_eq((via_args["options"] as Dictionary)["memory"], {"rhinovirus/wild": 3})
	assert_false(BalanceSimArgs.parse_args(["--scenario=mixed", "--memory=rhinovirus:3"]).get("ok", true))


func test_generations_option_bounds_and_default() -> void:
	var def: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed"])
	assert_eq((def["options"] as Dictionary)["generations"], 1)
	assert_eq((def["options"] as Dictionary)["flags"], [])
	assert_eq((def["options"] as Dictionary)["strains"], {})
	assert_eq((def["options"] as Dictionary)["memory"], {})
	assert_false(BalanceSimArgs.parse_args(["--scenario=mixed", "--generations=0"]).get("ok", true))
	assert_false(BalanceSimArgs.parse_args(["--scenario=mixed", "--generations=51"]).get("ok", true))
	var ok: Dictionary = BalanceSimArgs.parse_args(["--scenario=mixed", "--generations=50"])
	assert_eq((ok["options"] as Dictionary)["generations"], 50)


func test_repeat_swarm_is_valid_scenario() -> void:
	assert_true(BalanceSimArgs.parse_args(["--scenario=repeat_swarm"]).get("ok", false))


func test_apply_strains_matching_types_only_and_no_mutation() -> void:
	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 0)},
		{"type": "staphylococcus", "cell": Vector2i(1, 0)},
	]
	var out: Array = BalanceSimArgs.apply_strains(units, {"rhinovirus": "capsid_hardening"})
	assert_eq((out[0] as Dictionary).get("strain"), "capsid_hardening")
	assert_false((out[1] as Dictionary).has("strain"))
	assert_false((units[0] as Dictionary).has("strain"), "input array must not change")


func test_unit_strain_keys_default_wild_sorted_unique() -> void:
	var units: Array = [
		{"type": "staphylococcus"},
		{"type": "rhinovirus", "strain": "capsid_hardening"},
		{"type": "rhinovirus"},
		{"type": "rhinovirus"},
	]
	assert_eq(BalanceSimArgs.unit_strain_keys(units), ["rhinovirus/capsid_hardening", "rhinovirus/wild", "staphylococcus/wild"])


func test_memory_from_levels_clamps_to_max_level() -> void:
	var cfg: GameConfig = _load_config()
	var m: ImmuneMemory = BalanceSimArgs.memory_from_levels({"rhinovirus/wild": 9, "staphylococcus/wild": 1}, cfg)
	assert_eq(m.level_of("rhinovirus/wild"), cfg.memory_max_level)
	assert_eq(m.level_of("staphylococcus/wild"), 1)
	assert_eq(m.raids, 0)


# --- Phase 2 arguments (#172) ---

func _parse(extra: Array) -> Dictionary:
	var args: Array[String] = []
	for a: Variant in extra:
		args.append(str(a))
	return BalanceSimArgs.parse_args(args)


func test_ai_base_and_ai_army_parse_as_a_base_army_input() -> void:
	var res: Dictionary = _parse(["--ai-base=cold:7", "--ai-army=3"])
	assert_true(res["ok"], str(res))
	assert_eq(res["inputs"]["type"], "base_army")
	assert_eq(res["inputs"]["ai_base"], {"tier": "cold", "seed": 7})
	assert_eq(res["inputs"]["ai_army_seed"], 3)


func test_an_ai_base_can_take_an_army_file_and_a_base_file_an_ai_army() -> void:
	assert_true(_parse(["--ai-base=flu:1", "--army=a.json"])["ok"])
	assert_true(_parse(["--base=b.json", "--ai-army=2"])["ok"])


func test_ai_base_needs_an_army_side_and_vice_versa() -> void:
	var a: Dictionary = _parse(["--ai-base=cold:1"])
	assert_false(a["ok"])
	assert_true(str(a["error"]).contains("Both a base"), a["error"])
	assert_false(_parse(["--ai-army=1"])["ok"])
	# The old message is unchanged for the old arguments.
	assert_eq(_parse(["--base=b.json"])["error"], "Both --base and --army must be specified together")
	assert_false(_parse(["--base=b.json", "--ai-base=cold:1", "--army=a.json"])["ok"])
	assert_false(_parse(["--base=b.json", "--army=a.json", "--ai-army=1"])["ok"])


func test_bad_ai_values_give_readable_errors() -> void:
	assert_true(str(_parse(["--ai-base=cold", "--ai-army=1"])["error"]).contains("Invalid --ai-base value 'cold': expected <tier>:<seed>"))
	assert_true(str(_parse(["--ai-base=Cold:1", "--ai-army=1"])["error"]).contains("Invalid --ai-base"))
	assert_true(str(_parse(["--ai-base=cold:x", "--ai-army=1"])["error"]).contains("Invalid --ai-base"))
	assert_true(str(_parse(["--ai-base=cold:1", "--ai-army=abc"])["error"]).contains("Invalid --ai-army value 'abc': must be an integer seed"))


func test_ai_campaign_parses_and_validates() -> void:
	var res: Dictionary = _parse(["--ai-campaign=cold:1:3", "--army=a.json"])
	assert_true(res["ok"], str(res))
	assert_eq(res["inputs"]["type"], "ai_campaign")
	assert_eq(res["options"]["ai_campaign"], {"tier": "cold", "seed": 1, "raids": 3})
	assert_true(str(_parse(["--ai-campaign=cold:1:3"])["error"]).contains("needs --army"))
	assert_true(str(_parse(["--ai-campaign=cold:1", "--army=a.json"])["error"]).contains("expected <tier>:<seed>:<raids>"))
	assert_true(str(_parse(["--ai-campaign=cold:1:0", "--army=a.json"])["error"]).contains("must be an integer from 1 to 50"))
	assert_true(str(_parse(["--ai-campaign=cold:1:51", "--army=a.json"])["error"]).contains("must be an integer from 1 to 50"))
	assert_true(str(_parse(["--ai-campaign=cold:1:3", "--army=a.json", "--scenario=open_field"])["error"]).contains("cannot be combined"))
	assert_true(str(_parse(["--ai-campaign=cold:1:3", "--army=a.json", "--ai-base=cold:1"])["error"]).contains("cannot be combined"))


func test_upgrades_parse_and_validate() -> void:
	var res: Dictionary = _parse(["--scenario=open_field", "--upgrades=memory_slot:2,analysis_speed:1"])
	assert_true(res["ok"], str(res))
	assert_eq(res["options"]["upgrades"], {"memory_slot": 2, "analysis_speed": 1})
	assert_false(_parse(["--scenario=open_field"])["options"].has("upgrades"))
	assert_true(str(_parse(["--scenario=open_field", "--upgrades=hp_boost:1"])["error"]).contains("unknown upgrade 'hp_boost'"))
	assert_true(str(_parse(["--scenario=open_field", "--upgrades=memory_slot"])["error"]).contains("must be <upgrade>:<level>"))
	assert_true(str(_parse(["--scenario=open_field", "--upgrades=memory_slot:x"])["error"]).contains("must be an integer from 0 to 10"))
	assert_true(str(_parse(["--scenario=open_field", "--upgrades=memory_slot:11"])["error"]).contains("must be an integer from 0 to 10"))
	assert_true(str(_parse(["--scenario=open_field", "--upgrades="])["error"]).contains("empty upgrades specification"))


func test_old_arguments_keep_their_exact_options_shape() -> void:
	var res: Dictionary = _parse(["--scenario=open_field", "--runs=5"])
	assert_false(res["options"].has("ai_campaign"))
	assert_false(res["options"].has("upgrades"))
	assert_eq(res["inputs"], {"type": "scenario", "scenario": "open_field", "name": "open_field"})
