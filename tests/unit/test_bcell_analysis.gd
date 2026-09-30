extends GutTest

const BCELL_ORIGIN: Vector2i = Vector2i(10, 3)


func _cfg(flag_on: bool = true, threshold: int = -1) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["bcell_analysis"] = flag_on
	if threshold > 0:
		(cfg.structures["b_cell"] as StructureDef).analysis_threshold_ticks = threshold
	return cfg


func _sim(cfg: GameConfig, units: Array, extra_structs: Array = []) -> BattleSim:
	var structs: Array = [{"type": "b_cell", "origin": BCELL_ORIGIN}]
	structs.append_array(extra_structs)
	var sim: BattleSim = SimFixtures.make_sim(structs, units, 1, cfg)
	for p: PathogenState in sim.pathogens:
		sim.status.add(StatusEffects.key_pathogen(p.id), StatusEffects.Kind.ROOTED, 1, 100000, "root")
		p.hp = 100000
		p.max_hp = 100000
	return sim


func _staph_units() -> Array:
	return [{"type": "staphylococcus", "cell": Vector2i(10, 6)}]


func _steps(sim: BattleSim, n: int) -> void:
	for i: int in range(n):
		sim.step()


func test_flag_off_no_exposure() -> void:
	var sim: BattleSim = _sim(_cfg(false), _staph_units())
	_steps(sim, 50)
	var bc: StructureState = sim.structure(1)
	assert_true(bc.analysis_exposure.is_empty())
	assert_true(bc.analyzed.is_empty())
	assert_eq(bc.analysis_focus_key, "")
	# With no exposure the hash has no A: lines, so it must equal a sim whose
	# analysis fields were never touched (same battle, flag off, second run).
	var sim2: BattleSim = _sim(_cfg(false), _staph_units())
	_steps(sim2, 50)
	assert_eq(sim.state_hash(), sim2.state_hash())


func test_flag_on_adds_hash_lines() -> void:
	var off: BattleSim = _sim(_cfg(false), _staph_units())
	var on: BattleSim = _sim(_cfg(true), _staph_units())
	_steps(off, 20)
	_steps(on, 20)
	assert_ne(off.state_hash(), on.state_hash())


func test_accrual() -> void:
	var sim: BattleSim = _sim(_cfg(), _staph_units())
	var n: int = 7
	_steps(sim, n)
	var bc: StructureState = sim.structure(1)
	assert_eq(int(bc.analysis_exposure["staphylococcus/wild"]), n * 100)
	assert_eq(bc.analysis_focus_key, "staphylococcus/wild")


func test_completion_event_once() -> void:
	var sim: BattleSim = _sim(_cfg(true, 5), _staph_units())
	_steps(sim, 4)
	assert_false(sim.structure(1).is_analyzed("staphylococcus/wild"))
	sim.drain_events()
	sim.step()
	assert_true(sim.structure(1).is_analyzed("staphylococcus/wild"))
	var found: Array[Dictionary] = []
	for ev: Dictionary in sim.drain_events():
		if ev.get("type") == SimEvents.ANALYSIS_COMPLETE:
			found.append(ev)
	assert_eq(found.size(), 1)
	assert_eq(int(found[0]["structure_id"]), 1)
	assert_eq(str(found[0]["strain_key"]), "staphylococcus/wild")
	_steps(sim, 10)
	for ev: Dictionary in sim.drain_events():
		assert_ne(ev.get("type"), SimEvents.ANALYSIS_COMPLETE)


func test_boosted_damage_after_analysis() -> void:
	var cfg: GameConfig = _cfg(true, 5)
	var def: StructureDef = cfg.structures["b_cell"]
	var sim: BattleSim = _sim(cfg, _staph_units())
	_steps(sim, 5)
	sim.drain_events()
	_steps(sim, def.attack_interval_ticks * 2)
	var amounts: Array[int] = []
	for ev: Dictionary in sim.drain_events():
		if ev.get("type") == SimEvents.PATHOGEN_DAMAGED:
			amounts.append(int(ev["amount"]))
	assert_gt(amounts.size(), 0)
	for a: int in amounts:
		assert_eq(a, FixedMath.apply_pct(def.attack_damage, def.analysis_multiplier_pct))


func test_per_strain() -> void:
	var cfg: GameConfig = _cfg(true)
	var def: StructureDef = cfg.structures["b_cell"]
	var sim: BattleSim = _sim(cfg, _staph_units())
	sim.structure(1).analyzed["rhinovirus/wild"] = true
	_steps(sim, 12)
	var seen: bool = false
	for ev: Dictionary in sim.drain_events():
		if ev.get("type") == SimEvents.PATHOGEN_DAMAGED:
			seen = true
			assert_eq(int(ev["amount"]), def.attack_damage)
	assert_true(seen)


func test_per_tower() -> void:
	var sim: BattleSim = _sim(_cfg(), _staph_units(), [{"type": "b_cell", "origin": Vector2i(1, 15)}])
	_steps(sim, 10)
	var far: StructureState = sim.structure(2)
	assert_eq(far.type_id, "b_cell")
	assert_true(far.analysis_exposure.is_empty())
	assert_eq(far.analysis_focus_key, "")
	assert_false(sim.structure(1).analysis_exposure.is_empty())


func test_rate() -> void:
	var sim: BattleSim = _sim(_cfg(), _staph_units())
	sim.pathogen(1).analysis_rate_pct = 50
	var n: int = 8
	_steps(sim, n)
	assert_eq(int(sim.structure(1).analysis_exposure["staphylococcus/wild"]), n * 50)


func test_disabled_tower_gains_nothing() -> void:
	var sim: BattleSim = _sim(_cfg(), _staph_units())
	sim.status.add(StatusEffects.key_structure(1), StatusEffects.Kind.DISABLED, 1, 100000, "test")
	_steps(sim, 10)
	assert_true(sim.structure(1).analysis_exposure.is_empty())


func test_analyzed_strain_keys_sorted_unique() -> void:
	var sim: BattleSim = _sim(_cfg(), _staph_units(), [{"type": "b_cell", "origin": Vector2i(1, 15)}])
	sim.structure(1).analyzed["staphylococcus/wild"] = true
	sim.structure(1).analyzed["rhinovirus/wild"] = true
	sim.structure(2).analyzed["staphylococcus/wild"] = true
	sim.structure(2).analyzed["adenovirus/wild"] = true
	assert_eq(sim.analyzed_strain_keys(), ["adenovirus/wild", "rhinovirus/wild", "staphylococcus/wild"])


func test_determinism() -> void:
	var a: BattleSim = _sim(_cfg(), _staph_units())
	var b: BattleSim = _sim(_cfg(), _staph_units())
	_steps(a, 300)
	_steps(b, 300)
	assert_eq(a.state_hash(), b.state_hash())


func test_progress_pct() -> void:
	var sim: BattleSim = _sim(_cfg(true, 5), _staph_units())
	var bc: StructureState = sim.structure(1)
	assert_eq(bc.analysis_progress_pct("staphylococcus/wild"), 0)
	_steps(sim, 2)
	assert_eq(bc.analysis_progress_pct("staphylococcus/wild"), 40)
	_steps(sim, 3)
	assert_eq(bc.analysis_progress_pct("staphylococcus/wild"), 100)
	assert_true(bc.is_analyzed("staphylococcus/wild"))
