extends GutTest

## Phase 2 balance sim (#172): the AI campaign, the new CSV columns, upgrades, and byte-identical old output.


func _cfg(flags: Array[String] = []) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["living_base"] = true
	for f: String in flags:
		cfg.feature_flags[f] = true
	return cfg


func _army(count: int = 30) -> Array:
	var ring: Array[Vector2i] = Scenarios.ring_cells(40, 40)
	var units: Array = []
	for i: int in range(count):
		units.append({"type": "rhinovirus", "cell": ring[i * ring.size() / count]})
	return units


## Runs the tool as a subprocess and returns its exit code, the --out file's text and the console output.
func _run_tool(args: Array[String]) -> Dictionary:
	var out_path: String = ProjectSettings.globalize_path("user://balance_test_out.csv")
	DirAccess.remove_absolute(out_path)
	var full: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/balance_sim.gd", "--"]
	full.append_array(args)
	full.append("--out=%s" % out_path)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), full, output, true)
	var text: String = FileAccess.get_file_as_string(out_path) if FileAccess.file_exists(out_path) else ""
	DirAccess.remove_absolute(out_path)
	return {"code": code, "csv": text.replace("\r\n", "\n"), "log": "\n".join(output)}


func _golden(file_name: String) -> String:
	return FileAccess.get_file_as_string("res://tools/fixtures/%s" % file_name).replace("\r\n", "\n")


func test_a_campaign_gives_one_row_per_raid() -> void:
	var res: Dictionary = BalanceCampaign.run(_cfg(), "cold", 1, 3, _army())
	assert_true(res["ok"], str(res["error"]))
	var rows: Array = res["rows"]
	assert_eq(rows.size(), 3)
	for i: int in range(3):
		assert_eq(rows[i]["raid"], i + 1)
		assert_true(["attacker", "defender"].has(rows[i]["outcome"]))
	assert_eq(BalanceCampaign.csv_row(rows[0]).split(",").size(), BalanceCampaign.CSV_HEADER.split(",").size())
	assert_eq(res, BalanceCampaign.run(_cfg(), "cold", 1, 3, _army()), "deterministic")


func test_the_generation_column_rises_with_coevolution() -> void:
	var rose: bool = false
	for seed: int in range(1, 15):
		var rows: Array = BalanceCampaign.run(_cfg(["coevolution"]), "pneumonia", seed, 3, _army(20))["rows"]
		var gens: Array[int] = []
		for r: Dictionary in rows:
			gens.append(int(r["bcell_generation"]))
		if gens[0] >= 1:
			assert_true(gens[1] > gens[0] and gens[2] > gens[1], "generations %s" % [gens])
			rose = true
			break
	assert_true(rose, "a base with a B-Cell shows its pool breeding every raid")
	for r: Dictionary in BalanceCampaign.run(_cfg(), "pneumonia", 1, 3, _army(20))["rows"]:
		assert_eq(r["bcell_generation"], 0, "no breeding without the flag")


func test_the_base_learns_between_raids() -> void:
	var rows: Array = BalanceCampaign.run(_cfg(["immune_memory", "bcell_analysis"]), "pneumonia", 3, 3, _army(20))["rows"]
	var sums: Array[int] = []
	for r: Dictionary in rows:
		sums.append(int(r["memory_levels_sum"]))
	assert_true(sums[2] >= sums[0], "memory does not shrink while the same army keeps coming: %s" % [sums])


func test_an_unknown_tier_is_a_readable_error() -> void:
	var res: Dictionary = BalanceCampaign.run(_cfg(), "nope", 1, 1, _army())
	assert_false(res["ok"])
	assert_true(str(res["error"]).contains("Unknown AI tier 'nope'"))


func test_run_run_reports_the_new_counters_and_takes_upgrades() -> void:
	var cfg: GameConfig = _cfg(["amino_upgrades", "immune_memory", "bcell_analysis"])
	var ring: Array[Vector2i] = Scenarios.ring_cells(cfg.grid_width, cfg.grid_height)
	var base: BattleSetup = Scenarios.repeat_swarm(ring, cfg.default_seed)
	var plain: Array[Dictionary] = BalanceSimRunner.run_run(cfg, base, 0, 5, 2, 2, {}, ring)
	assert_eq(plain[0]["units_trapped"], 0)
	assert_eq(plain[0]["analyses_shared"], 0)
	assert_eq(plain[0]["turncoat_damage"], 0)
	var upgraded: Array[Dictionary] = BalanceSimRunner.run_run(cfg, base, 0, 5, 2, 2, {}, ring, {"analysis_speed": 2, "memory_slot": 1})
	assert_eq(upgraded.size(), 2)
	assert_ne(plain[1]["memory_after"], "", "memory is on")


func test_old_arguments_give_byte_identical_csv() -> void:
	var a: Dictionary = _run_tool(["--scenario=open_field", "--runs=3", "--seed=5"])
	assert_eq(a["code"], 0, a["log"])
	assert_eq(a["csv"], _golden("balance_golden_open_field.golden"))
	var b: Dictionary = _run_tool(["--scenario=repeat_swarm", "--runs=2", "--seed=9", "--generations=2", "--flag=bcell_analysis", "--flag=immune_memory"])
	assert_eq(b["code"], 0, b["log"])
	assert_eq(b["csv"], _golden("balance_golden_memory.golden"))


func test_the_new_columns_appear_only_when_their_flags_are_on() -> void:
	var off: Dictionary = _run_tool(["--scenario=walled_nucleus", "--runs=1", "--seed=1"])
	assert_false(str(off["csv"].split("\n")[0]).contains("units_trapped"))
	var on: Dictionary = _run_tool(["--scenario=walled_nucleus", "--runs=1", "--seed=1", "--flag=mucous_trap"])
	assert_eq(on["code"], 0, on["log"])
	var lines: PackedStringArray = on["csv"].split("\n")
	assert_true(lines[0].ends_with(",units_trapped,analyses_shared,turncoat_damage"), lines[0])
	assert_eq(lines[1].split(",").size(), lines[0].split(",").size())


func test_ai_base_and_ai_army_run_end_to_end() -> void:
	var res: Dictionary = _run_tool(["--ai-base=cold:1", "--ai-army=3", "--flag=living_base", "--runs=2", "--seed=1"])
	assert_eq(res["code"], 0, res["log"])
	var lines: PackedStringArray = str(res["csv"]).strip_edges().split("\n")
	assert_eq(lines.size(), 3, "header and 2 runs")
	var bad: Dictionary = _run_tool(["--ai-base=nope:1", "--ai-army=3", "--flag=living_base", "--runs=1"])
	assert_ne(bad["code"], 0)
	assert_true(str(bad["log"]).contains("Unknown AI tier 'nope'"), bad["log"])


func test_the_campaign_command_prints_one_row_per_raid() -> void:
	var army_path: String = ProjectSettings.globalize_path("user://balance_test_army.json")
	var f: FileAccess = FileAccess.open(army_path, FileAccess.WRITE)
	f.store_string(SnapshotIO.to_json(SnapshotIO.army_to_dict(_army(20))))
	f.close()
	var res: Dictionary = _run_tool(["--ai-campaign=cold:1:3", "--army=%s" % army_path, "--flag=living_base", "--flag=coevolution"])
	DirAccess.remove_absolute(army_path)
	assert_eq(res["code"], 0, res["log"])
	var lines: PackedStringArray = str(res["csv"]).strip_edges().split("\n")
	assert_eq(lines[0], BalanceCampaign.CSV_HEADER)
	assert_eq(lines.size(), 4)
