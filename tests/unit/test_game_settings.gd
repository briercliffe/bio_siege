extends GutTest

const TEST_PATH: String = "user://test_game_settings.cfg"


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_missing_file_returns_default() -> void:
	assert_false(GameSettings.get_bool("game", "seen_how_to_play", false, TEST_PATH))
	assert_true(GameSettings.get_bool("game", "seen_how_to_play", true, TEST_PATH))


func test_set_then_get_round_trips() -> void:
	assert_true(GameSettings.set_bool("audio", "muted", true, TEST_PATH))
	assert_true(GameSettings.get_bool("audio", "muted", false, TEST_PATH))
	assert_true(GameSettings.set_bool("audio", "muted", false, TEST_PATH))
	assert_false(GameSettings.get_bool("audio", "muted", true, TEST_PATH))


func test_writers_do_not_clobber_each_others_keys() -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, TEST_PATH)
	GameSettings.set_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, true, TEST_PATH)
	assert_true(GameSettings.get_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, false, TEST_PATH))
	assert_true(GameSettings.get_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, false, TEST_PATH))


func test_file_is_a_plain_config_file_with_the_documented_key() -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, TEST_PATH)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TEST_PATH), OK)
	assert_eq(cfg.get_value("game", "seen_how_to_play"), true)
	assert_eq(GameSettings.DEFAULT_PATH, "user://settings.cfg")


func test_int_round_trips_and_missing_returns_default() -> void:
	assert_eq(GameSettings.get_int("game", "best_score_test", 7, TEST_PATH), 7)
	assert_true(GameSettings.set_int("game", "best_score_test", 2650, TEST_PATH))
	assert_eq(GameSettings.get_int("game", "best_score_test", 0, TEST_PATH), 2650)
	assert_eq(GameSettings.get_int("game", "other_key", 3, TEST_PATH), 3)


func test_old_best_outbreak_key_is_harmless() -> void:
	# Outbreak was removed (#149). A settings file that still has its key loads and is ignored.
	assert_true(GameSettings.set_int("game", "best_outbreak_score", 2650, TEST_PATH))
	assert_false(GameSettings.get_bool("game", GameSettings.KEY_SEEN_HOW_TO_PLAY, false, TEST_PATH))


func test_float_round_trips_and_missing_returns_default() -> void:
	assert_almost_eq(GameSettings.get_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME, 0.8, TEST_PATH), 0.8, 0.0001)
	assert_true(GameSettings.set_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME, 0.35, TEST_PATH))
	assert_almost_eq(GameSettings.get_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME, 0.8, TEST_PATH), 0.35, 0.0001)
	GameSettings.set_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, true, TEST_PATH)
	assert_almost_eq(GameSettings.get_float(GameSettings.SECTION_AUDIO, GameSettings.KEY_MASTER_VOLUME, 0.8, TEST_PATH), 0.35, 0.0001)


func test_settings_keys_match_the_documented_names() -> void:
	assert_eq(GameSettings.SECTION_AUDIO, "audio")
	assert_eq(GameSettings.KEY_MASTER_VOLUME, "master_volume")
	assert_eq(GameSettings.KEY_MUTED, "muted")
	assert_eq(GameSettings.SECTION_GAMEPLAY, "gameplay")
	assert_eq(GameSettings.KEY_INTENT_LINES_DEFAULT, "intent_lines_default")
	assert_eq(GameSettings.SECTION_ACCESSIBILITY, "accessibility")
	assert_eq(GameSettings.KEY_REDUCE_FLASHES, "reduce_flashes")
	assert_eq(GameSettings.SECTION_PRIVACY, "privacy")
	assert_eq(GameSettings.KEY_TELEMETRY_CONSENT, "telemetry_consent")
	assert_eq(GameSettings.SECTION_DEBUG, "debug")
	assert_eq(GameSettings.KEY_DEBUG_OVERLAY, "debug_overlay")
	assert_eq(GameSettings.SECTION_GAME, "game")
	assert_eq(GameSettings.KEY_SEEN_HOW_TO_PLAY, "seen_how_to_play")
