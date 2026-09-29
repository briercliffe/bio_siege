extends Node

var config: GameConfig = null
var load_errors: PackedStringArray = PackedStringArray()

func _enter_tree() -> void:
	load_data()

func load_data(dir_path: String = "res://data") -> void:
	var result: ConfigLoadResult = GameConfig.load_from_dir(dir_path)
	config = result.config
	load_errors = result.errors
	if not load_errors.is_empty():
		push_error("GameData failed to load config from " + dir_path + ":\n" + "\n".join(load_errors))
