extends GutTest

const MAX_STEPS: int = 600
const MAC_ORIGIN: Vector2i = Vector2i(8, 5)


func _cfg(flag_on: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["phage_hijack"] = flag_on
	return cfg


## Macrophage at MAC_ORIGIN (structure 1). Phages start west of it; the tower
## deals only 1 damage per shot so a phage survives its channel.
func _sim(cfg: GameConfig, units: Array, weak_tower: bool = true) -> BattleSim:
	var sim: BattleSim = SimFixtures.make_sim([{"type": "macrophage", "origin": MAC_ORIGIN}], units, 1, cfg)
	if weak_tower:
		sim.status.add(StatusEffects.key_structure(1), StatusEffects.Kind.DAMAGE_DEALT_PCT, 0, 10000, "weak")
	return sim


func _phages(n: int = 1) -> Array:
	var units: Array = []
	for i: int in range(n):
		units.append({"type": "bacteriophage", "cell": Vector2i(4 - i, 5)})
	return units


func _steps(sim: BattleSim, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(n):
		sim.step()
		out.append_array(sim.drain_events())
	return out


## Steps until an event of type_id appears (cap MAX_STEPS). Returns all events seen.
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


func _channel_ticks(cfg: GameConfig) -> int:
	return (cfg.pathogens["bacteriophage"] as PathogenDef).hijack_channel_ticks


func _disable_ticks(cfg: GameConfig) -> int:
	return (cfg.pathogens["bacteriophage"] as PathogenDef).hijack_disable_ticks


func test_start() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _phages())
	var evs: Array[Dictionary] = _until(sim, SimEvents.HIJACK_STARTED)
	var started: Array[Dictionary] = _of(evs, SimEvents.HIJACK_STARTED)
	assert_eq(started.size(), 1)
	assert_eq(started[0]["structure_id"], 1)
	assert_eq(started[0]["unit_id"], 1)
	assert_eq(started[0]["channel_ticks"], _channel_ticks(cfg))
	var during: Array[Dictionary] = _steps(sim, _channel_ticks(cfg) - 1)
	assert_eq(_of(during, SimEvents.STRUCTURE_DAMAGED).size(), 0)
	assert_eq(sim.structure(1).hp, sim.structure(1).max_hp)


func test_complete() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _phages())
	_until(sim, SimEvents.HIJACK_STARTED)
	var before: Array[Dictionary] = _steps(sim, _channel_ticks(cfg) - 1)
	assert_eq(_of(before, SimEvents.HIJACK_COMPLETE).size(), 0)
	var last: Array[Dictionary] = _steps(sim, 1)
	var done: Array[Dictionary] = _of(last, SimEvents.HIJACK_COMPLETE)
	assert_eq(done.size(), 1)
	assert_eq(done[0]["duration_ticks"], _disable_ticks(cfg))
	assert_eq(sim.status.get_duration(StatusEffects.key_structure(1), StatusEffects.Kind.DISABLED, "hijack:1"), _disable_ticks(cfg))
	assert_false(sim.pathogen(1).alive)
	assert_eq(sim.pathogen(1).channel_target_id, 0)
	assert_eq(sim.pathogens_consumed, 1)
	assert_eq(sim.hijacks_completed, 1)
	assert_eq(sim.pathogens_killed, 0)
	var killed: Array[Dictionary] = _of(last, SimEvents.PATHOGEN_KILLED)
	assert_eq(killed.size(), 1)
	assert_eq(killed[0]["cause"], "hijack")


func test_silence_then_resume() -> void:
	var cfg: GameConfig = _cfg()
	var units: Array = _phages()
	units.append({"type": "rhinovirus", "cell": Vector2i(8, 7)})
	var sim: BattleSim = _sim(cfg, units)
	sim.status.add(StatusEffects.key_pathogen(2), StatusEffects.Kind.ROOTED, 1, 100000, "root")
	sim.pathogen(2).hp = 100000
	sim.pathogen(2).max_hp = 100000
	_until(sim, SimEvents.HIJACK_COMPLETE)
	var silent: Array[Dictionary] = _steps(sim, _disable_ticks(cfg) - 1)
	assert_eq(_of(silent, SimEvents.TOWER_FIRED).size(), 0)
	var after: Array[Dictionary] = _steps(sim, 60)
	assert_gt(_of(after, SimEvents.TOWER_FIRED).size(), 0)


func test_interrupted_by_death() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _phages())
	_until(sim, SimEvents.HIJACK_STARTED)
	_steps(sim, 5)
	sim.damage_pathogen(sim.pathogen(1), 9999, 0)
	var evs: Array[Dictionary] = _of(sim.drain_events(), SimEvents.HIJACK_INTERRUPTED)
	assert_eq(evs.size(), 1)
	assert_eq(evs[0]["reason"], "unit_died")
	assert_eq(sim.hijacks_interrupted, 1)
	_steps(sim, 20)
	assert_false(sim.status.has_flag(StatusEffects.key_structure(1), StatusEffects.Kind.DISABLED))


func test_interrupted_by_target_loss() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _phages())
	_until(sim, SimEvents.HIJACK_STARTED)
	_steps(sim, 5)
	sim._damage_structure(sim.structure(1), 99999, 0)
	sim.drain_events()
	var evs: Array[Dictionary] = _of(_steps(sim, 1), SimEvents.HIJACK_INTERRUPTED)
	assert_eq(evs.size(), 1)
	assert_eq(evs[0]["reason"], "target_destroyed")
	assert_eq(sim.pathogen(1).channel_target_id, 0)


func test_one_channel_per_tower() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _phages(2))
	var evs: Array[Dictionary] = _until(sim, SimEvents.HIJACK_STARTED)
	evs.append_array(_steps(sim, _channel_ticks(cfg) - 2))
	assert_eq(_of(evs, SimEvents.HIJACK_STARTED).size(), 1)
	var dmg_from_2: int = 0
	for ev: Dictionary in _of(evs, SimEvents.STRUCTURE_DAMAGED):
		if ev["source_unit_id"] == 2:
			dmg_from_2 += 1
	assert_gt(dmg_from_2, 0)
	assert_eq(sim.pathogen(2).channel_target_id, 0)
	assert_eq(sim.pathogen(1).channel_target_id, 1)


func test_already_disabled_attacks_normally() -> void:
	var cfg: GameConfig = _cfg()
	var sim: BattleSim = _sim(cfg, _phages())
	sim.status.add(StatusEffects.key_structure(1), StatusEffects.Kind.DISABLED, 1, 10000, "other")
	var evs: Array[Dictionary] = _until(sim, SimEvents.STRUCTURE_DAMAGED)
	assert_eq(_of(evs, SimEvents.HIJACK_STARTED).size(), 0)
	var hits: Array[Dictionary] = _of(evs, SimEvents.STRUCTURE_DAMAGED)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0]["amount"], 60)


func test_walls_are_not_hijacked() -> void:
	var cfg: GameConfig = _cfg()
	var structs: Array = [{"type": "macrophage", "origin": MAC_ORIGIN}]
	for dx: int in range(-1, 4):
		for dy: int in range(-1, 4):
			var inside_tower: bool = dx >= 0 and dx < 3 and dy >= 0 and dy < 3
			if not inside_tower:
				structs.append({"type": "mucous_wall", "origin": MAC_ORIGIN + Vector2i(dx, dy)})
	var sim: BattleSim = SimFixtures.make_sim(structs, _phages(), 1, cfg)
	sim.status.add(StatusEffects.key_structure(1), StatusEffects.Kind.DISABLED, 1, 10000, "off")
	var evs: Array[Dictionary] = _until(sim, SimEvents.STRUCTURE_DAMAGED)
	var hit: Dictionary = _of(evs, SimEvents.STRUCTURE_DAMAGED)[0] if not _of(evs, SimEvents.STRUCTURE_DAMAGED).is_empty() else {}
	assert_false(hit.is_empty())
	assert_gt(int(hit.get("structure_id", 0)), 1)
	assert_eq(_of(evs, SimEvents.HIJACK_STARTED).size(), 0)


func test_flag_off() -> void:
	var cfg: GameConfig = _cfg(false)
	var sim: BattleSim = _sim(cfg, _phages())
	var evs: Array[Dictionary] = _steps(sim, 400)
	assert_eq(_of(evs, SimEvents.HIJACK_STARTED).size(), 0)
	assert_eq(_of(evs, SimEvents.HIJACK_COMPLETE).size(), 0)
	assert_eq(_of(evs, SimEvents.HIJACK_INTERRUPTED).size(), 0)
	assert_eq(sim.pathogens_consumed, 0)
	# Flag on but no channel ever starts: the hash matches the flag-off hash.
	var off_sim: BattleSim = _sim(_cfg(false), _phages())
	var on_sim: BattleSim = _sim(_cfg(true), _phages())
	for p: PathogenState in on_sim.pathogens:
		on_sim.status.add(StatusEffects.key_pathogen(p.id), StatusEffects.Kind.ROOTED, 1, 100000, "root")
	for p: PathogenState in off_sim.pathogens:
		off_sim.status.add(StatusEffects.key_pathogen(p.id), StatusEffects.Kind.ROOTED, 1, 100000, "root")
	_steps(off_sim, 50)
	_steps(on_sim, 50)
	assert_eq(on_sim.state_hash(), off_sim.state_hash())


func test_determinism() -> void:
	var a: BattleSim = _sim(_cfg(), _phages(2))
	var b: BattleSim = _sim(_cfg(), _phages(2))
	_steps(a, 400)
	_steps(b, 400)
	assert_eq(a.state_hash(), b.state_hash())
	assert_gt(a.hijacks_completed + a.hijacks_interrupted, 0)
