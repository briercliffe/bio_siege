extends GutTest

const SfxScript = preload("res://src/game/sfx.gd")
const TEST_PATH: String = "user://test_sfx_settings.cfg"

var _sfx: Node = null


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _make_sfx() -> Node:
	var sfx: Node = SfxScript.new()
	sfx.settings_path = TEST_PATH
	add_child_autofree(sfx)
	return sfx


func _playing_streams(sfx: Node) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for player: AudioStreamPlayer in sfx._players:
		if player.playing:
			streams.append(player.stream)
	return streams


func test_autoload_is_registered() -> void:
	assert_not_null(Sfx)
	assert_true(Sfx.has_clip("place"))


func test_pool_has_eight_players_and_all_clips() -> void:
	var sfx: Node = _make_sfx()
	assert_eq(sfx._players.size(), 8)
	for clip_name: String in SfxSynth.NAMES:
		assert_true(sfx.has_clip(clip_name), clip_name)


func test_play_starts_the_named_clip() -> void:
	var sfx: Node = _make_sfx()
	sfx.play("place")
	var streams: Array[AudioStream] = _playing_streams(sfx)
	assert_eq(streams.size(), 1)
	assert_eq(streams[0], sfx._clips["place"])


func test_unknown_name_is_ignored() -> void:
	var sfx: Node = _make_sfx()
	sfx.play("does_not_exist")
	assert_eq(_playing_streams(sfx).size(), 0)


func test_pool_is_capped_at_eight_voices() -> void:
	var sfx: Node = _make_sfx()
	for i in range(12):
		sfx.play("win")
	assert_eq(_playing_streams(sfx).size(), 8)


func test_tower_fire_and_hit_share_a_six_per_window_limit() -> void:
	var sfx: Node = _make_sfx()
	var limiter := SfxRateLimiter.new(6, 100)
	# Freeze the clock by swapping in a limiter that never expires within the test.
	limiter.window_ms = 60000
	sfx._limiter = limiter
	for i in range(5):
		sfx.play("tower_fire")
	sfx.play("hit")
	sfx.play("hit")
	sfx.play("tower_fire")
	assert_eq(_playing_streams(sfx).size(), 6, "only 6 of the 8 rate-limited plays sound")


func test_other_sounds_are_not_rate_limited() -> void:
	var sfx: Node = _make_sfx()
	sfx._limiter = SfxRateLimiter.new(0, 60000)
	sfx.play("place")
	sfx.play("destroy")
	assert_eq(_playing_streams(sfx).size(), 2)


func test_rate_limit_constants_match_the_spec() -> void:
	assert_eq(SfxScript.RATE_LIMITED, ["tower_fire", "hit"] as Array[String])
	assert_eq(SfxScript.RATE_LIMIT_MAX, 6)
	assert_eq(SfxScript.RATE_LIMIT_WINDOW_MS, 100)


func test_mute_silences_and_stops_playing_sounds() -> void:
	var sfx: Node = _make_sfx()
	sfx.play("win")
	assert_eq(_playing_streams(sfx).size(), 1)
	sfx.set_muted(true)
	assert_true(sfx.muted)
	assert_eq(_playing_streams(sfx).size(), 0, "muting stops current sounds")
	sfx.play("place")
	assert_eq(_playing_streams(sfx).size(), 0, "muted plays nothing")
	sfx.toggle_mute()
	assert_false(sfx.muted)
	sfx.play("place")
	assert_eq(_playing_streams(sfx).size(), 1)


func test_mute_emits_signal_only_on_change() -> void:
	var sfx: Node = _make_sfx()
	watch_signals(sfx)
	sfx.set_muted(false)
	assert_signal_not_emitted(sfx, "mute_changed")
	sfx.set_muted(true)
	assert_signal_emit_count(sfx, "mute_changed", 1)
	assert_signal_emitted_with_parameters(sfx, "mute_changed", [true])


func test_mute_persists_across_instances() -> void:
	var first: Node = _make_sfx()
	assert_false(first.muted, "defaults to sound on")
	first.set_muted(true)
	assert_true(GameSettings.get_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, false, TEST_PATH))
	var second: Node = _make_sfx()
	assert_true(second.muted, "a fresh launch restores the saved mute")
	second.set_muted(false)
	assert_false(_make_sfx().muted)
