extends GutTest


func _cfg(flag_on: bool) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["strains"] = flag_on
	return cfg


func _sim(cfg: GameConfig, units: Array) -> BattleSim:
	var base: BattleSetup = Scenarios.walled_nucleus(1)
	return BattleSim.new(cfg, BattleSetup.create(base.structures, units, 1))


func _units(variant: String) -> Array:
	var u: Dictionary = {"type": "rhinovirus", "cell": Vector2i(0, 10)}
	if not variant.is_empty():
		u["strain"] = variant
	return [u]


func test_capsid_hardening_stats() -> void:
	var cfg: GameConfig = _cfg(true)
	var def: PathogenDef = cfg.pathogens["rhinovirus"]
	var sim: BattleSim = _sim(cfg, _units("capsid_hardening"))
	var p: PathogenState = sim.pathogens[0]
	assert_eq(p.hp, FixedMath.apply_pct(def.hp, 115))
	assert_eq(p.max_hp, p.hp)
	assert_eq(p.speed_mt_per_tick, FixedMath.apply_pct(def.speed_mt_per_tick, 90))
	assert_eq(p.strain_key(), "rhinovirus/capsid_hardening")


func test_antigenic_masking_rate_and_damage() -> void:
	var cfg: GameConfig = _cfg(true)
	var def: PathogenDef = cfg.pathogens["rhinovirus"]
	var sim: BattleSim = _sim(cfg, _units("antigenic_masking"))
	var p: PathogenState = sim.pathogens[0]
	assert_eq(p.analysis_rate_pct, 50)
	assert_eq(p.attack_damage, FixedMath.apply_pct(def.attack_damage, 90))
	var wall_ids: Dictionary = {}
	for s: StructureState in sim.structures:
		if s.type_id == "mucous_wall":
			wall_ids[s.id] = true
	var seen: bool = false
	for i: int in range(600):
		sim.step()
		for ev: Dictionary in sim.drain_events():
			if ev.get("type") == SimEvents.STRUCTURE_DAMAGED and wall_ids.has(int(ev["structure_id"])):
				seen = true
				assert_eq(int(ev["amount"]), FixedMath.apply_pct(def.attack_damage, 90))
		if seen:
			break
	assert_true(seen)


func test_flag_off_spawns_wild_and_hash_unchanged() -> void:
	var cfg: GameConfig = _cfg(false)
	var def: PathogenDef = cfg.pathogens["rhinovirus"]
	var a: BattleSim = _sim(cfg, _units("capsid_hardening"))
	var b: BattleSim = _sim(cfg, _units(""))
	assert_eq(a.pathogens[0].strain_id, "wild")
	assert_eq(a.pathogens[0].hp, def.hp)
	assert_eq(a.pathogens[0].speed_mt_per_tick, def.speed_mt_per_tick)
	for i: int in range(50):
		a.step()
		b.step()
	assert_eq(a.state_hash(), b.state_hash())
