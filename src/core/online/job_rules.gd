class_name JobRules
extends RefCounted

## Pure job rules for the headless worker (docs/SERVER_PLAN.md, "Job protocol"). Never touches the network,
## files or Time: the only clock is the job's own `created_unix`, which the server stamps.

const ECHO: String = "echo"


## Dispatches by job type. job = {"job_id", "type", "created_unix", "config_hash", "payload"}.
## Returns {"ok": bool, "result": Dictionary, "error": String}.
static func process(cfg: GameConfig, job: Dictionary) -> Dictionary:
	if str(job.get("config_hash", "")) != cfg.content_hash:
		return _fail("config_mismatch")
	var payload: Dictionary = job.get("payload", {}) as Dictionary if job.get("payload", {}) is Dictionary else {}
	match str(job.get("type", "")):
		ECHO:
			return {"ok": true, "result": payload.duplicate(true), "error": ""}
		_:
			return _fail("unknown_job_type")


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "result": {}, "error": error}
