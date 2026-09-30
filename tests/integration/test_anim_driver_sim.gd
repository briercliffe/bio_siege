extends GutTest

const SEED: int = 11

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func test_driver_poses_stay_in_range_and_never_change_the_sim() -> void:
	var plain: BattleSim = BattleSim.new(config, Scenarios.mixed([], SEED))
	while not plain.finished:
		plain.step()
	var expected: String = plain.state_hash()

	var sim: BattleSim = BattleSim.new(config, Scenarios.mixed([], SEED))
	var driver := AnimDriver.new()
	var seen_dead: bool = false
	var seen_strike: bool = false
	var seen_tower_anim: bool = false
	while not sim.finished:
		sim.step()
		for ev: Dictionary in sim.drain_events():
			driver.on_event(ev)
		for p: PathogenState in sim.pathogens:
			var ground: Vector2 = Vector2(p.pos) / 1000.0
			var pose: ModelPose = driver.pose_for_pathogen(p, sim.tick, ground, ground, 0.0, 0.0)
			_check(pose)
			seen_dead = seen_dead or pose.anim == ModelPose.Anim.DEAD
			seen_strike = seen_strike or pose.anim == ModelPose.Anim.STRIKE
		for s: StructureState in sim.structures:
			var pose: ModelPose = driver.pose_for_structure(s, sim.tick, Vector2.ZERO, 0.0)
			_check(pose)
			seen_tower_anim = seen_tower_anim or (s.def.has_attack and pose.anim != ModelPose.Anim.IDLE)

	assert_true(seen_dead, "some pathogen died")
	assert_true(seen_strike, "some pathogen struck")
	assert_true(seen_tower_anim, "some tower animated")
	assert_eq(sim.state_hash(), expected, "driver must not change the simulation")


func _check(pose: ModelPose) -> void:
	assert_true(pose.attack_t >= 0.0 and pose.attack_t <= 1.0, "attack_t in range")
	assert_true(pose.death_t >= 0.0 and pose.death_t <= 1.0, "death_t in range")
	assert_true(pose.hit_t >= 0.0 and pose.hit_t <= 1.0, "hit_t in range")
	assert_true(pose.gait_phase >= 0.0 and pose.gait_phase < 1.0, "gait_phase in range")
