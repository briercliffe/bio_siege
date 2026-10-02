class_name BackendClient
extends RefCounted

## The single client-side seam for online calls (docs/SERVER_PLAN.md). UI and flow code talk to this, never to
## Nakama types. Feature methods (profile_get, raid_start, ...) are added by later issues as thin wrappers over rpc().
## Every response is a Dictionary shaped {"ok": bool, "error": String, ...}.

signal status_changed(status: String)

const STATUS_OFFLINE: String = "offline"
const STATUS_CONNECTING: String = "connecting"
const STATUS_ONLINE: String = "online"
const STATUS_UPDATE_REQUIRED: String = "update_required"

var _status: String = STATUS_OFFLINE


func connect_and_auth() -> Dictionary:
	return {"ok": false, "error": "not_implemented"}


func rpc(_name: String, _payload: Dictionary) -> Dictionary:
	return {"ok": false, "error": "not_implemented"}


func status() -> String:
	return _status


func _set_status(new_status: String) -> void:
	if new_status == _status:
		return
	_status = new_status
	status_changed.emit(new_status)


## Calls the server's `ping` and compares its content hash with ours (docs/SERVER_PLAN.md, Versioning).
## A mismatch sets "update_required"; a good ping sets "online".
func verify_server(local_content_hash: String) -> Dictionary:
	var pong: Dictionary = await rpc("ping", {})
	if not bool(pong.get("ok", false)):
		_set_status(STATUS_OFFLINE)
		return pong
	if str(pong.get("content_hash", "")) != local_content_hash:
		_set_status(STATUS_UPDATE_REQUIRED)
		return {"ok": false, "error": "update_required"}
	_set_status(STATUS_ONLINE)
	return pong
