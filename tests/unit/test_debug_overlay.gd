extends GutTest

var config: GameConfig = null

func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load cleanly")
	config = res.config


func test_debug_overlay_replay_button_properties() -> void:
	var overlay_scene: PackedScene = load("res://src/ui/debug_overlay.tscn")
	assert_not_null(overlay_scene)
	var overlay: DebugOverlay = overlay_scene.instantiate() as DebugOverlay
	add_child_autofree(overlay)
	overlay.check_debug_build(true)

	assert_not_null(overlay.btn_replay)
	assert_true(overlay.btn_replay.custom_minimum_size.y >= 48.0, "Replay button must be >= 48 px tall")
	assert_not_null(overlay.replay_status_label)


func test_replay_last_battle_flow() -> void:
	var overlay_scene: PackedScene = load("res://src/ui/debug_overlay.tscn")
	var overlay: DebugOverlay = overlay_scene.instantiate() as DebugOverlay
	add_child_autofree(overlay)
	overlay.check_debug_build(true)

	# Clean directory or ensure it exists
	if not DirAccess.dir_exists_absolute("user://battles"):
		DirAccess.make_dir_recursive_absolute("user://battles")

	# Run a simulation and write a battle log
	var setup: BattleSetup = Scenarios.open_field(42)
	var sim := BattleSim.new(config, setup)
	while not sim.finished:
		sim.step()

	var b_dict: Dictionary = SnapshotIO.battle_to_dict(config, setup, sim)
	var b_json: String = SnapshotIO.to_json(b_dict)

	var unix_time: int = int(Time.get_unix_time_from_system())
	var path: String = "user://battles/battle_%d_%d.json" % [unix_time, setup.seed]
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f)
	f.store_string(b_json)
	f.close()

	var result: Dictionary = overlay.replay_last_battle()
	assert_true(result.get("ok", false))
	assert_true(result.get("match", false))
	assert_true("✓" in overlay.replay_status_label.text)


func test_battle_log_rotation_keeps_max_50() -> void:
	var phase_scene: PackedScene = load("res://src/game/phases/infection_phase.tscn")
	var phase: InfectionPhase = phase_scene.instantiate() as InfectionPhase
	add_child_autofree(phase)

	if not DirAccess.dir_exists_absolute("user://battles"):
		DirAccess.make_dir_recursive_absolute("user://battles")

	# Clear existing battles to test exact rotation count
	var dir := DirAccess.open("user://battles")
	if dir != null:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while not fn.is_empty():
			if not dir.current_is_dir() and fn.ends_with(".json"):
				dir.remove(fn)
			fn = dir.get_next()
		dir.list_dir_end()

	# Create 55 dummy battle log files
	for i in range(55):
		var file_path := "user://battles/battle_%d_%d.json" % [1000000 + i, i]
		var f := FileAccess.open(file_path, FileAccess.WRITE)
		if f != null:
			f.store_string("{}")
			f.close()

	# Trigger rotation
	phase._rotate_battle_logs()

	var remaining: Array[String] = []
	dir = DirAccess.open("user://battles")
	if dir != null:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while not fn.is_empty():
			if not dir.current_is_dir() and fn.ends_with(".json"):
				remaining.append(fn)
			fn = dir.get_next()
		dir.list_dir_end()

	assert_eq(remaining.size(), 50, "Battle log rotation must keep at most 50 files")
