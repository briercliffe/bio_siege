extends GutTest

var _cfg: GameConfig


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true}).config


func _stats(raids: int, hits: int, checks: int, gens: Dictionary = {}, flagged: bool = false) -> Dictionary:
	return {"raids": raids, "receptor_hits": hits, "receptor_checks": checks, "max_generation": gens, "flagged": flagged}


func test_the_threshold_comes_from_the_data() -> void:
	assert_eq(_cfg.pvp_suspicious_hit_rate_pct, 90)


func test_it_flags_a_high_hit_rate_over_enough_raids_at_low_generations() -> void:
	assert_true(CheatFlags.is_suspicious(_cfg, _stats(5, 90, 100, {"macrophage": 2})))
	assert_true(CheatFlags.is_suspicious(_cfg, _stats(12, 99, 100, {"macrophage": 4})))


func test_it_does_not_flag_below_the_rate_the_raid_count_or_with_high_generations() -> void:
	assert_false(CheatFlags.is_suspicious(_cfg, _stats(5, 89, 100, {"macrophage": 2})), "89% is under 90%")
	assert_false(CheatFlags.is_suspicious(_cfg, _stats(4, 100, 100, {"macrophage": 2})), "fewer than 5 raids")
	assert_false(CheatFlags.is_suspicious(_cfg, _stats(9, 100, 100, {"macrophage": 5})), "a base bred to generation 5 is believable")
	assert_false(CheatFlags.is_suspicious(_cfg, _stats(9, 100, 100, {"macrophage": 2, "b_cell": 7})), "any pool at 5 or more")
	assert_false(CheatFlags.is_suspicious(_cfg, _stats(9, 0, 0, {})), "nothing was checked")


func test_integer_maths_at_the_boundary() -> void:
	assert_true(CheatFlags.is_suspicious(_cfg, _stats(6, 9, 10)))
	assert_false(CheatFlags.is_suspicious(_cfg, _stats(6, 8, 10)))
	assert_true(CheatFlags.is_suspicious(_cfg, _stats(6, 27, 30)))
	assert_false(CheatFlags.is_suspicious(_cfg, _stats(6, 26, 30)))


func test_a_zero_threshold_turns_the_rule_off() -> void:
	var off: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true}).config
	off.pvp_suspicious_hit_rate_pct = 0
	assert_false(CheatFlags.is_suspicious(off, _stats(20, 100, 100)))


func test_updated_folds_a_raid_in_and_sets_the_flag_on_a_synthetic_stats_object() -> void:
	var s: Dictionary = {}
	for i: int in range(4):
		s = CheatFlags.updated(_cfg, s, 9, 10, {"macrophage": i})
		assert_false(bool(s["flagged"]), "raid %d" % (i + 1))
	s = CheatFlags.updated(_cfg, s, 10, 10, {"macrophage": 2, "b_cell": 1})
	assert_eq(int(s["raids"]), 5)
	assert_eq(int(s["receptor_hits"]), 46)
	assert_eq(int(s["receptor_checks"]), 50)
	assert_true(bool(s["flagged"]), "92% over 5 raids at generation 3")
	assert_eq(s["max_generation"], {"macrophage": 3, "b_cell": 1}, "the highest generation seen per type")


func test_the_flag_is_sticky_and_never_automatic_ban() -> void:
	var s: Dictionary = CheatFlags.updated(_cfg, _stats(9, 90, 100, {"macrophage": 1}), 10, 10, {"macrophage": 1})
	assert_true(bool(s["flagged"]))
	var later: Dictionary = CheatFlags.updated(_cfg, _stats(9, 0, 1000, {"macrophage": 1}, true), 0, 10, {"macrophage": 1})
	assert_true(bool(later["flagged"]), "once flagged, always listed for a human")
	assert_false(later.has("banned"))


func test_it_tolerates_json_floats_and_junk() -> void:
	var s: Dictionary = CheatFlags.updated(_cfg, {"raids": 4.0, "receptor_hits": 36.0, "receptor_checks": 40.0, "max_generation": {"macrophage": 1.0}}, 9, 10, {})
	assert_eq(int(s["raids"]), 5)
	assert_true(bool(s["flagged"]))
	var junk: Dictionary = CheatFlags.updated(_cfg, "nope", 1, 2, {"b_cell": 3})
	assert_eq(int(junk["raids"]), 1)
