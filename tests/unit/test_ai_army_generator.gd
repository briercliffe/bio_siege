extends GutTest

var _cfg: GameConfig = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true


func _base_layout(seed: int = 3) -> Array:
	return AiBaseGenerator.generate(_cfg, "flu", seed)["layout"]


func _budget_for(layout: Array) -> int:
	return maxi(_cfg.ai_min_army_atp, RaidScore.base_value(_cfg, layout) * _cfg.ai_army_budget_pct / 100)


func test_same_seed_same_army() -> void:
	var layout: Array = _base_layout()
	assert_eq(AiArmyGenerator.generate(_cfg, layout, 5), AiArmyGenerator.generate(_cfg, layout, 5))
	assert_ne(AiArmyGenerator.generate(_cfg, layout, 5)["units"], AiArmyGenerator.generate(_cfg, layout, 6)["units"])


func test_spend_stays_within_the_budget_and_the_floor_applies() -> void:
	var layout: Array = _base_layout()
	var res: Dictionary = AiArmyGenerator.generate(_cfg, layout, 9)
	assert_lte(int(res["spent"]), _budget_for(layout))
	assert_gt(int(res["spent"]), _budget_for(layout) - 40, "the budget is nearly used up")
	var total: int = 0
	for u: Dictionary in res["units"]:
		total += int(_cfg.pathogens[str(u["type"])].cost["atp"])
	assert_eq(total, int(res["spent"]))
	var empty_res: Dictionary = AiArmyGenerator.generate(_cfg, [], 9)
	assert_lte(int(empty_res["spent"]), _cfg.ai_min_army_atp)
	assert_gt(int(empty_res["spent"]), _cfg.ai_min_army_atp - 40, "min_army_atp is the floor")


func test_cells_are_deploy_ring_cells_on_one_side() -> void:
	var grid := GridModel.new(_cfg)
	var ring: Array[Vector2i] = grid.ring_cells()
	for seed: int in range(1, 9):
		var units: Array = AiArmyGenerator.generate(_cfg, _base_layout(), seed)["units"]
		assert_gt(units.size(), 0)
		var sides: Dictionary = {}
		for u: Dictionary in units:
			var c := Vector2i(int(u["cell"][0]), int(u["cell"][1]))
			assert_true(ring.has(c), "%s is on the ring" % c)
			var d: Array[int] = [c.y, grid.width - 1 - c.x, grid.height - 1 - c.y, c.x]
			sides[d.find(d.min())] = true
		assert_eq(sides.size(), 1, "one side per army")


func test_strains_off_are_all_wild_and_on_are_one_variant_per_type() -> void:
	var layout: Array = _base_layout()
	for u: Dictionary in AiArmyGenerator.generate(_cfg, layout, 4)["units"]:
		assert_eq(u["strain"], "wild")
	_cfg.feature_flags["strains"] = true
	var seen_variant: bool = false
	for seed: int in range(1, 12):
		var by_type: Dictionary = {}
		for u: Dictionary in AiArmyGenerator.generate(_cfg, layout, seed)["units"]:
			var t: String = str(u["type"])
			assert_true((_cfg.pathogens[t] as PathogenDef).strain_ids().has(str(u["strain"])))
			if by_type.has(t):
				assert_eq(by_type[t], u["strain"], "consistent within a type")
			by_type[t] = u["strain"]
			seen_variant = seen_variant or u["strain"] != "wild"
	assert_true(seen_variant, "some seed picks a variant")


func test_the_army_builds_a_valid_battle_setup_against_an_ai_base() -> void:
	_cfg.feature_flags["strains"] = true
	for seed: int in range(1, 6):
		var layout: Array = _base_layout(seed)
		var army: Dictionary = AiArmyGenerator.generate(_cfg, layout, seed)
		var setup: BattleSetup = BattleSetup.create(layout, army["units"], seed)
		assert_eq(setup.validate(_cfg).size(), 0, str(setup.validate(_cfg)))
