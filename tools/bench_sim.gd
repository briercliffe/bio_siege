extends SceneTree


func _init() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	var config: GameConfig = res.config
	if config == null:
		push_error("Failed to load config from res://data")
		quit(1)
		return

	var setup: BattleSetup = Scenarios.stress()
	var sim: BattleSim = BattleSim.new(config, setup)

	var elapsed_usecs: Array[int] = []
	var max_usec: int = -1
	var tick_of_max: int = -1

	while not sim.finished:
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var elapsed: int = Time.get_ticks_usec() - t0
		elapsed_usecs.append(elapsed)
		if elapsed > max_usec:
			max_usec = elapsed
			tick_of_max = sim.tick

	var total_ticks: int = elapsed_usecs.size()
	var total_usec: int = 0
	for u: int in elapsed_usecs:
		total_usec += u

	var avg_ms: float = (float(total_usec) / float(total_ticks) / 1000.0) if total_ticks > 0 else 0.0

	var sorted_usecs: Array[int] = elapsed_usecs.duplicate()
	sorted_usecs.sort()

	var p99_idx: int = clampi(int(float(sorted_usecs.size()) * 0.99), 0, sorted_usecs.size() - 1)
	var p99_ms: float = float(sorted_usecs[p99_idx]) / 1000.0 if not sorted_usecs.is_empty() else 0.0
	var max_ms: float = float(max_usec) / 1000.0 if max_usec >= 0 else 0.0

	var total_path_computations: int = sim.path_service.computations_total if sim.path_service != null else 0

	print("=== Battle Sim Benchmark (Stress Scenario) ===")
	print("Total ticks:              %d" % total_ticks)
	print("Average ms/step:          %.3f ms" % avg_ms)
	print("99th-percentile ms/step:  %.3f ms" % p99_ms)
	print("Max ms/step:              %.3f ms" % max_ms)
	print("Tick of max ms:           %d" % tick_of_max)
	print("Total path computations:  %d" % total_path_computations)
	print("Outcome:                  %s" % sim.outcome)
	print("End reason:               %s" % sim.end_reason)
	print("===============================================")

	quit(0)
