extends Node

signal config_reloaded(config: GameConfig)
signal config_reload_failed(errors: PackedStringArray)

const DEFAULT_DATA_DIR: String = "res://data"
const DATA_FILES: Array[String] = ["game_rules.json", "structures.json", "pathogens.json"]
const WATCH_INTERVAL_S: float = 1.0

var config: GameConfig = null
var load_errors: PackedStringArray = PackedStringArray()
var hot_reload_enabled: bool = false

var _data_dir: String = DEFAULT_DATA_DIR
var _mtimes: Dictionary = {}
var _watch_timer: Timer = null

func _enter_tree() -> void:
	load_data()

func _ready() -> void:
	setup_watcher(is_hot_reload_supported())

## Hot reload only makes sense for debug runs from the project folder.
## Exported builds (including web) pack res://, so the files never change.
static func is_hot_reload_supported(is_debug: bool = OS.is_debug_build(), is_template: bool = OS.has_feature("template")) -> bool:
	return is_debug and not is_template

func load_data(dir_path: String = DEFAULT_DATA_DIR) -> void:
	_data_dir = dir_path
	_mtimes = _read_mtimes()
	var result: ConfigLoadResult = GameConfig.load_from_dir(dir_path)
	config = result.config
	load_errors = result.errors
	if not load_errors.is_empty():
		push_error("GameData failed to load config from " + dir_path + ":\n" + "\n".join(load_errors))

func setup_watcher(enabled: bool) -> void:
	hot_reload_enabled = enabled
	print("GameData: config hot reload is %s" % ("ON" if enabled else "OFF"))
	if not enabled:
		return
	_watch_timer = Timer.new()
	_watch_timer.name = "ConfigWatchTimer"
	_watch_timer.wait_time = WATCH_INTERVAL_S
	_watch_timer.one_shot = false
	_watch_timer.timeout.connect(check_for_changes)
	add_child(_watch_timer)
	_watch_timer.start()

## Returns true when a data file changed and a reload was attempted.
func check_for_changes() -> bool:
	var now: Dictionary = _read_mtimes()
	if now == _mtimes:
		return false
	_mtimes = now
	reload_config()
	return true

## Loads the data files into a temporary config. The active config is only
## replaced when the new one is valid.
func reload_config() -> bool:
	var result: ConfigLoadResult = GameConfig.load_from_dir(_data_dir)
	if result.is_err():
		config_reload_failed.emit(result.errors)
		return false
	config = result.config
	load_errors = PackedStringArray()
	config_reloaded.emit(config)
	return true

func _read_mtimes() -> Dictionary:
	var times: Dictionary = {}
	var base: String = _data_dir if _data_dir.ends_with("/") else _data_dir + "/"
	for file_name: String in DATA_FILES:
		times[file_name] = FileAccess.get_modified_time(base + file_name)
	return times
