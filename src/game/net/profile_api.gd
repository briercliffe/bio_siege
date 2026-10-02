class_name ProfileApi
extends RefCounted

## Typed wrappers over the profile RPCs (docs/SERVER_PLAN.md). Every mutating call returns a job id; this class
## polls job_status (every 0.5 s, up to 15 s) and returns the finished job. Returns are Dictionaries shaped
## {"ok": bool, "error": String, "result": Dictionary}; `result.profile` is the new server profile.

const POLL_INTERVAL_S: float = 0.5
const POLL_TIMEOUT_S: float = 15.0

var backend: BackendClient = null
var poll_interval_s: float = POLL_INTERVAL_S
var max_polls: int = int(POLL_TIMEOUT_S / POLL_INTERVAL_S)


func _init(p_backend: BackendClient = null) -> void:
	backend = p_backend if p_backend != null else Net.backend()


## profile_get: {"ok", "error", "profile": Dictionary ({} when the server has none yet), "job_id": String, "busy": bool}.
func profile_get(client_version: String, config_hash: String) -> Dictionary:
	var res: Dictionary = await backend.rpc("profile_get", {"client_version": client_version, "config_hash": config_hash})
	if not bool(res.get("ok", false)):
		return res
	res["profile"] = res.get("profile", {}) if res.get("profile", null) is Dictionary else {}
	return res


func base_commit(layout: Array) -> Dictionary:
	return await _run("base_commit", {"layout": layout})


func collect() -> Dictionary:
	return await _run("collect", {})


func upgrade_buy(id: String) -> Dictionary:
	return await _run("upgrade_buy", {"id": id})


func mutation_unlock(type_id: String, variant_id: String) -> Dictionary:
	return await _run("mutation_unlock", {"type": type_id, "variant": variant_id})


func profile_import(local_profile: Dictionary) -> Dictionary:
	return await _run("profile_import", {"local_profile": local_profile})


## Polls a job until it finishes. {"ok": true, "result"} when done; {"ok": false, "error": <job error>} when the
## worker rejected it; error "timeout" when it is still running after max_polls polls.
func wait_job(job_id: String, polls: int = -1) -> Dictionary:
	for i: int in range(polls if polls > 0 else max_polls):
		var st: Dictionary = await backend.rpc("job_status", {"job_id": job_id})
		if not bool(st.get("ok", false)):
			return {"ok": false, "error": str(st.get("error", "network_error")), "result": {}}
		var status: String = str(st.get("status", ""))
		if status == "done":
			return {"ok": true, "error": "", "result": st.get("result", {}) if st.get("result", null) is Dictionary else {}}
		if status == "failed":
			return {"ok": false, "error": str(st.get("job_error", "failed")), "result": {}}
		await _sleep()
	return {"ok": false, "error": "timeout", "result": {}}


func _run(rpc_name: String, payload: Dictionary) -> Dictionary:
	var res: Dictionary = await backend.rpc(rpc_name, payload)
	if not bool(res.get("ok", false)):
		return {"ok": false, "error": str(res.get("error", "network_error")), "result": {}}
	return await wait_job(str(res.get("job_id", "")))


func _sleep() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if poll_interval_s > 0.0:
		await tree.create_timer(poll_interval_s).timeout
	else:
		await tree.process_frame
