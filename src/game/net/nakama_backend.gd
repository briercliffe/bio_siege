class_name NakamaBackend
extends BackendClient

## The real backend: Nakama anonymous device auth plus JSON RPCs (docs/SERVER_PLAN.md).
## The vendored client's autoload is not enabled; this class hosts Nakama.gd as a plain node under the SceneTree root.

const NAKAMA_SCRIPT: GDScript = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")
const REFRESH_MARGIN_S: int = 60

var _host: Node = null
var _client: NakamaClient = null
var _session: NakamaSession = null
var _device_id_path: String = DeviceId.DEFAULT_PATH
var _address: ServerAddress = null
var _server_key: String = ""
var _local_hash: String = ""


func _init(p_address: ServerAddress = null, p_server_key: String = "", p_local_hash: String = "",
		p_device_id_path: String = DeviceId.DEFAULT_PATH) -> void:
	_address = p_address if p_address != null else ServerAddress.from_project_settings()
	_server_key = p_server_key if not p_server_key.is_empty() else ServerAddress.server_key_from_project_settings()
	_local_hash = p_local_hash
	_device_id_path = p_device_id_path


func connect_and_auth() -> Dictionary:
	_set_status(STATUS_CONNECTING)
	if not await _ensure_client():
		_set_status(STATUS_OFFLINE)
		return {"ok": false, "error": "no_scene_tree"}
	var auth: Dictionary = await _authenticate()
	if not bool(auth.get("ok", false)):
		_set_status(STATUS_OFFLINE)
		return auth
	return await verify_server(_local_hash)


func rpc(name: String, payload: Dictionary) -> Dictionary:
	if _session == null or _client == null:
		return {"ok": false, "error": "not_connected"}
	if _session.would_expire_in(REFRESH_MARGIN_S):
		var refreshed: NakamaSession = null
		if not _session.is_refresh_expired():
			refreshed = await _client.session_refresh_async(_session)
		if refreshed != null and not refreshed.is_exception():
			_session = refreshed
		else:
			var auth: Dictionary = await _authenticate()
			if not bool(auth.get("ok", false)):
				_set_status(STATUS_OFFLINE)
				return auth
	var res: Variant = await _client.rpc_async(_session, name, JSON.stringify(payload))
	if res == null or bool(res.is_exception()):
		return {"ok": false, "error": "network_error"}
	var parsed: Variant = JSON.parse_string(str(res.payload))
	if not parsed is Dictionary:
		return {"ok": false, "error": "bad_response"}
	return parsed as Dictionary


func _ensure_client() -> bool:
	if _client != null:
		return true
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	_host = NAKAMA_SCRIPT.new() as Node
	_host.name = "NakamaHost"
	tree.root.add_child.call_deferred(_host)
	await tree.process_frame
	_client = _host.create_client(_server_key, _address.host, _address.port, _address.scheme) as NakamaClient
	return _client != null


func _authenticate() -> Dictionary:
	var device_id: String = DeviceId.load_or_create(_device_id_path)
	var session: NakamaSession = await _client.authenticate_device_async(device_id, null, true)
	if session == null or session.is_exception():
		return {"ok": false, "error": "auth_failed"}
	_session = session
	return {"ok": true, "error": ""}
