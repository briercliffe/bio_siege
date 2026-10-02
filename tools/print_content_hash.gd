extends SceneTree
## Prints GameConfig.content_hash for res://data (used to refresh server/test/fixtures/content_hash.txt).


func _init() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	if res.config == null:
		push_error("Failed to load config from res://data")
		quit(1)
		return
	print(res.config.content_hash)
	quit(0)
