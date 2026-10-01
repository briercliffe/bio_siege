extends GutTest

## Hijack turncoat (#150): a hijacked tower fires at neighbouring defense structures for its disable window.

const MAX_STEPS: int = 600
const MAC_ORIGIN: Vector2i = Vector2i(8, 5)
const BCELL_ORIGIN: Vector2i = Vector2i(11, 5)
## A rooted, unkillable rhinovirus far from every tower keeps the battle running after the phage is consumed.
const ANCHOR_CELL: Vector2i = Vector2i(2, 30)


func _cfg(turncoat_on: bool = true, hijack_on: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["phage_hijack"] = hijack_on
	cfg.feature_flags["phage_turncoat"] = turncoat_on
	return cfg


func _units(phages: int = 1) -> Array:
	var units: Array = [{"type": "rhinovirus", "cell": ANCHOR_CELL}]
	for i: int in range(phages):
		units.append({"type": "bacteriophage", "cell": Vector2i(4 - i, 5)})
	return units


## Structures: 1 = Macrophage (hijack target), 2 = B-Cell next to it, then `extra`, then the Nucleus.
## Both towers deal 1 damage to pathogens so the phage survives its channel. Unit 1 is the anchor.
func _sim(cfg: GameConfig, units: Array, extra: Array = [], with_bcell: bool = true) -> BattleSim:
	var structs: Array = [{"type": "macrophage", "origin": MAC_ORIGIN}]
	if with_bcell:
		structs.append({"type": "b_cell", "origin": BCELL_ORIGIN})
	structs.append_array(extra)
	var sim: BattleSim = SimFixtures.make_sim(structs, units, 1, cfg)
	for s: StructureState in sim.structures:
		sim.status.add(StatusEffects.key_structure(s.id), StatusEffects.Kind.DAMAGE_DEALT_PCT, 0, 100000, "weak")
	var anchor: PathogenState = sim.pathogen(1)
	anchor.hp = 1000000
	anchor.max_hp = 1000000
	sim.status.add(StatusEffects.key_pathogen(1), StatusEffects.Kind.ROOTED, 1, 100000, "root")
	return sim


func _steps(sim: BattleSim, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(n):
		sim.step()
		out.append_array(sim.drain_events())
	return out


func _until(sim: BattleSim, type_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(MAX_STEPS):
		sim.step()
		var evs: Array[Dictionary] = sim.drain_events()
		out.append_array(evs)
		for ev: Dictionary in evs:
			if ev["type"] == type_id:
				return out
	return out


func _of(events: Array[Dictionary], type_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in events:
		if ev["type"] == type_id:
			out.append(ev)
	return out


func _disable_ticks(cfg: GameConfig) -> int:
	return (cfg.pathogens["bacteriophage"] as PathogenDef).hijack_disable_ticks


func test_flag_off_keeps_disable_only() -> void:
	var cfg: GameConfig = _cfg(false)
	var sim: BattleSim = _sim(cfg, _units())
	var evs: Array[Dictionary] = _until(sim, SimEvents.HIJACK_COMPLETE)
	assert_eq(_of(evs, SimEvents.HIJACK_COMPLETE).size(), 1)
	evs = _steps(sim, _disable_ticks(cfg))
	assert_eq(_of(evs, SimEvents.TURNCOAT_FIRED).size(), 0)
	assert_eq(sim.structure(2).hp, sim.structure(2).max_hp)
	assert_eq(sim.turncoat_damage_dealt, 0)


func test_flag_off_hash_matches_absent_flag() -> void:
	var off: GameConfig = _cfg(false)
	var absent: GameConfig = _cfg(false)
	absent.feature_flags.erase("phage_turncoat")
	var a: BattleSim = _sim(off, _units())
	var b: BattleSim = _sim(absent, _units())
	_steps(a, 300)
	_steps(b, 300)
	assert_eq(a.state_hash(), b.state_hash())


func test_needs_hijack_flag() -> void:
	var sim: BattleSim = _sim(_cfg(true, false), _units())
	var evs: Array[Dictionary] = _steps(sim, 300)
	assert_eq(_of(evs, SimEvents.HIJACK_COMPLETE).size(), 0)
	assert_eq(_of(evs, SimEvents.TURNCOAT_FIRED).size(), 0)


func test_turncoat_shoots_neighbour_not_pathogens() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _units())
	_until(sim, SimEvents.HIJACK_COMPLETE)
	var window: Array[Dictionary] = _steps(sim, _disable_ticks(cfg))
	var shots: Array[Dictionary] = _of(window, SimEvents.TURNCOAT_FIRED)
	assert_gt(shots.size(), 0)
	var expected: int = FixedMath.apply_pct((sim.config.structures["macrophage"] as StructureDef).attack_damage, 50)
	assert_eq(expected, 20)
	for shot: Dictionary in shots:
		assert_eq(shot["structure_id"], 1)
		assert_eq(shot["target_structure_id"], 2)
		assert_eq(shot["amount"], expected)
	assert_eq(sim.structure(2).max_hp - sim.structure(2).hp, expected * shots.size())
	assert_eq(sim.turncoat_damage_dealt, expected * shots.size())
	for ev: Dictionary in _of(window, SimEvents.TOWER_FIRED):
		assert_ne(ev["structure_id"], 1, "a turncoat never fires at pathogens")
	assert_eq(sim.structure(1).turncoat_until_tick, -1, "the window has ended")


func test_budget_caps_friendly_damage() -> void:
	var cfg: GameConfig = _cfg()
	(cfg.pathogens["bacteriophage"] as PathogenDef).hijack_turncoat_max_damage = 50
	var sim: BattleSim = _sim(cfg, _units())
	_until(sim, SimEvents.HIJACK_COMPLETE)
	var shots: Array[Dictionary] = _of(_steps(sim, _disable_ticks(cfg)), SimEvents.TURNCOAT_FIRED)
	var amounts: Array[int] = []
	for shot: Dictionary in shots:
		amounts.append(int(shot["amount"]))
	assert_eq(amounts, [20, 20, 10] as Array[int])
	assert_eq(sim.turncoat_damage_dealt, 50)
	assert_eq(sim.structure(2).max_hp - sim.structure(2).hp, 50)


func test_never_targets_walls_or_core_and_stays_silent_alone() -> void:
	var cfg: GameConfig = _cfg()
	var extra: Array = [
		{"type": "nucleus", "origin": Vector2i(11, 5)},
		{"type": "mucous_wall", "origin": Vector2i(9, 9)},
	]
	var sim: BattleSim = _sim(cfg, _units(), extra, false)
	assert_true(Targeting.is_friendly_target(sim.structure(1), sim.structure(1)) == false)
	_until(sim, SimEvents.HIJACK_COMPLETE)
	var evs: Array[Dictionary] = _steps(sim, _disable_ticks(cfg))
	assert_eq(_of(evs, SimEvents.TURNCOAT_FIRED).size(), 0)
	for s: StructureState in sim.structures:
		if s.id != 1:
			assert_eq(s.hp, s.max_hp, s.type_id)


func test_no_chaining_onto_a_recent_victim() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _units(2))
	_until(sim, SimEvents.TURNCOAT_FIRED)
	# Phage 3 stands in as a would-be second hijacker of the B-Cell the turncoat just hit.
	var second: PathogenState = sim.pathogen(3)
	second.alive = true
	assert_false(sim._can_hijack(second, sim.structure(2)))
	var hit_tick: int = int(sim._turncoat_hit_tick[2])
	sim.tick = hit_tick + _disable_ticks(cfg)
	assert_true(sim._can_hijack(second, sim.structure(2)))


func test_hash_carries_turncoat_state() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _units())
	_until(sim, SimEvents.TURNCOAT_FIRED)
	var before: String = sim.state_hash()
	sim.structure(1).turncoat_budget += 1
	assert_ne(sim.state_hash(), before)


func test_determinism() -> void:
	var a: BattleSim = _sim(_cfg(), _units(2))
	var b: BattleSim = _sim(_cfg(), _units(2))
	_steps(a, 400)
	_steps(b, 400)
	assert_eq(a.state_hash(), b.state_hash())
	assert_gt(a.turncoat_damage_dealt, 0)


func test_overlay_draws_a_beam_per_shot() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _units())
	var overlay := BattleOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(sim, cfg, null, null, null)
	var evs: Array[Dictionary] = _until(sim, SimEvents.TURNCOAT_FIRED)
	for ev: Dictionary in evs:
		overlay.on_event(ev)
	assert_eq(overlay.beam_count(), 1)
