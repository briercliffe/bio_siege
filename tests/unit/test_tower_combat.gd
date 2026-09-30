extends GutTest


func test_splash_damage() -> void:
	# 3x3 Macrophage at (10,5) hits 3 rooted units, unit outside splash untouched, splash event emitted
	var structs := [
		{"type": "macrophage", "origin": Vector2i(10, 5)},
		{"type": "nucleus", "origin": Vector2i(30, 30)}
	]
	var units := [
		{"type": "staphylococcus", "cell": Vector2i(14, 6)},
		{"type": "staphylococcus", "cell": Vector2i(15, 6)},
		{"type": "staphylococcus", "cell": Vector2i(14, 7)},
		{"type": "staphylococcus", "cell": Vector2i(14, 10)}
	]
	var sim := SimFixtures.make_sim(structs, units)

	# Root all units so they do not move
	for i in range(1, 5):
		sim.status.add(StatusEffects.key_pathogen(i), StatusEffects.Kind.ROOTED, 1, 100, "root")

	var u1 := sim.pathogen(1)
	var u2 := sim.pathogen(2)
	var u3 := sim.pathogen(3)
	var u4 := sim.pathogen(4)

	var u1_hp_before: int = u1.hp
	var u2_hp_before: int = u2.hp
	var u3_hp_before: int = u3.hp
	var u4_hp_before: int = u4.hp

	sim.step()

	var events := sim.drain_events()
	var splash_found: bool = false
	for ev: Dictionary in events:
		if ev.get("type") == SimEvents.SPLASH:
			splash_found = true
			assert_eq(ev.get("structure_id"), 1)
			assert_eq(ev.get("pos"), u1.pos)
			assert_eq(ev.get("radius"), 2000)
			var hits: Array = ev.get("hit_unit_ids", [])
			assert_eq(hits, [1, 2, 3])
			break

	assert_true(splash_found, "SPLASH event must be emitted")
	assert_eq(u1.hp, u1_hp_before - 40, "Unit 1 should take 40 splash damage")
	assert_eq(u2.hp, u2_hp_before - 40, "Unit 2 should take 40 splash damage")
	assert_eq(u3.hp, u3_hp_before - 40, "Unit 3 should take 40 splash damage")
	assert_eq(u4.hp, u4_hp_before, "Unit 4 outside splash should be untouched")


func test_projectile_flight() -> void:
	# 3x3 B-Cell at (10,3) vs rooted unit at (11,14) 10000 mt away: alive at 9 steps, dead at 10 steps, projectile_hit emitted
	var structs := [
		{"type": "b_cell", "origin": Vector2i(10, 3)},
		{"type": "nucleus", "origin": Vector2i(30, 30)}
	]
	var units := [
		{"type": "rhinovirus", "cell": Vector2i(11, 14)}
	]
	var sim := SimFixtures.make_sim(structs, units)
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100, "root")

	var unit := sim.pathogen(1)
	assert_eq(FixedMath.dist_sq(sim.structure(1).center, unit.pos), 100000000, "Distance should be exactly 10000 mt")

	# Run 9 steps
	for i in range(9):
		sim.step()

	assert_true(unit.alive, "Unit should be alive at 9 steps")
	assert_gt(unit.hp, 0, "Unit hp should be > 0 at 9 steps")
	assert_eq(sim.projectiles.size(), 1, "Projectile should still be in flight at 9 steps")

	# 10th step: projectile reaches target and hits
	sim.step()

	assert_false(unit.alive, "Unit should be dead at 10 steps")
	assert_eq(unit.hp, 0, "Unit hp should be 0 at 10 steps")

	var events := sim.drain_events()
	var hit_found: bool = false
	for ev: Dictionary in events:
		if ev.get("type") == SimEvents.PROJECTILE_HIT:
			hit_found = true
			assert_eq(ev.get("structure_id"), 1)
			assert_eq(ev.get("target_unit_id"), 1)
			break
	assert_true(hit_found, "PROJECTILE_HIT event must be emitted on 10th step")


func test_fizzle() -> void:
	# Target dies while projectile in flight -> projectile_fizzled, no damage
	var structs := [
		{"type": "b_cell", "origin": Vector2i(10, 3)},
		{"type": "nucleus", "origin": Vector2i(30, 30)}
	]
	var units := [
		{"type": "rhinovirus", "cell": Vector2i(11, 14)}
	]
	var sim := SimFixtures.make_sim(structs, units)
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100, "root")

	# Step 3 times to get projectile in flight
	for i in range(3):
		sim.step()

	assert_eq(sim.projectiles.size(), 1)
	assert_true(sim.projectiles[0].alive)

	# Kill the target externally
	var unit := sim.pathogen(1)
	sim.damage_pathogen(unit, 9999, 0)
	assert_false(unit.alive)

	sim.drain_events()

	# Next step: projectile should fizzle
	sim.step()

	assert_eq(sim.projectiles.size(), 0, "Dead projectile should be removed")

	var events := sim.drain_events()
	var fizzle_found: bool = false
	for ev: Dictionary in events:
		if ev.get("type") == SimEvents.PROJECTILE_FIZZLED:
			fizzle_found = true
			assert_eq(ev.get("structure_id"), 1)
			assert_eq(ev.get("target_unit_id"), 1)
			break
	assert_true(fizzle_found, "PROJECTILE_FIZZLED event must be emitted")


func test_cooldown() -> void:
	# B-Cell vs Staphylococcus: tower_fired at ticks 0, 24, 48 within 50 steps
	var structs := [
		{"type": "b_cell", "origin": Vector2i(10, 5)},
		{"type": "nucleus", "origin": Vector2i(30, 30)}
	]
	var units := [
		{"type": "staphylococcus", "cell": Vector2i(14, 6)}
	]
	var sim := SimFixtures.make_sim(structs, units)
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100, "root")

	var fired_ticks: Array[int] = []
	for i in range(50):
		sim.step()
		for ev: Dictionary in sim.drain_events():
			if ev.get("type") == SimEvents.TOWER_FIRED:
				fired_ticks.append(int(ev.get("tick", -1)))

	assert_eq(fired_ticks, [0, 24, 48], "tower_fired should occur at ticks 0, 24, 48 within 50 steps")


func test_target_lock() -> void:
	# Sticky targeting on nearer unit even when closer unit arrives
	var structs := [
		{"type": "b_cell", "origin": Vector2i(10, 10)},
		{"type": "nucleus", "origin": Vector2i(30, 30)}
	]
	var units := [
		{"type": "staphylococcus", "cell": Vector2i(11, 15)}, # 4000 mt away (in range)
		{"type": "staphylococcus", "cell": Vector2i(11, 26)}  # 15000 mt away (out of range of 12000)
	]
	var sim := SimFixtures.make_sim(structs, units)
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100, "root")
	sim.status.add(StatusEffects.key_pathogen(2), StatusEffects.Kind.ROOTED, 1, 100, "root")

	var tower := sim.structure(1)

	# Step 1: acquires target 1
	sim.step()
	assert_eq(tower.target_id, 1, "Tower should target unit 1")

	# Now place unit 2 at (11, 13), only 2000 mt away (much closer than unit 1 at 4000 mt)
	var u2 := sim.pathogen(2)
	u2.pos = FixedMath.cell_center(Vector2i(11, 13))
	u2.cell = Vector2i(11, 13)

	# Step a few more times: tower must remain locked on unit 1
	for i in range(5):
		sim.step()
		assert_eq(tower.target_id, 1, "Tower should maintain target lock on unit 1")


func test_out_of_range() -> void:
	# Switching target when locked target leaves range
	var structs := [
		{"type": "b_cell", "origin": Vector2i(10, 10)},
		{"type": "nucleus", "origin": Vector2i(30, 30)}
	]
	var units := [
		{"type": "staphylococcus", "cell": Vector2i(11, 13)}, # 2000 mt away
		{"type": "staphylococcus", "cell": Vector2i(11, 17)}  # 6000 mt away
	]
	var sim := SimFixtures.make_sim(structs, units)
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100, "root")
	sim.status.add(StatusEffects.key_pathogen(2), StatusEffects.Kind.ROOTED, 1, 100, "root")

	var tower := sim.structure(1)

	# Step 1: picks unit 1 as closest
	sim.step()
	assert_eq(tower.target_id, 1, "Tower should initially target unit 1")

	# Move unit 1 out of range (15000 mt away, > 12000 mt range)
	var u1 := sim.pathogen(1)
	u1.pos = Vector2i(11500, 26500)
	u1.cell = Vector2i(11, 26)

	# Step: tower should retarget to unit 2
	sim.step()
	assert_eq(tower.target_id, 2, "Tower should switch target to unit 2 when unit 1 is out of range")


func test_disabled_status() -> void:
	# Cooldown frozen / no firing during disabled duration
	var structs := [
		{"type": "b_cell", "origin": Vector2i(10, 5)},
		{"type": "nucleus", "origin": Vector2i(30, 30)}
	]
	var units := [
		{"type": "staphylococcus", "cell": Vector2i(14, 6)}
	]
	var sim := SimFixtures.make_sim(structs, units)
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100, "root")

	var tower := sim.structure(1)

	# Tick 0: tower fires, cooldown set to 24
	sim.step()
	assert_eq(tower.attack_cooldown, 24)

	# Add DISABLED status for 5 ticks
	sim.status.add(StatusEffects.key_structure(tower.id), StatusEffects.Kind.DISABLED, 1, 5, "emp")

	sim.drain_events()

	# Run 3 steps: cooldown should remain frozen at 24, no firing events
	for i in range(3):
		sim.step()
		assert_eq(tower.attack_cooldown, 24, "Cooldown should be frozen while DISABLED")
		var events := sim.drain_events()
		for ev: Dictionary in events:
			assert_ne(ev.get("type"), SimEvents.TOWER_FIRED, "Tower should not fire while DISABLED")

	# Wait until DISABLED wears off and tower shoots again
	var fired: bool = false
	for i in range(50):
		sim.step()
		for ev: Dictionary in sim.drain_events():
			if ev.get("type") == SimEvents.TOWER_FIRED:
				fired = true
				break
		if fired:
			break

	assert_true(fired, "Tower should resume firing after DISABLED expires")


func test_full_battle_smoke_test() -> void:
	# 2 B-Cells, 1 Macrophage, 20 Rhinoviruses: ends before timeout, deterministic
	var structs := [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "b_cell", "origin": Vector2i(12, 18)},
		{"type": "b_cell", "origin": Vector2i(24, 18)},
		{"type": "macrophage", "origin": Vector2i(18, 14)}
	]
	var units: Array = []
	for x in range(20):
		units.append({"type": "rhinovirus", "cell": Vector2i(x * 2, 0)})

	var sim1 := SimFixtures.make_sim(structs, units, 42)
	var sim2 := SimFixtures.make_sim(structs, units, 42)

	sim1.run_to_end()
	sim2.run_to_end()

	assert_true(sim1.finished, "Simulation 1 should finish")
	assert_true(sim2.finished, "Simulation 2 should finish")
	assert_lt(sim1.tick, sim1.config.battle_timeout_ticks, "Simulation 1 should end before timeout")
	assert_ne(sim1.end_reason, "timeout", "End reason should not be timeout")
	assert_eq(sim1.state_hash(), sim2.state_hash(), "Simulations with same seed must be deterministic")
	assert_eq(sim1.outcome, sim2.outcome, "Both simulations should have same outcome")
	assert_eq(sim1.end_reason, sim2.end_reason, "Both simulations should have same end reason")
	assert_eq(sim1.pathogens_killed, 20, "All 20 rhinoviruses should be killed by defenders")
	assert_eq(sim1.outcome, "defender", "Defenders should win")
