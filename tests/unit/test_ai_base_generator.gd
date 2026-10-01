extends GutTest

## AiBaseGenerator (#160): seeded, valid, tiered AI bases.

var _cfg: GameConfig = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config


func _tier_ids() -> Array[String]:
	var ids: Array[String] = []
	for t: Dictionary in _cfg.ai_tiers:
		ids.append(str(t["id"]))
	return ids


func _count(layout: Array, type_id: String) -> int:
	var n: int = 0
	for e: Variant in layout:
		if str((e as Dictionary)["type"]) == type_id:
			n += 1
	return n


func test_config_block_loaded() -> void:
	assert_eq(_cfg.ai_opponents_shown, 3)
	assert_eq(_cfg.ai_tower_weights, {"macrophage": 50, "b_cell": 50})
	assert_eq(_tier_ids(), ["cold", "flu", "pneumonia"] as Array[String])
	assert_eq(_cfg.ai_tiers[1]["budget_atp"], 800)
	assert_eq(_cfg.ai_tiers[2]["dendritic"], 1)


func test_same_seed_same_layout_and_other_seed_differs() -> void:
	var a: Dictionary = AiBaseGenerator.generate(_cfg, "flu", 7)
	var b: Dictionary = AiBaseGenerator.generate(_cfg, "flu", 7)
	assert_eq(a, b)
	var c: Dictionary = AiBaseGenerator.generate(_cfg, "flu", 8)
	assert_ne(a["layout"], c["layout"])
	assert_eq(a["tier"], "flu")


func test_unknown_tier_gives_an_empty_result() -> void:
	var res: Dictionary = AiBaseGenerator.generate(_cfg, "nope", 1)
	assert_eq((res["layout"] as Array).size(), 0)
	assert_eq(res["spent"], 0)


func test_layouts_are_valid_for_every_tier_and_seed() -> void:
	for tier_id: String in _tier_ids():
		var budget: int = 0
		for t: Dictionary in _cfg.ai_tiers:
			if t["id"] == tier_id:
				budget = int(t["budget_atp"])
		for seed: int in range(1, 21):
			var res: Dictionary = AiBaseGenerator.generate(_cfg, tier_id, seed)
			var layout: Array = res["layout"]
			var grid := GridModel.new(_cfg)
			assert_eq(grid.load_layout(layout, LivingBaseProfile.unlimited_wallet()), GridModel.PlaceError.OK, "%s %d" % [tier_id, seed])
			assert_eq(_count(layout, "nucleus"), 1)
			assert_lte(int(res["spent"]), budget, "%s %d" % [tier_id, seed])
			assert_gt(_count(layout, "macrophage") + _count(layout, "b_cell"), 0, "has towers")


func test_nothing_overlaps_the_deploy_ring() -> void:
	var grid := GridModel.new(_cfg)
	for tier_id: String in _tier_ids():
		for seed: int in range(1, 6):
			var layout: Array = AiBaseGenerator.generate(_cfg, tier_id, seed)["layout"]
			assert_eq(grid.load_layout(layout, LivingBaseProfile.unlimited_wallet()), GridModel.PlaceError.OK)
			for s: GridModel.PlacedStructure in grid.structures():
				for c: Vector2i in s.cells():
					assert_false(grid.is_deploy_zone(c), "%s %d %s" % [tier_id, seed, s.type_id])


func test_mitochondria_only_with_living_base_on() -> void:
	var off: Array = AiBaseGenerator.generate(_cfg, "flu", 3)["layout"]
	assert_eq(_count(off, "mitochondria"), 0)
	_cfg.feature_flags["living_base"] = true
	assert_eq(_count(AiBaseGenerator.generate(_cfg, "cold", 3)["layout"], "mitochondria"), 1)
	assert_eq(_count(AiBaseGenerator.generate(_cfg, "flu", 3)["layout"], "mitochondria"), 2)
	assert_eq(_count(AiBaseGenerator.generate(_cfg, "pneumonia", 3)["layout"], "dendritic_cell"), 0, "no Dendritic Cell with its flag off")
	_cfg.feature_flags["dendritic_cell"] = true
	assert_eq(_count(AiBaseGenerator.generate(_cfg, "pneumonia", 3)["layout"], "dendritic_cell"), 1)
	assert_eq(_count(AiBaseGenerator.generate(_cfg, "flu", 3)["layout"], "dendritic_cell"), 0)


func test_tower_weights_pick_the_towers() -> void:
	_cfg.ai_tower_weights = {"b_cell": 1}
	for seed: int in range(1, 6):
		var layout: Array = AiBaseGenerator.generate(_cfg, "flu", seed)["layout"]
		assert_eq(_count(layout, "macrophage"), 0)
		assert_gt(_count(layout, "b_cell"), 0)


func test_every_base_has_a_path_from_the_ring_to_the_nucleus() -> void:
	for tier_id: String in _tier_ids():
		for seed: int in range(1, 6):
			var layout: Array = AiBaseGenerator.generate(_cfg, tier_id, seed)["layout"]
			var grid := GridModel.new(_cfg)
			grid.load_layout(layout, LivingBaseProfile.unlimited_wallet())
			var ps := PathService.new(grid.width, grid.height, _cfg.empty_path_weight, 10)
			for s: GridModel.PlacedStructure in grid.structures():
				var def: StructureDef = _cfg.structures[s.type_id]
				for c: Vector2i in s.cells():
					ps.set_cell_weight(c, def.path_weight)
			var core: GridModel.PlacedStructure = grid.find_core()
			var goal: Vector2i = core.origin
			var start: Vector2i = grid.ring_cells()[0]
			assert_gt(ps.find_path(start, goal).size(), 1, "%s %d" % [tier_id, seed])


func test_walls_come_after_towers_within_the_budget() -> void:
	var res: Dictionary = AiBaseGenerator.generate(_cfg, "cold", 11)
	var layout: Array = res["layout"]
	var walls: int = _count(layout, "mucous_wall")
	assert_gt(walls, 0)
	var spent: int = walls * 5 + _count(layout, "macrophage") * 100 + _count(layout, "b_cell") * 150
	assert_eq(int(res["spent"]), spent)


# --- ai_bases validation ---

func _load_rules(mutate: Callable) -> ConfigLoadResult:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_rules.json"))
	mutate.call(rules)
	return GameConfig.load_from_strings(JSON.stringify(rules),
		FileAccess.get_file_as_string("res://data/structures.json"),
		FileAccess.get_file_as_string("res://data/pathogens.json"))


func _has_error(res: ConfigLoadResult, fragment: String) -> bool:
	for e: String in res.errors:
		if e.find(fragment) != -1:
			return true
	return false


func test_validation_errors() -> void:
	var r1: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["opponents_shown"] = 4)
	assert_true(_has_error(r1, "game_rules.json: ai_bases.opponents_shown: must be <= 3 (got 4)"))
	var r2: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["opponents_shown"] = 0)
	assert_true(_has_error(r2, "game_rules.json: ai_bases.opponents_shown: must be >= 1 (got 0)"))
	var r3: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tower_weights"]["mucous_wall"] = 5)
	assert_true(_has_error(r3, "game_rules.json: ai_bases.tower_weights.mucous_wall: must be a buildable structure with an attack"))
	var r4: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tower_weights"]["b_cell"] = 0)
	assert_true(_has_error(r4, "game_rules.json: ai_bases.tower_weights.b_cell: must be > 0 (got 0)"))
	var r5: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tiers"][1]["id"] = "cold")
	assert_true(_has_error(r5, "ai_bases.tiers[1].id: must be unique (got cold)"))
	var r6: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tiers"][0]["budget_atp"] = 0)
	assert_true(_has_error(r6, "ai_bases.tiers[0].budget_atp: must be >= 1 (got 0)"))
	var r7: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tiers"][0]["wall_pct"] = 91)
	assert_true(_has_error(r7, "ai_bases.tiers[0].wall_pct: must be <= 90 (got 91)"))
	var r8: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tiers"][0]["bogus"] = 1)
	assert_true(_has_error(r8, "ai_bases.tiers[0].bogus: unknown key (got bogus)"))
	var r9: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tiers"][0].erase("stored_atp"))
	assert_true(_has_error(r9, "ai_bases.tiers[0].stored_atp: missing required field (got null)"))
	var r10: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tiers"][0]["display_name"] = "")
	assert_true(_has_error(r10, "ai_bases.tiers[0].display_name: must be a non-empty string"))
	var r11: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d["ai_bases"]["tiers"][0]["mitochondria"] = -1)
	assert_true(_has_error(r11, "ai_bases.tiers[0].mitochondria: must be >= 0 (got -1)"))


func test_block_required_only_when_living_base_is_on() -> void:
	var r1: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void: d.erase("ai_bases"))
	assert_true(r1.is_ok())
	var r2: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void:
		d.erase("ai_bases")
		d["feature_flags"]["living_base"] = true)
	assert_true(_has_error(r2, "game_rules.json: ai_bases: required when feature_flags.living_base is true"))
