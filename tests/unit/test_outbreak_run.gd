extends GutTest


func test_new_run_defaults() -> void:
	var run := OutbreakRun.new()
	assert_eq(run.generation, 1)
	assert_eq(run.total_score, 0)
	assert_false(run.ended)
	assert_eq(run.generations_cleared(), 0)


func test_attacker_wins_advance_generation() -> void:
	var run := OutbreakRun.new()
	run.record("attacker", 500)
	run.record("attacker", 700)
	assert_eq(run.generation, 3)
	assert_eq(run.total_score, 1200)
	assert_eq(run.generation_scores, [500, 700] as Array[int])
	assert_eq(run.generations_cleared(), 2)


func test_defender_hold_ends_run_and_locks_it() -> void:
	var run := OutbreakRun.new()
	run.record("attacker", 500)
	run.record("defender", 999)
	assert_true(run.ended)
	assert_eq(run.total_score, 500)
	assert_eq(run.generation, 2)
	run.record("attacker", 300)
	assert_eq(run.total_score, 500)
	assert_eq(run.generation, 2)
	assert_eq(run.generations_cleared(), 1)


func test_to_dict_has_all_keys() -> void:
	var d: Dictionary = OutbreakRun.new().to_dict()
	for key: String in ["generation", "total_score", "generation_scores", "ended"]:
		assert_true(d.has(key), key)


func test_hud_badges_follow_outbreak_state() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var off := Session.new(cfg)
	var hud_off := HudSpawn.new()
	add_child_autoqfree(hud_off)
	hud_off.setup(off)
	assert_null(hud_off.outbreak_badge)

	cfg.feature_flags["outbreak_mode"] = true
	var on := Session.new(cfg)
	on.record_outbreak("attacker", 1480)
	var hud_spawn := HudSpawn.new()
	add_child_autoqfree(hud_spawn)
	hud_spawn.setup(on)
	assert_eq(hud_spawn.outbreak_badge.text, "Generation 2 · Run 1,480")
	var hud_build := HudBuild.new()
	add_child_autoqfree(hud_build)
	hud_build.setup(on, null)
	assert_eq(hud_build.outbreak_badge.text, "Generation 2 · Run 1,480")
