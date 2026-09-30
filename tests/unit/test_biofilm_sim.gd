extends GutTest


func _cfg(flag_on: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["biofilm"] = flag_on
	return cfg


func _row(n: int, y: int = 2) -> Array:
	var units: Array = []
	for i: int in range(n):
		units.append({"type": "staphylococcus", "cell": Vector2i(4 + i, y)})
	return units


func _sim(cfg: GameConfig, units: Array, rooted: bool = true) -> BattleSim:
	var sim: BattleSim = SimFixtures.make_sim([], units, 1, cfg)
	if rooted:
		for p: PathogenState in sim.pathogens:
			sim.status.add(StatusEffects.key_pathogen(p.id), StatusEffects.Kind.ROOTED, 1, 100000, "root")
	return sim


func _steps(sim: BattleSim, n: int) -> void:
	for i: int in range(n):
		sim.step()


func _events(sim: BattleSim, type_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in sim.drain_events():
		if ev["type"] == type_id:
			out.append(ev)
	return out


func test_split_damage() -> void:
	var sim: BattleSim = _sim(_cfg(), _row(3))
	_steps(sim, 1)
	assert_eq(sim.biofilm.groups.size(), 1)
	sim.drain_events()
	var hp0: int = sim.pathogen(1).hp
	sim.damage_pathogen(sim.pathogen(2), 100, 0)
	for id: int in [1, 2, 3]:
		assert_eq(hp0 - sim.pathogen(id).hp, 25)
	assert_eq(_events(sim, SimEvents.PATHOGEN_DAMAGED).size(), 3)


func test_remainder_goes_to_hit_unit() -> void:
	var sim: BattleSim = _sim(_cfg(), _row(3))
	_steps(sim, 1)
	var hp0: int = sim.pathogen(1).hp
	sim.damage_pathogen(sim.pathogen(3), 10, 0)
	assert_eq(hp0 - sim.pathogen(3).hp, 3)
	assert_eq(hp0 - sim.pathogen(1).hp, 2)
	assert_eq(hp0 - sim.pathogen(2).hp, 2)


func test_member_death_leaves_group() -> void:
	var sim: BattleSim = _sim(_cfg(), _row(2))
	_steps(sim, 1)
	sim.pathogen(2).hp = 5
	sim.damage_pathogen(sim.pathogen(1), 100, 0)
	assert_false(sim.pathogen(2).alive)
	assert_true(sim.pathogen(1).alive)
	assert_true(sim.biofilm.group_of.is_empty())
	var hp: int = sim.pathogen(1).hp
	sim.damage_pathogen(sim.pathogen(1), 100, 0)
	assert_eq(hp - sim.pathogen(1).hp, 100)


func test_group_of_three_survivors_stay_grouped() -> void:
	var sim: BattleSim = _sim(_cfg(), _row(3))
	_steps(sim, 1)
	sim.pathogen(3).hp = 1
	sim.damage_pathogen(sim.pathogen(1), 100, 0)
	assert_false(sim.pathogen(3).alive)
	assert_eq(sim.biofilm.members(1), [1, 2])


func test_group_moves_at_slowest_speed() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _row(2), false)
	sim.status.add(StatusEffects.key_pathogen(2), StatusEffects.Kind.SPEED_PCT, 50, 100000, "slow")
	var start1: Vector2i = sim.pathogen(1).pos
	var start2: Vector2i = sim.pathogen(2).pos
	_steps(sim, 1)
	var slow: int = FixedMath.apply_pct((cfg.pathogens["staphylococcus"] as PathogenDef).speed_mt_per_tick, 50)
	var d1: Vector2i = sim.pathogen(1).pos - start1
	var d2: Vector2i = sim.pathogen(2).pos - start2
	assert_eq(absi(d1.x) + absi(d1.y), slow)
	assert_eq(absi(d2.x) + absi(d2.y), slow)


func test_lone_unit_keeps_own_speed() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _row(1), false)
	var start: Vector2i = sim.pathogen(1).pos
	_steps(sim, 1)
	var d: Vector2i = sim.pathogen(1).pos - start
	assert_eq(absi(d.x) + absi(d.y), (cfg.pathogens["staphylococcus"] as PathogenDef).speed_mt_per_tick)


func test_changed_event_only_on_change() -> void:
	var sim: BattleSim = _sim(_cfg(), _row(2))
	_steps(sim, 1)
	var evs: Array[Dictionary] = _events(sim, SimEvents.BIOFILM_CHANGED)
	assert_eq(evs.size(), 1)
	assert_eq(evs[0]["groups"], [[1, 2]])
	_steps(sim, 60)
	assert_eq(_events(sim, SimEvents.BIOFILM_CHANGED).size(), 0)


func test_flag_off() -> void:
	var sim: BattleSim = _sim(_cfg(false), _row(3))
	_steps(sim, 20)
	assert_true(sim.biofilm.group_of.is_empty())
	var hp0: int = sim.pathogen(1).hp
	sim.damage_pathogen(sim.pathogen(1), 100, 0)
	assert_eq(hp0 - sim.pathogen(1).hp, 100)
	assert_eq(hp0 - sim.pathogen(2).hp, 0)
	assert_eq(_events(sim, SimEvents.BIOFILM_CHANGED).size(), 0)


func test_flag_off_hash_matches_config_without_flag() -> void:
	var absent: GameConfig = _cfg(false)
	absent.feature_flags.erase("biofilm")
	var a: BattleSim = _sim(_cfg(false), _row(3), false)
	var b: BattleSim = _sim(absent, _row(3), false)
	_steps(a, 40)
	_steps(b, 40)
	assert_eq(a.state_hash(), b.state_hash())


func test_hash_lines_only_when_grouped() -> void:
	var on: BattleSim = _sim(_cfg(true), _row(1), false)
	var off: BattleSim = _sim(_cfg(false), _row(1), false)
	_steps(on, 20)
	_steps(off, 20)
	assert_eq(on.state_hash(), off.state_hash())
	var grouped: BattleSim = _sim(_cfg(true), _row(2))
	var ungrouped: BattleSim = _sim(_cfg(false), _row(2))
	_steps(grouped, 5)
	_steps(ungrouped, 5)
	assert_ne(grouped.state_hash(), ungrouped.state_hash())


func test_determinism() -> void:
	var a: BattleSim = _sim(_cfg(), _row(4), false)
	var b: BattleSim = _sim(_cfg(), _row(4), false)
	_steps(a, 300)
	_steps(b, 300)
	assert_eq(a.state_hash(), b.state_hash())
