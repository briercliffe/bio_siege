extends GutTest

var _cfg: GameConfig


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true}).config


func test_the_pvp_block_loads() -> void:
	assert_eq(_cfg.pvp_start_trophies, 100)
	assert_eq(_cfg.pvp_band, 100)
	assert_eq(_cfg.pvp_band_widen_steps, 3)
	assert_eq(_cfg.pvp_trophy_base, 20)
	assert_eq(_cfg.pvp_shield_hours, 12)
	assert_eq(_cfg.pvp_recent_opponent_hours, 24)


func test_delta_for_equal_trophies_is_the_base() -> void:
	assert_eq(Trophies.delta(_cfg, 500, 500), 20)


func test_delta_is_bigger_against_a_much_higher_defender_and_clamped() -> void:
	assert_eq(Trophies.delta(_cfg, 500, 600), 25)
	assert_eq(Trophies.delta(_cfg, 100, 1000), 40, "clamped to trophy_max")


func test_delta_is_smaller_against_a_much_lower_defender_and_clamped() -> void:
	assert_eq(Trophies.delta(_cfg, 600, 500), 15)
	assert_eq(Trophies.delta(_cfg, 1000, 100), 5, "clamped to trophy_min")


func test_integer_division_truncates_toward_zero() -> void:
	assert_eq(Trophies.delta(_cfg, 500, 519), 20, "a gap under the divisor changes nothing")
	assert_eq(Trophies.delta(_cfg, 519, 500), 20, "and truncation is toward zero for negatives too")
	assert_eq(Trophies.delta(_cfg, 540, 500), 18)


func test_an_attacker_win_moves_the_full_delta() -> void:
	var t: Dictionary = Trophies.settle(_cfg, 500, 500, true)
	assert_eq(t["attacker_delta"], 20)
	assert_eq(t["defender_delta"], -20)
	assert_eq(t["attacker_after"], 520)
	assert_eq(t["defender_after"], 480)


func test_a_defender_win_moves_half_the_delta() -> void:
	var t: Dictionary = Trophies.settle(_cfg, 500, 500, false)
	assert_eq(t["attacker_delta"], -10)
	assert_eq(t["defender_delta"], 10)
	var odd: Dictionary = Trophies.settle(_cfg, 500, 619, false)
	assert_eq(odd["attacker_delta"], -(25 / 2))
	assert_eq(odd["defender_delta"], 25 / 2)


func test_nobody_drops_below_zero() -> void:
	var t: Dictionary = Trophies.settle(_cfg, 500, 5, true)
	assert_eq(t["defender_after"], 0)
	assert_eq(t["defender_delta"], -5, "the delta is what really changed")
	var u: Dictionary = Trophies.settle(_cfg, 3, 500, false)
	assert_eq(u["attacker_after"], 0)
	assert_eq(u["attacker_delta"], -3)


func test_the_pvp_block_is_required_when_online_is_on() -> void:
	var dir: String = "user://test_pvp_cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in ["game_rules.json", "structures.json", "pathogens.json"]:
		DirAccess.copy_absolute("res://data/" + f, dir + "/" + f)
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/game_rules.json")) as Dictionary
	rules.erase("pvp")
	var out: FileAccess = FileAccess.open(dir + "/game_rules.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(rules))
	out.close()
	var off: ConfigLoadResult = GameConfig.load_from_dir(dir, {"living_base": true})
	assert_true(off.is_ok(), "optional while online is off")
	var on: ConfigLoadResult = GameConfig.load_from_dir(dir, {"living_base": true, "online": true})
	assert_false(on.is_ok())
	assert_true(", ".join(on.errors).contains("pvp: required when feature_flags.online is true"))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
