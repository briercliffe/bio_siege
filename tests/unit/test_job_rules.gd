extends GutTest

var _cfg: GameConfig


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config


func _job(type: String, payload: Dictionary, hash: String = "") -> Dictionary:
	return {"job_id": "j1", "type": type, "created_unix": 1800000000,
			"config_hash": hash if not hash.is_empty() else _cfg.content_hash, "payload": payload}


func test_echo_round_trips_the_payload() -> void:
	var payload: Dictionary = {"user_id": "u1", "n": 3, "nested": {"a": [1, 2]}}
	var res: Dictionary = JobRules.process(_cfg, _job("echo", payload))
	assert_true(res["ok"])
	assert_eq(res["error"], "")
	assert_eq(res["result"], payload)


func test_echo_result_is_a_copy() -> void:
	var payload: Dictionary = {"a": [1]}
	var res: Dictionary = JobRules.process(_cfg, _job("echo", payload))
	(res["result"] as Dictionary)["a"] = [2]
	assert_eq(payload, {"a": [1]})


func test_unknown_type_is_rejected() -> void:
	var res: Dictionary = JobRules.process(_cfg, _job("bogus", {}))
	assert_false(res["ok"])
	assert_eq(res["error"], "unknown_job_type")


func test_config_hash_mismatch_is_rejected() -> void:
	var res: Dictionary = JobRules.process(_cfg, _job("echo", {}, "not-the-hash"))
	assert_false(res["ok"])
	assert_eq(res["error"], "config_mismatch")


func test_missing_payload_is_treated_as_empty() -> void:
	var res: Dictionary = JobRules.process(_cfg, {"type": "echo", "config_hash": _cfg.content_hash})
	assert_true(res["ok"])
	assert_eq(res["result"], {})


func test_worker_parses_its_arguments() -> void:
	var worker: GDScript = load("res://tools/worker/worker.gd")
	var args: Dictionary = worker.parse_args(PackedStringArray(["--url=http://x:7350", "--http-key=a=b", "--once", "ignored"]))
	assert_eq(args["url"], "http://x:7350")
	assert_eq(args["http-key"], "a=b")
	assert_true(args["once"])
	assert_false(args.has("ignored"))
