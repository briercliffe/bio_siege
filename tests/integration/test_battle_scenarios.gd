extends GutTest

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func _run_sim_to_finish(sim: BattleSim, max_ticks: int = -1) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.append_array(sim.drain_events())
	var ticks_run: int = 0
	while not sim.finished and (max_ticks < 0 or ticks_run < max_ticks):
		sim.step()
		ticks_run += 1
		events.append_array(sim.drain_events())
	return events


func _format_structure_events(sim: BattleSim, events: Array[Dictionary], max_count: int = 10) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var count: int = 0
	for ev: Dictionary in events:
		if ev.has("structure_id"):
			var sid: int = int(ev.get("structure_id", 0))
			var s: StructureState = sim.structure(sid)
			var cell_str: String = str(s.origin) if s != null else "?"
			lines.append("%d: %s %d %s" % [int(ev.get("tick", 0)), str(ev.get("type", "")), sid, cell_str])
			count += 1
			if count >= max_count:
				break
	return "\n".join(lines)


func test_open_field() -> void:
	var setup := Scenarios.open_field()
	var sim := BattleSim.new(config, setup)
	var events := _run_sim_to_finish(sim)

	assert_true(sim.finished, "Sim should finish")
	assert_eq(sim.outcome, "attacker", "Outcome should be attacker")
	assert_eq(sim.end_reason, "nucleus_destroyed", "End reason should be nucleus_destroyed")
	assert_lt(sim.tick, 1200, "Tick should be < 1200")

	var unit_damage_counts: Dictionary = {}
	for ev: Dictionary in events:
		if ev.get("type") == SimEvents.STRUCTURE_DAMAGED:
			assert_eq(ev.get("structure_id"), 1, "Every structure_damaged event must target Nucleus (id 1)")
			var uid: int = int(ev.get("source_unit_id", 0))
			unit_damage_counts[uid] = int(unit_damage_counts.get(uid, 0)) + 1

	for uid in range(1, 6):
		assert_gt(int(unit_damage_counts.get(uid, 0)), 0, "Unit %d should appear as source_unit_id at least once" % uid)


func test_walled_nucleus() -> void:
	var setup := Scenarios.walled_nucleus()
	var sim := BattleSim.new(config, setup)
	var events := _run_sim_to_finish(sim)

	assert_true(sim.finished, "Sim should finish")
	assert_eq(sim.outcome, "attacker", "Outcome should be attacker")
	assert_lt(sim.tick, config.battle_timeout_ticks, "Outcome should be attacker before timeout")

	var first_destroyed_id: int = 0
	for ev: Dictionary in events:
		if ev.get("type") == SimEvents.STRUCTURE_DESTROYED:
			first_destroyed_id = int(ev.get("structure_id", 0))
			break

	assert_gt(first_destroyed_id, 0, "At least one structure should be destroyed.\n" + _format_structure_events(sim, events))
	var s: StructureState = sim.structure(first_destroyed_id)
	assert_not_null(s)
	if s != null:
		assert_eq(s.type_id, "mucous_wall")
		assert_eq(s.origin, Vector2i(8, 10), "First structure_destroyed must be the wall at (8, 10).\n" + _format_structure_events(sim, events))


func test_short_wall() -> void:
	var setup := Scenarios.short_wall()
	var sim := BattleSim.new(config, setup)
	var all_events: Array[Dictionary] = []
	all_events.append_array(sim.drain_events())

	var nucleus_damaged_within_600: bool = false
	while not sim.finished and sim.tick < 600:
		sim.step()
		var step_events := sim.drain_events()
		for ev in step_events:
			if ev.get("type") == SimEvents.STRUCTURE_DAMAGED:
				var sid: int = int(ev.get("structure_id", 0))
				var s: StructureState = sim.structure(sid)
				if s != null and s.type_id == "mucous_wall":
					assert_true(false, "No wall should be damaged during first 600 ticks, but wall at %s was damaged at tick %d.\n%s" % [
						str(s.origin),
						sim.tick,
						_format_structure_events(sim, step_events)
					])
				if sid == sim.nucleus_id:
					nucleus_damaged_within_600 = true
		all_events.append_array(step_events)

	assert_true(nucleus_damaged_within_600, "Nucleus must be damaged within the first 600 ticks")


func test_long_wall() -> void:
	var setup := Scenarios.long_wall()
	var sim := BattleSim.new(config, setup)
	var events := _run_sim_to_finish(sim)

	var first_destroyed_id: int = 0
	for ev: Dictionary in events:
		if ev.get("type") == SimEvents.STRUCTURE_DESTROYED:
			first_destroyed_id = int(ev.get("structure_id", 0))
			break

	assert_gt(first_destroyed_id, 0, "At least one structure should be destroyed.\n" + _format_structure_events(sim, events))
	var s: StructureState = sim.structure(first_destroyed_id)
	assert_not_null(s)
	if s != null:
		assert_eq(s.type_id, "mucous_wall")
		assert_eq(s.origin, Vector2i(5, 10), "First structure_destroyed must be the wall at (5, 10).\n" + _format_structure_events(sim, events))


func test_bacteriophage_priority() -> void:
	var setup := Scenarios.phage_priority()
	var sim := BattleSim.new(config, setup)

	sim.step()
	var step1_events := sim.drain_events()
	var b_cell_id: int = 2
	for i in range(1, 6):
		var p: PathogenState = sim.pathogen(i)
		assert_not_null(p)
		assert_eq(p.target_id, b_cell_id, "After step 1, bacteriophage %d target_id must be B-Cell id (%d)" % [i, b_cell_id])

	var all_events: Array[Dictionary] = []
	all_events.append_array(step1_events)

	var b_cell_destroyed: bool = false
	while not sim.finished:
		sim.step()
		var step_events := sim.drain_events()
		for ev in step_events:
			if ev.get("type") == SimEvents.STRUCTURE_DESTROYED and int(ev.get("structure_id", 0)) == b_cell_id:
				b_cell_destroyed = true
			if ev.get("type") == SimEvents.STRUCTURE_DAMAGED and int(ev.get("structure_id", 0)) == sim.nucleus_id:
				assert_true(b_cell_destroyed, "Nucleus (id 1) was damaged at tick %d before B-Cell was destroyed.\n%s" % [
					int(ev.get("tick", sim.tick)),
					_format_structure_events(sim, all_events)
				])
		all_events.append_array(step_events)

	assert_true(b_cell_destroyed, "B-Cell should have been destroyed during the battle")


func test_determinism_mixed() -> void:
	var setup1 := Scenarios.mixed([], 1)
	var setup2 := Scenarios.mixed([], 1)
	var sim1 := BattleSim.new(config, setup1)
	var sim2 := BattleSim.new(config, setup2)

	var events1: Array[Dictionary] = []
	var events2: Array[Dictionary] = []
	events1.append_array(sim1.drain_events())
	events2.append_array(sim2.drain_events())

	while not sim1.finished or not sim2.finished:
		if not sim1.finished:
			sim1.step()
			events1.append_array(sim1.drain_events())
		if not sim2.finished:
			sim2.step()
			events2.append_array(sim2.drain_events())

		if sim1.tick % 100 == 0:
			assert_eq(sim1.state_hash(), sim2.state_hash(), "state_hash() must match at tick %d" % sim1.tick)

	assert_eq(sim1.finished, true, "sim1 should finish")
	assert_eq(sim2.finished, true, "sim2 should finish")
	assert_eq(sim1.outcome, sim2.outcome, "Outcome must be identical")
	assert_eq(sim1.end_reason, sim2.end_reason, "End reason must be identical")
	assert_eq(sim1.tick, sim2.tick, "End tick must be identical")
	assert_eq(sim1.state_hash(), sim2.state_hash(), "Final state_hash() must be identical")
	assert_eq(events1.size(), events2.size(), "Total event count must be identical")


func test_path_budget_mixed() -> void:
	var setup := Scenarios.mixed([], 1)
	var sim := BattleSim.new(config, setup)

	while not sim.finished:
		sim.step()
		assert_lte(sim.path_service.computations_this_tick, config.max_path_recalcs_per_tick,
			"computations_this_tick (%d) exceeded max budget (%d) at tick %d" % [
				sim.path_service.computations_this_tick,
				config.max_path_recalcs_per_tick,
				sim.tick
			])


func test_no_recalcs_on_quiet_ticks() -> void:
	var setup := Scenarios.open_field()
	var sim := BattleSim.new(config, setup)
	var nuc: StructureState = sim.structure(sim.nucleus_id)
	assert_not_null(nuc)
	nuc.hp = 100000
	nuc.max_hp = 100000

	while not sim.finished and sim.tick < 600:
		sim.step()
		if sim.tick >= 20 and sim.tick <= 600:
			assert_eq(sim.path_service.computations_this_tick, 0,
				"computations_this_tick must be 0 on quiet tick %d (got %d)" % [
					sim.tick,
					sim.path_service.computations_this_tick
				])


func test_setup_validity() -> void:
	var scenario_list: Array[BattleSetup] = [
		Scenarios.open_field(),
		Scenarios.walled_nucleus(),
		Scenarios.short_wall(),
		Scenarios.long_wall(),
		Scenarios.phage_priority(),
		Scenarios.mixed(),
	]
	for s: BattleSetup in scenario_list:
		var errors: PackedStringArray = s.validate(config)
		assert_eq(errors.size(), 0, "Scenario should have no validation errors, got: %s" % str(errors))
