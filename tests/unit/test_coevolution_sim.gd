extends GutTest

## Coevolution in the sim (#143): genome assignment, receptor-vs-antigen damage, fitness, survival, hash.

const MAC_ORIGIN: Vector2i = Vector2i(5, 5)
const BCELL_ORIGIN: Vector2i = Vector2i(10, 3)
const MAX_STEPS: int = 600


func _cfg(coevo: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["coevolution"] = coevo
	return cfg


func _pop(antigens: Array, receptors: Array) -> Dictionary:
	return {"genomes": [{"antigens": antigens, "receptors": receptors}]}


func _sim(cfg: GameConfig, structs: Array, units: Array, pops: Dictionary = {}) -> BattleSim:
	var all_structs: Array = structs.duplicate(true)
	all_structs.append({"type": "nucleus", "origin": Vector2i(18, 18)})
	return BattleSim.new(cfg, BattleSetup.create(all_structs, units, 1, {}, pops))


func _mac_rhino(cfg: GameConfig, pops: Dictionary = {}) -> BattleSim:
	return _sim(cfg, [{"type": "macrophage", "origin": MAC_ORIGIN}], [{"type": "rhinovirus", "cell": Vector2i(5, 8)}], pops)


## HP the macrophage (structure 1) loses to one attack by pathogen 1.
func _pathogen_hit(sim: BattleSim, victim_id: int = 1) -> int:
	var v: StructureState = sim.structure(victim_id)
	var before: int = v.hp
	sim._pathogen_attack(sim.pathogen(1), v)
	return before - v.hp


## HP the rhinovirus loses to one macrophage shot.
func _tower_hit(sim: BattleSim) -> int:
	var p: PathogenState = sim.pathogen(1)
	p.hp = 100000
	var before: int = p.hp
	sim.damage_pathogen(p, sim._tower_damage(sim.structure(1), p), 1)
	return before - p.hp


func _steps(sim: BattleSim, n: int) -> void:
	for i: int in range(n):
		sim.step()


func _sum(values: Array) -> int:
	var t: int = 0
	for v: Variant in values:
		t += int(v)
	return t


# --- assignment ---

func test_default_genome_indexes_and_no_change_from_flag_off() -> void:
	var on: BattleSim = _mac_rhino(_cfg(true))
	var off: BattleSim = _mac_rhino(_cfg(false))
	assert_eq(on.structure(1).genome_index, 0)
	assert_eq(on.pathogen(1).genome_index, 0)
	assert_eq(on.structure(2).genome_index, -1, "the nucleus never gets a genome")
	assert_eq(off.structure(1).genome_index, -1)
	assert_eq(off.pathogen(1).genome_index, -1)
	for i: int in range(200):
		on.step()
		off.step()
	assert_eq(on.pathogen(1).hp, off.pathogen(1).hp)
	assert_eq(on.structure(1).hp, off.structure(1).hp)
	assert_eq(on.structure(2).hp, off.structure(2).hp)


func test_indexes_count_per_type_and_wrap() -> void:
	var structs: Array = [
		{"type": "macrophage", "origin": Vector2i(2, 2)},
		{"type": "mucous_wall", "origin": Vector2i(9, 2)},
		{"type": "macrophage", "origin": Vector2i(5, 2)},
	]
	var units: Array = []
	for i: int in range(10):
		units.append({"type": "rhinovirus", "cell": Vector2i(i, 20)})
	units.append({"type": "staphylococcus", "cell": Vector2i(0, 22)})
	var sim: BattleSim = _sim(_cfg(), structs, units)
	assert_eq(sim.structure(1).genome_index, 0)
	assert_eq(sim.structure(2).genome_index, -1)
	assert_eq(sim.structure(3).genome_index, 1)
	assert_eq(sim.pathogen(1).genome_index, 0)
	assert_eq(sim.pathogen(2).genome_index, 1)
	assert_eq(sim.pathogen(9).genome_index, 0, "ninth rhinovirus wraps modulo pool_size 8")
	assert_eq(sim.pathogen(11).genome_index, 0, "separate counter per type")


# --- damage ---

func test_pathogen_match_bonus() -> void:
	var cfg: GameConfig = _cfg()
	var base: int = _pathogen_hit(_mac_rhino(cfg))
	var pops: Dictionary = {
		"rhinovirus": _pop([], ["binder_a", ""]),
		"macrophage": _pop(["capsule_a", ""], []),
	}
	var hit: int = _pathogen_hit(_mac_rhino(cfg, pops))
	assert_eq(hit, FixedMath.apply_pct(base, 125))
	assert_gt(hit, base)


func test_tower_match_bonus() -> void:
	var cfg: GameConfig = _cfg()
	var base: int = _tower_hit(_mac_rhino(cfg))
	var pops: Dictionary = {
		"macrophage": _pop([], ["binder_a", ""]),
		"rhinovirus": _pop(["capsule_a", ""], []),
	}
	var hit: int = _tower_hit(_mac_rhino(cfg, pops))
	assert_eq(hit, FixedMath.apply_pct(base, 125))


func test_double_miss_halves_and_floors_at_one() -> void:
	var cfg: GameConfig = _cfg()
	var base: int = _pathogen_hit(_mac_rhino(cfg))
	var pops: Dictionary = {"rhinovirus": _pop([], ["binder_a", "binder_b"])}
	assert_eq(_pathogen_hit(_mac_rhino(cfg, pops)), maxi(1, FixedMath.apply_pct(base, 50)))
	cfg.coevo_miss_penalty_pct = 100
	assert_eq(_pathogen_hit(_mac_rhino(cfg, pops)), 1)


func test_nucleus_gets_no_match_but_pathogen_scores_fitness() -> void:
	var cfg: GameConfig = _cfg()
	var pops: Dictionary = {"rhinovirus": _pop([], ["binder_a", "binder_b"])}
	var sim: BattleSim = _mac_rhino(cfg, pops)
	var base: int = _pathogen_hit(_mac_rhino(_cfg(false)), 2)
	var dealt: int = _pathogen_hit(sim, 2)
	assert_eq(dealt, base, "walls and the nucleus take unmodified damage")
	assert_eq(sim.fitness_by_type()["rhinovirus"][0], dealt)


# --- fitness ---

func test_tower_fitness_is_damage_dealt() -> void:
	var sim: BattleSim = _mac_rhino(_cfg())
	sim.pathogen(1).hp = 100000
	var dealt: int = _tower_hit(sim)
	assert_eq(sim.fitness_by_type()["macrophage"][0], dealt)
	sim.damage_pathogen(sim.pathogen(1), 5, 0)
	assert_eq(sim.fitness_by_type()["macrophage"][0], dealt, "source id 0 earns nothing")


func test_survival_bonus_once() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _mac_rhino(cfg)
	sim.pathogen(1).alive = false
	sim.grant_survival_bonus()
	var fit: Dictionary = sim.fitness_by_type()
	assert_eq(fit["macrophage"][0], cfg.coevo_survival_bonus)
	assert_eq(fit["rhinovirus"][0], 0, "dead pathogens get no bonus")
	sim.grant_survival_bonus()
	assert_eq(sim.fitness_by_type()["macrophage"][0], cfg.coevo_survival_bonus)


func test_flag_off_no_state() -> void:
	var cfg: GameConfig = _cfg(false)
	var pops: Dictionary = {"rhinovirus": _pop([], ["binder_a", "binder_b"])}
	var with_pops: BattleSim = _mac_rhino(cfg, pops)
	var plain: BattleSim = _mac_rhino(cfg)
	assert_eq(with_pops.state_hash(), plain.state_hash())
	_steps(with_pops, 50)
	_steps(plain, 50)
	assert_eq(with_pops.state_hash(), plain.state_hash())
	with_pops.grant_survival_bonus()
	assert_true(with_pops.fitness_by_type().is_empty())


func test_flag_on_hash_differs_and_tracks_genome_index() -> void:
	var on: BattleSim = _mac_rhino(_cfg(true))
	var off: BattleSim = _mac_rhino(_cfg(false))
	assert_ne(on.state_hash(), off.state_hash())
	var two: BattleSim = _sim(_cfg(true), [{"type": "macrophage", "origin": MAC_ORIGIN}], [
		{"type": "rhinovirus", "cell": Vector2i(5, 8)}, {"type": "rhinovirus", "cell": Vector2i(6, 8)}])
	var one: BattleSim = _sim(_cfg(true), [{"type": "macrophage", "origin": MAC_ORIGIN}], [
		{"type": "rhinovirus", "cell": Vector2i(5, 8)}, {"type": "rhinovirus", "cell": Vector2i(6, 8)}])
	assert_eq(two.state_hash(), one.state_hash())
	one.pathogen(2).genome_index = 5
	assert_ne(two.state_hash(), one.state_hash())


func test_biofilm_credit_is_post_split_total() -> void:
	var cfg: GameConfig = _cfg()
	cfg.feature_flags["biofilm"] = true
	var units: Array = [
		{"type": "staphylococcus", "cell": Vector2i(4, 8)},
		{"type": "staphylococcus", "cell": Vector2i(5, 8)},
		{"type": "staphylococcus", "cell": Vector2i(6, 8)},
	]
	var sim: BattleSim = _sim(cfg, [{"type": "macrophage", "origin": MAC_ORIGIN}], units)
	for p: PathogenState in sim.pathogens:
		sim.status.add(StatusEffects.key_pathogen(p.id), StatusEffects.Kind.ROOTED, 1, 100000, "root")
	sim.step()
	assert_eq(sim.biofilm.groups.size(), 1)
	var hp_before: int = 0
	for p: PathogenState in sim.pathogens:
		hp_before += p.hp
	var fit_before: int = sim.fitness_by_type()["macrophage"][0]
	sim._tower_fire(sim.structure(1), sim.pathogen(2))
	var hp_after: int = 0
	for p: PathogenState in sim.pathogens:
		hp_after += p.hp
	assert_gt(hp_before - hp_after, 0)
	assert_eq(sim.fitness_by_type()["macrophage"][0] - fit_before, hp_before - hp_after)


func test_projectile_credits_dead_tower() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, [{"type": "b_cell", "origin": BCELL_ORIGIN}], [{"type": "rhinovirus", "cell": Vector2i(10, 9)}])
	var rhino: PathogenState = sim.pathogen(1)
	rhino.hp = 100000
	rhino.max_hp = 100000
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100000, "root")
	for i: int in range(MAX_STEPS):
		sim.step()
		if not sim.projectiles.is_empty():
			break
	assert_false(sim.projectiles.is_empty(), "the B-Cell fired")
	sim.structure(1).alive = false
	for i: int in range(MAX_STEPS):
		sim.step()
		if sim.projectiles.is_empty():
			break
	assert_gt(sim.fitness_by_type()["b_cell"][0], 0)


func test_turncoat_friendly_fire_earns_nothing_and_ignores_match() -> void:
	var run: Callable = func(coevo: bool) -> Dictionary:
		var cfg: GameConfig = _cfg(coevo)
		cfg.feature_flags["phage_hijack"] = true
		cfg.feature_flags["phage_turncoat"] = true
		var pops: Dictionary = {
			"macrophage": _pop(["capsule_a", ""], ["binder_a", "binder_b"]),
			"b_cell": _pop(["capsule_b", ""], ["binder_a", "binder_b"]),
		}
		var structs: Array = [
			{"type": "macrophage", "origin": Vector2i(8, 5)},
			{"type": "b_cell", "origin": Vector2i(11, 5)},
		]
		var units: Array = [
			{"type": "rhinovirus", "cell": Vector2i(2, 30)},
			{"type": "bacteriophage", "cell": Vector2i(4, 5)},
		]
		var sim: BattleSim = _sim(cfg, structs, units, pops)
		for s: StructureState in sim.structures:
			sim.status.add(StatusEffects.key_structure(s.id), StatusEffects.Kind.DAMAGE_DEALT_PCT, 0, 100000, "weak")
		sim.pathogen(1).hp = 1000000
		sim.pathogen(1).max_hp = 1000000
		sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100000, "root")
		var fired: Array[int] = []
		var tower_dealt: int = 0
		for i: int in range(MAX_STEPS):
			sim.step()
			for ev: Dictionary in sim.drain_events():
				if ev["type"] == SimEvents.TURNCOAT_FIRED:
					fired.append(int(ev["amount"]))
				elif ev["type"] == SimEvents.PATHOGEN_DAMAGED and int(ev["source_structure_id"]) != 0:
					tower_dealt += int(ev["amount"])
			if fired.size() >= 2:
				break
		var fit_total: int = 0
		for arr: Variant in sim.fitness_by_type().values():
			fit_total += _sum(arr as Array)
		return {"fired": fired, "tower_dealt": tower_dealt, "fit_total": fit_total}
	var off: Dictionary = run.call(false)
	var on: Dictionary = run.call(true)
	assert_gt((off["fired"] as Array).size(), 0, "the turncoat fired")
	assert_eq(on["fired"], off["fired"], "no match multiplier on friendly fire")
	assert_eq(on["fit_total"], on["tower_dealt"], "only tower hits on pathogens score fitness")
