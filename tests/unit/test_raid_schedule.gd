extends GutTest

const HOUR: int = 3600

var _cfg: GameConfig = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config


func test_config_block_loaded() -> void:
	assert_eq(_cfg.ai_raid_interval_s, 8 * HOUR)
	assert_eq(_cfg.ai_raid_max_pending, 3)
	assert_eq(_cfg.ai_army_budget_pct, 80)
	assert_eq(_cfg.ai_min_army_atp, 300)
	assert_eq(_cfg.ai_pathogen_weights, {"rhinovirus": 50, "bacteriophage": 25, "staphylococcus": 25})


func test_due_count_follows_the_interval_and_the_cap() -> void:
	assert_eq(RaidSchedule.due_count(_cfg, 0, 7 * HOUR), 0)
	assert_eq(RaidSchedule.due_count(_cfg, 0, 8 * HOUR), 1)
	assert_eq(RaidSchedule.due_count(_cfg, 0, 17 * HOUR), 2)
	assert_eq(RaidSchedule.due_count(_cfg, 0, 100 * HOUR), 3)


func test_a_clock_set_back_is_not_due() -> void:
	assert_eq(RaidSchedule.due_count(_cfg, 1000, 500), 0)
	assert_eq(RaidSchedule.due_count(_cfg, 1000, 1000), 0)


func test_advance_moves_by_whole_intervals() -> void:
	assert_eq(RaidSchedule.advance(_cfg, 0, 17 * HOUR, 2), 16 * HOUR)
	assert_eq(RaidSchedule.advance(_cfg, 0, 17 * HOUR, 0), 0)
	# Exactly the cap owed: no jump.
	assert_eq(RaidSchedule.advance(_cfg, 0, 24 * HOUR, 3), 24 * HOUR)


func test_advance_jumps_to_now_when_more_than_the_cap_was_owed() -> void:
	assert_eq(RaidSchedule.advance(_cfg, 0, 100 * HOUR, 3), 100 * HOUR)


func test_a_new_profile_starts_the_clock_at_creation() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 1, 5000)
	assert_eq(p.last_ai_raid_unix, 5000)
	assert_eq(RaidSchedule.due_count(_cfg, p.last_ai_raid_unix, 5000 + 8 * HOUR - 1), 0)
	assert_eq(RaidSchedule.due_count(_cfg, p.last_ai_raid_unix, 5000 + 8 * HOUR), 1)


# --- ai_raids validation ---

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
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["interval_hours"] = 0), "game_rules.json: ai_raids.interval_hours: must be >= 1 (got 0)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["interval_hours"] = 169), "game_rules.json: ai_raids.interval_hours: must be <= 168"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["max_pending"] = 11), "game_rules.json: ai_raids.max_pending: must be <= 10"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["army_budget_pct_of_base"] = 9), "game_rules.json: ai_raids.army_budget_pct_of_base: must be >= 10"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["min_army_atp"] = -1), "game_rules.json: ai_raids.min_army_atp: must be >= 0 (got -1)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["pathogen_weights"]["ghost"] = 5), "game_rules.json: ai_raids.pathogen_weights.ghost: must be a pathogen id"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["pathogen_weights"]["rhinovirus"] = 0), "game_rules.json: ai_raids.pathogen_weights.rhinovirus: must be > 0 (got 0)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"]["bogus"] = 1), "game_rules.json: ai_raids.bogus: unknown key (got bogus)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"].erase("pathogen_weights")), "game_rules.json: ai_raids.pathogen_weights: missing required field"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["ai_raids"].erase("max_pending")), "game_rules.json: ai_raids.max_pending: missing required field (got null)"))


func test_block_required_only_when_living_base_is_on() -> void:
	assert_true(_load_rules(func(d: Dictionary) -> void: d.erase("ai_raids")).is_ok())
	var r2: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void:
		d.erase("ai_raids")
		d["feature_flags"]["living_base"] = true)
	assert_true(_has_error(r2, "game_rules.json: ai_raids: required when feature_flags.living_base is true"))
