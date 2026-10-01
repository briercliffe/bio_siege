class_name LivingBaseStore
extends RefCounted

## Reads and writes the Living Base profile file (#156). Game layer, so it may
## touch files and the real-time clock; LivingBaseProfile itself stays pure.

const DEFAULT_PATH: String = "user://living_base.json"
const BAD_NOTICE: String = "Your saved base could not be read and was reset. The old file was kept as living_base.bad.json."

var path: String = DEFAULT_PATH

func exists() -> bool:
	return FileAccess.file_exists(path)

## Same shape as LivingBaseProfile.from_dict, plus "fresh": bool.
func load_profile(cfg: GameConfig) -> Dictionary:
	if not exists():
		var none: Array[String] = []
		return _new_profile(cfg, none)
	var text: String = FileAccess.get_file_as_string(path)
	var res: Dictionary = {}
	var json := JSON.new()
	if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
		res = LivingBaseProfile.from_dict(json.data, cfg)
	if not bool(res.get("ok", false)):
		_keep_bad_file()
		var bad: Array[String] = [BAD_NOTICE]
		return _new_profile(cfg, bad)
	res["fresh"] = false
	return res

func save_profile(p: LivingBaseProfile) -> bool:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("LivingBaseStore: could not open %s for writing (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(p.to_dict()))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(path)
		var err: Error = DirAccess.rename_absolute(tmp, path)
		if err != OK:
			push_warning("LivingBaseStore: could not move %s over %s (error %d)" % [tmp, path, err])
			return false
	return true

static func now_unix() -> int:
	return int(Time.get_unix_time_from_system())

func _new_profile(cfg: GameConfig, notices: Array[String]) -> Dictionary:
	var now: int = now_unix()
	var p: LivingBaseProfile = LivingBaseProfile.create_new(cfg, now ^ 0x5eed, now)
	save_profile(p)
	return {"ok": true, "profile": p, "error": "", "notices": notices, "fresh": true}

func _keep_bad_file() -> void:
	var bad: String = path.get_basename() + ".bad.json"
	if FileAccess.file_exists(bad):
		DirAccess.remove_absolute(bad)
	if DirAccess.rename_absolute(path, bad) != OK:
		push_warning("LivingBaseStore: could not keep the unreadable save as %s" % bad)
