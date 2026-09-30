extends GutTest

const ATTACKING: PathogenState.State = PathogenState.State.ATTACKING
const MOVING: PathogenState.State = PathogenState.State.MOVING

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func _rhino_sim() -> BattleSim:
	return SimFixtures.make_sim([], [{"type": "rhinovirus", "cell": Vector2i(3, 3)}], 1, config)


func test_windup_table() -> void:
	assert_eq(AnimDriver.windup_ticks(10), 4)
	assert_eq(AnimDriver.windup_ticks(20), 8)
	assert_eq(AnimDriver.windup_ticks(24), 9)
	assert_eq(AnimDriver.windup_ticks(30), 12)
	assert_eq(AnimDriver.windup_ticks(60), 12)


func test_recover_ticks_fit_inside_the_interval() -> void:
	for interval: int in [10, 20, 24, 30]:
		var rec: int = AnimDriver.recover_ticks(interval)
		assert_gt(rec, 0)
		assert_true(AnimDriver.windup_ticks(interval) + rec <= interval)


func test_impact_is_a_strike_on_the_damage_tick() -> void:
	var r: Vector2 = AnimDriver.pathogen_attack(ATTACKING, 20, 20, 0)
	assert_eq(int(r.x), ModelPose.Anim.STRIKE)
	assert_almost_eq(r.y, 0.5, 0.0001)


func test_recover_follows_the_strike() -> void:
	var rec: int = AnimDriver.recover_ticks(20)
	var r: Vector2 = AnimDriver.pathogen_attack(ATTACKING, 20, 20, rec)
	assert_eq(int(r.x), ModelPose.Anim.RECOVER)
	assert_almost_eq(r.y, 1.0, 0.0001)
	var r1: Vector2 = AnimDriver.pathogen_attack(ATTACKING, 19, 20, 1)
	assert_eq(int(r1.x), ModelPose.Anim.RECOVER)
	assert_gt(r1.y, 0.6)


func test_windup_edge() -> void:
	var at_edge: Vector2 = AnimDriver.pathogen_attack(ATTACKING, 8, 20, 99)
	assert_eq(int(at_edge.x), ModelPose.Anim.WINDUP)
	assert_almost_eq(at_edge.y, 0.0, 0.0001)
	var before: Vector2 = AnimDriver.pathogen_attack(ATTACKING, 9, 20, 99)
	assert_ne(int(before.x), ModelPose.Anim.WINDUP)
	var ready: Vector2 = AnimDriver.pathogen_attack(ATTACKING, 0, 20, 99)
	assert_eq(int(ready.x), ModelPose.Anim.WINDUP)
	assert_almost_eq(ready.y, 0.4, 0.0001)


func test_moving_and_idle() -> void:
	assert_eq(int(AnimDriver.pathogen_attack(MOVING, 0, 20, 99).x), ModelPose.Anim.MOVE)
	assert_eq(int(AnimDriver.pathogen_attack(PathogenState.State.SEEKING, 0, 20, 99).x), ModelPose.Anim.IDLE)


func test_gait_advances_wraps_and_holds_when_stopped() -> void:
	assert_almost_eq(AnimDriver.advance_gait(0.0, 0.8, 1.6), 0.5, 0.0001)
	assert_almost_eq(AnimDriver.advance_gait(0.75, 0.8, 1.6), 0.25, 0.0001)
	assert_eq(AnimDriver.advance_gait(0.3, 0.0, 1.6), 0.3)


func test_facing_flips_across_the_unit_and_holds_near_zero() -> void:
	var unit := Vector2(10.0, 10.0)
	assert_true(AnimDriver.facing_right(unit, Vector2(14.0, 10.0), false), "target to screen-right")
	assert_false(AnimDriver.facing_right(unit, Vector2(10.0, 14.0), true), "target to screen-left")
	assert_true(AnimDriver.facing_right(unit, Vector2(14.0, 14.0), true), "dx 0 keeps current")
	assert_false(AnimDriver.facing_right(unit, Vector2(14.0, 14.0), false), "dx 0 keeps current")
	assert_true(AnimDriver.facing_right(unit, Vector2(10.004, 10.0), true))


func test_reduce_flashes() -> void:
	assert_eq(AnimDriver.flash_amount(0, true), 0.0)
	assert_eq(AnimDriver.flash_amount(0, false), 1.0)
	assert_eq(AnimDriver.shake_amount(0, true), 0.5 * AnimDriver.shake_amount(0, false))
	assert_eq(AnimDriver.flash_amount(AnimDriver.HIT_DECAY_TICKS, false), 0.0)
	assert_eq(AnimDriver.flash_amount(99, false), 0.0)


func test_death_t_clamps() -> void:
	assert_eq(AnimDriver.death_t(0, 8), 0.0)
	assert_almost_eq(AnimDriver.death_t(4, 8), 0.5, 0.0001)
	assert_eq(AnimDriver.death_t(80, 8), 1.0)


func test_view_rng_is_deterministic_and_in_range() -> void:
	assert_eq(ViewRng.hash01(7, 1), ViewRng.hash01(7, 1))
	assert_ne(ViewRng.hash01(7, 1), ViewRng.hash01(8, 1))
	assert_ne(ViewRng.hash01(7, 1), ViewRng.hash01(7, 2))
	for i: int in range(200):
		var v: float = ViewRng.hash01(i, 3)
		assert_true(v >= 0.0 and v < 1.0)


func test_pose_strikes_on_the_damage_event_then_recovers() -> void:
	var sim: BattleSim = _rhino_sim()
	var p: PathogenState = sim.pathogens[0]
	p.state = ATTACKING
	p.blocker_id = sim.nucleus_id
	p.attack_cooldown = 10
	var driver := AnimDriver.new()
	driver.on_event({"type": SimEvents.STRUCTURE_DAMAGED, "tick": 4, "structure_id": sim.nucleus_id, "source_unit_id": p.id})
	var pose: ModelPose = driver.pose_for_pathogen(p, 5, Vector2(3.5, 3.5), Vector2(18.0, 18.0), 0.0, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.STRIKE)
	assert_same(driver.pose_for_pathogen(p, 6, Vector2(3.5, 3.5), Vector2(18.0, 18.0), 0.0, 0.0), pose, "pose object is reused")
	assert_eq(pose.anim, ModelPose.Anim.RECOVER)
	assert_true(pose.attack_t >= 0.0 and pose.attack_t <= 1.0)


func test_hit_reaction_layers_on_top_and_decays() -> void:
	var sim: BattleSim = _rhino_sim()
	var p: PathogenState = sim.pathogens[0]
	var driver := AnimDriver.new()
	driver.on_event({"type": SimEvents.PATHOGEN_DAMAGED, "tick": 9, "unit_id": p.id})
	var pose: ModelPose = driver.pose_for_pathogen(p, 10, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
	assert_eq(pose.hit_t, 1.0)
	assert_eq(pose.shake, 1.0)
	assert_eq(pose.anim, ModelPose.Anim.IDLE)
	driver.pose_for_pathogen(p, 10 + AnimDriver.HIT_DECAY_TICKS, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
	assert_eq(pose.hit_t, 0.0)
	var calm := AnimDriver.new(true)
	calm.on_event({"type": SimEvents.PATHOGEN_DAMAGED, "tick": 9, "unit_id": p.id})
	var calm_pose: ModelPose = calm.pose_for_pathogen(p, 10, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
	assert_eq(calm_pose.hit_t, 0.0)
	assert_eq(calm_pose.shake, 0.5)


func test_death_is_permanent() -> void:
	var sim: BattleSim = _rhino_sim()
	var p: PathogenState = sim.pathogens[0]
	var driver := AnimDriver.new()
	driver.on_event({"type": SimEvents.PATHOGEN_KILLED, "tick": 9, "unit_id": p.id})
	var pose: ModelPose = driver.pose_for_pathogen(p, 10, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.DEAD)
	assert_eq(pose.death_t, 0.0)
	driver.on_event({"type": SimEvents.STRUCTURE_DAMAGED, "tick": 12, "structure_id": 1, "source_unit_id": p.id})
	driver.on_event({"type": SimEvents.PATHOGEN_DAMAGED, "tick": 12, "unit_id": p.id})
	driver.pose_for_pathogen(p, 500, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.DEAD)
	assert_eq(pose.death_t, 1.0)


func test_gait_uses_the_type_stride() -> void:
	var sim: BattleSim = SimFixtures.make_sim([], [{"type": "bacteriophage", "cell": Vector2i(3, 3)}], 1, config)
	var p: PathogenState = sim.pathogens[0]
	p.state = MOVING
	var driver := AnimDriver.new()
	var pose: ModelPose = driver.pose_for_pathogen(p, 1, Vector2.ZERO, Vector2.ZERO, 1.0, 0.0)
	assert_almost_eq(pose.gait_phase, 0.5, 0.0001)
	driver.pose_for_pathogen(p, 2, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
	assert_almost_eq(pose.gait_phase, 0.5, 0.0001)


func test_idle_time_is_desynchronised_per_entity() -> void:
	var sim: BattleSim = SimFixtures.make_sim([], [
		{"type": "rhinovirus", "cell": Vector2i(3, 3)},
		{"type": "rhinovirus", "cell": Vector2i(4, 3)},
	], 1, config)
	var driver := AnimDriver.new()
	var a: ModelPose = driver.pose_for_pathogen(sim.pathogens[0], 1, Vector2.ZERO, Vector2.ZERO, 0.0, 2.0)
	var b: ModelPose = driver.pose_for_pathogen(sim.pathogens[1], 1, Vector2.ZERO, Vector2.ZERO, 0.0, 2.0)
	assert_ne(a.time, b.time)
	assert_eq(a.seed, sim.pathogens[0].id)


func _tower(sim: BattleSim, type_id: String) -> StructureState:
	for s: StructureState in sim.structures:
		if s.type_id == type_id:
			return s
	return null


func test_macrophage_windup_strike_recover() -> void:
	var sim: BattleSim = SimFixtures.make_sim(
		[{"type": "macrophage", "origin": Vector2i(10, 10)}],
		[{"type": "rhinovirus", "cell": Vector2i(14, 10)}], 1, config)
	var tower: StructureState = _tower(sim, "macrophage")
	tower.target_id = sim.pathogens[0].id
	var interval: int = tower.def.attack_interval_ticks
	var driver := AnimDriver.new()
	var aim_at := Vector2(14.5, 10.5)
	tower.attack_cooldown = AnimDriver.windup_ticks(interval) + 1
	assert_eq(driver.pose_for_structure(tower, 10, aim_at, 0.0).anim, ModelPose.Anim.IDLE)
	tower.attack_cooldown = AnimDriver.windup_ticks(interval)
	var pose: ModelPose = driver.pose_for_structure(tower, 10, aim_at, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.WINDUP)
	assert_almost_eq(pose.attack_t, 0.0, 0.0001)
	assert_almost_eq(pose.aim.length(), 1.0, 0.0001)
	assert_gt(pose.aim.x, 0.0)
	driver.on_event({"type": SimEvents.TOWER_FIRED, "tick": 10, "structure_id": tower.id})
	tower.attack_cooldown = interval
	assert_eq(driver.pose_for_structure(tower, 11, aim_at, 0.0).anim, ModelPose.Anim.STRIKE)
	assert_eq(driver.pose_for_structure(tower, 12, aim_at, 0.0).anim, ModelPose.Anim.RECOVER)


func test_bcell_charge_ramp_and_recoil() -> void:
	var sim: BattleSim = SimFixtures.make_sim(
		[{"type": "b_cell", "origin": Vector2i(10, 10)}],
		[{"type": "rhinovirus", "cell": Vector2i(14, 10)}], 1, config)
	var tower: StructureState = _tower(sim, "b_cell")
	tower.target_id = sim.pathogens[0].id
	var driver := AnimDriver.new()
	var aim_at := Vector2(14.5, 10.5)
	tower.attack_cooldown = AnimDriver.TOWER_CHARGE_TICKS + 1
	assert_eq(driver.pose_for_structure(tower, 10, aim_at, 0.0).anim, ModelPose.Anim.IDLE)
	tower.attack_cooldown = AnimDriver.TOWER_CHARGE_TICKS
	var pose: ModelPose = driver.pose_for_structure(tower, 10, aim_at, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.WINDUP)
	assert_almost_eq(pose.attack_t, 0.0, 0.0001)
	tower.attack_cooldown = 0
	driver.pose_for_structure(tower, 10, aim_at, 0.0)
	assert_almost_eq(pose.attack_t, 1.0, 0.0001)
	driver.on_event({"type": SimEvents.TOWER_FIRED, "tick": 10, "structure_id": tower.id})
	tower.attack_cooldown = 24
	driver.pose_for_structure(tower, 12, aim_at, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.RECOVER)
	driver.pose_for_structure(tower, 11 + AnimDriver.TOWER_RECOIL_TICKS + 1, aim_at, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.IDLE)


func test_nucleus_and_walls_never_attack() -> void:
	var sim: BattleSim = SimFixtures.make_sim([{"type": "mucous_wall", "origin": Vector2i(5, 5)}], [], 1, config)
	var driver := AnimDriver.new()
	for s: StructureState in sim.structures:
		s.target_id = 0
		s.attack_cooldown = 0
		var pose: ModelPose = driver.pose_for_structure(s, 10, Vector2.ZERO, 0.0)
		assert_eq(pose.anim, ModelPose.Anim.IDLE)
		assert_eq(pose.aim, Vector2.ZERO)


func test_destroyed_structure_plays_its_death() -> void:
	var sim: BattleSim = SimFixtures.make_sim([], [], 1, config)
	var nucleus: StructureState = sim.structure(sim.nucleus_id)
	var driver := AnimDriver.new()
	driver.on_event({"type": SimEvents.STRUCTURE_DESTROYED, "tick": 4, "structure_id": nucleus.id})
	var pose: ModelPose = driver.pose_for_structure(nucleus, 25, Vector2.ZERO, 0.0)
	assert_eq(pose.anim, ModelPose.Anim.DEAD)
	assert_almost_eq(pose.death_t, 20.0 / 40.0, 0.0001)
