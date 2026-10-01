extends GutTest

const SettingsScene: PackedScene = preload("res://src/ui/screens/settings_screen.tscn")
const SessionLoggerScript = preload("res://src/telemetry/session_logger.gd")
const TEST_PATH: String = "user://test_settings_screen.cfg"
const TEST_LOG_PATH: String = "user://telemetry/test_settings_screen_log.jsonl"

var _sfx_path: String = ""
var _sfx_muted: bool = false
var _bus_db: float = 0.0
var _bus_mute: bool = false
var _logger_consent: bool = true


func before_each() -> void:
	_cleanup()
	_sfx_path = Sfx.settings_path
	_sfx_muted = Sfx.muted
	Sfx.settings_path = TEST_PATH
	_bus_db = AudioServer.get_bus_volume_db(SettingsApply.MASTER_BUS)
	_bus_mute = AudioServer.is_bus_mute(SettingsApply.MASTER_BUS)
	_logger_consent = SessionLogger.has_consent()
	SessionLogger.set_consent(true)


func after_each() -> void:
	Sfx.settings_path = _sfx_path
	Sfx.muted = _sfx_muted
	AudioServer.set_bus_volume_db(SettingsApply.MASTER_BUS, _bus_db)
	AudioServer.set_bus_mute(SettingsApply.MASTER_BUS, _bus_mute)
	SessionLogger.set_consent(_logger_consent)
	_cleanup()


func _cleanup() -> void:
	for path: String in [TEST_PATH, TEST_LOG_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _make_screen(is_debug: bool = true) -> SettingsScreen:
	var screen: SettingsScreen = SettingsScene.instantiate() as SettingsScreen
	screen.setup(TEST_PATH, is_debug)
	add_child_autofree(screen)
	return screen


## A 1280x720 host, since the screen root fills its parent.
func _make_sized_screen() -> SettingsScreen:
	var host := Control.new()
	host.size = SettingsScreen.DESIGN_SIZE
	add_child_autofree(host)
	var screen: SettingsScreen = SettingsScene.instantiate() as SettingsScreen
	screen.setup(TEST_PATH, true)
	host.add_child(screen)
	return screen


func _saved(section: String, key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(TEST_PATH) != OK:
		return null
	return cfg.get_value(section, key, null)


func _flip(sw: ToggleSwitch) -> void:
	sw.button_pressed = not sw.button_pressed


static func _file_size(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_file_as_bytes(path).size()


func _make_logger() -> Node:
	var logger: Node = SessionLoggerScript.new()
	add_child_autoqfree(logger)
	logger.set_custom_file_path(TEST_LOG_PATH)
	return logger


func test_scene_root_follows_the_screen_contract() -> void:
	var screen := _make_screen()
	assert_true(screen.has_signal("back_requested"))
	assert_eq(screen.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(ScreenStack.SCREENS["settings"], screen.scene_file_path)


func test_each_switch_writes_its_section_and_key() -> void:
	var screen := _make_screen()
	var cases: Array[Dictionary] = [
		{"sw": screen.sfx_switch, "section": GameSettings.SECTION_AUDIO, "key": GameSettings.KEY_MUTED, "inverted": true},
		{"sw": screen.intent_switch, "section": GameSettings.SECTION_GAMEPLAY, "key": GameSettings.KEY_INTENT_LINES_DEFAULT, "inverted": false},
		{"sw": screen.flashes_switch, "section": GameSettings.SECTION_ACCESSIBILITY, "key": GameSettings.KEY_REDUCE_FLASHES, "inverted": false},
		{"sw": screen.telemetry_switch, "section": GameSettings.SECTION_PRIVACY, "key": GameSettings.KEY_TELEMETRY_CONSENT, "inverted": false},
		{"sw": screen.debug_switch, "section": GameSettings.SECTION_DEBUG, "key": GameSettings.KEY_DEBUG_OVERLAY, "inverted": false},
	]
	for c: Dictionary in cases:
		var sw: ToggleSwitch = c["sw"] as ToggleSwitch
		var section: String = c["section"] as String
		var key: String = c["key"] as String
		var inverted: bool = c["inverted"] as bool
		for _i: int in range(2):
			_flip(sw)
			var expected: bool = (not sw.button_pressed) if inverted else sw.button_pressed
			assert_eq(_saved(section, key), expected, "%s/%s after a flip" % [section, key])


func test_reopening_the_screen_shows_the_saved_values() -> void:
	var first := _make_screen()
	first.volume_slider.value = 0.3
	_flip(first.sfx_switch)
	_flip(first.intent_switch)
	_flip(first.flashes_switch)
	_flip(first.telemetry_switch)
	_flip(first.debug_switch)
	var expected: Array[bool] = [first.sfx_switch.button_pressed, first.intent_switch.button_pressed,
			first.flashes_switch.button_pressed, first.telemetry_switch.button_pressed, first.debug_switch.button_pressed]

	var second := _make_screen()
	assert_almost_eq(second.volume_slider.value, 0.3, 0.001)
	var shown: Array[bool] = [second.sfx_switch.button_pressed, second.intent_switch.button_pressed,
			second.flashes_switch.button_pressed, second.telemetry_switch.button_pressed, second.debug_switch.button_pressed]
	assert_eq(shown, expected)


func test_defaults_match_the_settings_table() -> void:
	Sfx.muted = false
	var screen := _make_screen()
	assert_almost_eq(screen.volume_slider.value, GameSettings.DEFAULT_MASTER_VOLUME, 0.001)
	assert_true(screen.sfx_switch.button_pressed)
	assert_eq(screen.intent_switch.button_pressed, SettingsApply.config_intent_lines_default(GameData.config))
	assert_false(screen.flashes_switch.button_pressed)
	assert_true(screen.telemetry_switch.button_pressed)
	assert_false(screen.debug_switch.button_pressed)
	assert_false(FileAccess.file_exists(TEST_PATH), "opening the screen saves nothing")


func test_volume_slider_sets_the_master_bus_and_saves() -> void:
	var screen := _make_screen()
	screen.volume_slider.value = 0.5
	assert_almost_eq(AudioServer.get_bus_volume_db(SettingsApply.MASTER_BUS), linear_to_db(0.5), 0.01)
	assert_false(AudioServer.is_bus_mute(SettingsApply.MASTER_BUS))
	assert_almost_eq(float(_saved(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME)), 0.5, 0.001)
	screen.volume_slider.value = 0.0
	assert_true(AudioServer.is_bus_mute(SettingsApply.MASTER_BUS))


func test_volume_drag_applies_live_and_saves_on_release() -> void:
	var screen := _make_screen()
	screen.volume_slider.drag_started.emit()
	screen.volume_slider.value = 0.4
	screen.volume_slider.value = 0.3
	assert_almost_eq(AudioServer.get_bus_volume_db(SettingsApply.MASTER_BUS), linear_to_db(0.3), 0.01)
	assert_null(_saved(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME), "nothing saved mid-drag")
	screen.volume_slider.drag_ended.emit(true)
	assert_almost_eq(float(_saved(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME)), 0.3, 0.001)


func test_main_uses_its_settings_path() -> void:
	GameSettings.set_bool(GameSettings.SECTION_DEBUG, GameSettings.KEY_DEBUG_OVERLAY, OS.is_debug_build(), TEST_PATH)
	GameSettings.set_bool(GameSettings.SECTION_GAMEPLAY, GameSettings.KEY_INTENT_LINES_DEFAULT, false, TEST_PATH)
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, TEST_PATH)
	GameSettings.set_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME, 0.6, TEST_PATH)
	var main_node: Node = (load("res://src/main.tscn") as PackedScene).instantiate()
	main_node.set("settings_path", TEST_PATH)
	add_child_autofree(main_node)
	var fsm: GameStateMachine = main_node.get_node("GameStateMachine") as GameStateMachine
	assert_eq(fsm.settings_path, TEST_PATH)
	assert_false(fsm.session.intent_lines_enabled)
	assert_almost_eq(AudioServer.get_bus_volume_db(SettingsApply.MASTER_BUS), linear_to_db(0.6), 0.01)
	var overlay: Control = main_node.get_node_or_null("DebugOverlay") as Control
	if overlay != null and not overlay.is_queued_for_deletion():
		assert_true(overlay.visible)
	var stack: ScreenStack = main_node.get_node("ScreenStack") as ScreenStack
	assert_false(stack.is_open(), "How to play was already seen in this settings file")
	stack.push("settings")
	var screen: SettingsScreen = stack.top_screen() as SettingsScreen
	assert_eq(screen.settings_path, TEST_PATH)
	assert_false(screen.intent_switch.button_pressed)


func test_sound_effects_off_mutes_sfx() -> void:
	Sfx.muted = false
	var screen := _make_screen()
	assert_true(screen.sfx_switch.button_pressed)
	screen.sfx_switch.button_pressed = false
	assert_true(Sfx.muted)
	assert_eq(_saved(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED), true)
	screen.sfx_switch.button_pressed = true
	assert_false(Sfx.muted)


func test_telemetry_off_stops_the_session_logger_writing() -> void:
	var screen := _make_screen()
	var log_path: String = SessionLogger._current_path
	assert_false(log_path.is_empty(), "the autoload has a session file while consent is on")
	SessionLogger.log_event("probe", {})
	assert_gt(_file_size(log_path), 0)
	screen.telemetry_switch.button_pressed = false
	assert_false(SessionLogger.has_consent())
	var before: int = _file_size(log_path)
	SessionLogger.log_event("x", {})
	assert_eq(_file_size(log_path), before)


func test_telemetry_switch_drives_an_injected_logger() -> void:
	var logger: Node = _make_logger()
	var screen := _make_screen()
	screen.logger = logger
	screen.telemetry_switch.button_pressed = false
	logger.log_event("x", {})
	assert_eq(_file_size(TEST_LOG_PATH), 0)
	screen.telemetry_switch.button_pressed = true
	logger.log_event("x", {})
	assert_gt(_file_size(TEST_LOG_PATH), 0)


func test_logger_without_consent_writes_nothing() -> void:
	var logger: Node = _make_logger()
	logger.set_consent(false)
	logger.log_event("x", {"a": 1})
	assert_eq(_file_size(TEST_LOG_PATH), 0)
	logger.set_consent(true)
	logger.log_event("x", {"a": 1})
	assert_gt(_file_size(TEST_LOG_PATH), 0)


func test_reset_shows_the_tips_again() -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, TEST_PATH)
	assert_false(HowToPlayScreen.should_show_on_launch(TEST_PATH))
	var screen := _make_screen()
	screen.reset_button.pressed.emit()
	assert_true(HowToPlayScreen.should_show_on_launch(TEST_PATH))
	assert_eq(screen.toast.last_message, "Tips will show again")


func test_release_build_disables_but_shows_the_debug_switch() -> void:
	var screen := _make_screen(false)
	assert_true(screen.debug_switch.disabled)
	assert_true(screen.debug_switch.is_visible_in_tree())
	var dev := _make_screen(true)
	assert_false(dev.debug_switch.disabled)


func test_every_tappable_control_is_at_least_48px() -> void:
	var screen := _make_sized_screen()
	await get_tree().process_frame
	var controls: Array[Control] = screen.tappable_controls()
	assert_eq(controls.size(), 8)
	for c: Control in controls:
		assert_true(c.size.x >= 48.0 and c.size.y >= 48.0, "%s is %s" % [c.name, c.size])
	assert_eq(screen.volume_slider.size.x, 220.0)
	assert_eq(screen.reset_button.size, Vector2(92.0, 48.0))


func test_layout_matches_the_mockup_at_1280x720() -> void:
	var screen := _make_sized_screen()
	await get_tree().process_frame
	assert_eq(screen.back_button.position, Vector2(32.0, 28.0))
	assert_eq(screen.card.position, Vector2(320.0, 112.0))
	assert_eq(screen.card.size.x, 640.0)
	var rows: Array[Node] = screen.rows_box.get_children().filter(func(n: Node) -> bool: return n is HBoxContainer)
	assert_eq(rows.size(), 7)
	for row: Node in rows:
		assert_almost_eq((row as Control).size.y, 72.0, 2.0)
	assert_lt(screen.card.get_rect().end.y, screen.footer_label.position.y)


func test_back_pops_the_screen_from_the_stack() -> void:
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	stack.push("settings")
	var screen: SettingsScreen = stack.top_screen() as SettingsScreen
	assert_not_null(screen)
	screen.back_button.pressed.emit()
	assert_false(stack.is_open())


func test_night_theme_keeps_the_layout() -> void:
	var screen := _make_sized_screen()
	await get_tree().process_frame
	var day_card: Rect2 = screen.card.get_rect()
	screen.night = true
	await get_tree().process_frame
	assert_true(screen.background.night)
	assert_true(screen.sfx_switch.night)
	assert_true(screen.volume_slider.night)
	assert_true(screen.reset_button.night)
	assert_eq(screen.card.get_rect(), day_card)


func test_session_reads_the_intent_lines_default() -> void:
	var cfg: GameConfig = GameData.config
	assert_eq(Session.new(cfg, TEST_PATH).intent_lines_enabled, SettingsApply.config_intent_lines_default(cfg))
	GameSettings.set_bool(GameSettings.SECTION_GAMEPLAY, GameSettings.KEY_INTENT_LINES_DEFAULT, false, TEST_PATH)
	assert_false(Session.new(cfg, TEST_PATH).intent_lines_enabled)
	GameSettings.set_bool(GameSettings.SECTION_GAMEPLAY, GameSettings.KEY_INTENT_LINES_DEFAULT, true, TEST_PATH)
	assert_true(Session.new(cfg, TEST_PATH).intent_lines_enabled)


func test_apply_all_sets_the_master_bus_and_debug_overlay() -> void:
	var overlay := Control.new()
	add_child_autofree(overlay)
	GameSettings.set_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME, 0.25, TEST_PATH)
	GameSettings.set_bool(GameSettings.SECTION_DEBUG, GameSettings.KEY_DEBUG_OVERLAY, true, TEST_PATH)
	SettingsApply.apply_all(overlay, TEST_PATH, true)
	assert_almost_eq(AudioServer.get_bus_volume_db(SettingsApply.MASTER_BUS), linear_to_db(0.25), 0.01)
	assert_true(overlay.visible)
	SettingsApply.apply_all(overlay, TEST_PATH, false)
	assert_false(overlay.visible, "release builds never show the overlay")
	GameSettings.set_bool(GameSettings.SECTION_DEBUG, GameSettings.KEY_DEBUG_OVERLAY, false, TEST_PATH)
	SettingsApply.apply_all(overlay, TEST_PATH, true)
	assert_false(overlay.visible)


func test_reduce_flashes_reaches_the_anim_driver() -> void:
	var layer := UnitLayer.new()
	add_child_autofree(layer)
	assert_false(layer.driver.reduce_flashes)
	layer.reduce_flashes = true
	assert_true(layer.driver.reduce_flashes)


func test_infection_phase_refreshes_reduce_flashes_on_change() -> void:
	var phase := InfectionPhase.new()
	phase.settings_path = TEST_PATH
	phase.unit_layer = UnitLayer.new()
	phase.add_child(phase.unit_layer)
	phase.effect_layer = EffectLayer.new()
	phase.effect_layer.model = phase.effect_model
	phase.add_child(phase.effect_layer)
	add_child_autofree(phase)
	assert_true(phase.is_in_group(SettingsApply.GROUP))
	var screen := _make_screen()
	screen.flashes_switch.button_pressed = true
	assert_true(phase.unit_layer.driver.reduce_flashes)
	assert_true(phase.effect_layer.reduce_flashes)
	assert_true(phase.effect_model.reduce_flashes, "no hit sparks from now on")
	screen.flashes_switch.button_pressed = false
	assert_false(phase.unit_layer.driver.reduce_flashes)
	assert_false(phase.effect_layer.reduce_flashes)
	assert_false(phase.effect_model.reduce_flashes)
