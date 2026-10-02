class_name Net
extends RefCounted

## The single place the game gets its backend. With the `online` flag off this is an OfflineBackend that never
## touches the network; with it on, a NakamaBackend.

static var _backend: BackendClient = null
static var _injected: bool = false


static func backend(config: GameConfig = null) -> BackendClient:
	if _injected:
		return _backend
	var cfg: GameConfig = config if config != null else GameData.config
	var want_online: bool = cfg != null and cfg.flag("online")
	if _backend != null and (_backend is NakamaBackend) == want_online:
		return _backend
	if want_online:
		_backend = NakamaBackend.new(null, "", cfg.content_hash)
	else:
		_backend = OfflineBackend.new()
	return _backend


static func is_online_enabled(config: GameConfig = null) -> bool:
	var cfg: GameConfig = config if config != null else GameData.config
	return cfg != null and cfg.flag("online")


static func set_backend_for_tests(b: BackendClient) -> void:
	_backend = b
	_injected = b != null


static func reset() -> void:
	_backend = null
	_injected = false
