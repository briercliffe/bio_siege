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


## Raid lifecycle wrappers (docs/SERVER_PLAN.md). Each is one RPC; results arrive as worker jobs (see ProfileApi.wait_job).
func raid_start(defender_id: String) -> Dictionary:
	return await rpc("raid_start", {"defender_id": defender_id})


## `army` is [{"type", "cell": [x, y], "strain"}]; the client sends its deployments and its final hash, never results.
func raid_submit(raid_id: String, army: Array, client_final_hash: String) -> Dictionary:
	return await rpc("raid_submit", {"raid_id": raid_id, "army": army, "client_final_hash": client_final_hash})


## Cancels a raid that was not submitted. Pass the army so the server can still charge it.
func raid_cancel(raid_id: String, army: Array = []) -> Dictionary:
	var payload: Dictionary = {"raid_id": raid_id}
	if not army.is_empty():
		payload["army"] = army
	return await rpc("raid_cancel", payload)


## One matchmade player to raid: {"defender_id", "preview": snapshot, "trophies"}, or {"ai": true} when none qualifies.
func find_opponent() -> Dictionary:
	return await rpc("find_opponent", {})


## The top 50 and the caller's rank: {"records": [{rank, user_id, name, trophies}], "me": {rank, trophies}}.
func leaderboard_top() -> Dictionary:
	return await rpc("leaderboard_top", {})


## Online defense log: entries without battles (newest first, 20 per page), one full entry, and "seen" marks.
func defense_log_list(cursor: String = "") -> Dictionary:
	return await rpc("defense_log_list", {"cursor": cursor})


func defense_log_get(raid_id: String) -> Dictionary:
	return await rpc("defense_log_get", {"raid_id": raid_id})


func defense_log_mark_seen(raid_ids: Array) -> Dictionary:
	return await rpc("defense_log_mark_seen", {"raid_ids": raid_ids})


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
