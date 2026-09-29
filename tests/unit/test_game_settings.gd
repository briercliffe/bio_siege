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
