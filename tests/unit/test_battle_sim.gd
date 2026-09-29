extends GutTest

func test_walk_and_first_hit() -> void:
	var sim := SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(0, 10)}])
	for i in range(65):
		sim.step()

	var nucleus := sim.structure(sim.nucleus_id)
	assert_not_null(nucleus)
	assert_eq(nucleus.hp, 1994, "Nucleus hp after 65 steps should be 1994")

	var unit := sim.pathogen(1)
	assert_not_null(unit)
	assert_eq(unit.state, PathogenState.State.ATTACKING, "Unit state should be ATTACKING")
	assert_eq(unit.target_id, 1, "Unit target_id should be 1")
	assert_eq(unit.pos, Vector2i(8500, 10500), "Unit pos should be (8500, 10500)")
	assert_eq(sim.first_contact_tick, 64, "First contact tick should be 64")

	for i in range(10):
		sim.step()

	assert_eq(nucleus.hp, 1988, "Nucleus hp after 75 steps should be 1988")


func test_blocker() -> void:
	var walls: Array = []
	for y in range(1, 19):
		walls.append({"type": "mucous_wall", "origin": Vector2i(5, y)})
	var sim := SimFixtures.make_sim(walls, [{"type": "rhinovirus", "cell": Vector2i(0, 10)}])

	while sim.pathogen(1).state != PathogenState.State.ATTACKING and sim.tick < 50:
		sim.step()

	var unit := sim.pathogen(1)
	assert_eq(unit.state, PathogenState.State.ATTACKING)
	assert_eq(unit.target_id, sim.nucleus_id)
	var wall_id := sim.structure_id_at(Vector2i(5, 10))
	assert_eq(unit.blocker_id, wall_id)

	var events := sim.drain_events()
	var blocked_event_found: bool = false
	for ev: Dictionary in events:
		if ev.get("type") == SimEvents.UNIT_BLOCKED and ev.get("blocker_id") == wall_id:
			blocked_event_found = true
			break
	assert_true(blocked_event_found, "unit_blocked event should be emitted")

	var wall := sim.structure(wall_id)
	while wall.alive and not sim.finished:
		sim.step()

	assert_false(wall.alive, "Wall should be destroyed")

	if unit.blocker_id != 0 or unit.path_version != sim.path_service.grid_version:
		sim.step()

	assert_eq(unit.blocker_id, 0, "blocker_id should be 0 within 1 tick of destruction")
	assert_eq(unit.path_version, sim.path_service.grid_version, "path_version should match new grid_version")

	var nucleus := sim.structure(sim.nucleus_id)
	while nucleus.hp == nucleus.max_hp and not sim.finished and sim.tick < 1000:
		sim.step()

	assert_lt(nucleus.hp, nucleus.max_hp, "Unit should eventually damage the Nucleus")


func test_retarget_mid_walk() -> void:
	var structs := [
		{"type": "b_cell", "origin": Vector2i(2, 10)},
		{"type": "nucleus", "origin": Vector2i(9, 9)}
	]
	var units := [{"type": "rhinovirus", "cell": Vector2i(0, 10)}]
	var sim := SimFixtures.make_sim(structs, units)

	for i in range(3):
		sim.step()

	var unit := sim.pathogen(1)
	assert_eq(unit.pos, Vector2i(875, 10500))
	assert_ne(unit.pos, FixedMath.cell_center(unit.cell))

	var b_cell := sim.structure(1)
	assert_eq(unit.target_id, b_cell.id)

	sim._damage_structure(b_cell, 9999, 0)
	assert_false(b_cell.alive)

	sim.step()
	assert_eq(unit.target_id, sim.nucleus_id)
	assert_eq(unit.pos, Vector2i(1000, 10500))

	while unit.pos != Vector2i(1500, 10500):
		sim.step()

	assert_eq(unit.pos, Vector2i(1500, 10500))
	assert_eq(unit.cell, Vector2i(1, 10))

	sim.step()
	assert_eq(unit.path_version, sim.path_service.grid_version)
	assert_ne(unit.state, PathogenState.State.DEAD)
	assert_gt(unit.pos.x, 1500, "Unit should continue moving towards Nucleus")

	var nucleus := sim.structure(sim.nucleus_id)
	while nucleus.hp == nucleus.max_hp and not sim.finished and sim.tick < 200:
		sim.step()

	assert_lt(nucleus.hp, nucleus.max_hp, "Unit should eventually damage Nucleus after retargeting")


func test_damage_multiplier() -> void:
	var sim_bcell := SimFixtures.make_sim(
		[{"type": "b_cell", "origin": Vector2i(2, 2)}],
		[{"type": "bacteriophage", "cell": Vector2i(1, 2)}]
	)
	sim_bcell.step()
	var b_cell := sim_bcell.structure(1)
	assert_eq(b_cell.max_hp - b_cell.hp, 60, "Bacteriophage vs B-Cell should deal 60 damage")

	var sim_nuc := SimFixtures.make_sim(
		[{"type": "nucleus", "origin": Vector2i(9, 9)}],
		[{"type": "bacteriophage", "cell": Vector2i(8, 9)}]
	)
	sim_nuc.step()
	var nucleus := sim_nuc.structure(sim_nuc.nucleus_id)
	assert_eq(nucleus.max_hp - nucleus.hp, 20, "Bacteriophage vs Nucleus should deal 20 damage")


func test_end_attacker() -> void:
	var sim := SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(8, 9)}])
	var nuc := sim.structure(sim.nucleus_id)
	nuc.hp = 6
	sim.run_to_end()

	assert_true(sim.finished)
	assert_eq(sim.outcome, "attacker")
	assert_eq(sim.end_reason, "nucleus_destroyed")


func test_end_empty_army() -> void:
	var sim := SimFixtures.make_sim([], [])
	sim.step()

	assert_true(sim.finished)
	assert_eq(sim.outcome, "defender")
	assert_eq(sim.end_reason, "all_pathogens_dead")


func test_end_timeout() -> void:
	var res := GameConfig.load_from_dir("res://data")
	var cfg: GameConfig = res.config
	cfg.battle_timeout_ticks = 50

	var sim := SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(0, 0)}], 1, cfg)
	sim.run_to_end()

	assert_true(sim.finished)
	assert_eq(sim.outcome, "defender")
	assert_eq(sim.end_reason, "timeout")
	assert_eq(sim.tick, 50)


func test_budget() -> void:
	var res := GameConfig.load_from_dir("res://data")
	var cfg: GameConfig = res.config
	cfg.max_path_recalcs_per_tick = 20

	var units: Array = []
	for x in range(20):
		units.append({"type": "rhinovirus", "cell": Vector2i(x, 0)})
	for y in range(1, 11):
		units.append({"type": "rhinovirus", "cell": Vector2i(19, y)})

	var sim := SimFixtures.make_sim([], units, 1, cfg)

	sim.step()
	assert_lte(sim.path_service.computations_this_tick, 20)
	for i in range(1, 21):
		assert_gt(sim.pathogen(i).path.size(), 0, "Unit %d should have computed path on tick 1" % i)
		assert_eq(sim.pathogen(i).state, PathogenState.State.MOVING)
	for i in range(21, 31):
		assert_eq(sim.pathogen(i).path.size(), 0, "Unit %d should have empty path on tick 1" % i)
		assert_eq(sim.pathogen(i).state, PathogenState.State.SEEKING)

	sim.step()
	assert_lte(sim.path_service.computations_this_tick, 20)
	for i in range(1, 31):
		assert_gt(sim.pathogen(i).path.size(), 0, "All 30 units should have paths after step 2 (unit %d)" % i)


func test_status_hooks() -> void:
	var sim_root := SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(0, 10)}])
	var key := StatusEffects.key_pathogen(1)
	sim_root.status.add(key, StatusEffects.Kind.ROOTED, 1, 100, "root_effect")
	var initial_pos := sim_root.pathogen(1).pos
	for i in range(5):
		sim_root.step()
	assert_eq(sim_root.pathogen(1).pos, initial_pos, "ROOTED unit pos must not change over 5 steps")

	var sim_speed := SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(0, 10)}])
	sim_speed.status.add(key, StatusEffects.Kind.SPEED_PCT, 50, 100, "slow_effect")
	var speed_start_pos := sim_speed.pathogen(1).pos
	sim_speed.step()
	assert_eq(sim_speed.pathogen(1).pos, speed_start_pos + Vector2i(62, 0), "SPEED_PCT 50 unit should move 62 mt in one step")


func test_determinism() -> void:
	var units := [
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "bacteriophage", "cell": Vector2i(19, 10)}
	]
	var walls: Array = []
	for y in range(5, 15):
		walls.append({"type": "mucous_wall", "origin": Vector2i(5, y)})

	var sim1 := SimFixtures.make_sim(walls, units, 999)
	var sim2 := SimFixtures.make_sim(walls, units, 999)

	for i in range(10):
		sim1.step()
	var hash_10 := sim1.state_hash()

	for i in range(10):
		sim1.step()
	var hash_20 := sim1.state_hash()

	assert_ne(hash_10, hash_20, "State hash should change between tick 10 and tick 20")

	for i in range(280):
		sim1.step()

	for i in range(300):
		sim2.step()

	assert_eq(sim1.state_hash(), sim2.state_hash(), "Two identical setups must produce identical state hash after 300 steps")


func test_drain_events() -> void:
	var sim := SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(0, 10)}])
	var events1 := sim.drain_events()
	assert_gt(events1.size(), 0, "First drain_events call should return events")
	var events2 := sim.drain_events()
	assert_eq(events2.size(), 0, "Second drain_events call must return empty array")


func test_performance_100_units_20_structures() -> void:
	var structs: Array = []
	for x in range(1, 10):
		structs.append({"type": "mucous_wall", "origin": Vector2i(x, 5)})
		structs.append({"type": "mucous_wall", "origin": Vector2i(x, 15)})
	structs.append({"type": "b_cell", "origin": Vector2i(5, 8)})

	var units: Array = []
	for x in range(20):
		units.append({"type": "rhinovirus", "cell": Vector2i(x, 0)})
		units.append({"type": "rhinovirus", "cell": Vector2i(x, 19)})
	for y in range(1, 19):
		units.append({"type": "rhinovirus", "cell": Vector2i(0, y)})
		units.append({"type": "rhinovirus", "cell": Vector2i(19, y)})
	for x in range(1, 13):
		units.append({"type": "rhinovirus", "cell": Vector2i(x, 1)})
		units.append({"type": "rhinovirus", "cell": Vector2i(x, 18)})

	var sim := SimFixtures.make_sim(structs, units, 42)
	sim.structure(sim.nucleus_id).hp = 999999
	sim.structure(sim.nucleus_id).max_hp = 999999
	var t0 := Time.get_ticks_msec()
	sim.run_to_end(3600)
	var elapsed_ms := Time.get_ticks_msec() - t0
	print("Performance test: 100 units, 20 structures ran %d ticks in %d ms" % [sim.tick, elapsed_ms])
	assert_gt(sim.tick, 0)
