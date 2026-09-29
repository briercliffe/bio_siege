class_name BalanceSimArgs
extends RefCounted

## CLI argument parsing and helper utilities for the Balance Simulator.
## Pure RefCounted with strict GDScript 4 static typing.

const VALID_SCENARIOS: Array[String] = [
	"open_field", "walled_nucleus", "short_wall", "long_wall", "phage_priority", "mixed", "stress"
]


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
		else:
			return {
				"ok": false,
				"error": "Unknown argument: '%s'" % arg,
				"exit_code": 1,
				"inputs": {},
				"options": {},
			}

	var input_modes: int = 0
	if not scenario.is_empty():
		input_modes += 1
	if not battle.is_empty():
		input_modes += 1
	if not base_file.is_empty() or not army_file.is_empty():
		if base_file.is_empty() or army_file.is_empty():
			return {
				"ok": false,
				"error": "Both --base and --army must be specified together",
				"exit_code": 1,
				"inputs": {},
				"options": {},
			}
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
	if not scenario.is_empty():
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

	var options: Dictionary = {
		"runs": runs,
		"seed": seed,
		"jitter": jitter,
		"set": set_overrides,
		"sweep": sweep,
		"out": out_file,
	}

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
