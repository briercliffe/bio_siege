extends Node

static var instance: Node = null

var _current_path: String = ""
var _file: FileAccess = null
## Cached telemetry consent. While it is off, log_event() writes nothing and no session file is opened.
var _consent: bool = true
## Player preferences file the consent is read from at _ready(). Tests point it at a temp file.
var settings_path: String = GameSettings.DEFAULT_PATH

func _enter_tree() -> void:
	if instance == null:
		instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _file != null:
		_file.close()
		_file = null

func _ready() -> void:
	if instance == null:
		instance = self
	_consent = GameSettings.get_bool(GameSettings.SECTION_PRIVACY, GameSettings.KEY_TELEMETRY_CONSENT,
			GameSettings.DEFAULT_TELEMETRY_CONSENT, settings_path)
	if _file == null and _consent:
		_init_session_file()

## Called by the Settings screen after it saves the consent key. Turning consent back on opens a new
## session file if none was opened yet.
func set_consent(on: bool) -> void:
	_consent = on
	if _consent and _file == null and _current_path.is_empty() and is_inside_tree():
		_init_session_file()

func has_consent() -> bool:
	return _consent

func _init_session_file() -> void:
	if not DirAccess.dir_exists_absolute("user://telemetry"):
		DirAccess.make_dir_recursive_absolute("user://telemetry")
	var unix_time: int = int(Time.get_unix_time_from_system())
	var hex_part: String = "%04x" % (randi() & 0xffff)
	_current_path = "user://telemetry/session_%d_%s.jsonl" % [unix_time, hex_part]
	_file = FileAccess.open(_current_path, FileAccess.WRITE)
	if _file == null:
		push_warning("SessionLogger: could not open %s" % _current_path)
		return

	var config_hash: String = ""
	var gd = get_node_or_null("/root/GameData")
	if gd != null and "config" in gd and gd.config != null:
		config_hash = str(gd.config.content_hash)

	var build_str: String = BuildInfo.read()

	log_event("session_start", {
		"config_hash": config_hash,
		"platform": OS.get_name(),
		"build": build_str
	})

func set_custom_file_path(path: String) -> void:
	if _file != null:
		_file.close()
		_file = null
	_current_path = path
	var dir_path: String = path.get_base_dir()
	if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("SessionLogger: Failed to open custom file path: " + path)

func log_event(event: String, data: Dictionary = {}) -> void:
	if not _consent:
		return
	if _file == null:
		push_warning("SessionLogger: File not open, cannot log event: " + event)
		return

	var entry: Dictionary = {
		"t_ms": Time.get_ticks_msec(),
		"event": event
	}
	for k in data.keys():
		entry[str(k)] = _sanitize_value(data[k])

	var line: String = JSON.stringify(entry)
	_file.store_line(line)
	_file.flush()

static func log_session_event(event: String, data: Dictionary = {}) -> void:
	if instance != null:
		instance.log_event(event, data)

static func _sanitize_value(val: Variant) -> Variant:
	if val is Vector2i:
		return [val.x, val.y]
	elif val is Vector2:
		return [val.x, val.y]
	elif val is Array:
		var arr: Array = []
		for item in val:
			arr.append(_sanitize_value(item))
		return arr
	elif val is Dictionary:
		var dict: Dictionary = {}
		for k in val:
			dict[str(k)] = _sanitize_value(val[k])
		return dict
	return val

static func all_sessions_text() -> String:
	if instance != null and instance._file != null:
		instance._file.flush()

	if not DirAccess.dir_exists_absolute("user://telemetry"):
		return ""

	var dir := DirAccess.open("user://telemetry")
	if dir == null:
		return ""

	var files: Array[String] = []
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while not fn.is_empty():
		if not dir.current_is_dir() and fn.ends_with(".jsonl"):
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	files.sort()

	var result: String = ""
	for f_name in files:
		var f := FileAccess.open("user://telemetry/" + f_name, FileAccess.READ)
		if f != null:
			var txt: String = f.get_as_text()
			f.close()
			result += txt
			if not txt.is_empty() and not txt.ends_with("\n"):
				result += "\n"
	return result
