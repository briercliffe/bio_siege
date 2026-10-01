class_name GameSettings
extends RefCounted

## Tiny persistent key/value store for player preferences (user://settings.cfg).
## Every call re-reads the file, so independent writers (Sfx, HowToPlayScreen) never
## overwrite each other's keys.

const DEFAULT_PATH: String = "user://settings.cfg"

const SECTION_GAME: String = "game"
const KEY_SEEN_HOW_TO_PLAY: String = "seen_how_to_play"

const SECTION_AUDIO: String = "audio"
const KEY_MASTER_VOLUME: String = "master_volume"
const KEY_MUTED: String = "muted"

const SECTION_GAMEPLAY: String = "gameplay"
const KEY_INTENT_LINES_DEFAULT: String = "intent_lines_default"

const SECTION_ACCESSIBILITY: String = "accessibility"
const KEY_REDUCE_FLASHES: String = "reduce_flashes"

const SECTION_PRIVACY: String = "privacy"
const KEY_TELEMETRY_CONSENT: String = "telemetry_consent"

const SECTION_DEBUG: String = "debug"
const KEY_DEBUG_OVERLAY: String = "debug_overlay"

## Defaults for the keys above. The intent lines default comes from config.feature_flags instead.
const DEFAULT_MASTER_VOLUME: float = 0.8
const DEFAULT_MUTED: bool = false
const DEFAULT_REDUCE_FLASHES: bool = false
const DEFAULT_TELEMETRY_CONSENT: bool = true
const DEFAULT_DEBUG_OVERLAY: bool = false


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


static func get_int(section: String, key: String, default_value: int = 0, path: String = DEFAULT_PATH) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return default_value
	return int(cfg.get_value(section, key, default_value))


static func set_int(section: String, key: String, value: int, path: String = DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(section, key, value)
	return cfg.save(path) == OK


static func get_float(section: String, key: String, default_value: float = 0.0, path: String = DEFAULT_PATH) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return default_value
	return float(cfg.get_value(section, key, default_value))


static func set_float(section: String, key: String, value: float, path: String = DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(section, key, value)
	return cfg.save(path) == OK
