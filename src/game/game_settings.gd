class_name GameSettings
extends RefCounted

## Tiny persistent key/value store for player preferences (user://settings.cfg).
## Every call re-reads the file, so independent writers (Sfx, HowToPlay) never
## overwrite each other's keys.

const DEFAULT_PATH: String = "user://settings.cfg"

const SECTION_GAME: String = "game"
const KEY_SEEN_HOW_TO_PLAY: String = "seen_how_to_play"

const SECTION_AUDIO: String = "audio"
const KEY_MUTED: String = "muted"


static func get_bool(section: String, key: String, default_value: bool = false, path: String = DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return default_value
	return bool(cfg.get_value(section, key, default_value))


static func set_bool(section: String, key: String, value: bool, path: String = DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(section, key, value)
	return cfg.save(path) == OK
