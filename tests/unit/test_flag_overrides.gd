extends GutTest

## Debug-build feature flag overrides (#217).

const TEST_PATH: String = "user://test_flag_overrides.json"
const BAD_DATA_DIR: String = "user://test_flag_overrides_data"
const GAME_DATA_SCRIPT: String = "res://src/game/game_data.gd"

var rules_str: String = ""
var structures_str: String = ""
var pathogens_str: String = ""


func before_all() -> void:
	rules_str = FileAccess.get_file_as_string("res://data/game_rules.json")
	structures_str = FileAccess.get_file_as_string("res://data/structures.json")
	pathogens_str = FileAccess.get_file_as_string("res://data/pathogens.json")


func before_each() -> void:
	FlagOverrides.clear(TEST_PATH)


func after_all() -> void:
	FlagOverrides.clear(TEST_PATH)
	for f: String in ["game_rules.json", "structures.json", "pathogens.json"]:
		if FileAccess.file_exists(BAD_DATA_DIR + "/" + f):
			DirAccess.remove_absolute(BAD_DATA_DIR + "/" + f)
	if DirAccess.dir_exists_absolute(BAD_DATA_DIR):
		DirAccess.remove_absolute(BAD_DATA_DIR)


## A GameData node reading overrides from TEST_PATH, as a debug build would.
func _game_data(data_dir: String = "res://data", enabled: bool = true) -> Node:
	var gd: Node = (load(GAME_DATA_SCRIPT) as GDScript).new()
	gd.flag_overrides_path = TEST_PATH
	gd.flag_overrides_enabled = enabled
	add_child_autofree(gd)  # _enter_tree loads res://data
	gd.load_data(data_dir)
	return gd


func _rules_without_coevolution_block() -> String:
	var rules: Dictionary = JSON.parse_string(rules_str)
	rules.erase("coevolution")
	return JSON.stringify(rules)


# --- GameConfig ------------------------------------------------------------------

func test_no_overrides_keeps_the_file_hash() -> void:
	var plain: ConfigLoadResult = GameConfig.load_from_strings(rules_str, structures_str, pathogens_str)
	assert_true(plain.is_ok())
	assert_eq(plain.config.content_hash, (rules_str + structures_str + pathogens_str).sha256_text())
	assert_true(plain.config.flag_overrides.is_empty())
	assert_eq(plain.config.file_feature_flags, plain.config.feature_flags)


func test_override_flips_the_flag_and_the_hash() -> void:
	var plain: GameConfig = GameConfig.load_from_strings(rules_str, structures_str, pathogens_str).config
	var res: ConfigLoadResult = GameConfig.load_from_strings(rules_str, structures_str, pathogens_str, {"coevolution": true})
	assert_true(res.is_ok())
	assert_true(res.config.flag("coevolution"))
	assert_true(res.config.coevolution_enabled())
	assert_false(bool(res.config.file_feature_flags["coevolution"]), "shipped value is kept")
	assert_eq(res.config.flag_overrides, {"coevolution": true})
	assert_ne(res.config.content_hash, plain.content_hash)


func test_unknown_and_non_bool_overrides_are_ignored() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_strings(rules_str, structures_str, pathogens_str,
			{"no_such_flag": true, "biofilm": "yes", "strains": 1})
	assert_true(res.is_ok())
	assert_true(res.config.flag_overrides.is_empty())
	assert_false(res.config.flag("no_such_flag"))
	assert_false(res.config.flag("biofilm"))


func test_override_is_validated_like_the_file() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_strings(_rules_without_coevolution_block(), structures_str,
			pathogens_str, {"coevolution": true})
	assert_true(res.is_err())
	assert_true("\n".join(res.errors).contains("coevolution: required when feature_flags.coevolution is true"))


# --- FlagOverrides ---------------------------------------------------------------

func test_write_read_and_clear_round_trip() -> void:
	assert_eq(FlagOverrides.read(TEST_PATH), {})
	assert_true(FlagOverrides.write({"strains": true, "biofilm": false}, TEST_PATH))
	assert_eq(FlagOverrides.read(TEST_PATH), {"biofilm": false, "strains": true})
	assert_true(FlagOverrides.write({}, TEST_PATH))
	assert_false(FileAccess.file_exists(TEST_PATH), "an empty override set deletes the file")


func test_read_drops_malformed_content() -> void:
	var f: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{\"strains\": true, \"biofilm\": 3}")
	f.close()
	assert_eq(FlagOverrides.read(TEST_PATH), {"strains": true})
	f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	assert_eq(FlagOverrides.read(TEST_PATH), {})


func test_diff_keeps_only_changes_from_the_shipped_flags() -> void:
	var shipped: Dictionary = {"strains": false, "biofilm": false, "raid_score": true}
	var d: Dictionary = FlagOverrides.diff({"strains": true, "biofilm": false, "raid_score": true, "bogus": true}, shipped)
	assert_eq(d, {"strains": true})


func test_listed_flags_hide_settings_owned_flags() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var listed: Array[String] = FlagOverrides.listed_flags(cfg)
	assert_false(listed.has("intent_lines_default"))
	for flag_name: String in FlagOverrides.IDENTITY_FLAGS:
		assert_true(listed.has(flag_name), flag_name + " is declared in game_rules.json and listed")


func test_release_builds_do_not_read_overrides() -> void:
	assert_false(FlagOverrides.is_supported(false, false))
	assert_false(FlagOverrides.is_supported(true, true), "headless tools and tests ignore overrides")
	assert_true(FlagOverrides.is_supported(true, false))
	FlagOverrides.write({"coevolution": true}, TEST_PATH)
	var gd: Node = _game_data("res://data", false)
	assert_false(gd.config.flag("coevolution"))
	assert_false(gd.set_flag_overrides({"strains": true}))


# --- GameData --------------------------------------------------------------------

func test_game_data_applies_and_persists_overrides() -> void:
	var gd: Node = _game_data()
	watch_signals(gd)
	assert_false(gd.config.flag("coevolution"))
	assert_true(gd.set_flag_overrides({"coevolution": true}))
	assert_signal_emitted(gd, "config_reloaded")
	assert_true(gd.config.flag("coevolution"))
	assert_eq(FlagOverrides.read(TEST_PATH), {"coevolution": true})
	var restarted: Node = _game_data()
	assert_true(restarted.config.flag("coevolution"), "overrides survive a restart")


func test_invalid_overrides_fall_back_to_shipped_flags() -> void:
	DirAccess.make_dir_recursive_absolute(BAD_DATA_DIR)
	var files: Dictionary = {
		"game_rules.json": _rules_without_coevolution_block(),
		"structures.json": structures_str,
		"pathogens.json": pathogens_str,
	}
	for name: String in files.keys():
		var f: FileAccess = FileAccess.open(BAD_DATA_DIR + "/" + name, FileAccess.WRITE)
		f.store_string(str(files[name]))
		f.close()
	FlagOverrides.write({"coevolution": true}, TEST_PATH)
	var gd: Node = _game_data(BAD_DATA_DIR)
	assert_not_null(gd.config, "the game still loads")
	assert_true(gd.load_errors.is_empty())
	assert_false(gd.config.flag("coevolution"))
	assert_true(str(gd.flag_override_error).contains("coevolution"))


# --- Debug overlay ---------------------------------------------------------------

func _overlay(gd: Node) -> DebugOverlay:
	var overlay: DebugOverlay = (load("res://src/ui/debug_overlay.tscn") as PackedScene).instantiate() as DebugOverlay
	overlay.data_source = gd
	add_child_autofree(overlay)
	return overlay


func test_overlay_lists_flags_and_controls_are_tappable() -> void:
	var overlay: DebugOverlay = _overlay(_game_data())
	assert_not_null(overlay.flags_button)
	assert_false(overlay.flag_switches.has("intent_lines_default"))
	assert_true(overlay.flag_switches.has("coevolution"))
	var controls: Array[Control] = [overlay.flags_button, overlay.btn_identity_on, overlay.btn_reset_flags]
	for sw: Variant in overlay.flag_switches.values():
		controls.append(sw as Control)
	for c: Control in controls:
		assert_gte(c.custom_minimum_size.y, 48.0, c.name)
		assert_gte(c.get_combined_minimum_size().x, 48.0, c.name)


func test_identity_preset_switch_and_reset() -> void:
	var gd: Node = _game_data()
	var overlay: DebugOverlay = _overlay(gd)
	overlay.toggle_flags()
	assert_true(overlay.flags_panel.visible)
	overlay.btn_identity_on.pressed.emit()
	for flag_name: String in FlagOverrides.IDENTITY_FLAGS:
		assert_true(gd.config.flag(flag_name), flag_name)
		assert_true((overlay.flag_switches[flag_name] as CheckButton).button_pressed)
		assert_eq((overlay.flag_switches[flag_name] as CheckButton).text, flag_name + " *")
	assert_false(gd.config.flag("move_nucleus"), "the preset only touches identity flags")

	(overlay.flag_switches["biofilm"] as CheckButton).button_pressed = false
	assert_false(gd.config.flag("biofilm"))
	assert_true(gd.config.flag("coevolution"), "one switch leaves the other overrides alone")
	assert_false(FlagOverrides.read(TEST_PATH).has("biofilm"), "back at the shipped value, so not stored")

	overlay.btn_reset_flags.pressed.emit()
	assert_true(gd.config.flag_overrides.is_empty())
	assert_false(FileAccess.file_exists(TEST_PATH))
	assert_eq(overlay.flags_status_label.text, "Shipped flags (no overrides)")


func test_flags_and_tools_panels_are_exclusive() -> void:
	var overlay: DebugOverlay = _overlay(_game_data())
	overlay.toggle()
	assert_true(overlay.is_open)
	overlay.toggle_flags()
	assert_true(overlay.flags_panel.visible)
	assert_false(overlay.is_open)
	overlay.toggle()
	assert_false(overlay.flags_panel.visible)
