class_name SnapshotIO
extends RefCounted

## SnapshotIO provides stable serialization and strict validation for
## base snapshots, army setups, and complete battle logs.
## Pure RefCounted with zero Node/OS/scene dependencies.


static func base_to_dict(grid: GridModel, memory: ImmuneMemory = null, populations: Dictionary = {}) -> Dictionary:
	var structs_arr: Array = []
	if grid != null:
		for s: GridModel.PlacedStructure in grid.structures():
			structs_arr.append({
				"type": s.type_id,
				"origin": [s.origin.x, s.origin.y],
			})
	var w: int = grid.width if grid != null else 0
	var h: int = grid.height if grid != null else 0
	var out: Dictionary = {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {
			"width": w,
			"height": h,
		},
		"structures": structs_arr,
	}
	if memory != null and not memory.is_empty():
		out["memory"] = memory.to_dict()
	if not populations.is_empty():
		out["populations"] = populations.duplicate(true)
	return out


static func army_to_dict(deployments: Array) -> Dictionary:
	var units_arr: Array = []
	for item: Variant in deployments:
		if item is Dictionary:
			var d: Dictionary = item as Dictionary
			var t: String = str(d.get("type", d.get("type_id", "")))
			var c_val: Variant = d.get("cell", Vector2i.ZERO)
			var cx: int = 0
			var cy: int = 0
			if c_val is Vector2i:
				cx = (c_val as Vector2i).x
				cy = (c_val as Vector2i).y
			elif c_val is Array and (c_val as Array).size() >= 2:
				cx = int((c_val as Array)[0])
				cy = int((c_val as Array)[1])
			var unit_dict: Dictionary = {
				"type": t,
				"cell": [cx, cy],
			}
			var strain_id: String = str(d.get("strain", "wild"))
			if strain_id != "wild":
				unit_dict["strain"] = strain_id
			units_arr.append(unit_dict)
	return {
		"format": "bio_siege.army",
		"version": 1,
		"units": units_arr,
	}


static func battle_to_dict(config: GameConfig, setup: BattleSetup, sim: BattleSim) -> Dictionary:
	var structs_arr: Array = []
	if setup != null:
		for s_val: Variant in setup.structures:
			if s_val is Dictionary:
				var s: Dictionary = s_val as Dictionary
				var t: String = str(s.get("type", ""))
				var orig_val: Variant = s.get("origin", Vector2i.ZERO)
				var ox: int = 0
				var oy: int = 0
				if orig_val is Vector2i:
					ox = (orig_val as Vector2i).x
					oy = (orig_val as Vector2i).y
				elif orig_val is Array and (orig_val as Array).size() >= 2:
					ox = int((orig_val as Array)[0])
					oy = int((orig_val as Array)[1])
				structs_arr.append({
					"type": t,
					"origin": [ox, oy],
				})

	var w: int = config.grid_width if config != null else 0
	var h: int = config.grid_height if config != null else 0
	var base_dict: Dictionary = {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {
			"width": w,
			"height": h,
		},
		"structures": structs_arr,
	}
	# Pools ride inside the base object, so the battle log gains no new top-level key.
	if setup != null and not setup.populations.is_empty():
		base_dict["populations"] = setup.populations.duplicate(true)

	var army_dict: Dictionary = army_to_dict(setup.units if setup != null else [])

	var result_dict: Dictionary = {
		"outcome": sim.outcome if sim != null else "",
		"end_reason": sim.end_reason if sim != null else "",
		"ticks": sim.tick if sim != null else 0,
		"final_state_hash": sim.state_hash() if sim != null else "",
	}

	var battle: Dictionary = {
		"format": "bio_siege.battle",
		"version": 1,
		"config_hash": config.content_hash if config != null else "",
		"seed": setup.seed if setup != null else 0,
		"base": base_dict,
		"army": army_dict,
		"result": result_dict,
	}
	if setup != null and not setup.memory_seed.is_empty():
		battle["memory_seed"] = setup.memory_seed.duplicate(true)
	return battle


static func sort_keys(val: Variant) -> Variant:
	if val is Dictionary:
		var d: Dictionary = val as Dictionary
		var keys: Array = d.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str(a) < str(b)
		)
		var sorted_d: Dictionary = {}
		for k: Variant in keys:
			sorted_d[k] = sort_keys(d[k])
		return sorted_d
	elif val is Array:
		var arr: Array = val as Array
		var sorted_arr: Array = []
		for item: Variant in arr:
			sorted_arr.append(sort_keys(item))
		return sorted_arr
	elif val is Vector2i:
		var v: Vector2i = val as Vector2i
		return [v.x, v.y]
	else:
		return val


static func to_json(d: Dictionary) -> String:
	var sorted: Variant = sort_keys(d)
	return JSON.stringify(sorted)


static func parse_base(text: String, config: GameConfig) -> Dictionary:
	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		return {
			"ok": false,
			"error": "Invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()],
			"layout": [],
		}

	var data: Variant = json.data
	if not (data is Dictionary):
		return {
			"ok": false,
			"error": "Invalid base format: expected JSON object",
			"layout": [],
		}

	var d: Dictionary = data as Dictionary

	var fmt: Variant = d.get("format")
	if str(fmt) != "bio_siege.base":
		return {
			"ok": false,
			"error": "Not a Bio Siege base",
			"layout": [],
		}

	var ver: int = int(d.get("version", 0))
	if ver > 1:
		return {
			"ok": false,
			"error": "Made with a newer version (v%s)" % [str(ver)],
			"layout": [],
		}
	if ver < 1:
		return {
			"ok": false,
			"error": "Invalid version (%d)" % ver,
			"layout": [],
		}

	var grid_val: Variant = d.get("grid")
	if not (grid_val is Dictionary):
		return {
			"ok": false,
			"error": "Missing or invalid grid specification",
			"layout": [],
		}

	var grid_dict: Dictionary = grid_val as Dictionary
	var g_w: int = int(grid_dict.get("width", 0))
	var g_h: int = int(grid_dict.get("height", 0))
	if config != null:
		if g_w != config.grid_width or g_h != config.grid_height:
			return {
				"ok": false,
				"error": "Grid size mismatch: expected %dx%d, got %dx%d" % [config.grid_width, config.grid_height, g_w, g_h],
				"layout": [],
			}

	var structs_val: Variant = d.get("structures")
	if not (structs_val is Array):
		return {
			"ok": false,
			"error": "Missing or invalid structures list",
			"layout": [],
		}

	var structs_arr: Array = structs_val as Array
	var layout: Array = []
	for i in range(structs_arr.size()):
		var s_item: Variant = structs_arr[i]
		if not (s_item is Dictionary):
			return {
				"ok": false,
				"error": "Structure at index %d is not an object" % i,
				"layout": [],
			}
		var s_dict: Dictionary = s_item as Dictionary
		if not s_dict.has("type"):
			return {
				"ok": false,
				"error": "Structure at index %d missing type" % i,
				"layout": [],
			}
		var type_id: String = str(s_dict["type"])
		if config != null and not config.structures.has(type_id):
			return {
				"ok": false,
				"error": "Unknown structure type '%s'" % type_id,
				"layout": [],
			}
		if not s_dict.has("origin"):
			return {
				"ok": false,
				"error": "Invalid origin cell",
				"layout": [],
			}
		var orig_val: Variant = s_dict["origin"]
		var origin := Vector2i.ZERO
		if orig_val is Array:
			var arr: Array = orig_val as Array
			if arr.size() != 2 or not (arr[0] is int or arr[0] is float) or not (arr[1] is int or arr[1] is float):
				return {
					"ok": false,
					"error": "Invalid origin cell",
					"layout": [],
				}
			origin = Vector2i(int(arr[0]), int(arr[1]))
		elif orig_val is Vector2i:
			origin = orig_val as Vector2i
		else:
			return {
				"ok": false,
				"error": "Invalid origin cell",
				"layout": [],
			}

		layout.append({
			"type": type_id,
			"origin": origin,
		})

	var memory_out: Dictionary = {}
	if d.has("memory"):
		var mem_val: Variant = d["memory"]
		if not (mem_val is Dictionary):
			return {
				"ok": false,
				"error": "Invalid memory block",
				"layout": [],
			}
		memory_out = (mem_val as Dictionary).duplicate(true)

	var populations_out: Dictionary = {}
	if d.has("populations"):
		var pop_val: Variant = d["populations"]
		if not (pop_val is Dictionary):
			return {
				"ok": false,
				"error": "Invalid populations block",
				"layout": [],
			}
		populations_out = (pop_val as Dictionary).duplicate(true)

	if config != null:
		var setup := BattleSetup.create(layout, [], 0)
		var val_errors: PackedStringArray = setup.validate(config)
		if not val_errors.is_empty():
			return {
				"ok": false,
				"error": val_errors[0],
				"layout": [],
			}

	return {
		"ok": true,
		"error": "",
		"layout": layout,
		"memory": memory_out,
		"populations": populations_out,
	}


static func parse_army(text: String, config: GameConfig) -> Dictionary:
	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		return {
			"ok": false,
			"error": "Invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()],
			"units": [],
		}

	var data: Variant = json.data
	if not (data is Dictionary):
		return {
			"ok": false,
			"error": "Invalid army format: expected JSON object",
			"units": [],
		}

	var d: Dictionary = data as Dictionary

	var fmt: Variant = d.get("format")
	if str(fmt) != "bio_siege.army":
		return {
			"ok": false,
			"error": "Not a Bio Siege army",
			"units": [],
		}

	var ver: int = int(d.get("version", 0))
	if ver > 1:
		return {
			"ok": false,
			"error": "Made with a newer version (v%s)" % [str(ver)],
			"units": [],
		}
	if ver < 1:
		return {
			"ok": false,
			"error": "Invalid version (%d)" % ver,
			"units": [],
		}

	var units_val: Variant = d.get("units")
	if not (units_val is Array):
		return {
			"ok": false,
			"error": "Missing or invalid units list",
			"units": [],
		}

	var units_arr: Array = units_val as Array
	var units: Array = []
	var type_strains: Dictionary = {}
	for i in range(units_arr.size()):
		var u_item: Variant = units_arr[i]
		if not (u_item is Dictionary):
			return {
				"ok": false,
				"error": "Unit at index %d is not an object" % i,
				"units": [],
			}
		var u_dict: Dictionary = u_item as Dictionary
		if not u_dict.has("type"):
			return {
				"ok": false,
				"error": "Unit at index %d missing type" % i,
				"units": [],
			}
		var type_id: String = str(u_dict["type"])
		if config != null and not config.pathogens.has(type_id):
			return {
				"ok": false,
				"error": "Unknown pathogen type '%s'" % type_id,
				"units": [],
			}
		if not u_dict.has("cell"):
			return {
				"ok": false,
				"error": "Malformed cell",
				"units": [],
			}
		var cell_val: Variant = u_dict["cell"]
		var cell := Vector2i.ZERO
		if cell_val is Array:
			var arr: Array = cell_val as Array
			if arr.size() != 2 or not (arr[0] is int or arr[0] is float) or not (arr[1] is int or arr[1] is float):
				return {
					"ok": false,
					"error": "Malformed cell",
					"units": [],
				}
			cell = Vector2i(int(arr[0]), int(arr[1]))
		elif cell_val is Vector2i:
			cell = cell_val as Vector2i
		else:
			return {
				"ok": false,
				"error": "Malformed cell",
				"units": [],
			}

		if config != null:
			if cell.x < 0 or cell.x >= config.grid_width or cell.y < 0 or cell.y >= config.grid_height:
				return {
					"ok": false,
					"error": "Unit '%s' at %s is out of grid bounds" % [type_id, str(cell)],
					"units": [],
				}

		var unit_out: Dictionary = {
			"type": type_id,
			"cell": cell,
		}
		if u_dict.has("strain"):
			var strain_val: Variant = u_dict["strain"]
			if typeof(strain_val) != TYPE_STRING:
				return {
					"ok": false,
					"error": "Unknown strain '%s' for %s" % [str(strain_val), type_id],
					"units": [],
				}
			var strain_id: String = str(strain_val)
			if config != null and config.pathogens[type_id].strain(strain_id) == null:
				return {
					"ok": false,
					"error": "Unknown strain '%s' for %s" % [strain_id, type_id],
					"units": [],
				}
			if type_strains.has(type_id) and str(type_strains[type_id]) != strain_id:
				return {
					"ok": false,
					"error": "An army can use only one strain per pathogen type (%s)" % type_id,
					"units": [],
				}
			if strain_id != "wild":
				unit_out["strain"] = strain_id
		var eff_strain: String = str(unit_out.get("strain", "wild"))
		if type_strains.has(type_id) and str(type_strains[type_id]) != eff_strain:
			return {
				"ok": false,
				"error": "An army can use only one strain per pathogen type (%s)" % type_id,
				"units": [],
			}
		type_strains[type_id] = eff_strain
		units.append(unit_out)

	return {
		"ok": true,
		"error": "",
		"units": units,
	}


static func parse_battle(text: String, config: GameConfig) -> Dictionary:
	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		return {
			"ok": false,
			"error": "Invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()],
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var data: Variant = json.data
	if not (data is Dictionary):
		return {
			"ok": false,
			"error": "Invalid battle format: expected JSON object",
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var d: Dictionary = data as Dictionary

	var fmt: Variant = d.get("format")
	if str(fmt) != "bio_siege.battle":
		return {
			"ok": false,
			"error": "Not a Bio Siege battle",
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var ver: int = int(d.get("version", 0))
	if ver > 1:
		return {
			"ok": false,
			"error": "Made with a newer version (v%s)" % [str(ver)],
			"setup": null,
			"result": {},
			"config_hash": "",
		}
	if ver < 1:
		return {
			"ok": false,
			"error": "Invalid version (%d)" % ver,
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var base_val: Variant = d.get("base")
	if not (base_val is Dictionary):
		return {
			"ok": false,
			"error": "Missing or invalid base object in battle",
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var parsed_base: Dictionary = parse_base(to_json(base_val as Dictionary), config)
	if not parsed_base.get("ok", false):
		return {
			"ok": false,
			"error": "Invalid base in battle: %s" % parsed_base.get("error", ""),
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var army_val: Variant = d.get("army")
	if not (army_val is Dictionary):
		return {
			"ok": false,
			"error": "Missing or invalid army object in battle",
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var parsed_army: Dictionary = parse_army(to_json(army_val as Dictionary), config)
	if not parsed_army.get("ok", false):
		return {
			"ok": false,
			"error": "Invalid army in battle: %s" % parsed_army.get("error", ""),
			"setup": null,
			"result": {},
			"config_hash": "",
		}

	var seed_val: int = int(d.get("seed", 0))
	var config_hash: String = str(d.get("config_hash", ""))
	var result_val: Variant = d.get("result", {})
	var result: Dictionary = result_val as Dictionary if result_val is Dictionary else {}

	var memory_seed: Dictionary = {}
	if d.has("memory_seed"):
		var ms_val: Variant = d["memory_seed"]
		if not (ms_val is Dictionary):
			return {
				"ok": false,
				"error": "Invalid memory_seed",
				"setup": null,
				"result": {},
				"config_hash": "",
			}
		memory_seed = _parse_memory_seed(ms_val as Dictionary)
		if memory_seed.is_empty() and not (ms_val as Dictionary).is_empty():
			return {
				"ok": false,
				"error": "Invalid memory_seed",
				"setup": null,
				"result": {},
				"config_hash": "",
			}

	var setup: BattleSetup = BattleSetup.create(parsed_base.layout, parsed_army.units, seed_val, memory_seed, parsed_base.get("populations", {}))

	return {
		"ok": true,
		"error": "",
		"setup": setup,
		"result": result,
		"config_hash": config_hash,
	}


## Returns key -> int pct, or {} if any entry is malformed.
static func _parse_memory_seed(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in raw.keys():
		var v: Variant = raw[k]
		if typeof(k) != TYPE_STRING or not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
			return {}
		if not is_equal_approx(float(v), roundf(float(v))):
			return {}
		var pct: int = int(v)
		if pct < 0 or pct > 100:
			return {}
		out[str(k)] = pct
	return out


static func setup_from_battle(d: Dictionary) -> BattleSetup:
	var base_dict: Dictionary = d.get("base", {})
	var army_dict: Dictionary = d.get("army", {})
	var seed_val: int = int(d.get("seed", 0))

	var structs_arr: Array = []
	for s_item: Variant in base_dict.get("structures", []):
		if s_item is Dictionary:
			var s: Dictionary = s_item as Dictionary
			var t: String = str(s.get("type", ""))
			var orig_val: Variant = s.get("origin", Vector2i.ZERO)
			var origin := Vector2i.ZERO
			if orig_val is Vector2i:
				origin = orig_val
			elif orig_val is Array and (orig_val as Array).size() >= 2:
				origin = Vector2i(int((orig_val as Array)[0]), int((orig_val as Array)[1]))
			structs_arr.append({"type": t, "origin": origin})

	var units_arr: Array = []
	for u_item: Variant in army_dict.get("units", []):
		if u_item is Dictionary:
			var u: Dictionary = u_item as Dictionary
			var t: String = str(u.get("type", ""))
			var c_val: Variant = u.get("cell", Vector2i.ZERO)
			var cell := Vector2i.ZERO
			if c_val is Vector2i:
				cell = c_val
			elif c_val is Array and (c_val as Array).size() >= 2:
				cell = Vector2i(int((c_val as Array)[0]), int((c_val as Array)[1]))
			var unit_entry: Dictionary = {"type": t, "cell": cell}
			if u.has("strain"):
				unit_entry["strain"] = str(u["strain"])
			units_arr.append(unit_entry)

	var ms_val: Variant = d.get("memory_seed", {})
	var memory_seed: Dictionary = {}
	if ms_val is Dictionary:
		memory_seed = _parse_memory_seed(ms_val as Dictionary)
	var pops_val: Variant = base_dict.get("populations", {})
	var populations: Dictionary = pops_val if pops_val is Dictionary else {}
	return BattleSetup.create(structs_arr, units_arr, seed_val, memory_seed, populations)
