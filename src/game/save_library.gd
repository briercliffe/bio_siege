class_name SaveLibrary
extends RefCounted

## Saved bases and armies (screen 03): one JSON file per slot under `<root>/bases` and `<root>/armies`.
## A slot wraps SnapshotIO's versioned format unchanged in `data`, so the inner JSON (what Share hands out)
## loads in the game, in the import dialog and in `tools/balance_sim.gd --base=<file>`.
##
## Lives in src/game because it touches the filesystem and the clock. Tests pass a temp root.

const DEFAULT_ROOT: String = "user://saves"
const MAX_SLOTS: int = 12
const SLOT_VERSION: int = 1
const KIND_BASE: String = "base"
const KIND_ARMY: String = "army"
const KIND_DIRS: Dictionary = {KIND_BASE: "bases", KIND_ARMY: "armies"}
const FULL_ERROR: String = "Library is full (%d). Delete a slot first."

## Where HudBuild.export_base and HudSpawn.export_army wrote files before the library existed.
const LEGACY_BASES_DIR: String = "user://bases"
const LEGACY_ARMIES_DIR: String = "user://armies"
const LEGACY_NAMES: Dictionary = {KIND_BASE: "Imported base %d", KIND_ARMY: "Imported army %d"}
const MIGRATED_MARKER: String = "legacy_migrated.txt"

const SLUG_MAX: int = 32
const SECONDS_PER_DAY: int = 86400
const WALL_TAG: String = "wall"

var root: String = DEFAULT_ROOT
## Legacy folders moved into the library by migrate_legacy(). Only the default root migrates by default,
## so a test library never touches the player's files.
var legacy_dirs: Dictionary = {}
## Pins the clock for tests; 0 uses the system time.
var now_unix: int = 0


func _init(p_root: String = DEFAULT_ROOT) -> void:
	root = p_root.trim_suffix("/")
	if root == DEFAULT_ROOT:
		legacy_dirs = {KIND_BASE: LEGACY_BASES_DIR, KIND_ARMY: LEGACY_ARMIES_DIR}


## A library at `p_root` with the legacy files already moved in (they need a config to validate).
static func open(p_root: String, config: GameConfig) -> SaveLibrary:
	var lib := SaveLibrary.new(p_root)
	lib.migrate_legacy(config)
	return lib


func kind_dir(kind: String) -> String:
	return "%s/%s" % [root, str(KIND_DIRS.get(kind, KIND_DIRS[KIND_BASE]))]


## Slots of one kind, newest first: {path, name, saved_unix, summary}. Unreadable files are skipped.
func list(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir_path: String = kind_dir(kind)
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	for file_name: String in DirAccess.get_files_at(dir_path):
		if not file_name.ends_with(".json"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var slot: Dictionary = _read_slot(path)
		if slot.is_empty() or str(slot.get("kind", "")) != kind:
			continue
		var summary: Variant = slot.get("summary", {})
		out.append({
			"path": path,
			"name": str(slot.get("name", "")),
			"saved_unix": int(slot.get("saved_unix", 0)),
			"summary": summary if summary is Dictionary else {},
		})
	out.sort_custom(_newer_first)
	return out


func count(kind: String) -> int:
	return list(kind).size()


func save_base(slot_name: String, grid: GridModel, config: GameConfig, memory: ImmuneMemory = null) -> Dictionary:
	if grid == null:
		return {"ok": false, "path": "", "error": "Nothing to save"}
	return _write_slot(KIND_BASE, slot_name, SnapshotIO.base_to_dict(grid, memory), summary_for_base(grid, config))


func save_army(slot_name: String, army: Army, config: GameConfig) -> Dictionary:
	if army == null:
		return {"ok": false, "path": "", "error": "Nothing to save"}
	return _write_slot(KIND_ARMY, slot_name, SnapshotIO.army_to_dict(army.deployments),
			summary_for_units(army.deployments, config))


## {ok, kind, name, parsed, error}; `parsed` is SnapshotIO.parse_base or parse_army's result.
func load_slot(path: String, config: GameConfig) -> Dictionary:
	var slot: Dictionary = _read_slot(path)
	if slot.is_empty():
		return {"ok": false, "kind": "", "name": "", "parsed": {}, "error": "Could not read this slot"}
	var kind: String = str(slot["kind"])
	var text: String = SnapshotIO.to_json(slot["data"] as Dictionary)
	var parsed: Dictionary = SnapshotIO.parse_army(text, config) if kind == KIND_ARMY else SnapshotIO.parse_base(text, config)
	return {
		"ok": bool(parsed.get("ok", false)),
		"kind": kind,
		"name": str(slot.get("name", "")),
		"parsed": parsed,
		"error": str(parsed.get("error", "")),
	}


func delete_slot(path: String) -> bool:
	if not _is_inside_root(path) or not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## The inner SnapshotIO JSON of a slot, or "" when the slot cannot be read.
func export_json(path: String) -> String:
	var slot: Dictionary = _read_slot(path)
	if slot.is_empty():
		return ""
	return SnapshotIO.to_json(slot["data"] as Dictionary)


## Validates a shared base or army with SnapshotIO, then saves it as a new slot. An empty `slot_name`
## becomes "Imported base N" or "Imported army N". Returns {ok, kind, path, name, error}.
func import_json(text: String, slot_name: String, config: GameConfig) -> Dictionary:
	var source: String = text
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		var d: Dictionary = json.data as Dictionary
		# A whole slot file shared by hand: unwrap it and keep its name.
		if d.has("slot_version") and d.get("data") is Dictionary:
			if slot_name.strip_edges().is_empty():
				slot_name = str(d.get("name", ""))
			d = d["data"] as Dictionary
			source = SnapshotIO.to_json(d)
		if str(d.get("format", "")) == "bio_siege.army":
			return _import_army(source, slot_name, config)
	return _import_base(source, slot_name, config)


## Moves the pre-library export folders into the library once. Files that do not validate, or that no
## longer fit once the library is full, stay where they are.
func migrate_legacy(config: GameConfig) -> int:
	if legacy_dirs.is_empty() or FileAccess.file_exists(_marker_path()):
		return 0
	var moved: int = 0
	for kind: String in [KIND_BASE, KIND_ARMY]:
		var legacy: String = str(legacy_dirs.get(kind, ""))
		if legacy.is_empty() or not DirAccess.dir_exists_absolute(legacy):
			continue
		var files: Array[String] = []
		for file_name: String in DirAccess.get_files_at(legacy):
			if file_name.ends_with(".json"):
				files.append(file_name)
		files.sort()
		var n: int = 0
		for file_name: String in files:
			var path: String = "%s/%s" % [legacy.trim_suffix("/"), file_name]
			var text: String = FileAccess.get_file_as_string(path)
			var parsed: Dictionary = SnapshotIO.parse_army(text, config) if kind == KIND_ARMY else SnapshotIO.parse_base(text, config)
			if not bool(parsed.get("ok", false)):
				continue
			var saved: int = _legacy_unix(file_name, path)
			var res: Dictionary
			if kind == KIND_ARMY:
				var units: Array = parsed.get("units", [])
				res = _write_slot(kind, LEGACY_NAMES[kind] % (n + 1), SnapshotIO.army_to_dict(units),
						summary_for_units(units, config), saved)
			else:
				var layout: Array = parsed.get("layout", [])
				res = _write_slot(kind, LEGACY_NAMES[kind] % (n + 1), _base_dict(layout, parsed.get("memory", {}), config),
						summary_for_layout(layout, config), saved)
			if not bool(res.get("ok", false)):
				break
			n += 1
			moved += 1
			DirAccess.remove_absolute(path)
	DirAccess.make_dir_recursive_absolute(root)
	var marker := FileAccess.open(_marker_path(), FileAccess.WRITE)
	if marker != null:
		marker.store_string(str(_now()))
		marker.close()
	return moved


## {atp, walls, towers}: atp is the layout's cost, walls have the "wall" tag, towers have an attack.
static func summary_for_base(grid: GridModel, config: GameConfig) -> Dictionary:
	if grid == null:
		return {"atp": 0, "walls": 0, "towers": 0}
	var summary: Dictionary = summary_for_layout(grid.to_layout(), config)
	summary["atp"] = int(grid.total_cost().get("atp", 0))
	return summary


static func summary_for_layout(layout: Array, config: GameConfig) -> Dictionary:
	var atp: int = 0
	var walls: int = 0
	var towers: int = 0
	for item: Variant in layout:
		if not (item is Dictionary):
			continue
		var type_id: String = str((item as Dictionary).get("type", ""))
		var sdef: StructureDef = config.structures.get(type_id) as StructureDef if config != null else null
		if sdef == null:
			continue
		if not sdef.has_tag("core"):
			atp += int(sdef.cost.get("atp", 0))
		if sdef.has_tag(WALL_TAG):
			walls += 1
		elif sdef.has_attack:
			towers += 1
	return {"atp": atp, "walls": walls, "towers": towers}


## {atp, units, types}: `types` maps pathogen id to count, in first-seen order. Costs follow each type's strain.
static func summary_for_units(units: Array, config: GameConfig) -> Dictionary:
	var army := Army.new(config)
	var types: Dictionary = {}
	for item: Variant in units:
		if not (item is Dictionary):
			continue
		var type_id: String = str((item as Dictionary).get("type", ""))
		if not types.has(type_id):
			army.set_strain(type_id, str((item as Dictionary).get("strain", "wild")))
		types[type_id] = int(types.get(type_id, 0)) + 1
	var atp: int = 0
	for type_id: String in types.keys():
		atp += int(army.unit_cost(type_id).get("atp", 0)) * int(types[type_id])
	var total: int = 0
	for c: Variant in types.values():
		total += int(c)
	return {"atp": atp, "units": total, "types": types}


## "Saved today", "Saved yesterday" or "Saved N days ago", by calendar day. `bias_seconds` shifts both
## times into the player's time zone.
static func relative_time(saved_unix: int, now_unix_value: int, bias_seconds: int = 0) -> String:
	var days: int = _day_index(now_unix_value + bias_seconds) - _day_index(saved_unix + bias_seconds)
	if days <= 0:
		return "Saved today"
	if days == 1:
		return "Saved yesterday"
	return "Saved %d days ago" % days


## "760 ATP · 52 walls, 4 towers" or "230 ATP · 8 units".
static func summary_text(kind: String, summary: Dictionary) -> String:
	var atp: int = int(summary.get("atp", 0))
	if kind == KIND_ARMY:
		return "%d ATP · %s" % [atp, _plural(int(summary.get("units", 0)), "unit")]
	return "%d ATP · %s, %s" % [atp, _plural(int(summary.get("walls", 0)), "wall"),
			_plural(int(summary.get("towers", 0)), "tower")]


## Lowercase letters, digits and underscores, at most SLUG_MAX long.
static func slugify(text: String) -> String:
	var out: String = ""
	var last_underscore: bool = true
	for ch: String in text.to_lower():
		var code: int = ch.unicode_at(0)
		var keep: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if keep:
			out += ch
			last_underscore = false
		elif not last_underscore:
			out += "_"
			last_underscore = true
	out = out.trim_suffix("_").substr(0, SLUG_MAX).trim_suffix("_")
	return out


## Applies a parsed base to the session like the Synthesis import always has: budget check, clear the army
## so the wallet stays start budget minus spend, reset the wallet, rebuild the grid. Returns "" or an error.
static func apply_base(session: Session, parsed: Dictionary) -> String:
	if session == null or session.config == null or session.grid == null or session.wallet == null:
		return "No game session"
	var layout: Array = parsed.get("layout", [])
	var total_cost: int = int(summary_for_layout(layout, session.config).get("atp", 0))
	var budget: int = int(session.config.start_wallet.get("atp", 0))
	if total_cost > budget:
		return "This base costs %d ATP; the budget is %d" % [total_cost, budget]
	if session.army != null and session.army.total_count() > 0:
		session.army.refund_all(null)
	session.wallet.reset(session.config.start_wallet)
	session.grid.load_layout(layout, session.wallet)
	if session.config.memory_enabled():
		var memory: Variant = parsed.get("memory", {})
		session.memory = ImmuneMemory.from_dict(memory if memory is Dictionary else {}, session.config)
	return ""


## Refunds the current army and buys and deploys the parsed units while ATP lasts. Returns {deployed, total}.
static func apply_army(session: Session, parsed: Dictionary) -> Dictionary:
	var units: Array = parsed.get("units", [])
	var result: Dictionary = {"deployed": 0, "total": units.size()}
	if session == null or session.config == null or session.army == null or session.wallet == null:
		return result
	session.army.refund_all(session.wallet)
	if session.config.flag("strains"):
		var seen_types: Dictionary = {}
		for su: Variant in units:
			if su is Dictionary:
				var su_type: String = str(su.get("type", ""))
				if not seen_types.has(su_type):
					seen_types[su_type] = true
					session.army.set_strain(su_type, str(su.get("strain", "wild")))
	var deployed: int = 0
	for item: Variant in units:
		if not (item is Dictionary):
			continue
		var tid: String = str(item.get("type", ""))
		var cell_val: Variant = item.get("cell", Vector2i.ZERO)
		var cell: Vector2i = Vector2i.ZERO
		if cell_val is Vector2i:
			cell = cell_val
		elif cell_val is Array and (cell_val as Array).size() >= 2:
			cell = Vector2i(int((cell_val as Array)[0]), int((cell_val as Array)[1]))
		if not session.army.buy(tid, session.wallet):
			break
		if not session.army.deploy(tid, cell):
			session.army.unbuy(tid, session.wallet)
			break
		deployed += 1
	result["deployed"] = deployed
	return result


func _import_base(text: String, slot_name: String, config: GameConfig) -> Dictionary:
	var parsed: Dictionary = SnapshotIO.parse_base(text, config)
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "kind": KIND_BASE, "path": "", "name": "", "error": str(parsed.get("error", ""))}
	var layout: Array = parsed.get("layout", [])
	var final_name: String = _name_or_default(slot_name, KIND_BASE)
	var res: Dictionary = _write_slot(KIND_BASE, final_name, _base_dict(layout, parsed.get("memory", {}), config),
			summary_for_layout(layout, config))
	res["kind"] = KIND_BASE
	res["name"] = final_name
	return res


func _import_army(text: String, slot_name: String, config: GameConfig) -> Dictionary:
	var parsed: Dictionary = SnapshotIO.parse_army(text, config)
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "kind": KIND_ARMY, "path": "", "name": "", "error": str(parsed.get("error", ""))}
	var units: Array = parsed.get("units", [])
	var final_name: String = _name_or_default(slot_name, KIND_ARMY)
	var res: Dictionary = _write_slot(KIND_ARMY, final_name, SnapshotIO.army_to_dict(units), summary_for_units(units, config))
	res["kind"] = KIND_ARMY
	res["name"] = final_name
	return res


func _name_or_default(slot_name: String, kind: String) -> String:
	var trimmed: String = slot_name.strip_edges()
	if not trimmed.is_empty():
		return trimmed
	return LEGACY_NAMES[kind] % (count(kind) + 1)


## SnapshotIO's base format rebuilt from a parsed layout (a GridModel cannot place without a wallet).
static func _base_dict(layout: Array, memory: Variant, config: GameConfig) -> Dictionary:
	var structs_arr: Array = []
	for item: Variant in layout:
		if item is Dictionary:
			var origin: Vector2i = (item as Dictionary).get("origin", Vector2i.ZERO)
			structs_arr.append({"type": str((item as Dictionary).get("type", "")), "origin": [origin.x, origin.y]})
	var out: Dictionary = {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": config.grid_width if config != null else 0, "height": config.grid_height if config != null else 0},
		"structures": structs_arr,
	}
	if memory is Dictionary and not (memory as Dictionary).is_empty():
		out["memory"] = (memory as Dictionary).duplicate(true)
	return out


func _write_slot(kind: String, slot_name: String, data: Dictionary, summary: Dictionary, saved_unix: int = 0) -> Dictionary:
	if count(kind) >= MAX_SLOTS:
		return {"ok": false, "path": "", "error": FULL_ERROR % MAX_SLOTS}
	var final_name: String = slot_name.strip_edges()
	if final_name.is_empty():
		final_name = LEGACY_NAMES[kind] % (count(kind) + 1)
	var stamp: int = saved_unix if saved_unix > 0 else _now()
	var dir_path: String = kind_dir(kind)
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK and not DirAccess.dir_exists_absolute(dir_path):
		return {"ok": false, "path": "", "error": "Could not create %s" % dir_path}
	var slug: String = slugify(final_name)
	if slug.is_empty():
		slug = kind
	var path: String = "%s/%s_%d.json" % [dir_path, slug, stamp]
	var suffix: int = 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d_%d.json" % [dir_path, slug, stamp, suffix]
		suffix += 1
	var wrapper: Dictionary = {
		"slot_version": SLOT_VERSION,
		"name": final_name,
		"kind": kind,
		"saved_unix": stamp,
		"summary": summary,
		"data": data,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": "", "error": "Could not write %s" % path}
	file.store_string(SnapshotIO.to_json(wrapper))
	file.close()
	return {"ok": true, "path": path, "error": ""}


## The slot wrapper with whole numbers back as ints, or {} when the file is missing or malformed.
func _read_slot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return {}
	var d: Dictionary = _whole_numbers_to_int(json.data) as Dictionary
	if int(d.get("slot_version", 0)) < 1 or not KIND_DIRS.has(str(d.get("kind", ""))) or not (d.get("data") is Dictionary):
		return {}
	return d


static func _whole_numbers_to_int(value: Variant) -> Variant:
	if value is float and is_equal_approx(value as float, roundf(value as float)):
		return int(value)
	if value is Array:
		var arr: Array = []
		for item: Variant in value:
			arr.append(_whole_numbers_to_int(item))
		return arr
	if value is Dictionary:
		var d: Dictionary = {}
		for k: Variant in (value as Dictionary).keys():
			d[k] = _whole_numbers_to_int((value as Dictionary)[k])
		return d
	return value


func _is_inside_root(path: String) -> bool:
	return path.begins_with(root + "/") and not path.contains("..")


func _marker_path() -> String:
	return "%s/%s" % [root, MIGRATED_MARKER]


func _now() -> int:
	return now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())


## The unix time in a legacy name such as base_1790712000.json, else the file's modified time.
static func _legacy_unix(file_name: String, path: String) -> int:
	var digits: String = file_name.get_basename().get_slice("_", file_name.get_basename().get_slice_count("_") - 1)
	if digits.is_valid_int() and int(digits) > 0:
		return int(digits)
	return int(FileAccess.get_modified_time(path))


static func _newer_first(a: Dictionary, b: Dictionary) -> bool:
	if int(a["saved_unix"]) != int(b["saved_unix"]):
		return int(a["saved_unix"]) > int(b["saved_unix"])
	return str(a["path"]).naturalnocasecmp_to(str(b["path"])) > 0


static func _day_index(unix: int) -> int:
	return (unix - posmod(unix, SECONDS_PER_DAY)) / SECONDS_PER_DAY


static func _plural(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]
