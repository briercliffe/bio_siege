class_name BattleSim
extends RefCounted

var config: GameConfig
var tick: int = 0
var finished: bool = false
var outcome: String = ""        # "attacker" or "defender"
var end_reason: String = ""     # "nucleus_destroyed", "all_pathogens_dead" or "timeout"
var structures: Array[StructureState] = []   # structures[id - 1]
var pathogens: Array[PathogenState] = []     # pathogens[id - 1]
var projectiles: Array[ProjectileState] = []
var path_service: PathService
var status: StatusEffects
var nucleus_id: int = 0
var first_contact_tick: int = -1  # tick of the first damage dealt by any pathogen
var structures_destroyed: int = 0
var pathogens_killed: int = 0
var first_destroyed_structure_id: int = 0
var first_destroyed_structure_type: String = ""
var seed: int = 0

var _events: Array[Dictionary] = []
var _occupancy: Dictionary = {}  # Vector2i -> int
var _next_projectile_id: int = 0
var _analysis_on: bool = false
var biofilm: Biofilm = Biofilm.new()
var _biofilm_on: bool = false
var _strains_on: bool = false
var _biofilm_regroup_ticks: int = 0
var _hijack_on: bool = false
var _channeled_by: Dictionary = {}  # structure id -> unit id
var pathogens_consumed: int = 0
var hijacks_completed: int = 0
var hijacks_interrupted: int = 0
var _turncoat_on: bool = false
var _turncoat_hit_tick: Dictionary = {}  # structure id -> last tick it took turncoat damage
var turncoat_damage_dealt: int = 0
var _coevo_on: bool = false
var _pools: Dictionary = {}  # type_id -> BreedPool
var _survival_granted: bool = false


func _init(p_config: GameConfig, setup: BattleSetup) -> void:
	config = p_config
	status = StatusEffects.new()
	_analysis_on = p_config != null and p_config.flag("bcell_analysis")
	_biofilm_on = p_config != null and p_config.flag("biofilm")
	_hijack_on = p_config != null and p_config.flag("phage_hijack")
	_turncoat_on = _hijack_on and p_config.flag("phage_turncoat")
	_strains_on = p_config != null and p_config.flag("strains")
	_coevo_on = p_config != null and p_config.coevolution_enabled()
	if _biofilm_on:
		for pd: PathogenDef in p_config.pathogens.values():
			if pd.has_biofilm and (_biofilm_regroup_ticks == 0 or pd.biofilm_regroup_ticks < _biofilm_regroup_ticks):
				_biofilm_regroup_ticks = pd.biofilm_regroup_ticks
	if setup != null:
		seed = setup.seed

	if config == null:
		push_error("Config is null")
		finished = true
		outcome = ""
		return

	if setup == null:
		push_error("Setup is null")
		finished = true
		outcome = ""
		return

	var errors: PackedStringArray = setup.validate(config)
	if not errors.is_empty():
		for err: String in errors:
			push_error(err)
		finished = true
		outcome = ""
		return

	path_service = PathService.new(
		config.grid_width,
		config.grid_height,
		config.empty_path_weight,
		config.max_path_recalcs_per_tick
	)

	var structure_genome_counts: Dictionary = {}
	var pathogen_genome_counts: Dictionary = {}
	if _coevo_on:
		for pool_type: String in config.coevo_types:
			var pop: Variant = setup.populations.get(pool_type, null)
			if pop is Dictionary:
				_pools[pool_type] = BreedPool.from_dict(pop, pool_type, config)
			else:
				_pools[pool_type] = BreedPool.wild_pool(pool_type, config)

	for i: int in range(setup.structures.size()):
		var s_data: Dictionary = setup.structures[i]
		var type_id: String = str(s_data.get("type", ""))
		var origin := Vector2i.ZERO
		var origin_val: Variant = s_data.get("origin")
		if origin_val is Vector2i:
			origin = origin_val
		elif origin_val is Array and (origin_val as Array).size() >= 2:
			origin = Vector2i(int((origin_val as Array)[0]), int((origin_val as Array)[1]))

		var s_def: StructureDef = config.structures[type_id]
		var sid: int = i + 1
		var s_state := StructureState.create(sid, type_id, s_def, origin)
		structures.append(s_state)
		if _coevo_on and config.is_breeding_type(type_id):
			var sn: int = int(structure_genome_counts.get(type_id, 0))
			s_state.genome_index = sn % config.coevo_pool_size
			structure_genome_counts[type_id] = sn + 1

		if s_def.has_tag("core") or type_id == "nucleus":
			nucleus_id = sid

		for cell: Vector2i in s_state.cells():
			_occupancy[cell] = sid
			path_service.set_cell_weight(cell, s_def.path_weight)

	for i: int in range(setup.units.size()):
		var u_data: Dictionary = setup.units[i]
		var type_id: String = str(u_data.get("type", ""))
		var cell := Vector2i.ZERO
		var cell_val: Variant = u_data.get("cell")
		if cell_val is Vector2i:
			cell = cell_val
		elif cell_val is Array and (cell_val as Array).size() >= 2:
			cell = Vector2i(int((cell_val as Array)[0]), int((cell_val as Array)[1]))

		var p_def: PathogenDef = config.pathogens[type_id]
		var uid: int = i + 1
		var u_strain: StrainDef = null
		if _strains_on:
			u_strain = p_def.strain(str(u_data.get("strain", "wild")))
		var p_state := PathogenState.create(uid, type_id, p_def, cell, u_strain)
		pathogens.append(p_state)
		if _coevo_on and config.is_breeding_type(type_id):
			var pn: int = int(pathogen_genome_counts.get(type_id, 0))
			p_state.genome_index = pn % config.coevo_pool_size
			pathogen_genome_counts[type_id] = pn + 1

		_emit_event(SimEvents.UNIT_SPAWNED, {
			"unit_id": p_state.id,
			"unit_type": p_state.type_id,
			"pos": p_state.pos,
		})

	if _analysis_on and not setup.memory_seed.is_empty():
		_apply_memory_seed(setup.memory_seed)


## Immune memory: pre-load every analysis tower with partial (or full) exposure.
func _apply_memory_seed(memory_seed: Dictionary) -> void:
	var keys: Array[String] = []
	for k: Variant in memory_seed.keys():
		keys.append(str(k))
	keys.sort()
	for s: StructureState in structures:
		if not s.def.has_analysis:
			continue
		for key: String in keys:
			var pct: int = int(memory_seed[key])
			if pct <= 0:
				continue
			s.analysis_exposure[key] = s.def.analysis_threshold_ticks * pct
			if pct >= 100:
				s.analyzed[key] = true
				_emit_event(SimEvents.ANALYSIS_COMPLETE, {"structure_id": s.id, "strain_key": key, "unit_type": key.get_slice("/", 0)})


func step() -> void:
	if finished:
		return

	path_service.begin_tick()
	status.tick()

	if _biofilm_on and _biofilm_regroup_ticks > 0 and tick % _biofilm_regroup_ticks == 0:
		if biofilm.regroup(pathogens):
			_emit_biofilm_changed()

	for p: PathogenState in pathogens:
		if p.alive:
			_update_pathogen(p)

	_update_towers()
	_update_projectiles()

	var nuc: StructureState = structure(nucleus_id)
	if nuc == null or not nuc.alive:
		_finish("attacker", "nucleus_destroyed")
	elif not _is_any_pathogen_alive():
		_finish("defender", "all_pathogens_dead")

	tick += 1

	if not finished and tick >= config.battle_timeout_ticks:
		_finish("defender", "timeout")


func run_to_end(max_ticks: int = -1) -> void:
	if max_ticks >= 0:
		var steps_left: int = max_ticks
		while not finished and steps_left > 0:
			step()
			steps_left -= 1
	else:
		while not finished:
			step()


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _events.duplicate()
	_events.clear()
	return result


func structure(id: int) -> StructureState:
	if id <= 0 or id > structures.size():
		return null
	return structures[id - 1]


func pathogen(id: int) -> PathogenState:
	if id <= 0 or id > pathogens.size():
		return null
	return pathogens[id - 1]


func structure_id_at(cell: Vector2i) -> int:
	if not _occupancy.has(cell):
		return 0
	var sid: int = int(_occupancy[cell])
	var s: StructureState = structure(sid)
	if s != null and s.alive:
		return sid
	_occupancy.erase(cell)
	return 0


func state_hash() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Seed:%d" % seed)
	lines.append("T:%d" % tick)
	for s: StructureState in structures:
		lines.append("S:%d:%d:%d" % [s.id, s.hp, 1 if s.alive else 0])
	for s: StructureState in structures:
		if s.analysis_exposure.is_empty():
			continue
		var akeys: Array = s.analysis_exposure.keys()
		akeys.sort()
		for akey: Variant in akeys:
			lines.append("A:%d:%s:%d:%d" % [s.id, str(akey), int(s.analysis_exposure[akey]), 1 if s.analyzed.has(akey) else 0])
	for p: PathogenState in pathogens:
		lines.append("P:%d:%d:%d:%d:%d:%d:%d:%d:%d" % [
			p.id,
			p.pos.x,
			p.pos.y,
			p.hp,
			1 if p.alive else 0,
			int(p.state),
			p.target_id,
			p.blocker_id,
			p.path_index,
		])
	for p: PathogenState in pathogens:
		if p.channel_target_id != 0:
			lines.append("H:%d:%d:%d" % [p.id, p.channel_target_id, p.channel_ticks_left])
	if _turncoat_on:
		for s: StructureState in structures:
			if s.turncoat_until_tick >= 0:
				lines.append("TC:%d:%d:%d:%d" % [s.id, s.turncoat_until_tick, s.turncoat_budget, s.turncoat_target_id])
	for proj: ProjectileState in projectiles:
		lines.append("J:%d:%d:%d:%d" % [
			proj.id,
			proj.pos.x,
			proj.pos.y,
			1 if proj.alive else 0,
		])
	if not biofilm.group_of.is_empty():
		var bkeys: Array = biofilm.group_of.keys()
		bkeys.sort()
		for bk: Variant in bkeys:
			lines.append("B:%d:%d" % [int(bk), int(biofilm.group_of[bk])])
	if _coevo_on:
		for s: StructureState in structures:
			if s.genome_index >= 0:
				lines.append("G:S:%d:%d" % [s.id, s.genome_index])
		for p: PathogenState in pathogens:
			if p.genome_index >= 0:
				lines.append("G:P:%d:%d" % [p.id, p.genome_index])
	var combined: String = "\n".join(lines)
	return combined.sha256_text()


func damage_pathogen(p: PathogenState, amount: int, source_structure_id: int) -> void:
	if p == null or not p.alive:
		return
	var ids: Array[int] = []
	if _biofilm_on:
		ids = biofilm.members(p.id)
	if ids.size() < 2:
		_apply_pathogen_damage(p, amount, source_structure_id)
		return
	var total: int = maxi(1, FixedMath.apply_pct(amount, p.def.biofilm_damage_taken_pct))
	var share: int = total / ids.size()
	var rem: int = total % ids.size()
	for id: int in ids:
		var dmg: int = share + (rem if id == p.id else 0)
		var m: PathogenState = pathogen(id)
		if dmg > 0 and m != null and m.alive:
			_apply_pathogen_damage(m, dmg, source_structure_id)


func _emit_biofilm_changed() -> void:
	var roots: Array = biofilm.groups.keys()
	roots.sort()
	var out: Array = []
	for r: Variant in roots:
		out.append((biofilm.groups[r] as Array).duplicate())
	_emit_event(SimEvents.BIOFILM_CHANGED, {"groups": out})


func _apply_pathogen_damage(p: PathogenState, amount: int, source_structure_id: int) -> void:
	if p == null or not p.alive:
		return
	p.hp = maxi(0, p.hp - amount)
	if _coevo_on and source_structure_id != 0:
		var src: StructureState = structure(source_structure_id)
		if src != null and src.genome_index >= 0:
			var src_pool: BreedPool = _pools.get(src.type_id, null)
			if src_pool != null:
				src_pool.add_fitness(src.genome_index, amount)
	_emit_event(SimEvents.PATHOGEN_DAMAGED, {
		"unit_id": p.id,
		"amount": amount,
		"hp": p.hp,
		"source_structure_id": source_structure_id,
	})
	if p.hp == 0:
		p.alive = false
		p.cause_of_death = "killed"
		p.state = PathogenState.State.DEAD
		if p.channel_target_id != 0:
			_clear_channel(p, "unit_died")
		biofilm.remove(p.id)
		pathogens_killed += 1
		var key: String = StatusEffects.key_pathogen(p.id)
		status.clear_entity(key)
		_emit_event(SimEvents.PATHOGEN_KILLED, {
			"unit_id": p.id,
			"unit_type": p.type_id,
			"source_structure_id": source_structure_id,
		})


## Receptor-vs-antigen damage percent (100 = x1). Missing pools or genomes mean no change.
func _match_pct(attacker_type: String, attacker_index: int, defender_type: String, defender_index: int) -> int:
	var a_pool: BreedPool = _pools.get(attacker_type, null)
	var d_pool: BreedPool = _pools.get(defender_type, null)
	if a_pool == null or d_pool == null:
		return 100
	if attacker_index < 0 or attacker_index >= a_pool.genomes.size() or defender_index < 0 or defender_index >= d_pool.genomes.size():
		return 100
	return a_pool.match_pct(a_pool.genomes[attacker_index], d_pool.genomes[defender_index], config)


## Adds the survival bonus once to every alive genome. No-op when coevolution is off.
func grant_survival_bonus() -> void:
	if not _coevo_on or _survival_granted:
		return
	_survival_granted = true
	var alive_by_type: Dictionary = {}
	for s: StructureState in structures:
		if s.alive and s.genome_index >= 0:
			_collect_alive(alive_by_type, s.type_id, s.genome_index)
	for p: PathogenState in pathogens:
		if p.alive and p.genome_index >= 0:
			_collect_alive(alive_by_type, p.type_id, p.genome_index)
	for type_id: Variant in alive_by_type.keys():
		var pool: BreedPool = _pools.get(str(type_id), null)
		if pool != null:
			pool.apply_survival(alive_by_type[type_id], config)


func _collect_alive(into: Dictionary, type_id: String, index: int) -> void:
	if not into.has(type_id):
		var fresh: Array[int] = []
		into[type_id] = fresh
	(into[type_id] as Array[int]).append(index)


## type_id -> copy of that pool's fitness array. Empty when coevolution is off.
func fitness_by_type() -> Dictionary:
	var out: Dictionary = {}
	for type_id: Variant in _pools.keys():
		out[type_id] = (_pools[type_id] as BreedPool).fitness.duplicate()
	return out


func _tower_damage(s: StructureState, victim: PathogenState) -> int:
	if s == null or s.def == null or victim == null or victim.def == null:
		return 0
	var mult: int = 100
	for tag: String in victim.def.tags:
		if s.def.damage_multipliers_pct.has(tag):
			mult = maxi(mult, int(s.def.damage_multipliers_pct[tag]))
	var dmg: int = FixedMath.apply_pct(s.def.attack_damage, mult)
	if _analysis_on and s.def.has_analysis and s.analyzed.has(victim.strain_key()):
		dmg = FixedMath.apply_pct(dmg, s.def.analysis_multiplier_pct)
	if _coevo_on and s.genome_index >= 0 and victim.genome_index >= 0:
		dmg = FixedMath.apply_pct(dmg, _match_pct(s.type_id, s.genome_index, victim.type_id, victim.genome_index))
	dmg = FixedMath.apply_pct(dmg, status.pct(StatusEffects.key_structure(s.id), StatusEffects.Kind.DAMAGE_DEALT_PCT))
	dmg = FixedMath.apply_pct(dmg, status.pct(StatusEffects.key_pathogen(victim.id), StatusEffects.Kind.DAMAGE_TAKEN_PCT))
	return maxi(dmg, 1)


func _tower_fire(s: StructureState, target: PathogenState) -> void:
	if s == null or s.def == null or target == null:
		return
	if s.def.projectile_speed_mt_per_tick == 0:
		if s.def.splash_radius_mt > 0:
			var hit_unit_ids: Array[int] = []
			var victims: Array[PathogenState] = []
			for p: PathogenState in pathogens:
				if p != null and p.alive and FixedMath.within(target.pos, p.pos, s.def.splash_radius_mt):
					hit_unit_ids.append(p.id)
					victims.append(p)
			for p: PathogenState in victims:
				damage_pathogen(p, _tower_damage(s, p), s.id)
			_emit_event({
				"type": SimEvents.SPLASH,
				"tick": tick,
				"structure_id": s.id,
				"pos": target.pos,
				"radius": s.def.splash_radius_mt,
				"hit_unit_ids": hit_unit_ids,
			})
		else:
			damage_pathogen(target, _tower_damage(s, target), s.id)
	elif s.def.projectile_speed_mt_per_tick > 0:
		_next_projectile_id += 1
		var p_id: int = _next_projectile_id
		var proj := ProjectileState.create(p_id, s.id, target.id, s.center, s.def.projectile_speed_mt_per_tick, 0)
		projectiles.append(proj)
		_emit_event({
			"type": SimEvents.PROJECTILE_SPAWNED,
			"tick": tick,
			"projectile_id": p_id,
			"structure_id": s.id,
			"target_unit_id": target.id,
		})


func _update_towers() -> void:
	for s: StructureState in structures:
		if s.turncoat_until_tick >= 0 and s.alive:
			_update_turncoat(s)
			continue
		if not s.alive or s.def == null or not s.def.has_attack or status.has_flag(StatusEffects.key_structure(s.id), StatusEffects.Kind.DISABLED):
			continue
		if s.attack_cooldown > 0:
			s.attack_cooldown -= 1
		if not Targeting.tower_keeps_target(s, pathogen(s.target_id)):
			s.target_id = Targeting.pick_unit_target(s, pathogens)
		if _analysis_on and s.def.has_analysis:
			_accrue_analysis(s)
		if s.target_id != 0 and s.attack_cooldown == 0:
			var tgt: PathogenState = pathogen(s.target_id)
			_tower_fire(s, tgt)
			s.attack_cooldown = maxi(1, FixedMath.apply_pct(s.def.attack_interval_ticks, status.pct(StatusEffects.key_structure(s.id), StatusEffects.Kind.ATTACK_INTERVAL_PCT)))
			_emit_event({
				"type": SimEvents.TOWER_FIRED,
				"tick": tick,
				"structure_id": s.id,
				"target_unit_id": tgt.id,
			})


## Hijack turncoat (#150): while its window lasts, a hijacked tower shoots nearby friendly
## defense/support structures instead of pathogens. Instant hits, capped by turncoat_budget.
func _update_turncoat(s: StructureState) -> void:
	if tick >= s.turncoat_until_tick or s.turncoat_budget <= 0:
		_end_turncoat(s)
		return
	if s.attack_cooldown > 0:
		s.attack_cooldown -= 1
	if not Targeting.is_friendly_target(s, structure(s.turncoat_target_id)):
		s.turncoat_target_id = Targeting.pick_friendly_target(s, structures)
	if s.turncoat_target_id == 0 or s.attack_cooldown > 0:
		return
	var victim: StructureState = structure(s.turncoat_target_id)
	var dmg: int = mini(s.turncoat_budget, maxi(1, FixedMath.apply_pct(s.def.attack_damage, s.turncoat_pct)))
	_damage_structure(victim, dmg, 0)
	_turncoat_hit_tick[victim.id] = tick
	s.turncoat_budget -= dmg
	turncoat_damage_dealt += dmg
	s.attack_cooldown = maxi(1, s.def.attack_interval_ticks)
	_emit_event(SimEvents.TURNCOAT_FIRED, {
		"structure_id": s.id,
		"target_structure_id": victim.id,
		"amount": dmg,
	})
	if s.turncoat_budget <= 0:
		_end_turncoat(s)


func _end_turncoat(s: StructureState) -> void:
	# The rest of the DISABLED window still runs out as before.
	s.turncoat_until_tick = -1
	s.turncoat_target_id = 0
	s.turncoat_budget = 0


func _accrue_analysis(s: StructureState) -> void:
	if s.target_id == 0:
		s.analysis_focus_key = ""
		return
	var tgt: PathogenState = pathogen(s.target_id)
	var key: String = tgt.strain_key()
	s.analysis_focus_key = key
	if s.analyzed.has(key):
		return
	var e: int = int(s.analysis_exposure.get(key, 0)) + tgt.analysis_rate_pct
	s.analysis_exposure[key] = e
	if e >= s.def.analysis_threshold_ticks * 100:
		s.analyzed[key] = true
		_emit_event(SimEvents.ANALYSIS_COMPLETE, {"structure_id": s.id, "strain_key": key, "unit_type": tgt.type_id})


## Sorted, unique strain keys of every pathogen in the battle.
func seen_strain_keys() -> Array[String]:
	var seen: Dictionary = {}
	for p: PathogenState in pathogens:
		seen[p.strain_key()] = true
	var out: Array[String] = []
	for k: Variant in seen.keys():
		out.append(str(k))
	out.sort()
	return out


## Sorted, unique strain keys analyzed by any tower, alive or destroyed.
func analyzed_strain_keys() -> Array[String]:
	var seen: Dictionary = {}
	for s: StructureState in structures:
		for k: Variant in s.analyzed.keys():
			seen[str(k)] = true
	var out: Array[String] = []
	for k: Variant in seen.keys():
		out.append(str(k))
	out.sort()
	return out


func _update_projectiles() -> void:
	for j: ProjectileState in projectiles:
		if not j.alive:
			continue
		var tgt: PathogenState = pathogen(j.target_id)
		if tgt == null or not tgt.alive:
			j.alive = false
			_emit_event({
				"type": SimEvents.PROJECTILE_FIZZLED,
				"tick": tick,
				"projectile_id": j.id,
				"structure_id": j.source_id,
				"target_unit_id": j.target_id,
			})
			continue
		j.pos = FixedMath.move_towards(j.pos, tgt.pos, j.speed)
		if j.pos == tgt.pos:
			damage_pathogen(tgt, _tower_damage(structure(j.source_id), tgt), j.source_id)
			j.alive = false
			_emit_event({
				"type": SimEvents.PROJECTILE_HIT,
				"tick": tick,
				"projectile_id": j.id,
				"structure_id": j.source_id,
				"target_unit_id": j.target_id,
			})

	var alive_projectiles: Array[ProjectileState] = []
	for j: ProjectileState in projectiles:
		if j.alive:
			alive_projectiles.append(j)
	projectiles = alive_projectiles



func _update_pathogen(p: PathogenState) -> void:
	var key: String = StatusEffects.key_pathogen(p.id)
	var at_center: bool = (p.pos == FixedMath.cell_center(p.cell))

	# 1. Cooldown
	if p.attack_cooldown > 0:
		p.attack_cooldown -= 1

	# 2. Target lock
	var cur_target: StructureState = structure(p.target_id)
	if cur_target == null or not cur_target.alive:
		var old_target_id: int = p.target_id
		if p.channel_target_id != 0:
			_clear_channel(p, "target_destroyed")
		p.target_id = Targeting.pick_structure_target(p, structures)
		p.blocker_id = 0
		p.path_version = -1
		p.state = PathogenState.State.SEEKING
		if p.target_id != old_target_id:
			_emit_event(SimEvents.UNIT_TARGET_CHANGED, {
				"unit_id": p.id,
				"target_id": p.target_id,
			})
		if p.target_id == 0:
			return

	# 3. Blocker died
	if p.blocker_id != 0:
		var blocker: StructureState = structure(p.blocker_id)
		if blocker == null or not blocker.alive:
			p.blocker_id = 0
			p.state = PathogenState.State.SEEKING

	# 4. Keep attacking
	if p.state == PathogenState.State.ATTACKING:
		var victim: StructureState = structure(p.attacking_id())
		if victim != null and victim.alive:
			_pathogen_attack(p, victim)
			return
		else:
			p.state = PathogenState.State.SEEKING

	# 5. (Re)path
	if at_center and (p.path.is_empty() or p.path_version != path_service.grid_version):
		var target: StructureState = structure(p.target_id)
		var goal: Vector2i = Targeting.goal_cell_for(p, target)
		if path_service.peek_cached(p.cell, goal) or path_service.can_compute():
			var computed_path: Array[Vector2i] = path_service.find_path(p.cell, goal)
			if computed_path.size() > 1:
				p.path = computed_path
				p.path_index = 1
				p.path_version = path_service.grid_version
				p.state = PathogenState.State.MOVING
			else:
				p.path = computed_path
				p.path_index = computed_path.size()
				p.path_version = path_service.grid_version
				p.state = PathogenState.State.SEEKING
		else:
			return

	# 6. Move
	if not status.has_flag(key, StatusEffects.Kind.ROOTED):
		var budget: int = _move_budget(p)
		while budget > 0 and p.path_index < p.path.size():
			var next: Vector2i = p.path[p.path_index]
			var occ: int = structure_id_at(next)
			if occ != 0 and p.pos == FixedMath.cell_center(p.cell):
				if occ != p.target_id:
					p.blocker_id = occ
					_emit_event(SimEvents.UNIT_BLOCKED, {
						"unit_id": p.id,
						"blocker_id": p.blocker_id,
					})
				p.state = PathogenState.State.ATTACKING
				var victim: StructureState = structure(occ)
				_pathogen_attack(p, victim)
				return
			var c: Vector2i = FixedMath.cell_center(next)
			var d: int = FixedMath.isqrt(FixedMath.dist_sq(p.pos, c))
			if d <= budget:
				p.pos = c
				p.cell = next
				p.path_index += 1
				budget -= d
				if p.path_version != path_service.grid_version:
					break
			else:
				p.pos = FixedMath.move_towards(p.pos, c, budget)
				budget = 0
		if p.path_index >= p.path.size():
			p.path = []
			p.state = PathogenState.State.SEEKING


func _unit_move_budget(p: PathogenState) -> int:
	return FixedMath.apply_pct(p.speed_mt_per_tick, status.pct(StatusEffects.key_pathogen(p.id), StatusEffects.Kind.SPEED_PCT))


## A biofilm group moves at the speed of its slowest alive member.
func _move_budget(p: PathogenState) -> int:
	var budget: int = _unit_move_budget(p)
	if not _biofilm_on or not biofilm.group_of.has(p.id):
		return budget
	for id: int in biofilm.members(p.id):
		var m: PathogenState = pathogen(id)
		if m != null and m.alive:
			budget = mini(budget, _unit_move_budget(m))
	return budget


func _can_hijack(p: PathogenState, victim: StructureState) -> bool:
	if not _hijack_on or not p.def.has_hijack or victim == null or not victim.alive:
		return false
	var tagged: bool = false
	for t: String in p.def.hijack_target_tags:
		if victim.def.has_tag(t):
			tagged = true
			break
	if not tagged:
		return false
	if status.has_flag(StatusEffects.key_structure(victim.id), StatusEffects.Kind.DISABLED):
		return false
	if _channeled_by.has(victim.id) and int(_channeled_by[victim.id]) != p.id:
		return false
	# No chaining: a structure a turncoat hit recently can't be hijacked.
	if _turncoat_on and _turncoat_hit_tick.has(victim.id) and tick - int(_turncoat_hit_tick[victim.id]) < p.def.hijack_disable_ticks:
		return false
	return true


func _hijack_tick(p: PathogenState, victim: StructureState) -> void:
	if p.channel_target_id != victim.id:
		p.channel_target_id = victim.id
		p.channel_ticks_left = p.def.hijack_channel_ticks
		_channeled_by[victim.id] = p.id
		_emit_event(SimEvents.HIJACK_STARTED, {
			"unit_id": p.id,
			"structure_id": victim.id,
			"channel_ticks": p.def.hijack_channel_ticks,
		})
		return
	p.channel_ticks_left -= 1
	if p.channel_ticks_left > 0:
		return
	status.add(StatusEffects.key_structure(victim.id), StatusEffects.Kind.DISABLED, 1, p.def.hijack_disable_ticks, "hijack:%d" % p.id)
	if _turncoat_on and victim.def.has_attack:
		victim.turncoat_until_tick = tick + p.def.hijack_disable_ticks
		victim.turncoat_budget = p.def.hijack_turncoat_max_damage
		victim.turncoat_pct = p.def.hijack_turncoat_damage_pct
		victim.turncoat_target_id = 0
	_emit_event(SimEvents.HIJACK_COMPLETE, {
		"unit_id": p.id,
		"structure_id": victim.id,
		"duration_ticks": p.def.hijack_disable_ticks,
	})
	hijacks_completed += 1
	p.hp = 0
	p.alive = false
	p.cause_of_death = "hijack"
	p.state = PathogenState.State.DEAD
	biofilm.remove(p.id)
	status.clear_entity(StatusEffects.key_pathogen(p.id))
	_channeled_by.erase(victim.id)
	p.channel_target_id = 0
	p.channel_ticks_left = 0
	pathogens_consumed += 1
	_emit_event(SimEvents.PATHOGEN_KILLED, {
		"unit_id": p.id,
		"unit_type": p.type_id,
		"source_structure_id": 0,
		"cause": "hijack",
	})


func _clear_channel(p: PathogenState, reason: String) -> void:
	_emit_event(SimEvents.HIJACK_INTERRUPTED, {
		"unit_id": p.id,
		"structure_id": p.channel_target_id,
		"reason": reason,
	})
	_channeled_by.erase(p.channel_target_id)
	p.channel_target_id = 0
	p.channel_ticks_left = 0
	hijacks_interrupted += 1


func _pathogen_attack(p: PathogenState, victim: StructureState) -> void:
	if _can_hijack(p, victim) or p.channel_target_id == victim.id:
		_hijack_tick(p, victim)
		return
	if p.attack_cooldown > 0:
		return
	var mult: int = 100
	var found_mult: bool = false
	var best_mult: int = 0
	for tag: String in victim.def.tags:
		if p.def.damage_multipliers_pct.has(tag):
			var m: int = int(p.def.damage_multipliers_pct[tag])
			if not found_mult or m > best_mult:
				best_mult = m
				found_mult = true
	if found_mult:
		mult = best_mult

	var dmg: int = FixedMath.apply_pct(p.attack_damage, mult)
	if _coevo_on and p.genome_index >= 0 and victim.genome_index >= 0:
		dmg = FixedMath.apply_pct(dmg, _match_pct(p.type_id, p.genome_index, victim.type_id, victim.genome_index))
	var key_p: String = StatusEffects.key_pathogen(p.id)
	var key_s: String = StatusEffects.key_structure(victim.id)
	dmg = FixedMath.apply_pct(dmg, status.pct(key_p, StatusEffects.Kind.DAMAGE_DEALT_PCT))
	dmg = FixedMath.apply_pct(dmg, status.pct(key_s, StatusEffects.Kind.DAMAGE_TAKEN_PCT))
	dmg = maxi(dmg, 1)

	_damage_structure(victim, dmg, p.id)
	if _coevo_on and p.genome_index >= 0:
		var atk_pool: BreedPool = _pools.get(p.type_id, null)
		if atk_pool != null:
			atk_pool.add_fitness(p.genome_index, dmg)
	p.attack_cooldown = maxi(1, FixedMath.apply_pct(p.def.attack_interval_ticks, status.pct(key_p, StatusEffects.Kind.ATTACK_INTERVAL_PCT)))
	if first_contact_tick < 0:
		first_contact_tick = tick


func _damage_structure(s: StructureState, dmg: int, unit_id: int) -> void:
	if s == null or not s.alive:
		return
	s.hp = maxi(0, s.hp - dmg)
	_emit_event(SimEvents.STRUCTURE_DAMAGED, {
		"structure_id": s.id,
		"amount": dmg,
		"hp": s.hp,
		"source_unit_id": unit_id,
	})
	if s.hp == 0:
		s.alive = false
		structures_destroyed += 1
		if first_destroyed_structure_id == 0:
			first_destroyed_structure_id = s.id
			first_destroyed_structure_type = s.type_id
		for cell: Vector2i in s.cells():
			_occupancy.erase(cell)
			path_service.clear_cell(cell)
		_emit_event(SimEvents.STRUCTURE_DESTROYED, {
			"structure_id": s.id,
			"structure_type": s.type_id,
		})


func _finish(p_outcome: String, p_reason: String) -> void:
	if finished:
		return
	finished = true
	outcome = p_outcome
	end_reason = p_reason
	_emit_event(SimEvents.BATTLE_ENDED, {
		"outcome": outcome,
		"end_reason": end_reason,
	})


func _emit_event(type_or_dict: Variant, payload: Dictionary = {}) -> void:
	var event: Dictionary = {}
	if type_or_dict is Dictionary:
		var d: Dictionary = type_or_dict as Dictionary
		event["type"] = d.get("type", "")
		event["tick"] = d.get("tick", tick)
		for k: Variant in d.keys():
			event[k] = d[k]
	else:
		event["type"] = str(type_or_dict)
		event["tick"] = tick
		for k: Variant in payload.keys():
			event[k] = payload[k]
	_events.append(event)


func _is_any_pathogen_alive() -> bool:
	for p: PathogenState in pathogens:
		if p != null and p.alive:
			return true
	return false
