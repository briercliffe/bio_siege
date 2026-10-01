extends GutTest

## Mucous trap (#165): `small` pathogens touching a Mucous Wall are rooted for 2 s, once per unit per wall.

const WALL_CELL: Vector2i = Vector2i(10, 10)
const UNIT_CELL: Vector2i = Vector2i(10, 11)


func _cfg(trap: bool = true, slow: bool = false) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["mucous_trap"] = trap
	cfg.feature_flags["mucous_slow"] = slow
	return cfg


func _wall(cell: Vector2i) -> Dictionary:
	return {"type": "mucous_wall", "origin": cell}


func _sim(cfg: GameConfig, walls: Array, type_id: String = "rhinovirus", cell: Vector2i = UNIT_CELL) -> BattleSim:
	return SimFixtures.make_sim(walls, [{"type": type_id, "cell": cell}], 1, cfg)


## Steps until the unit first moves; returns how many steps it stood still (starting with step 1).
func _steps_rooted(sim: BattleSim, limit: int = 200) -> int:
	var start: Vector2i = sim.pathogen(1).pos
	var n: int = 0
	while n < limit:
		sim.step()
		if sim.pathogen(1).pos != start:
			return n
		n += 1
	return n


func test_default_data_has_the_trap_and_the_flag_is_off() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var wall: StructureDef = cfg.structures["mucous_wall"]
	assert_true(wall.has_trap)
	assert_eq(wall.trap_root_ticks, 2 * cfg.tick_rate)
	assert_eq(wall.trap_target_tags, PackedStringArray(["small"]))
	assert_false(cfg.flag("mucous_trap"))


func test_a_rhinovirus_is_rooted_for_exactly_the_root_ticks_then_moves_on() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, [_wall(WALL_CELL)])
	var root_ticks: int = cfg.structures["mucous_wall"].trap_root_ticks
	assert_eq(_steps_rooted(sim), root_ticks)
	assert_eq(sim.units_trapped, 1)
	for i: int in range(60):
		sim.step()
	assert_eq(sim.units_trapped, 1, "the same wall does not trap it again")
	assert_false(sim.status.has_flag(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED))


func test_a_second_wall_traps_it_again() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, [_wall(WALL_CELL), _wall(Vector2i(10, 12))])
	var root_ticks: int = cfg.structures["mucous_wall"].trap_root_ticks
	assert_eq(_steps_rooted(sim), 2 * root_ticks)
	assert_eq(sim.units_trapped, 2)


func test_a_unit_without_the_tag_is_never_trapped() -> void:
	var sim: BattleSim = _sim(_cfg(), [_wall(WALL_CELL)], "staphylococcus")
	for i: int in range(120):
		sim.step()
	assert_eq(sim.units_trapped, 0)


func test_a_unit_blocked_by_the_wall_is_trapped() -> void:
	var sim: BattleSim = _sim(_cfg(), [_wall(WALL_CELL)], "rhinovirus", Vector2i(10, 20))
	sim.pathogen(1).blocker_id = 1
	sim.step()
	assert_eq(sim.units_trapped, 1)
	assert_true(sim.status.has_flag(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED))


func test_the_trap_emits_an_event() -> void:
	var sim: BattleSim = _sim(_cfg(), [_wall(WALL_CELL)])
	sim.step()
	var found: Dictionary = {}
	for ev: Dictionary in sim.drain_events():
		if ev.get("type", "") == SimEvents.UNIT_TRAPPED:
			found = ev
	assert_false(found.is_empty())
	assert_eq(int(found["unit_id"]), 1)
	assert_eq(int(found["structure_id"]), 1)
	assert_eq(int(found["ticks"]), 40)


func test_flag_off_changes_nothing() -> void:
	var off: BattleSim = _sim(_cfg(false), [_wall(WALL_CELL)])
	var without_block_cfg: GameConfig = _cfg(false)
	without_block_cfg.structures["mucous_wall"].has_trap = false
	var plain: BattleSim = _sim(without_block_cfg, [_wall(WALL_CELL)])
	for i: int in range(80):
		off.step()
		plain.step()
	assert_eq(off.units_trapped, 0)
	assert_eq(off.state_hash(), plain.state_hash())
	assert_true(off._trap_cells.is_empty())


func test_trapped_battles_are_deterministic_and_differ_from_untrapped() -> void:
	var walls: Array = []
	for y: int in range(8, 14):
		walls.append(_wall(Vector2i(12, y)))
	var hashes: Array[String] = []
	for trap: bool in [true, true, false]:
		var sim: BattleSim = SimFixtures.make_sim(walls, [
			{"type": "rhinovirus", "cell": Vector2i(2, 10)},
			{"type": "rhinovirus", "cell": Vector2i(2, 11)},
		], 7, _cfg(trap))
		sim.run_to_end(400)
		hashes.append(sim.state_hash())
	assert_eq(hashes[0], hashes[1])
	assert_ne(hashes[0], hashes[2])


func test_slow_and_trap_together_are_deterministic() -> void:
	var walls: Array = []
	for y: int in range(8, 14):
		walls.append(_wall(Vector2i(12, y)))
	var hashes: Array[String] = []
	for i: int in range(2):
		var sim: BattleSim = SimFixtures.make_sim(walls, [
			{"type": "rhinovirus", "cell": Vector2i(2, 10)},
			{"type": "staphylococcus", "cell": Vector2i(2, 12)},
		], 7, _cfg(true, true))
		sim.run_to_end(600)
		hashes.append(sim.state_hash())
	assert_eq(hashes[0], hashes[1])


func test_a_destroyed_wall_no_longer_traps() -> void:
	var sim: BattleSim = _sim(_cfg(), [_wall(WALL_CELL)], "rhinovirus", Vector2i(10, 20))
	assert_true(sim._trap_cells.has(UNIT_CELL))
	sim._damage_structure(sim.structure(1), 100000, 0)
	assert_false(sim._trap_cells.has(UNIT_CELL))


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


func test_trap_validation() -> void:
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["trap"]["root_s"] = 0), "structures.json: mucous_wall.trap.root_s: must be > 0 (got 0)"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["trap"]["target_tags"] = []), "structures.json: mucous_wall.trap.target_tags: must be a non-empty array"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["trap"]["target_tags"] = ["weird"]), "structures.json: mucous_wall.trap.target_tags: unknown tag (got weird)"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["trap"]["bogus"] = 1), "structures.json: mucous_wall.trap.bogus: unknown key"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["trap"].erase("root_s")), "structures.json: mucous_wall.trap.root_s: missing required field"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"]["trap"] = "x"), "structures.json: mucous_wall.trap: must be a JSON object"))
	assert_true(_load_structures(func(s: Dictionary) -> void: s["mucous_wall"].erase("trap")).is_ok())
