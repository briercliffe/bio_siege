class_name BalanceSimArgs
extends RefCounted

## CLI argument parsing and helper utilities for the Balance Simulator.
## Pure RefCounted with strict GDScript 4 static typing.

const VALID_SCENARIOS: Array[String] = [
	"open_field", "walled_nucleus", "short_wall", "long_wall", "phage_priority", "mixed", "stress", "repeat_swarm"
]

const FLAG_NAME_PATTERN: String = "^[a-z_]+$"


static func _fail(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"exit_code": 1,
		"inputs": {},
		"options": {},
	}


static func parse_args(args: Array[String]) -> Dictionary:
	var scenario: String = ""
	var battle: String = ""
	var base_file: String = ""
	var army_file: String = ""
	var runs: int = 100
	var seed: int = -1
	var jitter: int = 2
	var set_overrides: Array[String] = []
	var sweep: String = ""
	var out_file: String = ""
	var flags: Array[String] = []
	var strains: Dictionary = {}
	var memory: Dictionary = {}
	var generations: int = 1
	var ai_base: Dictionary = {}
	var ai_army_seed: int = -1
	var has_ai_army: bool = false
	var upgrades: Dictionary = {}
	var ai_campaign: Dictionary = {}
	var flag_re := RegEx.new()
	flag_re.compile(FLAG_NAME_PATTERN)

	for arg: String in args:
		if arg == "--help" or arg == "-h":
			return {
				"ok": false,
				"error": "Help requested",
				"exit_code": 1,
				"inputs": {},
				"options": {},
			}
		elif arg.begins_with("--scenario="):
			scenario = arg.substr("--scenario=".length()).strip_edges()
			if not VALID_SCENARIOS.has(scenario):
				return {
					"ok": false,
					"error": "Invalid scenario '%s'. Allowed: %s" % [scenario, ", ".join(VALID_SCENARIOS)],
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
		elif arg.begins_with("--battle="):
			battle = arg.substr("--battle=".length()).strip_edges()
			if battle.is_empty():
				return {
					"ok": false,
					"error": "--battle requires a non-empty file path",
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
		elif arg.begins_with("--base="):
			base_file = arg.substr("--base=".length()).strip_edges()
			if base_file.is_empty():
				return {
					"ok": false,
					"error": "--base requires a non-empty file path",
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
		elif arg.begins_with("--army="):
			army_file = arg.substr("--army=".length()).strip_edges()
			if army_file.is_empty():
				return {
					"ok": false,
					"error": "--army requires a non-empty file path",
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
		elif arg.begins_with("--runs="):
			var val_str: String = arg.substr("--runs=".length()).strip_edges()
			if not val_str.is_valid_int() or val_str.to_int() <= 0:
				return {
					"ok": false,
					"error": "Invalid --runs value '%s': must be a positive integer" % val_str,
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
			runs = val_str.to_int()
		elif arg.begins_with("--seed="):
			var val_str: String = arg.substr("--seed=".length()).strip_edges()
			if not val_str.is_valid_int():
				return {
					"ok": false,
					"error": "Invalid --seed value '%s': must be an integer" % val_str,
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
			seed = val_str.to_int()
		elif arg.begins_with("--jitter="):
			var val_str: String = arg.substr("--jitter=".length()).strip_edges()
			if not val_str.is_valid_int() or val_str.to_int() < 0:
				return {
					"ok": false,
					"error": "Invalid --jitter value '%s': must be a non-negative integer" % val_str,
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
			jitter = val_str.to_int()
		elif arg.begins_with("--set="):
			var val_str: String = arg.substr("--set=".length()).strip_edges()
			if not ("=" in val_str):
				return {
					"ok": false,
					"error": "Invalid --set format '%s': expected <path>=<value>" % val_str,
					"exit_code": 1,
					"inputs": {},
					"options": {},
				}
			set_overrides.append(val_str)
		elif arg.begins_with("--sweep="):
			sweep = arg.substr("--sweep=".length()).strip_edges()
		elif arg.begins_with("--out="):
			out_file = arg.substr("--out=".length()).strip_edges()
		elif arg.begins_with("--flag="):
			var flag_name: String = arg.substr("--flag=".length()).strip_edges()
			if flag_re.search(flag_name) == null:
				return _fail("Invalid --flag value '%s': expected lowercase letters and underscores" % flag_name)
			if not flags.has(flag_name):
				flags.append(flag_name)
		elif arg.begins_with("--strain="):
			var strain_spec: String = arg.substr("--strain=".length()).strip_edges()
			var strain_parts: PackedStringArray = strain_spec.split(":")
			if strain_parts.size() != 2 or strain_parts[0].strip_edges().is_empty() or strain_parts[1].strip_edges().is_empty():
				return _fail("Invalid --strain value '%s': expected <type>:<variant>" % strain_spec)
			strains[strain_parts[0].strip_edges()] = strain_parts[1].strip_edges()
		elif arg.begins_with("--memory="):
			var mem_res: Dictionary = parse_memory(arg.substr("--memory=".length()))
			if not mem_res.get("ok", false):
				return _fail("Invalid --memory value: %s" % mem_res.get("error", ""))
			var mem_levels: Dictionary = mem_res.get("levels", {})
			for mk: Variant in mem_levels.keys():
				memory[mk] = mem_levels[mk]
		elif arg.begins_with("--ai-base="):
			var ab_parts: PackedStringArray = arg.substr("--ai-base=".length()).strip_edges().split(":")
			if ab_parts.size() != 2 or flag_re.search(ab_parts[0].strip_edges()) == null or not ab_parts[1].strip_edges().is_valid_int():
				return _fail("Invalid --ai-base value '%s': expected <tier>:<seed>" % arg.substr("--ai-base=".length()))
			ai_base = {"tier": ab_parts[0].strip_edges(), "seed": ab_parts[1].strip_edges().to_int()}
		elif arg.begins_with("--ai-army="):
			var aa_str: String = arg.substr("--ai-army=".length()).strip_edges()
			if not aa_str.is_valid_int():
				return _fail("Invalid --ai-army value '%s': must be an integer seed" % aa_str)
			ai_army_seed = aa_str.to_int()
			has_ai_army = true
		elif arg.begins_with("--upgrades="):
			var up_res: Dictionary = parse_upgrades(arg.substr("--upgrades=".length()))
			if not up_res.get("ok", false):
				return _fail("Invalid --upgrades value: %s" % up_res.get("error", ""))
			var up_levels: Dictionary = up_res.get("levels", {})
			for uk: Variant in up_levels.keys():
				upgrades[uk] = up_levels[uk]
		elif arg.begins_with("--ai-campaign="):
			var ac_parts: PackedStringArray = arg.substr("--ai-campaign=".length()).strip_edges().split(":")
			if ac_parts.size() != 3 or flag_re.search(ac_parts[0].strip_edges()) == null \
					or not ac_parts[1].strip_edges().is_valid_int() or not ac_parts[2].strip_edges().is_valid_int():
				return _fail("Invalid --ai-campaign value '%s': expected <tier>:<seed>:<raids>" % arg.substr("--ai-campaign=".length()))
			var raids: int = ac_parts[2].strip_edges().to_int()
			if raids < 1 or raids > 50:
				return _fail("Invalid --ai-campaign raids '%d': must be an integer from 1 to 50" % raids)
			ai_campaign = {"tier": ac_parts[0].strip_edges(), "seed": ac_parts[1].strip_edges().to_int(), "raids": raids}
		elif arg.begins_with("--generations="):
			var gen_str: String = arg.substr("--generations=".length()).strip_edges()
			if not gen_str.is_valid_int() or gen_str.to_int() < 1 or gen_str.to_int() > 50:
				return _fail("Invalid --generations value '%s': must be an integer from 1 to 50" % gen_str)
			generations = gen_str.to_int()
		else:
			return {
				"ok": false,
				"error": "Unknown argument: '%s'" % arg,
				"exit_code": 1,
				"inputs": {},
				"options": {},
			}

	var input_modes: int = 0
	if not ai_campaign.is_empty():
		# A campaign is its own input: the AI base comes from the tier and the player army from --army.
		if not scenario.is_empty() or not battle.is_empty() or not base_file.is_empty() or not ai_base.is_empty() or has_ai_army:
			return _fail("--ai-campaign cannot be combined with --scenario, --battle, --base, --ai-base or --ai-army")
		if army_file.is_empty():
			return _fail("--ai-campaign needs --army=<file>: the player army that raids the AI base")
		input_modes += 1
		scenario = ""
	if not scenario.is_empty():
		input_modes += 1
	if not battle.is_empty():
		input_modes += 1
	var base_side: bool = not base_file.is_empty() or not ai_base.is_empty()
	var army_side: bool = not army_file.is_empty() or has_ai_army
	if ai_campaign.is_empty() and (base_side or army_side):
		if not base_side or not army_side:
			var ai_used: bool = not ai_base.is_empty() or has_ai_army
			return {
				"ok": false,
				"error": "Both a base (--base or --ai-base) and an army (--army or --ai-army) must be specified together" if ai_used else "Both --base and --army must be specified together",
				"exit_code": 1,
				"inputs": {},
				"options": {},
			}
		if not base_file.is_empty() and not ai_base.is_empty():
			return _fail("Specify only one of --base and --ai-base")
		if not army_file.is_empty() and has_ai_army:
			return _fail("Specify only one of --army and --ai-army")
		input_modes += 1

	if input_modes == 0:
		return {
			"ok": false,
			"error": "No input specified. Must specify exactly one of: --scenario=<name>, --battle=<file>, or --base=<file> and --army=<file>",
			"exit_code": 1,
			"inputs": {},
			"options": {},
		}
	if input_modes > 1:
		return {
			"ok": false,
			"error": "Multiple inputs specified. Must specify exactly one of: --scenario=<name>, --battle=<file>, or --base=<file> and --army=<file>",
			"exit_code": 1,
			"inputs": {},
			"options": {},
		}

	var inputs: Dictionary = {}
	if not ai_campaign.is_empty():
		inputs["type"] = "ai_campaign"
		inputs["army"] = army_file
	elif not scenario.is_empty():
		inputs["type"] = "scenario"
		inputs["scenario"] = scenario
		inputs["name"] = scenario
	elif not battle.is_empty():
		inputs["type"] = "battle"
		inputs["battle"] = battle
		inputs["file"] = battle
	else:
		inputs["type"] = "base_army"
		inputs["base"] = base_file
		inputs["army"] = army_file
		if not ai_base.is_empty():
			inputs["ai_base"] = ai_base
		if has_ai_army:
			inputs["ai_army_seed"] = ai_army_seed

	var options: Dictionary = {
		"runs": runs,
		"seed": seed,
		"jitter": jitter,
		"set": set_overrides,
		"sweep": sweep,
		"out": out_file,
		"flags": flags,
		"strains": strains,
		"memory": memory,
		"generations": generations,
	}
	if not upgrades.is_empty():
		options["upgrades"] = upgrades
	if not ai_campaign.is_empty():
		options["ai_campaign"] = ai_campaign

	return {
		"ok": true,
		"error": "",
		"exit_code": 0,
		"inputs": inputs,
		"options": options,
	}


static func parse_sweep(sweep_str: String) -> Dictionary:
	var clean: String = sweep_str.strip_edges()
	if clean.is_empty():
		return {
			"ok": false,
			"error": "Empty sweep specification",
			"path": "",
			"values": [],
		}

	var parts: PackedStringArray = clean.split(":")
	if parts.size() < 4:
		return {
			"ok": false,
			"error": "Invalid sweep format '%s': expected <path>:<start>:<end>:<step>" % sweep_str,
			"path": "",
			"values": [],
		}

	var step_str: String = parts[parts.size() - 1].strip_edges()
	var end_str: String = parts[parts.size() - 2].strip_edges()
	var start_str: String = parts[parts.size() - 3].strip_edges()
	var path_parts: PackedStringArray = parts.slice(0, parts.size() - 3)
	var path: String = ":".join(path_parts).strip_edges()

	if path.is_empty():
		return {
			"ok": false,
			"error": "Empty path in sweep specification",
			"path": "",
			"values": [],
		}

	if start_str.is_valid_int() and end_str.is_valid_int() and step_str.is_valid_int():
		var s: int = start_str.to_int()
		var e: int = end_str.to_int()
		var step: int = step_str.to_int()
		if step == 0:
			return {
				"ok": false,
				"error": "Sweep step cannot be 0",
				"path": "",
				"values": [],
			}
		if (step > 0 and s > e) or (step < 0 and s < e):
			return {
				"ok": false,
				"error": "Sweep step direction does not reach end value",
				"path": "",
				"values": [],
			}
		var values: Array = []
		var cur: int = s
		while (step > 0 and cur <= e) or (step < 0 and cur >= e):
			values.append(cur)
			cur += step
		return {
			"ok": true,
			"error": "",
			"path": path,
			"values": values,
		}
	elif start_str.is_valid_float() and end_str.is_valid_float() and step_str.is_valid_float():
		var s: float = start_str.to_float()
		var e: float = end_str.to_float()
		var step: float = step_str.to_float()
		if is_zero_approx(step) or step == 0.0:
			return {
				"ok": false,
				"error": "Sweep step cannot be 0",
				"path": "",
				"values": [],
			}
		if (step > 0.0 and s > e) or (step < 0.0 and s < e):
			return {
				"ok": false,
				"error": "Sweep step direction does not reach end value",
				"path": "",
				"values": [],
			}
		var values: Array = []
		var steps_count: int = int(floor((e - s) / step + 1.0000001))
		for i in range(steps_count):
			values.append(s + float(i) * step)
		return {
			"ok": true,
			"error": "",
			"path": path,
			"values": values,
		}
	else:
		return {
			"ok": false,
			"error": "Sweep parameters must be numeric (start=%s, end=%s, step=%s)" % [start_str, end_str, step_str],
			"path": "",
			"values": [],
		}


static func apply_override(json_roots: Dictionary, dotted_path: String, value_str: String) -> String:
	var path_clean: String = dotted_path.strip_edges()
	if path_clean.is_empty():
		return "Path cannot be empty"

	var parts: PackedStringArray = path_clean.split(".")
	if parts.is_empty():
		return "Path cannot be empty"

	var cur: Variant = json_roots
	for i in range(parts.size() - 1):
		var part: String = parts[i]
		if not (cur is Dictionary):
			return "Cannot navigate through non-dictionary at '%s' in path '%s'" % [part, dotted_path]
		var cur_dict: Dictionary = cur as Dictionary
		if not cur_dict.has(part):
			return "Key '%s' not found in path '%s'" % [part, dotted_path]
		cur = cur_dict[part]

	var last_key: String = parts[parts.size() - 1]
	if not (cur is Dictionary):
		return "Cannot set key on non-dictionary at '%s' in path '%s'" % [last_key, dotted_path]
	var target_dict: Dictionary = cur as Dictionary
	if not target_dict.has(last_key):
		return "Key '%s' not found in path '%s'" % [last_key, dotted_path]

	var parsed_val: Variant = _parse_value_string(value_str)
	target_dict[last_key] = parsed_val
	return ""


static func apply_jitter(units: Array, jitter: int, seed: int, ring_cells: Array[Vector2i]) -> Array:
	var new_units: Array = units.duplicate(true)
	if jitter == 0 or ring_cells.is_empty():
		return new_units

	var rng := Rng.new(seed)
	for item: Variant in new_units:
		if not (item is Dictionary):
			continue
		var unit: Dictionary = item as Dictionary
		var cell_val: Variant = unit.get("cell")
		var cell: Vector2i = Vector2i.ZERO
		if cell_val is Vector2i:
			cell = cell_val
		elif cell_val is Array and (cell_val as Array).size() >= 2:
			cell = Vector2i(int((cell_val as Array)[0]), int((cell_val as Array)[1]))
		else:
			continue

		var index: int = ring_cells.find(cell)
		if index != -1:
			var offset: int = rng.next_range(-jitter, jitter)
			var new_idx: int = posmod(index + offset, ring_cells.size())
			unit["cell"] = ring_cells[new_idx]

	return new_units


## Parses "memory_slot:2,analysis_speed:1" into {"ok", "error", "levels": {id: int}}. Ids are GameConfig.KNOWN_UPGRADES.
static func parse_upgrades(spec: String) -> Dictionary:
	var levels: Dictionary = {}
	var clean: String = spec.strip_edges()
	if clean.is_empty():
		return {"ok": false, "error": "empty upgrades specification", "levels": {}}
	for entry: String in clean.split(","):
		var parts: PackedStringArray = entry.strip_edges().split(":")
		if parts.size() != 2:
			return {"ok": false, "error": "entry '%s' must be <upgrade>:<level>" % entry, "levels": {}}
		var id: String = parts[0].strip_edges()
		if not GameConfig.KNOWN_UPGRADES.has(id):
			return {"ok": false, "error": "unknown upgrade '%s'. Allowed: %s" % [id, ", ".join(GameConfig.KNOWN_UPGRADES)], "levels": {}}
		var level_str: String = parts[1].strip_edges()
		if not level_str.is_valid_int() or level_str.to_int() < 0 or level_str.to_int() > 10:
			return {"ok": false, "error": "level '%s' must be an integer from 0 to 10" % level_str, "levels": {}}
		levels[id] = level_str.to_int()
	return {"ok": true, "error": "", "levels": levels}


## Parses "rhinovirus/wild:3,staphylococcus/wild:1" into {"ok", "error", "levels": {key: int}}.
static func parse_memory(spec: String) -> Dictionary:
	var levels: Dictionary = {}
	var clean: String = spec.strip_edges()
	if clean.is_empty():
		return {"ok": false, "error": "empty memory specification", "levels": {}}
	for entry: String in clean.split(","):
		var parts: PackedStringArray = entry.strip_edges().split(":")
		if parts.size() != 2:
			return {"ok": false, "error": "entry '%s' must be <type>/<strain>:<level>" % entry, "levels": {}}
		var key: String = parts[0].strip_edges()
		var key_parts: PackedStringArray = key.split("/")
		if key_parts.size() != 2 or key_parts[0].is_empty() or key_parts[1].is_empty():
			return {"ok": false, "error": "key '%s' must contain exactly one '/'" % key, "levels": {}}
		var level_str: String = parts[1].strip_edges()
		if not level_str.is_valid_int() or level_str.to_int() < 1:
			return {"ok": false, "error": "level '%s' must be an integer >= 1" % level_str, "levels": {}}
		levels[key] = level_str.to_int()
	return {"ok": true, "error": "", "levels": levels}


## Deep copy of units with "strain" set on every unit whose type is in strains.
static func apply_strains(units: Array, strains: Dictionary) -> Array:
	var out: Array = units.duplicate(true)
	for item: Variant in out:
		if not (item is Dictionary):
			continue
		var unit: Dictionary = item as Dictionary
		var type_id: String = str(unit.get("type", ""))
		if strains.has(type_id):
			unit["strain"] = str(strains[type_id])
	return out


## Starting memory from {key: level}: fresh entries, clamped to the config limits.
static func memory_from_levels(levels: Dictionary, cfg: GameConfig) -> ImmuneMemory:
	var m := ImmuneMemory.new()
	for k: Variant in levels.keys():
		m.entries[str(k)] = {"level": int(levels[k]), "absent": 0, "since": 0}
	m.raids = 0
	m.clamp_to(cfg)
	return m


## Sorted unique "type/strain" keys of the units (strain defaults to "wild").
static func unit_strain_keys(units: Array) -> Array[String]:
	var seen: Dictionary = {}
	for item: Variant in units:
		if not (item is Dictionary):
			continue
		var unit: Dictionary = item as Dictionary
		seen["%s/%s" % [str(unit.get("type", "")), str(unit.get("strain", "wild"))]] = true
	var out: Array[String] = []
	for k: Variant in seen.keys():
		out.append(str(k))
	out.sort()
	return out


static func _parse_value_string(value_str: String) -> Variant:
	var trimmed: String = value_str.strip_edges()
	var lower: String = trimmed.to_lower()
	if lower == "true":
		return true
	if lower == "false":
		return false
	if trimmed.is_valid_int():
		return trimmed.to_int()
	if trimmed.is_valid_float():
		return trimmed.to_float()
	return trimmed
