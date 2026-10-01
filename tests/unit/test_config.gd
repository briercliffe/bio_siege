extends GutTest

var default_rules_str: String = ""
var default_structures_str: String = ""
var default_pathogens_str: String = ""

func before_all() -> void:
	default_rules_str = FileAccess.get_file_as_string("res://data/game_rules.json")
	default_structures_str = FileAccess.get_file_as_string("res://data/structures.json")
	default_pathogens_str = FileAccess.get_file_as_string("res://data/pathogens.json")

func _contains_error(errors: PackedStringArray, expected_substring: String) -> bool:
	for err: String in errors:
		if err.find(expected_substring) != -1:
			return true
	return false

# -----------------------------------------------------------------------------
# 1. Valid loading tests
# -----------------------------------------------------------------------------

func test_load_from_dir_success() -> void:
	var result: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(result.is_ok(), "Expected is_ok() to be true")
	assert_false(result.is_err(), "Expected is_err() to be false")
	assert_eq(result.errors.size(), 0, "Expected 0 errors")
	assert_not_null(result.config, "Expected config to be populated")

func test_content_hash() -> void:
	var result: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_not_null(result.config)
	var expected_hash: String = (default_rules_str + default_structures_str + default_pathogens_str).sha256_text()
	assert_eq(result.config.content_hash, expected_hash, "Content hash must match sha256 of 3 raw files")

func test_rules_values() -> void:
	var result: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	var cfg: GameConfig = result.config
	assert_not_null(cfg)
	assert_eq(cfg.grid_width, 40)
	assert_eq(cfg.grid_height, 40)
	assert_eq(cfg.deploy_ring, 2)
	assert_eq(cfg.tile_px, 14)
	assert_eq(cfg.grid_scale, 2)
	assert_eq(cfg.tick_rate, 20)
	assert_eq(cfg.battle_timeout_ticks, 3600) # 180s * 20 ticks
	assert_eq(cfg.max_path_recalcs_per_tick, 20)
	assert_eq(cfg.empty_path_weight, 1.0)
	assert_eq(cfg.deploy_hold_interval_s, 0.1)
	assert_eq(cfg.start_wallet.get("atp", 0), 1000)
	assert_eq(cfg.default_seed, 12345)
	assert_eq(cfg.feature_flags.get("move_nucleus"), false)
	assert_eq(cfg.feature_flags.get("intent_lines_default"), true)

func test_query_methods() -> void:
	var result: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	var cfg: GameConfig = result.config
	assert_not_null(cfg)

	# structure_ids alphabetical
	var s_ids: Array[String] = cfg.structure_ids()
	assert_eq(s_ids, ["b_cell", "macrophage", "mucous_wall", "nucleus"])

	# pathogen_ids alphabetical
	var p_ids: Array[String] = cfg.pathogen_ids()
	assert_eq(p_ids, ["bacteriophage", "rhinovirus", "staphylococcus"])

	# buildable_structure_ids sorted by cost ascending, then id
	var b_ids: Array[String] = cfg.buildable_structure_ids()
	assert_eq(b_ids, ["mucous_wall", "macrophage", "b_cell"])

	# core_structure_id
	assert_eq(cfg.core_structure_id(), "nucleus")

func test_structure_stats() -> void:
	var result: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	var cfg: GameConfig = result.config
	assert_not_null(cfg)

	var n: StructureDef = cfg.structures.get("nucleus")
	assert_not_null(n)
	assert_eq(n.display_name, "Nucleus")
	assert_eq(n.role, "HQ: destroy it to win")
	assert_eq(n.cost.get("atp", 0), 0)
	assert_eq(n.hp, 2000)
	assert_eq(n.footprint, Vector2i(4, 4))
	assert_eq(n.buildable, false)
	assert_eq(n.is_targetable, true)
	assert_eq(n.visible_to_attacker, true)
	assert_eq(n.path_weight, 20.0)
	assert_true(n.has_tag("core"))
	assert_false(n.has_attack)
	assert_eq(n.placeholder_shape, "rounded_square")

	var w: StructureDef = cfg.structures.get("mucous_wall")
	assert_not_null(w)
	assert_eq(w.hp, 300)
	assert_eq(w.cost.get("atp", 0), 5)
	assert_eq(w.footprint, Vector2i(1, 1))
	assert_eq(w.buildable, true)
	assert_eq(w.is_targetable, false)
	assert_eq(w.visible_to_attacker, true)
	assert_eq(w.path_weight, 10.0)
	assert_true(w.has_tag("wall"))
	assert_false(w.has_attack)

	var m: StructureDef = cfg.structures.get("macrophage")
	assert_not_null(m)
	assert_eq(m.hp, 500)
	assert_eq(m.cost.get("atp", 0), 100)
	assert_eq(m.footprint, Vector2i(3, 3))
	assert_eq(m.buildable, true)
	assert_eq(m.is_targetable, true)
	assert_true(m.has_tag("defense"))
	assert_true(m.has_attack)
	assert_eq(m.attack_damage, 40)
	assert_eq(m.attack_interval_ticks, 20) # 1.0s * 20
	assert_eq(m.attack_range_mt, 4000) # 2.0 * 2 (grid_scale) * 1000
	assert_eq(m.splash_radius_mt, 2000) # 1.0 * 2 * 1000
	assert_eq(m.projectile_speed_mt_per_tick, 0)

	var b: StructureDef = cfg.structures.get("b_cell")
	assert_not_null(b)
	assert_eq(b.hp, 250)
	assert_eq(b.cost.get("atp", 0), 150)
	assert_eq(b.footprint, Vector2i(3, 3))
	assert_eq(b.buildable, true)
	assert_eq(b.is_targetable, true)
	assert_true(b.has_tag("defense"))
	assert_true(b.has_attack)
	assert_eq(b.attack_damage, 75)
	assert_eq(b.attack_interval_ticks, 24) # 1.2s * 20
	assert_eq(b.attack_range_mt, 12000) # 6.0 * 2 * 1000
	assert_eq(b.splash_radius_mt, 0)
	assert_eq(b.projectile_speed_mt_per_tick, 1000) # 10.0 * 2 * 1000 / 20

func test_pathogen_stats() -> void:
	var result: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	var cfg: GameConfig = result.config
	assert_not_null(cfg)

	var r: PathogenDef = cfg.pathogens.get("rhinovirus")
	assert_not_null(r)
	assert_eq(r.display_name, "Rhinovirus")
	assert_eq(r.role, "Fast swarm")
	assert_eq(r.cost.get("atp", 0), 10)
	assert_eq(r.hp, 30)
	assert_eq(r.speed_mt_per_tick, 140) # 1.4 * 2 * 1000 / 20
	assert_eq(r.attack_damage, 6)
	assert_eq(r.attack_interval_ticks, 10) # 0.5s * 20
	assert_eq(r.attack_range_mt, 2000)
	assert_true(r.has_tag("virus"))
	assert_true(r.has_tag("small"))

	var p: PathogenDef = cfg.pathogens.get("bacteriophage")
	assert_not_null(p)
	assert_eq(p.hp, 80)
	assert_eq(p.cost.get("atp", 0), 40)
	assert_eq(p.speed_mt_per_tick, 115) # 1.15 * 2 * 1000 / 20
	assert_eq(p.attack_damage, 20)
	assert_eq(p.attack_interval_ticks, 20) # 1.0s * 20
	assert_eq(p.attack_range_mt, 2000)
	assert_eq(p.damage_multipliers_pct.get("defense", 0), 300) # 3.0 * 100
	assert_eq(p.priority_tags, PackedStringArray(["defense"]))

	var s: PathogenDef = cfg.pathogens.get("staphylococcus")
	assert_not_null(s)
	assert_eq(s.hp, 600)
	assert_eq(s.cost.get("atp", 0), 100)
	assert_eq(s.speed_mt_per_tick, 75) # 0.75 * 2 * 1000 / 20
	assert_eq(s.attack_damage, 25)
	assert_eq(s.attack_interval_ticks, 30) # 1.5s * 20
	assert_eq(s.attack_range_mt, 2000)
	assert_true(s.has_tag("bacteria"))

# -----------------------------------------------------------------------------
# 2. Fixed-point conversion edge cases
# -----------------------------------------------------------------------------

func test_fixed_point_scaling() -> void:
	var rules_dict: Dictionary = JSON.parse_string(default_rules_str)
	rules_dict["grid_scale"] = 2
	rules_dict["tick_rate"] = 10
	rules_dict["battle_timeout_s"] = 100
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(rules_dict), default_structures_str, default_pathogens_str
	)
	assert_true(res.is_ok())
	var cfg: GameConfig = res.config

	# timeout: 100s * 10 = 1000 ticks
	assert_eq(cfg.battle_timeout_ticks, 1000)

	# b_cell range: 6.0 * 2 * 1000 = 12000 mt
	var b: StructureDef = cfg.structures.get("b_cell")
	assert_eq(b.attack_range_mt, 12000)
	# b_cell interval: 1.2 * 10 = 12 ticks
	assert_eq(b.attack_interval_ticks, 12)
	# b_cell projectile speed: 10.0 * 2 * 1000 / 10 = 2000 mt/tick
	assert_eq(b.projectile_speed_mt_per_tick, 2000)
	# footprint should NOT be scaled
	assert_eq(b.footprint, Vector2i(3, 3))

	# rhinovirus speed: 1.4 * 2 * 1000 / 10 = 280 mt/tick
	var r: PathogenDef = cfg.pathogens.get("rhinovirus")
	assert_eq(r.speed_mt_per_tick, 280)

func test_attack_interval_minimum_one_tick() -> void:
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	structs_dict["b_cell"]["attack"]["interval_s"] = 0.001
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(structs_dict), default_pathogens_str
	)
	assert_true(res.is_ok())
	var b: StructureDef = res.config.structures.get("b_cell")
	assert_eq(b.attack_interval_ticks, 1, "Attack interval minimum must be 1 tick")

# -----------------------------------------------------------------------------
# 3. Validation tests
# -----------------------------------------------------------------------------

func test_json_parse_error() -> void:
	var bad_json: String = '{\n  "version": 1,\n  "grid": {\n}'
	var res: ConfigLoadResult = GameConfig.load_from_strings(bad_json, default_structures_str, default_pathogens_str)
	assert_true(res.is_err())
	assert_null(res.config)
	assert_true(_contains_error(res.errors, "game_rules.json: JSON parse error at line"))

func test_unknown_keys_rejected() -> void:
	var rules_dict: Dictionary = JSON.parse_string(default_rules_str)
	rules_dict["unknown_rule_key"] = "test"
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(rules_dict), default_structures_str, default_pathogens_str
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "game_rules.json: unknown_rule_key: unknown key (got unknown_rule_key)"))

func test_underscore_keys_ignored() -> void:
	var rules_dict: Dictionary = JSON.parse_string(default_rules_str)
	rules_dict["_comment"] = "This is a comment"
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	structs_dict["nucleus"]["_note"] = "Ignored note"
	var paths_dict: Dictionary = JSON.parse_string(default_pathogens_str)
	paths_dict["rhinovirus"]["_meta"] = {"author": "designer"}

	var res: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(rules_dict), JSON.stringify(structs_dict), JSON.stringify(paths_dict)
	)
	assert_true(res.is_ok(), "Keys starting with '_' should be ignored")

func test_missing_required_keys() -> void:
	var rules_dict: Dictionary = JSON.parse_string(default_rules_str)
	rules_dict.erase("tick_rate")
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(rules_dict), default_structures_str, default_pathogens_str
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "game_rules.json: tick_rate: missing required field (got null)"))

func test_integer_fields_must_be_whole_numbers() -> void:
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	structs_dict["macrophage"]["hp"] = 500.5
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(structs_dict), default_pathogens_str
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "structures.json: macrophage.hp: must be an integer > 0 (got 500.5)"))

func test_negative_or_zero_constraints() -> void:
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	structs_dict["b_cell"]["attack"]["range_tiles"] = -1
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(structs_dict), default_pathogens_str
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "structures.json: b_cell.attack.range_tiles: must be > 0 (got -1)"))

func test_unknown_tag() -> void:
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	structs_dict["macrophage"]["tags"] = ["alien_species"]
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(structs_dict), default_pathogens_str
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "structures.json: macrophage.tags: unknown tag (got alien_species)"))

func test_unknown_currency() -> void:
	var paths_dict: Dictionary = JSON.parse_string(default_pathogens_str)
	paths_dict["rhinovirus"]["cost"] = {"gold": 100}
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, default_structures_str, JSON.stringify(paths_dict)
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "pathogens.json: rhinovirus.cost.gold: unknown currency (got gold)"))

func test_unknown_shape() -> void:
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	structs_dict["nucleus"]["placeholder"]["shape"] = "pentagon"
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(structs_dict), default_pathogens_str
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "structures.json: nucleus.placeholder.shape: unknown shape (got pentagon)"))

func test_invalid_color_hex() -> void:
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	structs_dict["nucleus"]["placeholder"]["color"] = "not_a_color"
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(structs_dict), default_pathogens_str
	)
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "structures.json: nucleus.placeholder.color: invalid color hex (got not_a_color)"))

func test_core_structure_validation() -> void:
	# Case 1: No core structure
	var s_no_core: Dictionary = JSON.parse_string(default_structures_str)
	s_no_core["nucleus"]["tags"] = ["defense"]
	var res1: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s_no_core), default_pathogens_str
	)
	assert_true(res1.is_err())
	assert_true(_contains_error(res1.errors, "structures.json: structures: must contain exactly one core structure (got 0)"))

	# Case 2: Multiple core structures
	var s_two_cores: Dictionary = JSON.parse_string(default_structures_str)
	s_two_cores["mucous_wall"]["tags"] = ["core"]
	s_two_cores["mucous_wall"]["buildable"] = false
	var res2: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s_two_cores), default_pathogens_str
	)
	assert_true(res2.is_err())
	assert_true(_contains_error(res2.errors, "structures.json: structures: must contain exactly one core structure (got 2)"))

	# Case 3: Core structure is buildable
	var s_buildable_core: Dictionary = JSON.parse_string(default_structures_str)
	s_buildable_core["nucleus"]["buildable"] = true
	var res3: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s_buildable_core), default_pathogens_str
	)
	assert_true(res3.is_err())
	assert_true(_contains_error(res3.errors, "structures.json: nucleus.buildable: core structure must not be buildable (got true)"))

func test_levels_array_of_dicts() -> void:
	# Case 1: levels is not an array
	var s_not_arr: Dictionary = JSON.parse_string(default_structures_str)
	s_not_arr["nucleus"]["levels"] = "invalid"
	var res1: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s_not_arr), default_pathogens_str
	)
	assert_true(res1.is_err())
	assert_true(_contains_error(res1.errors, "structures.json: nucleus.levels: must be an array"))

	# Case 2: levels contains non-dictionary
	var s_bad_item: Dictionary = JSON.parse_string(default_structures_str)
	s_bad_item["nucleus"]["levels"] = [123]
	var res2: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s_bad_item), default_pathogens_str
	)
	assert_true(res2.is_err())
	assert_true(_contains_error(res2.errors, "structures.json: nucleus.levels[0]: must be a JSON object (got 123)"))

	# Case 3: valid levels
	var s_valid_lvls: Dictionary = JSON.parse_string(default_structures_str)
	s_valid_lvls["macrophage"]["levels"] = [{"level": 2, "hp": 600}]
	var res3: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s_valid_lvls), default_pathogens_str
	)
	assert_true(res3.is_ok())
	var mac: StructureDef = res3.config.structures.get("macrophage")
	assert_eq(mac.levels.size(), 1)
	assert_eq(int(mac.levels[0].get("hp")), 600)

func test_collect_all_errors() -> void:
	var s_multi: Dictionary = JSON.parse_string(default_structures_str)
	s_multi["macrophage"]["hp"] = -10
	s_multi["b_cell"]["hp"] = -20
	var p_multi: Dictionary = JSON.parse_string(default_pathogens_str)
	p_multi["rhinovirus"]["hp"] = -5
	var res: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s_multi), JSON.stringify(p_multi)
	)
	assert_true(res.is_err())
	assert_gt(res.errors.size(), 2, "Should collect all errors across files and entities")
	assert_true(_contains_error(res.errors, "macrophage.hp"))
	assert_true(_contains_error(res.errors, "b_cell.hp"))
	assert_true(_contains_error(res.errors, "rhinovirus.hp"))

# -----------------------------------------------------------------------------
# 4. GameData autoload tests
# -----------------------------------------------------------------------------

func test_game_data_autoload() -> void:
	assert_not_null(GameData, "GameData autoload must exist")
	assert_not_null(GameData.config, "GameData.config must be loaded")
	assert_eq(GameData.load_errors.size(), 0, "GameData.load_errors should be empty")
	assert_eq(GameData.config.structure_ids().size(), 4)
	assert_eq(GameData.config.pathogen_ids().size(), 3)

# -----------------------------------------------------------------------------
# 5. Main UI tests
# -----------------------------------------------------------------------------

func test_main_ui_normal_and_error() -> void:
	var main_scene: PackedScene = load("res://src/main.tscn")
	assert_not_null(main_scene)
	var main_node: Node = main_scene.instantiate()
	add_child_autofree(main_node)

	var normal_ui: Control = main_node.get_node("NormalUI")
	var error_panel: DataErrorScreen = main_node.get_node("DataErrorScreen")

	# Initial state with valid GameData
	assert_true(normal_ui.visible, "Normal UI should be visible when config is valid")
	assert_false(error_panel.visible, "Error panel should be hidden when config is valid")

	# Simulate error
	GameData.load_errors = PackedStringArray(["structures.json: test.hp: must be > 0 (got -1)"])
	main_node.check_config_errors()

	assert_false(normal_ui.visible, "Normal UI should be hidden on config error")
	assert_true(error_panel.visible, "Error panel should be visible on config error")
	assert_eq(error_panel.chips.size(), 1)
	assert_eq(error_panel.chips[0].text, "structures.json · test")

	# Restore GameData
	GameData.load_errors = PackedStringArray()
	main_node.check_config_errors()
	assert_true(normal_ui.visible)
	assert_false(error_panel.visible)

# -----------------------------------------------------------------------------
# 6. Additional edge case tests
# -----------------------------------------------------------------------------

func test_load_from_dir_missing_dir() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://non_existent_dir")
	assert_true(res.is_err())
	assert_true(_contains_error(res.errors, "game_rules.json: file not found"))
	assert_true(_contains_error(res.errors, "structures.json: file not found"))
	assert_true(_contains_error(res.errors, "pathogens.json: file not found"))

func test_rules_validation_edge_cases() -> void:
	# deploy ring too large
	var r1: Dictionary = JSON.parse_string(default_rules_str)
	r1["grid"]["deploy_ring"] = 25
	var res1: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(r1), default_structures_str, default_pathogens_str
	)
	assert_true(res1.is_err())
	assert_true(_contains_error(res1.errors, "grid.deploy_ring: deploy ring too large for grid (got 25)"))

	# grid_scale <= 0
	var r2: Dictionary = JSON.parse_string(default_rules_str)
	r2["grid_scale"] = 0
	var res2: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(r2), default_structures_str, default_pathogens_str
	)
	assert_true(res2.is_err())
	assert_true(_contains_error(res2.errors, "grid_scale: must be > 0 (got 0)"))

	# empty start_wallet
	var r3: Dictionary = JSON.parse_string(default_rules_str)
	r3["start_wallet"] = {}
	var res3: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(r3), default_structures_str, default_pathogens_str
	)
	assert_true(res3.is_err())
	assert_true(_contains_error(res3.errors, "start_wallet: cannot be empty (got empty)"))

	# negative start_wallet
	var r4: Dictionary = JSON.parse_string(default_rules_str)
	r4["start_wallet"]["atp"] = -100
	var res4: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(r4), default_structures_str, default_pathogens_str
	)
	assert_true(res4.is_err())
	assert_true(_contains_error(res4.errors, "start_wallet.atp: must be >= 0 (got -100)"))

	# non-bool feature_flags
	var r5: Dictionary = JSON.parse_string(default_rules_str)
	r5["feature_flags"]["move_nucleus"] = "false"
	var res5: ConfigLoadResult = GameConfig.load_from_strings(
		JSON.stringify(r5), default_structures_str, default_pathogens_str
	)
	assert_true(res5.is_err())
	assert_true(_contains_error(res5.errors, "feature_flags.move_nucleus: must be a boolean (got false)"))

func test_damage_multipliers_validation() -> void:
	# unknown tag in damage_multipliers
	var s1: Dictionary = JSON.parse_string(default_structures_str)
	s1["macrophage"]["damage_multipliers"]["unknown_tag"] = 2.0
	var res1: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s1), default_pathogens_str
	)
	assert_true(res1.is_err())
	assert_true(_contains_error(res1.errors, "damage_multipliers.unknown_tag: unknown tag (got unknown_tag)"))

	# non-positive multiplier
	var s2: Dictionary = JSON.parse_string(default_structures_str)
	s2["macrophage"]["damage_multipliers"]["virus"] = 0
	var res2: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s2), default_pathogens_str
	)
	assert_true(res2.is_err())
	assert_true(_contains_error(res2.errors, "damage_multipliers.virus: must be > 0 (got 0)"))

func test_attack_validation_edge_cases() -> void:
	# unknown key in attack
	var s1: Dictionary = JSON.parse_string(default_structures_str)
	s1["macrophage"]["attack"]["extra_field"] = 123
	var res1: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s1), default_pathogens_str
	)
	assert_true(res1.is_err())
	assert_true(_contains_error(res1.errors, "attack.extra_field: unknown key (got extra_field)"))

	# negative splash radius
	var s2: Dictionary = JSON.parse_string(default_structures_str)
	s2["macrophage"]["attack"]["splash_radius_tiles"] = -0.5
	var res2: ConfigLoadResult = GameConfig.load_from_strings(
		default_rules_str, JSON.stringify(s2), default_pathogens_str
	)
	assert_true(res2.is_err())
	assert_true(_contains_error(res2.errors, "attack.splash_radius_tiles: must be >= 0 (got -0.5)"))

func test_empty_entity_dictionaries() -> void:
	var res1: ConfigLoadResult = GameConfig.load_from_strings(default_rules_str, "{}", default_pathogens_str)
	assert_true(res1.is_err())
	assert_true(_contains_error(res1.errors, "structures.json: root: structures cannot be empty (got empty)"))

	var res2: ConfigLoadResult = GameConfig.load_from_strings(default_rules_str, default_structures_str, "{}")
	assert_true(res2.is_err())
	assert_true(_contains_error(res2.errors, "pathogens.json: root: pathogens cannot be empty (got empty)"))


# -----------------------------------------------------------------------------
# B-Cell analysis block (#87)
# -----------------------------------------------------------------------------

func _load_with_analysis(mutate: Callable) -> ConfigLoadResult:
	var structs_dict: Dictionary = JSON.parse_string(default_structures_str)
	mutate.call(structs_dict)
	return GameConfig.load_from_strings(default_rules_str, JSON.stringify(structs_dict), default_pathogens_str)

func test_analysis_default_data() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var bc: StructureDef = cfg.structures["b_cell"]
	assert_true(bc.has_analysis)
	assert_eq(bc.analysis_threshold_ticks, roundi(10.0 * cfg.tick_rate))
	assert_eq(bc.analysis_multiplier_pct, 300)
	assert_false((cfg.structures["macrophage"] as StructureDef).has_analysis)
	assert_false(cfg.flag("bcell_analysis"))

func test_analysis_key_optional() -> void:
	var res: ConfigLoadResult = _load_with_analysis(func(d: Dictionary) -> void: d["b_cell"].erase("analysis"))
	assert_true(res.is_ok())
	assert_false((res.config.structures["b_cell"] as StructureDef).has_analysis)

func test_analysis_validation_errors() -> void:
	var r1: ConfigLoadResult = _load_with_analysis(func(d: Dictionary) -> void: d["b_cell"]["analysis"]["exposure_s"] = 0)
	assert_true(_contains_error(r1.errors, "structures.json: b_cell.analysis.exposure_s: must be > 0 (got 0)"))
	var r2: ConfigLoadResult = _load_with_analysis(func(d: Dictionary) -> void: d["b_cell"]["analysis"]["damage_multiplier"] = 0.5)
	assert_true(_contains_error(r2.errors, "structures.json: b_cell.analysis.damage_multiplier: must be >= 1 (got 0.5)"))
	var r3: ConfigLoadResult = _load_with_analysis(func(d: Dictionary) -> void: d["b_cell"]["analysis"]["bogus"] = 1)
	assert_true(_contains_error(r3.errors, "structures.json: b_cell.analysis.bogus: unknown key"))
	var r4: ConfigLoadResult = _load_with_analysis(func(d: Dictionary) -> void: d["nucleus"]["analysis"] = {"exposure_s": 10.0, "damage_multiplier": 3.0})
	assert_true(_contains_error(r4.errors, "structures.json: nucleus.analysis: only allowed on structures with an attack"))


# -----------------------------------------------------------------------------
# Biofilm block (#91)
# -----------------------------------------------------------------------------

func _load_with_biofilm(mutate: Callable) -> ConfigLoadResult:
	var p_dict: Dictionary = JSON.parse_string(default_pathogens_str)
	mutate.call(p_dict)
	return GameConfig.load_from_strings(default_rules_str, default_structures_str, JSON.stringify(p_dict))

func test_biofilm_default_data() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var staph: PathogenDef = cfg.pathogens["staphylococcus"]
	assert_true(staph.has_biofilm)
	assert_eq(staph.biofilm_damage_taken_pct, 75)
	assert_eq(staph.biofilm_regroup_ticks, roundi(0.5 * cfg.tick_rate))
	assert_eq(staph.biofilm_link_mt, roundi(1.5 * cfg.grid_scale * 1000.0))
	assert_eq(staph.biofilm_break_mt, roundi(2.0 * cfg.grid_scale * 1000.0))
	assert_false((cfg.pathogens["rhinovirus"] as PathogenDef).has_biofilm)
	assert_false(cfg.flag("biofilm"))

func test_biofilm_key_optional() -> void:
	var res: ConfigLoadResult = _load_with_biofilm(func(d: Dictionary) -> void: d["staphylococcus"].erase("biofilm"))
	assert_false(res.is_err())
	assert_false((res.config.pathogens["staphylococcus"] as PathogenDef).has_biofilm)

func test_biofilm_validation_errors() -> void:
	var r1: ConfigLoadResult = _load_with_biofilm(func(d: Dictionary) -> void: d["staphylococcus"]["biofilm"]["break_radius_tiles"] = 1.0)
	assert_true(_contains_error(r1.errors, "pathogens.json: staphylococcus.biofilm.break_radius_tiles: must be >= link_radius_tiles"))
	var r2: ConfigLoadResult = _load_with_biofilm(func(d: Dictionary) -> void: d["staphylococcus"]["biofilm"]["damage_taken_multiplier"] = 1.5)
	assert_true(_contains_error(r2.errors, "pathogens.json: staphylococcus.biofilm.damage_taken_multiplier: must be > 0 and <= 1 (got 1.5)"))
	var r3: ConfigLoadResult = _load_with_biofilm(func(d: Dictionary) -> void: d["staphylococcus"]["biofilm"]["bogus"] = 1)
	assert_true(_contains_error(r3.errors, "pathogens.json: staphylococcus.biofilm.bogus: unknown key"))
	var r4: ConfigLoadResult = _load_with_biofilm(func(d: Dictionary) -> void: d["staphylococcus"]["biofilm"]["regroup_interval_s"] = 0)
	assert_true(_contains_error(r4.errors, "pathogens.json: staphylococcus.biofilm.regroup_interval_s: must be > 0 (got 0)"))
	var r5: ConfigLoadResult = _load_with_biofilm(func(d: Dictionary) -> void: d["staphylococcus"]["biofilm"].erase("link_radius_tiles"))
	assert_true(_contains_error(r5.errors, "pathogens.json: staphylococcus.biofilm.link_radius_tiles: missing required field"))



# -----------------------------------------------------------------------------
# Hijack block (#92)
# -----------------------------------------------------------------------------

func _load_with_hijack(mutate: Callable) -> ConfigLoadResult:
	var p_dict: Dictionary = JSON.parse_string(default_pathogens_str)
	mutate.call(p_dict)
	return GameConfig.load_from_strings(default_rules_str, default_structures_str, JSON.stringify(p_dict))

func test_hijack_default_data() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var phage: PathogenDef = cfg.pathogens["bacteriophage"]
	assert_true(phage.has_hijack)
	assert_eq(phage.hijack_channel_ticks, roundi(2.0 * cfg.tick_rate))
	assert_eq(phage.hijack_disable_ticks, roundi(8.0 * cfg.tick_rate))
	assert_eq(phage.hijack_target_tags, PackedStringArray(["defense"]))
	assert_false((cfg.pathogens["rhinovirus"] as PathogenDef).has_hijack)
	assert_false(cfg.flag("phage_hijack"))

func test_hijack_key_optional() -> void:
	var res: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"].erase("hijack"))
	assert_false(res.is_err())
	assert_false((res.config.pathogens["bacteriophage"] as PathogenDef).has_hijack)

func test_hijack_validation_errors() -> void:
	var r1: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"]["hijack"]["channel_s"] = 0)
	assert_true(_contains_error(r1.errors, "pathogens.json: bacteriophage.hijack.channel_s: must be > 0 (got 0)"))
	var r2: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"]["hijack"]["target_tags"] = [])
	assert_true(_contains_error(r2.errors, "pathogens.json: bacteriophage.hijack.target_tags: cannot be empty"))
	var r3: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"]["hijack"]["target_tags"] = ["bogus"])
	assert_true(_contains_error(r3.errors, "pathogens.json: bacteriophage.hijack.target_tags: unknown tag (got bogus)"))
	var r4: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"]["hijack"]["bogus"] = 1)
	assert_true(_contains_error(r4.errors, "pathogens.json: bacteriophage.hijack.bogus: unknown key"))

func test_hijack_turncoat_keys() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var phage: PathogenDef = cfg.pathogens["bacteriophage"]
	assert_eq(phage.hijack_turncoat_damage_pct, 50)
	assert_eq(phage.hijack_turncoat_max_damage, 300)
	assert_false(cfg.flag("phage_turncoat"))
	var bare: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void:
		d["bacteriophage"]["hijack"].erase("turncoat_damage_pct")
		d["bacteriophage"]["hijack"].erase("turncoat_max_damage"))
	assert_false(bare.is_err())
	assert_eq((bare.config.pathogens["bacteriophage"] as PathogenDef).hijack_turncoat_max_damage, 0)
	var r1: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"]["hijack"]["turncoat_damage_pct"] = 101)
	assert_true(_contains_error(r1.errors, "pathogens.json: bacteriophage.hijack.turncoat_damage_pct: must be <= 100 (got 101)"))
	var r2: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"]["hijack"]["turncoat_damage_pct"] = 12.5)
	assert_true(_contains_error(r2.errors, "pathogens.json: bacteriophage.hijack.turncoat_damage_pct: must be an integer"))
	var r3: ConfigLoadResult = _load_with_hijack(func(d: Dictionary) -> void: d["bacteriophage"]["hijack"]["turncoat_max_damage"] = -1)
	assert_true(_contains_error(r3.errors, "pathogens.json: bacteriophage.hijack.turncoat_max_damage: must be >= 0 (got -1)"))


func _load_with_strains(mutate: Callable) -> ConfigLoadResult:
	var p_dict: Dictionary = JSON.parse_string(default_pathogens_str)
	mutate.call(p_dict)
	return GameConfig.load_from_strings(default_rules_str, default_structures_str, JSON.stringify(p_dict))

func test_strains_default_data() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var rhino: PathogenDef = cfg.pathogens["rhinovirus"]
	assert_eq(rhino.strain_ids(), ["wild", "capsid_hardening", "rapid_replication", "antigenic_masking"] as Array[String])
	assert_eq(rhino.strain("capsid_hardening").hp_pct, 115)
	assert_eq(rhino.strain("capsid_hardening").speed_pct, 90)
	assert_true(rhino.strain("wild").is_wild())
	assert_null(rhino.strain("nope"))
	assert_false(cfg.flag("strains"))

func test_strains_key_optional() -> void:
	var res: ConfigLoadResult = _load_with_strains(func(d: Dictionary) -> void: d["rhinovirus"].erase("strains"))
	assert_false(res.is_err())
	assert_eq((res.config.pathogens["rhinovirus"] as PathogenDef).strain_ids(), ["wild"] as Array[String])

func test_strains_validation_errors() -> void:
	var r1: ConfigLoadResult = _load_with_strains(func(d: Dictionary) -> void: d["rhinovirus"]["strains"][0]["id"] = "wild")
	assert_true(_contains_error(r1.errors, "pathogens.json: rhinovirus.strains[0].id: reserved id (got wild)"))
	var r2: ConfigLoadResult = _load_with_strains(func(d: Dictionary) -> void: d["rhinovirus"]["strains"][2]["id"] = "rapid_replication")
	assert_true(_contains_error(r2.errors, "pathogens.json: rhinovirus.strains[2].id: duplicate id (got rapid_replication)"))
	var r3: ConfigLoadResult = _load_with_strains(func(d: Dictionary) -> void: d["rhinovirus"]["strains"][0]["id"] = "Bad-Id")
	assert_true(_contains_error(r3.errors, "pathogens.json: rhinovirus.strains[0].id: must match"))
	var r4: ConfigLoadResult = _load_with_strains(func(d: Dictionary) -> void: d["rhinovirus"]["strains"][0]["modifiers"]["bogus"] = 1.0)
	assert_true(_contains_error(r4.errors, "pathogens.json: rhinovirus.strains[0].modifiers.bogus: unknown key"))
	var r5: ConfigLoadResult = _load_with_strains(func(d: Dictionary) -> void: d["rhinovirus"]["strains"][0]["modifiers"]["hp"] = 0)
	assert_true(_contains_error(r5.errors, "pathogens.json: rhinovirus.strains[0].modifiers.hp: must be > 0"))
	var r6: ConfigLoadResult = _load_with_strains(func(d: Dictionary) -> void: d["rhinovirus"]["strains"] = "nope")
	assert_true(_contains_error(r6.errors, "pathogens.json: rhinovirus.strains: must be an array"))

# -----------------------------------------------------------------------------
# immune_memory block (#89)
# -----------------------------------------------------------------------------

func _memory_rules(mutate: Callable) -> ConfigLoadResult:
	var r: Dictionary = JSON.parse_string(default_rules_str)
	mutate.call(r)
	return GameConfig.load_from_strings(JSON.stringify(r), default_structures_str, default_pathogens_str)

func test_immune_memory_defaults_load() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	assert_eq(cfg.memory_max_level, 3)
	assert_eq(cfg.memory_seed_pct_per_level, 25)
	assert_eq(cfg.memory_decay_raids, 2)
	assert_eq(cfg.memory_slots, 3)
	assert_eq(cfg.memory_drift_pct, 50)
	assert_false(cfg.memory_enabled())
	cfg.feature_flags["immune_memory"] = true
	cfg.feature_flags["bcell_analysis"] = true
	assert_true(cfg.memory_enabled())

func test_immune_memory_validation_errors() -> void:
	var r1: ConfigLoadResult = _memory_rules(func(r: Dictionary) -> void: r["immune_memory"]["slots"] = 0)
	assert_true(_contains_error(r1.errors, "immune_memory.slots: must be >= 1 (got 0)"))
	var r2: ConfigLoadResult = _memory_rules(func(r: Dictionary) -> void: r["immune_memory"]["drift_pct"] = 150)
	assert_true(_contains_error(r2.errors, "immune_memory.drift_pct: must be <= 100 (got 150)"))
	var r3: ConfigLoadResult = _memory_rules(func(r: Dictionary) -> void: r["immune_memory"]["max_level"] = "x")
	assert_true(_contains_error(r3.errors, "immune_memory.max_level: must be an integer"))
	var r4: ConfigLoadResult = _memory_rules(func(r: Dictionary) -> void: r["immune_memory"]["bogus"] = 1)
	assert_true(_contains_error(r4.errors, "immune_memory.bogus: unknown key"))
	var r5: ConfigLoadResult = _memory_rules(func(r: Dictionary) -> void:
		r.erase("immune_memory")
		r["feature_flags"]["immune_memory"] = true)
	assert_true(_contains_error(r5.errors, "game_rules.json: immune_memory: required when feature_flags.immune_memory is true (got null)"))

func test_config_without_immune_memory_block_loads() -> void:
	var res: ConfigLoadResult = _memory_rules(func(r: Dictionary) -> void:
		r.erase("immune_memory")
		r["feature_flags"].erase("immune_memory"))
	assert_true(res.is_ok())
	assert_eq(res.config.memory_slots, 0)
	assert_false(res.config.memory_enabled())


func test_outbreak_flag_removed_but_tolerated() -> void:
	# Outbreak was removed (#149): the shipped data has no flag, and an old config that still sets it loads.
	var shipped: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(shipped.is_ok())
	assert_false(shipped.config.feature_flags.has("outbreak_mode"))
	var res: ConfigLoadResult = _memory_rules(func(r: Dictionary) -> void: r["feature_flags"]["outbreak_mode"] = true)
	assert_true(res.is_ok())
	assert_true(res.config.flag("outbreak_mode"))
