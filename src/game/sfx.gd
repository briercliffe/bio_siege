extends Node

## Autoload "Sfx": procedural sound effects through a pool of 8 players.
## Deliberately has no class_name (it would clash with the autoload name).

signal mute_changed(is_muted: bool)

const POOL_SIZE: int = 8
const RATE_LIMITED: Array[String] = ["tower_fire", "hit"]
const RATE_LIMIT_MAX: int = 6
const RATE_LIMIT_WINDOW_MS: int = 100

var muted: bool = false
var settings_path: String = GameSettings.DEFAULT_PATH

var _clips: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_steal: int = 0
var _limiter: SfxRateLimiter = SfxRateLimiter.new(RATE_LIMIT_MAX, RATE_LIMIT_WINDOW_MS)


func _ready() -> void:
	muted = GameSettings.get_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, false, settings_path)
	_clips = SfxSynth.build_all()
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "Player%d" % i
		add_child(player)
		_players.append(player)


func has_clip(sound_name: String) -> bool:
	return _clips.has(sound_name)


func play(sound_name: String) -> void:
	if muted or not _clips.has(sound_name):
		return
	if RATE_LIMITED.has(sound_name) and not _limiter.allow(Time.get_ticks_msec()):
		return
	var player: AudioStreamPlayer = _acquire_player()
	player.stream = _clips[sound_name]
	player.play()


func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	if muted:
		for player: AudioStreamPlayer in _players:
			player.stop()
	GameSettings.set_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, muted, settings_path)
	mute_changed.emit(muted)


func toggle_mute() -> void:
	set_muted(not muted)


## First idle player, otherwise the pool is stolen from round-robin.
func _acquire_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if not player.playing:
			return player
	var stolen: AudioStreamPlayer = _players[_next_steal]
	_next_steal = (_next_steal + 1) % _players.size()
	return stolen
