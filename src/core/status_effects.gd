class_name StatusEffects
extends RefCounted

enum Kind {
	SPEED_PCT,
	ATTACK_INTERVAL_PCT,
	DAMAGE_DEALT_PCT,
	DAMAGE_TAKEN_PCT,
	DISABLED,
	ROOTED
}

# _effects[entity_key][kind][source_key] = {"value": value, "duration": duration_ticks}
var _effects: Dictionary = {}

func add(entity_key: String, kind: Kind, value: int, duration_ticks: int, source_key: String) -> void:
	if not _effects.has(entity_key):
		_effects[entity_key] = {}
	var kinds_dict: Dictionary = _effects[entity_key]
	if not kinds_dict.has(kind):
		kinds_dict[kind] = {}
	var sources_dict: Dictionary = kinds_dict[kind]
	sources_dict[source_key] = {
		"value": value,
		"duration": duration_ticks
	}

func tick() -> void:
	var empty_entities: Array[String] = []
	for entity_key: String in _effects.keys():
		var kinds_dict: Dictionary = _effects[entity_key]
		var empty_kinds: Array = []
		for kind: Variant in kinds_dict.keys():
			var sources_dict: Dictionary = kinds_dict[kind]
			var empty_sources: Array[String] = []
			for source_key: String in sources_dict.keys():
				var eff: Dictionary = sources_dict[source_key]
				var dur: int = eff.get("duration", 0)
				if dur > 0:
					dur -= 1
					if dur == 0:
						empty_sources.append(source_key)
					else:
						eff["duration"] = dur
				elif dur != -1:
					empty_sources.append(source_key)
			for sk: String in empty_sources:
				sources_dict.erase(sk)
			if sources_dict.is_empty():
				empty_kinds.append(kind)
		for k: Variant in empty_kinds:
			kinds_dict.erase(k)
		if kinds_dict.is_empty():
			empty_entities.append(entity_key)
	for ek: String in empty_entities:
		_effects.erase(ek)

func pct(entity_key: String, kind: Kind) -> int:
	if not _effects.has(entity_key):
		return 100
	var kinds_dict: Dictionary = _effects[entity_key]
	if not kinds_dict.has(kind):
		return 100
	var sources_dict: Dictionary = kinds_dict[kind]
	if sources_dict.is_empty():
		return 100
	var sources: Array = sources_dict.keys()
	sources.sort()
	var result: int = 100
	for source_key: String in sources:
		var val: int = sources_dict[source_key].get("value", 100)
		result = (result * val) / 100
	return result

func has_flag(entity_key: String, kind: Kind) -> bool:
	if not _effects.has(entity_key):
		return false
	var kinds_dict: Dictionary = _effects[entity_key]
	if not kinds_dict.has(kind):
		return false
	return not kinds_dict[kind].is_empty()

func clear_entity(entity_key: String) -> void:
	_effects.erase(entity_key)

func clear() -> void:
	_effects.clear()

func get_duration(entity_key: String, kind: Kind, source_key: String) -> int:
	if _effects.has(entity_key) and _effects[entity_key].has(kind) and _effects[entity_key][kind].has(source_key):
		return _effects[entity_key][kind][source_key].get("duration", 0)
	return 0

static func key_structure(id: int) -> String:
	return "s:%d" % id

static func key_pathogen(id: int) -> String:
	return "p:%d" % id
