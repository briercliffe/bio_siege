class_name SettingsApply
extends RefCounted

## Applies the saved player preferences (GameSettings) to the engine and to live nodes. No autoload:
## Main calls apply_all() at startup, and the Settings screen calls notify_changed() after each save so
## nodes in GROUP re-read what they use (Main: debug overlay; InfectionPhase: reduce flashes).

## Nodes in this group implement `on_settings_changed() -> void`.
const GROUP: String = "settings_listeners"
const MASTER_BUS: int = 0
const SILENT_VOLUME: float = 0.001


static func apply_all(debug_overlay: Control = null, path: String = GameSettings.DEFAULT_PATH,
		is_debug: bool = OS.is_debug_build()) -> void:
	apply_master_volume(master_volume(path))
	apply_debug_overlay(debug_overlay, path, is_debug)


static func master_volume(path: String = GameSettings.DEFAULT_PATH) -> float:
	var v: float = GameSettings.get_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME,
			GameSettings.DEFAULT_MASTER_VOLUME, path)
	return clampf(v, 0.0, 1.0)


static func apply_master_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(v))
	AudioServer.set_bus_mute(MASTER_BUS, v <= SILENT_VOLUME)


## The overlay is a dev tool: release builds never show it, whatever the saved value.
static func debug_overlay_visible(path: String = GameSettings.DEFAULT_PATH, is_debug: bool = OS.is_debug_build()) -> bool:
	return is_debug and GameSettings.get_bool(GameSettings.SECTION_DEBUG, GameSettings.KEY_DEBUG_OVERLAY,
			GameSettings.DEFAULT_DEBUG_OVERLAY, path)


static func apply_debug_overlay(debug_overlay: Control, path: String = GameSettings.DEFAULT_PATH,
		is_debug: bool = OS.is_debug_build()) -> void:
	if debug_overlay == null or not is_instance_valid(debug_overlay) or debug_overlay.is_queued_for_deletion():
		return
	debug_overlay.visible = debug_overlay_visible(path, is_debug)


static func reduce_flashes(path: String = GameSettings.DEFAULT_PATH) -> bool:
	return GameSettings.get_bool(GameSettings.SECTION_ACCESSIBILITY, GameSettings.KEY_REDUCE_FLASHES,
			GameSettings.DEFAULT_REDUCE_FLASHES, path)


static func telemetry_consent(path: String = GameSettings.DEFAULT_PATH) -> bool:
	return GameSettings.get_bool(GameSettings.SECTION_PRIVACY, GameSettings.KEY_TELEMETRY_CONSENT,
			GameSettings.DEFAULT_TELEMETRY_CONSENT, path)


## The config's feature flag is the default until the player picks a value on the Settings screen.
static func config_intent_lines_default(config: GameConfig) -> bool:
	if config == null:
		return true
	return bool(config.feature_flags.get("intent_lines_default", true))


static func intent_lines_default(config: GameConfig, path: String = GameSettings.DEFAULT_PATH) -> bool:
	return GameSettings.get_bool(GameSettings.SECTION_GAMEPLAY, GameSettings.KEY_INTENT_LINES_DEFAULT,
			config_intent_lines_default(config), path)


static func notify_changed(tree: SceneTree) -> void:
	if tree != null:
		tree.call_group(GROUP, "on_settings_changed")
