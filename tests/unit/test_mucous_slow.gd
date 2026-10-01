extends GutTest

## Mucous slow (#164): pathogens on a cell next to a Mucous Wall move at half speed (mucous_slow flag).

const WALL_CELL: Vector2i = Vector2i(10, 10)


func _cfg(slow: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["mucous_slow"] = slow
	return cfg


func _wall(cell: Vector2i = WALL_CELL) -> Dictionary:
	return {"type": "mucous_wall", "origin": cell}


func _sim(cfg: GameConfig, walls: Array, unit_cell: Vector2i) -> BattleSim:
	return SimFixtures.make_sim(walls, [{"type": "rhinovirus", "cell": unit_cell}], 1, cfg)


## Milli-tiles the rhinovirus moves in one tick.
func _step_distance(sim: BattleSim) -> int:
	var p: PathogenState = sim.pathogen(1)
	var before: Vector2i = p.pos
	sim.step()
	return FixedMath.isqrt(FixedMath.dist_sq(before, p.pos))


func test_default_data_has_the_aura_and_the_flag_is_off() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var wall: StructureDef = cfg.structures["mucous_wall"]
	assert_true(wall.has_slow_aura)
	assert_eq(wall.slow_aura_speed_pct, 50)
	assert_false(wall.slow_aura_chebyshev)
	assert_false(cfg.flag("mucous_slow"))
	assert_false(cfg.structures["macrophage"].has_slow_aura)


func test_flag_off_moves_at_full_speed() -> void:
	var full: int = _step_distance(_sim(_cfg(false), [], Vector2i(10, 11)))
	var near_wall: int = _step_distance(_sim(_cfg(false), [_wall()], Vector2i(10, 11)))
	assert_gt(full, 0)
	assert_eq(near_wall, full)


func test_flag_on_halves_the_speed_next_to_a_wall() -> void:
	var cfg: GameConfig = _cfg()
	var full: int = _step_distance(_sim(cfg, [], Vector2i(10, 11)))
	var slowed: int = _step_distance(_sim(cfg, [_wall()], Vector2i(10, 11)))
	assert_lte(absi(slowed * 2 - full), 2, "half speed within rounding (%d vs %d)" % [slowed, full])
	var far: int = _step_distance(_sim(cfg, [_wall()], Vector2i(10, 20)))
	assert_eq(far, full, "a cell away from every wall is not slowed")


func test_two_walls_do_not_stack() -> void:
	var cfg: GameConfig = _cfg()
	var full: int = _step_distance(_sim(cfg, [], Vector2i(10, 11)))
	var two: int = _step_distance(_sim(cfg, [_wall(WALL_CELL), _wall(Vector2i(10, 12))], Vector2i(10, 11)))
	assert_lte(absi(two * 2 - full), 2, "still 50%, not 25%")


func test_diagonal_neighbours_are_not_slowed_unless_chebyshev() -> void:
	var cfg: GameConfig = _cfg()
	var full: int = _step_distance(_sim(cfg, [], Vector2i(11, 11)))
	assert_eq(_step_distance(_sim(cfg, [_wall()], Vector2i(11, 11))), full)
	cfg.structures["mucous_wall"].slow_aura_chebyshev = true
	var slowed: int = _step_distance(_sim(cfg, [_wall()], Vector2i(11, 11)))
	assert_lte(absi(slowed * 2 - full), 2)


func test_a_destroyed_wall_stops_slowing() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, [_wall()], Vector2i(10, 11))
	assert_true(sim.slow_cells().has(Vector2i(10, 11)))
	var version: int = sim.slow_version
	sim._damage_structure(sim.structure(1), 100000, 0)
	assert_false(sim.structure(1).alive)
	assert_false(sim.slow_cells().has(Vector2i(10, 11)))
	assert_gt(sim.slow_version, version)
	var full: int = _step_distance(_sim(cfg, [], Vector2i(10, 11)))
	assert_eq(_step_distance(sim), full, "full speed on the next tick")


func test_occupied_cells_are_never_marked() -> void:
	var sim: BattleSim = _sim(_cfg(), [_wall(WALL_CELL), _wall(Vector2i(10, 11))], Vector2i(10, 20))
	assert_false(sim.slow_cells().has(Vector2i(10, 11)))
	assert_false(sim.slow_cells().has(WALL_CELL))
	assert_true(sim.slow_cells().has(Vector2i(10, 12)))


func test_the_flag_off_marks_nothing() -> void:
	assert_true(_sim(_cfg(false), [_wall()], Vector2i(10, 11)).slow_cells().is_empty())


func test_slowed_battles_are_deterministic_and_differ_from_unslowed() -> void:
	var walls: Array = []
	for y: int in range(8, 14):
		walls.append(_wall(Vector2i(12, y)))
	var hashes: Array[String] = []
	for slow: bool in [true, true, false]:
		var sim: BattleSim = SimFixtures.make_sim(walls, [
			{"type": "rhinovirus", "cell": Vector2i(2, 10)},
			{"type": "rhinovirus", "cell": Vector2i(2, 11)},
		], 7, _cfg(slow))
		sim.run_to_end(400)
		hashes.append(sim.state_hash())
	assert_eq(hashes[0], hashes[1])
	assert_ne(hashes[0], hashes[2])


func test_the_synthesis_role_text_mentions_the_slow_only_with_the_flag() -> void:
	var on: GameConfig = _cfg()
	var off: GameConfig = _cfg(false)
	assert_eq(UnitCopy.role(on.structures["mucous_wall"], on), "Blocks paths. Slows pathogens next to it.")
	assert_eq(UnitCopy.role(off.structures["mucous_wall"], off), "Blocks paths")
	assert_eq(UnitCopy.role(on.structures["macrophage"], on), on.structures["macrophage"].role)


func _load_structures(mutate: Callable) -> ConfigLoadResult:
	var structs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/structures.json"))
	mutate.call(structs)
	return GameConfig.load_from_strings(FileAccess.get_file_as_string("res://data/game_rules.json"),
		JSON.stringify(structs), FileAccess.get_file_as_string("res://data/pathogens.json"))


func _has_error(res: ConfigLoadResult, fragment: String) -> bool:
	for e: String in res.errors:
		if e.find(fragment) != -1:
			return true
	return false


func test_slow_aura_validation() -> void:
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["slow_aura"]["speed_multiplier"] = 0), "structures.json: mucous_wall.slow_aura.speed_multiplier: must be > 0 and <= 1 (got 0)"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["slow_aura"]["speed_multiplier"] = 1.5), "slow_aura.speed_multiplier: must be > 0 and <= 1"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["slow_aura"]["adjacency"] = "diagonal"), "structures.json: mucous_wall.slow_aura.adjacency: must be"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["slow_aura"]["bogus"] = 1), "structures.json: mucous_wall.slow_aura.bogus: unknown key"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["slow_aura"].erase("adjacency")), "structures.json: mucous_wall.slow_aura.adjacency: missing required field"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["slow_aura"] = 5), "structures.json: mucous_wall.slow_aura: must be a JSON object"))
	assert_true(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"].erase("slow_aura")).is_ok())
	var chebyshev: ConfigLoadResult = _load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["slow_aura"]["adjacency"] = "chebyshev")
	assert_true(chebyshev.is_ok())
	assert_true(chebyshev.config.structures["mucous_wall"].slow_aura_chebyshev)
