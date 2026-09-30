extends GutTest

func _load_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	return res.config

func test_create_and_properties() -> void:
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(9, 9)}]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 0)}]
	var setup := BattleSetup.create(structs, units, 12345)

	assert_eq(setup.seed, 12345)
	assert_eq(setup.structures.size(), 1)
	assert_eq(setup.units.size(), 1)
	assert_eq(setup.structures[0]["type"], "nucleus")
	assert_eq(setup.units[0]["type"], "rhinovirus")

	# Verify deep copy isolation
	structs[0]["origin"] = Vector2i(0, 0)
	assert_eq(setup.structures[0]["origin"], Vector2i(9, 9))

func test_serialization_round_trip() -> void:
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(9, 9)}]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 0)}]
	var setup := BattleSetup.create(structs, units, 777)

	var dict: Dictionary = setup.to_dict()
	assert_eq(dict["seed"], 777)

	var restored := BattleSetup.from_dict(dict)
	assert_eq(restored.seed, 777)
	assert_eq(restored.structures, setup.structures)
	assert_eq(restored.units, setup.units)

	var dup := setup.duplicate_setup()
	assert_eq(dup.seed, setup.seed)
	assert_eq(dup.structures, setup.structures)
	assert_eq(dup.units, setup.units)

func test_validate_null_config() -> void:
	var setup := BattleSetup.create([], [], 1)
	var errs: PackedStringArray = setup.validate(null)
	assert_true(errs.has("Config is null"))

func test_validate_valid_setup() -> void:
	var cfg := _load_config()
	var setup := BattleSetup.create(
		[
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "mucous_wall", "origin": Vector2i(5, 5)}
		],
		[
			{"type": "rhinovirus", "cell": Vector2i(0, 0)},
			{"type": "bacteriophage", "cell": Vector2i(19, 19)}
		],
		42
	)
	var errs: PackedStringArray = setup.validate(cfg)
	assert_eq(errs.size(), 0)

func test_validate_core_count() -> void:
	var cfg := _load_config()

	# 0 cores
	var setup_zero := BattleSetup.create(
		[{"type": "mucous_wall", "origin": Vector2i(5, 5)}],
		[],
		1
	)
	var errs_zero := setup_zero.validate(cfg)
	assert_true(errs_zero.has("Expected exactly 1 core structure, found 0"))

	# 2 cores
	var setup_two := BattleSetup.create(
		[
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "nucleus", "origin": Vector2i(3, 3)}
		],
		[],
		1
	)
	var errs_two := setup_two.validate(cfg)
	assert_true(errs_two.has("Expected exactly 1 core structure, found 2"))

func test_validate_unknown_types() -> void:
	var cfg := _load_config()

	var bad_struct := BattleSetup.create(
		[
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "non_existent_tower", "origin": Vector2i(5, 5)}
		],
		[],
		1
	)
	var errs_struct := bad_struct.validate(cfg)
	assert_true(errs_struct.has("Unknown structure type: 'non_existent_tower'"))

	var bad_unit := BattleSetup.create(
		[{"type": "nucleus", "origin": Vector2i(9, 9)}],
		[{"type": "alien_monster", "cell": Vector2i(0, 0)}],
		1
	)
	var errs_unit := bad_unit.validate(cfg)
	assert_true(errs_unit.has("Unknown pathogen type: 'alien_monster'"))

func test_validate_out_of_bounds() -> void:
	var cfg := _load_config()

	# Structure negative origin
	var neg_origin := BattleSetup.create(
		[
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "mucous_wall", "origin": Vector2i(-1, 5)}
		],
		[],
		1
	)
	assert_true(neg_origin.validate(cfg).size() > 0)

	# Structure exceeds grid bounds (nucleus is 2x2, origin 19x19 exceeds 20x20)
	var exceed_grid := BattleSetup.create(
		[{"type": "nucleus", "origin": Vector2i(19, 19)}],
		[],
		1
	)
	assert_true(exceed_grid.validate(cfg).size() > 0)

	# Unit out of bounds
	var oob_unit := BattleSetup.create(
		[{"type": "nucleus", "origin": Vector2i(9, 9)}],
		[{"type": "rhinovirus", "cell": Vector2i(20, 0)}],
		1
	)
	assert_true(oob_unit.validate(cfg).size() > 0)

func test_validate_structure_overlap() -> void:
	var cfg := _load_config()
	# Nucleus at (9, 9) occupies (9,9), (10,9), (9,10), (10,10)
	var overlap := BattleSetup.create(
		[
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "mucous_wall", "origin": Vector2i(10, 10)}
		],
		[],
		1
	)
	var errs := overlap.validate(cfg)
	assert_true(errs.size() > 0)

func test_validate_invalid_coord_formats() -> void:
	var cfg := _load_config()

	# Origin as Array [x, y] is supported
	var arr_origin := BattleSetup.create(
		[{"type": "nucleus", "origin": [9, 9]}],
		[{"type": "rhinovirus", "cell": [0, 0]}],
		1
	)
	assert_eq(arr_origin.validate(cfg).size(), 0)

	# Origin invalid
	var invalid_origin := BattleSetup.create(
		[{"type": "nucleus", "origin": "invalid"}],
		[],
		1
	)
	assert_true(invalid_origin.validate(cfg).size() > 0)

	# Unit cell invalid
	var invalid_cell := BattleSetup.create(
		[{"type": "nucleus", "origin": Vector2i(9, 9)}],
		[{"type": "rhinovirus", "cell": "bad_coord"}],
		1
	)
	assert_true(invalid_cell.validate(cfg).size() > 0)


func test_unknown_strain_fails_validation() -> void:
	var cfg: GameConfig = _load_config()
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(9, 9)}]
	var bad: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 0), "strain": "nope"}]
	var errors: PackedStringArray = BattleSetup.create(structs, bad, 1).validate(cfg)
	assert_true(errors.has("Unknown strain 'nope' for pathogen 'rhinovirus'"))
	var good: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 0), "strain": "capsid_hardening"}]
	assert_eq(BattleSetup.create(structs, good, 1).validate(cfg).size(), 0)

func test_strain_round_trips_through_dict() -> void:
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(9, 9)}]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 0), "strain": "capsid_hardening"}]
	var back: BattleSetup = BattleSetup.from_dict(BattleSetup.create(structs, units, 5).to_dict())
	assert_eq(back.units[0]["strain"], "capsid_hardening")


func test_memory_seed_round_trip_and_validation() -> void:
	var cfg: GameConfig = _load_config()
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(9, 9)}]
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 0)}]
	var plain: BattleSetup = BattleSetup.create(structs, units, 5)
	assert_false(plain.to_dict().has("memory_seed"))

	var seeded: BattleSetup = BattleSetup.create(structs, units, 5, {"rhinovirus/wild": 50})
	assert_eq(seeded.to_dict()["memory_seed"], {"rhinovirus/wild": 50})
	assert_eq(BattleSetup.from_dict(seeded.to_dict()).memory_seed, {"rhinovirus/wild": 50})
	assert_eq(seeded.duplicate_setup().memory_seed, {"rhinovirus/wild": 50})
	assert_eq(seeded.validate(cfg).size(), 0)

	var bad: BattleSetup = BattleSetup.create(structs, units, 5, {"rhinovirus/wild": 101})
	assert_gt(bad.validate(cfg).size(), 0)
