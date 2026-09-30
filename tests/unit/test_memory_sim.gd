extends GutTest

const BCELL_ORIGIN: Vector2i = Vector2i(10, 3)


func _cfg(analysis: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["bcell_analysis"] = analysis
	return cfg


func _structs() -> Array:
	return [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
		{"type": "b_cell", "origin": BCELL_ORIGIN},
		{"type": "b_cell", "origin": Vector2i(14, 3)},
		{"type": "macrophage", "origin": Vector2i(5, 3)},
	]


func _units() -> Array:
	return [
		{"type": "staphylococcus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(0, 11)},
		{"type": "rhinovirus", "cell": Vector2i(0, 12)},
	]


func _sim(cfg: GameConfig, memory_seed: Dictionary) -> BattleSim:
	return BattleSim.new(cfg, BattleSetup.create(_structs(), _units(), 3, memory_seed))


func test_partial_seed_on_every_bcell_only() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, {"rhinovirus/wild": 50})
	var threshold: int = (cfg.structures["b_cell"] as StructureDef).analysis_threshold_ticks
	for s: StructureState in sim.structures:
		if s.type_id == "b_cell":
			assert_eq(int(s.analysis_exposure["rhinovirus/wild"]), threshold * 50)
			assert_false(s.analyzed.has("rhinovirus/wild"))
		else:
			assert_true(s.analysis_exposure.is_empty())


func test_full_seed_starts_analyzed_and_emits_event() -> void:
	var sim: BattleSim = _sim(_cfg(), {"rhinovirus/wild": 100})
	var completes: int = 0
	for ev: Dictionary in sim.drain_events():
		if ev["type"] == SimEvents.ANALYSIS_COMPLETE and ev["strain_key"] == "rhinovirus/wild":
			completes += 1
	assert_eq(completes, 2)
	assert_eq(sim.tick, 0)
	assert_eq(sim.analyzed_strain_keys(), ["rhinovirus/wild"] as Array[String])


func test_flag_off_ignores_seed() -> void:
	var seeded: BattleSim = _sim(_cfg(false), {"rhinovirus/wild": 100})
	var plain: BattleSim = _sim(_cfg(false), {})
	assert_eq(seeded.state_hash(), plain.state_hash())
	for i: int in range(20):
		seeded.step()
		plain.step()
	assert_eq(seeded.state_hash(), plain.state_hash())


func test_seen_strain_keys_sorted_unique() -> void:
	var sim: BattleSim = _sim(_cfg(), {})
	assert_eq(sim.seen_strain_keys(), ["rhinovirus/wild", "staphylococcus/wild"] as Array[String])
