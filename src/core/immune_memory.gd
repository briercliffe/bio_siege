class_name ImmuneMemory
extends RefCounted

## Base-side immune memory: strains the B-Cells have learned across raids.
## Pure integer logic; configuration comes from GameConfig.memory_* fields.

var raids: int = 0
var entries: Dictionary = {}  # strain_key -> {"level": int, "absent": int, "since": int}


func level_of(strain_key: String) -> int:
	if not entries.has(strain_key):
		return 0
	return int((entries[strain_key] as Dictionary).get("level", 0))


## Own level, or the best drifted level from another strain of the same pathogen type.
func effective_level(strain_key: String, cfg: GameConfig) -> int:
	var best: int = level_of(strain_key)
	var type_id: String = strain_key.get_slice("/", 0)
	for k_var: Variant in entries.keys():
		var k: String = str(k_var)
		if k == strain_key or k.get_slice("/", 0) != type_id:
			continue
		var drifted: int = level_of(k) * cfg.memory_drift_pct / 100
		if drifted > best:
			best = drifted
	return best


func seed_pct(strain_key: String, cfg: GameConfig) -> int:
	return mini(100, effective_level(strain_key, cfg) * cfg.memory_seed_pct_per_level)


func seed_map(strain_keys: Array[String], cfg: GameConfig) -> Dictionary:
	var out: Dictionary = {}
	for k: String in strain_keys:
		var pct: int = seed_pct(k, cfg)
		if pct > 0:
			out[k] = pct
	return out


## `slots_override` and `decay_override` replace cfg.memory_slots and cfg.memory_decay_raids for this base
## (Living Base upgrades); -1 uses the config.
func update_after_raid(seen: Array[String], analyzed: Array[String], cfg: GameConfig, slots_override: int = -1, decay_override: int = -1) -> Array[Dictionary]:
	var slots: int = slots_override if slots_override >= 0 else cfg.memory_slots
	var decay: int = decay_override if decay_override >= 0 else cfg.memory_decay_raids
	var changes: Array[Dictionary] = []
	raids += 1

	var keys: Array[String] = _sorted_keys()
	for k: String in keys:
		if seen.has(k):
			continue
		var e: Dictionary = entries[k]
		e["absent"] = int(e["absent"]) + 1
		if int(e["absent"]) >= decay:
			var from_level: int = int(e["level"])
			e["level"] = from_level - 1
			e["absent"] = 0
			if int(e["level"]) <= 0:
				entries.erase(k)
				changes.append({"strain_key": k, "from": from_level, "to": 0, "reason": "forgotten"})
			else:
				changes.append({"strain_key": k, "from": from_level, "to": from_level - 1, "reason": "waned"})

	for k: String in seen:
		if entries.has(k):
			(entries[k] as Dictionary)["absent"] = 0

	var learn: Array[String] = []
	for k: String in analyzed:
		if not learn.has(k):
			learn.append(k)
	learn.sort()
	for k: String in learn:
		if entries.has(k):
			var e2: Dictionary = entries[k]
			var old_level: int = int(e2["level"])
			var new_level: int = mini(cfg.memory_max_level, old_level + 1)
			if new_level != old_level:
				e2["level"] = new_level
				changes.append({"strain_key": k, "from": old_level, "to": new_level, "reason": "learned"})
		else:
			if entries.size() >= slots:
				var victim: String = _eviction_victim()
				if victim != "":
					changes.append({"strain_key": victim, "from": level_of(victim), "to": 0, "reason": "evicted"})
					entries.erase(victim)
			entries[k] = {"level": 1, "absent": 0, "since": raids}
			changes.append({"strain_key": k, "from": 0, "to": 1, "reason": "learned"})
	return changes


func clamp_to(cfg: GameConfig, slots_override: int = -1) -> void:
	var slots: int = slots_override if slots_override >= 0 else cfg.memory_slots
	for k: String in _sorted_keys():
		var e: Dictionary = entries[k]
		if int(e["level"]) > cfg.memory_max_level:
			e["level"] = cfg.memory_max_level
	while entries.size() > slots and not entries.is_empty():
		entries.erase(_eviction_victim())


func is_empty() -> bool:
	return entries.is_empty()


func to_dict() -> Dictionary:
	return {"raids": raids, "entries": entries.duplicate(true)}


static func from_dict(d: Dictionary, cfg: GameConfig, slots_override: int = -1) -> ImmuneMemory:
	var m := ImmuneMemory.new()
	var raids_val: Variant = d.get("raids", 0)
	if _is_whole(raids_val) and int(raids_val) >= 0:
		m.raids = int(raids_val)
	var ent_val: Variant = d.get("entries", {})
	if ent_val is Dictionary:
		for k_var: Variant in (ent_val as Dictionary).keys():
			if typeof(k_var) != TYPE_STRING or str(k_var).is_empty():
				continue
			var e_val: Variant = (ent_val as Dictionary)[k_var]
			if not (e_val is Dictionary):
				continue
			var e: Dictionary = e_val
			if not (_is_whole(e.get("level")) and _is_whole(e.get("absent")) and _is_whole(e.get("since"))):
				continue
			if int(e["level"]) < 1 or int(e["absent"]) < 0 or int(e["since"]) < 0:
				continue
			m.entries[str(k_var)] = {"level": int(e["level"]), "absent": int(e["absent"]), "since": int(e["since"])}
	m.clamp_to(cfg, slots_override)
	return m


static func _is_whole(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_equal_approx(float(v), roundf(float(v)))


func _sorted_keys() -> Array[String]:
	var keys: Array[String] = []
	for k: Variant in entries.keys():
		keys.append(str(k))
	keys.sort()
	return keys


## Lowest level, then oldest (lowest since), then lowest key.
func _eviction_victim() -> String:
	var victim: String = ""
	for k: String in _sorted_keys():
		if victim == "":
			victim = k
			continue
		var a: Dictionary = entries[k]
		var b: Dictionary = entries[victim]
		if int(a["level"]) < int(b["level"]) or (int(a["level"]) == int(b["level"]) and int(a["since"]) < int(b["since"])):
			victim = k
	return victim
