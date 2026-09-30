class_name BattleSetup
extends RefCounted

var structures: Array[Dictionary] = []
var units: Array[Dictionary] = []
var seed: int = 0
var memory_seed: Dictionary = {}  # strain_key -> int pct (0..100)

static func create(p_structures: Array, p_units: Array, p_seed: int, p_memory_seed: Dictionary = {}) -> BattleSetup:
	var setup: BattleSetup = BattleSetup.new()
	setup.seed = p_seed
	setup.memory_seed = p_memory_seed.duplicate(true)
	for item: Variant in p_structures:
		if item is Dictionary:
			setup.structures.append((item as Dictionary).duplicate(true))
	for item: Variant in p_units:
		if item is Dictionary:
			setup.units.append((item as Dictionary).duplicate(true))
	return setup

func duplicate_setup() -> BattleSetup:
	return create(structures, units, seed, memory_seed)

func to_dict() -> Dictionary:
	var d: Dictionary = {
		"structures": structures.duplicate(true),
		"units": units.duplicate(true),
		"seed": seed,
	}
	if not memory_seed.is_empty():
		d["memory_seed"] = memory_seed.duplicate(true)
	return d

static func from_dict(d: Dictionary) -> BattleSetup:
	var s: Array = d.get("structures", [])
	var u: Array = d.get("units", [])
	var sd: int = int(d.get("seed", 0))
	var ms_val: Variant = d.get("memory_seed", {})
	var ms: Dictionary = {}
	if ms_val is Dictionary:
		for mk: Variant in (ms_val as Dictionary).keys():
			var mv: Variant = (ms_val as Dictionary)[mk]
			# JSON numbers parse as floats; whole values are coerced back to int.
			if typeof(mv) == TYPE_FLOAT and is_equal_approx(float(mv), roundf(float(mv))):
				mv = int(mv)
			ms[mk] = mv
	return create(s, u, sd, ms)

func validate(config: GameConfig) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if config == null:
		errors.append("Config is null")
		return errors

	for mk: Variant in memory_seed.keys():
		var mv: Variant = memory_seed[mk]
		if typeof(mk) != TYPE_STRING or typeof(mv) != TYPE_INT or int(mv) < 0 or int(mv) > 100:
			errors.append("Invalid memory_seed entry '%s'" % [str(mk)])

	var core_count: int = 0
	var occupied_cells: Dictionary = {}

	for i: int in range(structures.size()):
		var s: Dictionary = structures[i]
		var type_id: String = str(s.get("type", ""))
		if type_id.is_empty() or not config.structures.has(type_id):
			errors.append("Unknown structure type: '%s'" % type_id)
			continue

		var sdef: StructureDef = config.structures[type_id]
		if (sdef != null and sdef.has_tag("core")) or type_id == "nucleus":
			core_count += 1

		var origin: Vector2i = Vector2i.ZERO
		var origin_val: Variant = s.get("origin")
		if origin_val is Vector2i:
			origin = origin_val
		elif origin_val is Array and (origin_val as Array).size() >= 2:
			origin = Vector2i(int((origin_val as Array)[0]), int((origin_val as Array)[1]))
		else:
			errors.append("Structure '%s' at index %d has invalid origin" % [type_id, i])
			continue

		var footprint: Vector2i = sdef.footprint if sdef != null else Vector2i.ONE
		if origin.x < 0 or origin.y < 0 or origin.x + footprint.x > config.grid_width or origin.y + footprint.y > config.grid_height:
			errors.append("Structure '%s' at %s is out of grid bounds" % [type_id, str(origin)])
			continue

		var overlap: bool = false
		for y: int in range(origin.y, origin.y + footprint.y):
			for x: int in range(origin.x, origin.x + footprint.x):
				var cell := Vector2i(x, y)
				if occupied_cells.has(cell):
					errors.append("Structure '%s' at %s overlaps occupied cell %s" % [type_id, str(origin), str(cell)])
					overlap = true
					break
				occupied_cells[cell] = true
			if overlap:
				break

	if core_count != 1:
		errors.append("Expected exactly 1 core structure, found %d" % core_count)

	for i: int in range(units.size()):
		var u: Dictionary = units[i]
		var type_id: String = str(u.get("type", ""))
		if type_id.is_empty() or not config.pathogens.has(type_id):
			errors.append("Unknown pathogen type: '%s'" % type_id)
		elif u.has("strain"):
			var strain_val: Variant = u["strain"]
			if typeof(strain_val) != TYPE_STRING or config.pathogens[type_id].strain(str(strain_val)) == null:
				errors.append("Unknown strain '%s' for pathogen '%s'" % [str(strain_val), type_id])

		var cell: Vector2i = Vector2i.ZERO
		var cell_val: Variant = u.get("cell")
		if cell_val is Vector2i:
			cell = cell_val
		elif cell_val is Array and (cell_val as Array).size() >= 2:
			cell = Vector2i(int((cell_val as Array)[0]), int((cell_val as Array)[1]))
		else:
			errors.append("Unit '%s' at index %d has invalid cell" % [type_id, i])
			continue

		if cell.x < 0 or cell.x >= config.grid_width or cell.y < 0 or cell.y >= config.grid_height:
			errors.append("Unit '%s' at %s is out of grid bounds" % [type_id, str(cell)])

	return errors
