extends SceneTree

## Headless validation worker (docs/SERVER_PLAN.md, "Job protocol"). Claims jobs from the Nakama server over
## server-to-server RPC (http_key, no user session), runs the pure rules in JobRules and reports the result.
##
##   godot --headless --path . -s tools/worker/worker.gd -- --url=http://127.0.0.1:7350 --http-key=KEY [--once]
##
## --once processes one claimed batch and exits (tests and CI). Otherwise it loops, sleeping 1 s when idle.

const CLAIM_MAX: int = 4
const IDLE_SLEEP_S: float = 1.0
const HTTP_TIMEOUT_S: float = 15.0

var _url: String = ""
var _http_key: String = ""
var _once: bool = false
var _cfg: GameConfig = null


func _initialize() -> void:
	_main()


func _main() -> void:
	var args: Dictionary = parse_args(OS.get_cmdline_user_args())
	_url = str(args.get("url", "")).rstrip("/")
	_http_key = str(args.get("http-key", ""))
	_once = args.has("once")
	if _url.is_empty() or _http_key.is_empty():
		printerr("worker: --url=... and --http-key=... are required")
		quit(2)
		return
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	if res.config == null:
		printerr("worker: invalid game data in res://data: %s" % ", ".join(res.errors))
		quit(2)
		return
	_cfg = res.config
	print("worker: config_hash=%s url=%s once=%s" % [_cfg.content_hash, _url, str(_once)])
	var failed_claims: int = 0
	while true:
		var claim: Dictionary = await _rpc("worker_claim", {"config_hash": _cfg.content_hash, "max": CLAIM_MAX})
		var jobs: Array = []
		if bool(claim.get("ok", false)):
			failed_claims = 0
			jobs = claim.get("jobs", []) as Array
		else:
			failed_claims += 1
			printerr("worker: worker_claim failed: %s" % str(claim.get("error", "?")))
			if _once:
				quit(1)
				return
		for j: Variant in jobs:
			if j is Dictionary:
				await _run_job(j as Dictionary)
		if _once and bool(claim.get("ok", false)):
			quit(0)
			return
		if jobs.is_empty():
			await create_timer(IDLE_SLEEP_S).timeout


## "--a=b --flag" -> {"a": "b", "flag": true}.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a: String in args:
		if not a.begins_with("--"):
			continue
		var body: String = a.substr(2)
		var eq: int = body.find("=")
		if eq < 0:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


func _run_job(job: Dictionary) -> void:
	var t0: int = Time.get_ticks_msec()
	var outcome: Dictionary = JobRules.process(_cfg, job)
	var ms: int = Time.get_ticks_msec() - t0
	var done: Dictionary = await _rpc("worker_complete", {
		"job_id": str(job.get("job_id", "")),
		"ok": bool(outcome.get("ok", false)),
		"result": outcome.get("result", {}),
		"error": str(outcome.get("error", "")),
	})
	print("%s %s %d %s%s" % [str(job.get("job_id", "")), str(job.get("type", "")), ms, str(bool(outcome.get("ok", false))),
			"" if bool(done.get("ok", false)) else " (complete failed: %s)" % str(done.get("error", "?"))])


## POST /v2/rpc/<id>?http_key=...&unwrap with the JSON payload as the body.
func _rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = HTTP_TIMEOUT_S
	root.add_child.call_deferred(req)
	await process_frame
	var full_url: String = "%s/v2/rpc/%s?http_key=%s&unwrap" % [_url, rpc_id, _http_key.uri_encode()]
	var err: int = req.request(full_url, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "request_failed_%d" % err}
	var resp: Array = await req.request_completed
	req.queue_free()
	var code: int = int(resp[1])
	var body: String = (resp[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {"ok": false, "error": "http_%d" % code}
