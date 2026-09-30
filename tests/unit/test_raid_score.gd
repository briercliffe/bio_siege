extends GutTest

var _config: GameConfig = null


func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	_config = res.config


func _atp(type_id: String) -> int:
	return int(_config.structures[type_id].cost.get("atp", 0))


func _layout(types: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var x: int = 2
	for t: String in types:
		out.append({"type": t, "origin": Vector2i(x, 2)})
		x += 2
	return out


func test_flag_helper_defaults_false() -> void:
	assert_false(_config.flag("raid_score"))
	assert_false(_config.flag("no_such_flag"))
	_config.feature_flags["raid_score"] = true
	assert_true(_config.flag("raid_score"))
	_config.feature_flags["raid_score"] = false


func test_nucleus_only_layout_is_zero() -> void:
	var grid := GridModel.new(_config)
	grid.reset_with_nucleus()
	assert_eq(RaidScore.base_value(_config, grid.to_layout()), 0)


func test_walls_and_macrophage_sum_from_config() -> void:
	var layout: Array[Dictionary] = [{"type": _config.core_structure_id(), "origin": Vector2i(0, 0)}]
	layout.append_array(_layout(["mucous_wall", "mucous_wall", "macrophage"]))
	var expected: int = 2 * _atp("mucous_wall") + _atp("macrophage")
	assert_gt(expected, 0)
	assert_eq(RaidScore.base_value(_config, layout), expected)


func test_unknown_types_ignored_and_null_config_zero() -> void:
	var layout: Array[Dictionary] = _layout(["macrophage", "not_a_structure"])
	assert_eq(RaidScore.base_value(_config, layout), _atp("macrophage"))
	assert_eq(RaidScore.base_value(null, layout), 0)
	assert_eq(RaidScore.base_value(_config, []), 0)


func test_compute_by_outcome() -> void:
	var layout: Array[Dictionary] = _layout(["mucous_wall", "macrophage"])
	var value: int = RaidScore.base_value(_config, layout)
	assert_gt(value, 0)
	assert_eq(RaidScore.compute(_config, layout, "attacker"), value)
	assert_eq(RaidScore.compute(_config, layout, "defender"), 0)
