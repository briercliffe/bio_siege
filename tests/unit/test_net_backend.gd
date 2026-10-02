extends GutTest

const DEVICE_PATH: String = "user://test_net_device_id.txt"
const GOOD_HASH: String = "abc123"


func after_each() -> void:
	Net.reset()
	if FileAccess.file_exists(DEVICE_PATH):
		DirAccess.remove_absolute(DEVICE_PATH)


func _config(online: bool) -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data", {"online": online})
	assert_true(res.is_ok())
	return res.config


func test_online_flag_defaults_to_false() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	assert_false(cfg.flag("online"))
	assert_false(Net.is_online_enabled(cfg))


func test_offline_backend_records_calls_and_returns_canned_responses() -> void:
	var b := OfflineBackend.new()
	b.respond("profile_get", {"ok": true, "error": "", "job_id": "j1"})
	var res: Dictionary = await b.rpc("profile_get", {"client_version": "0.1"})
	assert_true(res["ok"])
	assert_eq(res["job_id"], "j1")
	var unknown: Dictionary = await b.rpc("nope", {})
	assert_false(unknown["ok"])
	assert_eq(b.call_names(), ["profile_get", "nope"] as Array[String])
	assert_eq(b.calls[0]["payload"], {"client_version": "0.1"})


func test_base_class_methods_are_not_implemented() -> void:
	var b := BackendClient.new()
	assert_eq((await b.connect_and_auth())["error"], "not_implemented")
	assert_eq((await b.rpc("x", {}))["error"], "not_implemented")
	assert_eq(b.status(), "offline")


func test_net_backend_respects_the_flag() -> void:
	var off: BackendClient = Net.backend(_config(false))
	assert_true(off is OfflineBackend)
	assert_eq(Net.backend(_config(false)), off, "the same backend is reused")
	var on: BackendClient = Net.backend(_config(true))
	assert_true(on is NakamaBackend)
	assert_true(Net.backend(_config(false)) is OfflineBackend, "flipping the flag swaps the backend")


func test_flag_off_makes_no_network_calls() -> void:
	var b: BackendClient = Net.backend(_config(false))
	var res: Dictionary = await b.rpc("profile_get", {})
	assert_false(res["ok"])
	assert_eq(b.status(), "offline")


func test_set_backend_for_tests_injects() -> void:
	var fake := OfflineBackend.new()
	Net.set_backend_for_tests(fake)
	assert_eq(Net.backend(_config(true)), fake)


func test_device_id_is_created_once_and_reused() -> void:
	var first: String = DeviceId.load_or_create(DEVICE_PATH)
	assert_eq(first.length(), 32)
	assert_eq(DeviceId.load_or_create(DEVICE_PATH), first)


func test_content_hash_mismatch_sets_update_required() -> void:
	var b := OfflineBackend.new()
	b.respond("ping", {"ok": true, "error": "", "content_hash": "different"})
	var seen: Array[String] = []
	b.status_changed.connect(func(s: String) -> void: seen.append(s))
	var res: Dictionary = await b.verify_server(GOOD_HASH)
	assert_false(res["ok"])
	assert_eq(res["error"], "update_required")
	assert_eq(b.status(), "update_required")
	assert_eq(seen, ["update_required"] as Array[String])


func test_matching_content_hash_goes_online() -> void:
	var b := OfflineBackend.new()
	b.respond("ping", {"ok": true, "error": "", "content_hash": GOOD_HASH})
	var res: Dictionary = await b.verify_server(GOOD_HASH)
	assert_true(res["ok"])
	assert_eq(b.status(), "online")


func test_failed_ping_goes_offline() -> void:
	var b := OfflineBackend.new()
	b.set_status_for_tests("online")
	await b.verify_server(GOOD_HASH)
	assert_eq(b.status(), "offline")


func test_server_address_parse() -> void:
	var a: ServerAddress = ServerAddress.parse("http://127.0.0.1:7350")
	assert_eq([a.scheme, a.host, a.port], ["http", "127.0.0.1", 7350])
	var b: ServerAddress = ServerAddress.parse("https://play.example.com")
	assert_eq([b.scheme, b.host, b.port], ["https", "play.example.com", 443])
	var c: ServerAddress = ServerAddress.parse("https://play.example.com:7350/")
	assert_eq([c.scheme, c.host, c.port], ["https", "play.example.com", 7350])


func test_connection_pill_follows_backend_status() -> void:
	var pill := ConnectionPill.new()
	add_child_autofree(pill)
	var b := OfflineBackend.new()
	pill.bind(b)
	assert_eq(pill.shown_status, "offline")
	b.set_status_for_tests("connecting")
	assert_eq(pill.shown_status, "connecting")
	b.set_status_for_tests("update_required")
	assert_eq(pill.shown_status, "update_required")
	assert_eq(pill.custom_minimum_size, ConnectionPill.PILL_SIZE)


func test_only_src_game_net_references_nakama_types() -> void:
	var offenders: Array[String] = []
	_scan("res://src", offenders)
	_scan("res://tools", offenders)
	assert_eq(offenders, [] as Array[String], "NakamaClient/NakamaSession may only appear under src/game/net")


func _scan(dir_path: String, offenders: Array[String]) -> void:
	for sub: String in DirAccess.get_directories_at(dir_path):
		if dir_path == "res://src/game" and sub == "net":
			continue
		_scan("%s/%s" % [dir_path, sub], offenders)
	for file_name: String in DirAccess.get_files_at(dir_path):
		if not file_name.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string("%s/%s" % [dir_path, file_name])
		if text.contains("NakamaClient") or text.contains("NakamaSession"):
			offenders.append("%s/%s" % [dir_path, file_name])
