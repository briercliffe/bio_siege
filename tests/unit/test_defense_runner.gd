extends GutTest

## DefenseRunner (#163): AI raids on the player's base, resolved headless.

var _cfg: GameConfig = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true


## A profile whose base is `towers` defended, with some ATP stored in a Mitochondria.
func _profile(layout_extra: Array, seed: int = 11, stored: int = 200) -> LivingBaseProfile:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, seed, 0)
	for e: Dictionary in layout_extra:
		p.layout.append(e)
	p.stored_atp = stored
	return p


func _undefended() -> LivingBaseProfile:
	return _profile([{"type": "mitochondria", "origin": [10, 10]}])


func _strong() -> LivingBaseProfile:
	var gen: Dictionary = AiBaseGenerator.generate(_cfg, "pneumonia", 5)
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 11, 0)
	p.layout = []
	for e: Dictionary in gen["layout"]:
		p.layout.append({"type": str(e["type"]), "origin": [(e["origin"] as Vector2i).x, (e["origin"] as Vector2i).y]})
	p.stored_atp = 200
	return p


func test_build_setup_is_deterministic_and_uses_the_profile_seed() -> void:
	var p: LivingBaseProfile = _undefended()
	var a: BattleSetup = DefenseRunner.build_setup(_cfg, p, 3)
	var b: BattleSetup = DefenseRunner.build_setup(_cfg, p, 3)
	assert_eq(a.to_dict(), b.to_dict())
	assert_eq(a.seed, 11 + 104729 * 3)
	assert_eq(a.structures.size(), p.layout.size())
	assert_gt(a.units.size(), 0)
	assert_ne(DefenseRunner.build_setup(_cfg, p, 4).units, a.units)
	assert_eq(a.validate(_cfg).size(), 0, str(a.validate(_cfg)))


func test_an_undefended_base_loses_atp_and_is_repaired() -> void:
	var p: LivingBaseProfile = _undefended()
	var layout_before: Array[Dictionary] = p.layout.duplicate(true)
	var entry: Dictionary = DefenseRunner.resolve_offline(_cfg, p, 0)
	assert_eq(entry["outcome"], "attacker")
	assert_gt(int(entry["atp_lost"]), 0)
	assert_eq(int(entry["atp_lost"]), 100, "50% of the 200 stored ATP")
	assert_eq(p.stored_atp, 100)
	assert_eq(p.layout, layout_before, "the base is repaired")
	assert_eq(p.ai_raid_counter, 1)
	assert_eq(entry["raid_index"], 0)
	assert_gt(int(entry["ticks"]), 0)
	assert_false((entry["army"] as Dictionary).is_empty())


func test_a_strong_base_holds_and_earns_amino_acids() -> void:
	var held: int = 0
	var amino: int = 0
	for raid_index: int in range(0, 4):
		var p: LivingBaseProfile = _strong()
		var entry: Dictionary = DefenseRunner.resolve_offline(_cfg, p, raid_index)
		if entry["outcome"] == "defender":
			held += 1
			amino += int(entry["amino_gained"])
			assert_eq(int(p.wallet.get("amino_acids", 0)), int(entry["amino_gained"]))
	assert_gt(held, 0, "a 1200 ATP base holds against some of these armies")
	assert_gt(amino, 0)


func test_consecutive_raids_carry_the_learning_forward() -> void:
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	var p: LivingBaseProfile = _strong()
	var first: Dictionary = DefenseRunner.resolve_offline(_cfg, p, 0)
	var second: Dictionary = DefenseRunner.resolve_offline(_cfg, p, 1)
	assert_eq(p.ai_raid_counter, 2)
	assert_gt((first["memory_changes"] as Array).size(), 0, "raid 1 learned something")
	var learned_first: Array = []
	for c: Dictionary in first["memory_changes"]:
		if c["reason"] == "learned":
			learned_first.append(str(c["strain_key"]))
	var saw_level_up: bool = false
	for c: Dictionary in second["memory_changes"]:
		if learned_first.has(str(c["strain_key"])) and int(c["from"]) >= 1:
			saw_level_up = true
	assert_true(saw_level_up, "raid 2 builds on what raid 1 taught the base")
	var ref := ImmuneMemory.from_dict(p.memory, _cfg)
	assert_eq(ref.raids, 2)


func test_pools_breed_with_coevolution_and_stay_split() -> void:
	_cfg.feature_flags["coevolution"] = true
	var p: LivingBaseProfile = _strong()
	DefenseRunner.resolve_offline(_cfg, p, 0)
	assert_true(p.ai_army_populations.has("rhinovirus"), "the AI army's pools are kept apart")
	assert_true(p.populations.has("macrophage"))
	assert_false(p.populations.has("rhinovirus"))
	assert_false(p.ai_army_populations.has("macrophage"))


func test_the_battle_dict_replays() -> void:
	var p: LivingBaseProfile = _undefended()
	var entry: Dictionary = DefenseRunner.resolve_offline(_cfg, p, 0)
	var res: Dictionary = Replay.verify(SnapshotIO.to_json(entry["battle"]), _cfg)
	assert_true(bool(res.get("ok", false)), str(res))
	assert_true(bool(res.get("match", res.get("ok", false))), str(res))


func test_perf_of_one_offline_raid() -> void:
	var p: LivingBaseProfile = _strong()
	var start: int = Time.get_ticks_msec()
	DefenseRunner.resolve_offline(_cfg, p, 0)
	var ms: int = Time.get_ticks_msec() - start
	gut.p("offline raid took %d ms" % ms)
	assert_lt(ms, 20000)
