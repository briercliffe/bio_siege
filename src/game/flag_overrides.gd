class_name FlagOverrides
extends RefCounted

## Debug-build feature flag overrides (#217): `user://flag_overrides.json` holds {flag name: bool}.
## Testers flip flags on a device from the debug overlay without rebuilding the APK. Release builds
## never read the file. GameConfig applies the overrides before validation.

const DEFAULT_PATH: String = "user://flag_overrides.json"

## The flags the identity playtest turns on together (IDENTITY_PROPOSAL section 7, epic #141).
const IDENTITY_FLAGS: Array[String] = [
	"raid_score", "bcell_analysis", "biofilm", "phage_hijack", "phage_turncoat",
	"strains", "immune_memory", "coevolution",
]

## Flags owned elsewhere (Settings), so the overlay does not list them.
const HIDDEN_FLAGS: Array[String] = ["intent_lines_default"]


## Debug builds with a display only. Headless runs (the GUT suite, the balance sim and other tools) ignore
## the file, so a tester's local overrides never change test or balance results.
static func is_supported(is_debug: bool = OS.is_debug_build(),
		is_headless: bool = DisplayServer.get_name() == "headless") -> bool:
	return is_debug and not is_headless


## Reads the overrides. A missing, unreadable or malformed file is {}; non-bool values are dropped.
static func read(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for k: Variant in (parsed as Dictionary).keys():
		var v: Variant = (parsed as Dictionary)[k]
		if typeof(v) == TYPE_BOOL:
			out[str(k)] = v
	return out


## Writes the overrides (keys sorted). An empty dictionary deletes the file. Returns false on error.
static func write(overrides: Dictionary, path: String = DEFAULT_PATH) -> bool:
	if overrides.is_empty():
		return clear(path)
	var keys: Array = overrides.keys()
	keys.sort()
	var ordered: Dictionary = {}
	for k: Variant in keys:
		ordered[str(k)] = bool(overrides[k])
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("FlagOverrides: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(ordered, "  ", false))
	return true


static func clear(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


## The overrides needed to reach `wanted` (flag -> bool): only flags whose wanted value differs from the
## shipped value in `file_flags`. Keeps the file minimal, so a later data change to a default still lands.
static func diff(wanted: Dictionary, file_flags: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in wanted.keys():
		var flag_name: String = str(k)
		if not file_flags.has(flag_name):
			continue
		if bool(wanted[k]) != bool(file_flags[flag_name]):
			out[flag_name] = bool(wanted[k])
	return out


## Flags the overlay lists: every declared feature flag except HIDDEN_FLAGS, sorted.
static func listed_flags(config: GameConfig) -> Array[String]:
	var out: Array[String] = []
	if config == null:
		return out
	for k: Variant in config.file_feature_flags.keys():
		if not HIDDEN_FLAGS.has(str(k)):
			out.append(str(k))
	out.sort()
	return out
