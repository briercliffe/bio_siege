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

var _events: Array[Dictionary] = []
var _occupancy: Dictionary = {}  # Vector2i -> int


func _init(p_config: GameConfig, setup: BattleSetup) -> void:
	config = p_config
	status = StatusEffects.new()

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
		var p_state := PathogenState.create(uid, type_id, p_def, cell)
		pathogens.append(p_state)

		_emit_event(SimEvents.UNIT_SPAWNED, {
			"unit_id": p_state.id,
			"unit_type": p_state.type_id,
			"pos": p_state.pos,
		})


func step() -> void:
	if finished:
		return

	path_service.begin_tick()
	status.tick()

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
	lines.append("T:%d" % tick)
	for s: StructureState in structures:
		lines.append("S:%d:%d:%d" % [s.id, s.hp, 1 if s.alive else 0])
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
	for proj: ProjectileState in projectiles:
		lines.append("J:%d:%d:%d:%d" % [
			proj.id,
			proj.pos.x,
			proj.pos.y,
			1 if proj.alive else 0,
		])
	var combined: String = "\n".join(lines)
	return combined.sha256_text()


func damage_pathogen(p: PathogenState, amount: int, source_structure_id: int) -> void:
	if p == null or not p.alive:
		return
	p.hp = maxi(0, p.hp - amount)
	_emit_event(SimEvents.PATHOGEN_DAMAGED, {
		"unit_id": p.id,
		"amount": amount,
		"hp": p.hp,
		"source_structure_id": source_structure_id,
	})
	if p.hp == 0:
		p.alive = false
		p.state = PathogenState.State.DEAD
		pathogens_killed += 1
		var key: String = StatusEffects.key_pathogen(p.id)
		status.clear_entity(key)
		_emit_event(SimEvents.PATHOGEN_KILLED, {
			"unit_id": p.id,
			"unit_type": p.type_id,
			"source_structure_id": source_structure_id,
		})


func _update_towers() -> void:
	pass


func _update_projectiles() -> void:
	pass


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
		var budget: int = FixedMath.apply_pct(p.def.speed_mt_per_tick, status.pct(key, StatusEffects.Kind.SPEED_PCT))
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


func _pathogen_attack(p: PathogenState, victim: StructureState) -> void:
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

	var dmg: int = FixedMath.apply_pct(p.def.attack_damage, mult)
	var key_p: String = StatusEffects.key_pathogen(p.id)
	var key_s: String = StatusEffects.key_structure(victim.id)
	dmg = FixedMath.apply_pct(dmg, status.pct(key_p, StatusEffects.Kind.DAMAGE_DEALT_PCT))
	dmg = FixedMath.apply_pct(dmg, status.pct(key_s, StatusEffects.Kind.DAMAGE_TAKEN_PCT))
	dmg = maxi(dmg, 1)

	_damage_structure(victim, dmg, p.id)
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


func _emit_event(type: String, payload: Dictionary) -> void:
	var event := {
		"type": type,
		"tick": tick,
	}
	for k: Variant in payload.keys():
		event[k] = payload[k]
	_events.append(event)


func _is_any_pathogen_alive() -> bool:
	for p: PathogenState in pathogens:
		if p != null and p.alive:
			return true
	return false
