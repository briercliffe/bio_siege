extends GutTest

## The online Living Base flow with OfflineBackend canned responses (no network).

const DIR: String = "user://test_lb_online"
const T0: int = 1800000000

var _cfg: GameConfig
var _backend: OfflineBackend
var _flow: LivingBaseFlow
var _session: Session
var _messages: Array[String] = []


func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true, "amino_upgrades": true})
	_cfg = res.config
	_backend = OfflineBackend.new()
	_backend.set_status_for_tests("online")
	_messages = []


func after_each() -> void:
	_clean()
	Net.reset()


func _clean() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _server_profile(extra: Dictionary = {}) -> Dictionary:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 5, T0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict())) as Dictionary
	d["trophies"] = 0
	for k: Variant in extra.keys():
		d[k] = extra[k]
	return d


func _layout_with(entries: Array) -> Array:
	var grid := GridModel.new(_cfg)
	grid.reset_with_nucleus()
	var layout: Array = JSON.parse_string(JSON.stringify(LivingBaseFlow._layout_payload(grid.to_layout()))) as Array
	layout.append_array(entries)
	return layout


func _enter(server: Dictionary) -> Dictionary:
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": server, "job_id": "tick"})
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	_flow = LivingBaseFlow.new(store)
	_flow.online_cache_path = DIR + "/online.json"
	_flow.local_base_path = DIR + "/local.json"
	_flow.import_answered_path = DIR + "/answered.txt"
	_flow.message.connect(func(t: String) -> void: _messages.append(t))
	_session = Session.new(_cfg)
	var api := ProfileApi.new(_backend)
	api.poll_interval_s = 0.0
	api.max_polls = 5
	return await _flow.enter_online(_session, api)


func test_enter_online_shows_the_stored_copy() -> void:
	var server: Dictionary = _server_profile()
	(server["wallet"] as Dictionary)["atp"] = 777
	var res: Dictionary = await _enter(server)
	assert_true(res["ok"])
	assert_true(_flow.is_online())
	assert_eq(_session.mode, Session.Mode.LIVING_BASE)
	assert_eq(_session.wallet.get_amount("atp"), 777)
	assert_eq(_flow.store.path, DIR + "/online.json", "the offline base file is never written")
	assert_eq(_flow.pending_raids, 0, "no local away raids online")
	assert_false(_flow.layout_dirty())
	assert_eq(_backend.call_names(), ["profile_get"] as Array[String])
	assert_eq(_backend.calls[0]["payload"]["config_hash"], _cfg.content_hash)


func test_new_profile_path() -> void:
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": null, "job_id": "new"})
	_backend.respond_sequence("job_status", [
		{"ok": true, "status": "queued", "result": null},
		{"ok": true, "status": "done", "result": {"profile": _server_profile()}},
	])
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	_flow = LivingBaseFlow.new(store)
	_flow.online_cache_path = DIR + "/online.json"
	_flow.local_base_path = DIR + "/local.json"
	_flow.import_answered_path = DIR + "/answered.txt"
	_session = Session.new(_cfg)
	var api := ProfileApi.new(_backend)
	api.poll_interval_s = 0.0
	var res: Dictionary = await _flow.enter_online(_session, api)
	assert_true(res["ok"])
	assert_true(_flow.is_online())
	assert_false(_flow.import_offer_pending, "no offline base exists")


func test_import_is_offered_once_when_an_offline_base_exists() -> void:
	var f: FileAccess = FileAccess.open(DIR + "/local.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(LivingBaseProfile.create_new(_cfg, 9, T0).to_dict()))
	f.close()
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": null, "job_id": "new"})
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": _server_profile()}})
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	_flow = LivingBaseFlow.new(store)
	_flow.online_cache_path = DIR + "/online.json"
	_flow.local_base_path = DIR + "/local.json"
	_flow.import_answered_path = DIR + "/answered.txt"
	_session = Session.new(_cfg)
	var api := ProfileApi.new(_backend)
	api.poll_interval_s = 0.0
	var entered: Dictionary = await _flow.enter_online(_session, api)
	assert_true(entered["ok"], str(entered))
	assert_true(FileAccess.file_exists(DIR + "/local.json"))
	assert_true(_flow.import_offer_pending)
	_backend.respond("profile_import", {"ok": true, "error": "", "job_id": "imp"})
	var imported: Dictionary = _server_profile()
	(imported["wallet"] as Dictionary)["atp"] = 850
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": imported}})
	var res: Dictionary = await _flow.import_local_base()
	assert_true(res["ok"])
	assert_false(_flow.import_offer_pending)
	assert_eq(_session.wallet.get_amount("atp"), 850)
	var sent: Dictionary = _backend.calls[_backend.calls.size() - 2]["payload"]["local_profile"] as Dictionary
	assert_eq(sent["format"], LivingBaseProfile.FORMAT)
	assert_true(FileAccess.file_exists(DIR + "/answered.txt"))
	# A second online entry no longer offers it.
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": null, "job_id": "new"})
	var again := LivingBaseFlow.new(store)
	again.online_cache_path = DIR + "/online.json"
	again.local_base_path = DIR + "/local.json"
	again.import_answered_path = DIR + "/answered.txt"
	await again.enter_online(Session.new(_cfg), api)
	assert_false(again.import_offer_pending)


func test_optimistic_edit_then_accepted_commit() -> void:
	await _enter(_server_profile())
	var cost: int = int(_cfg.structures["mitochondria"].cost["atp"])
	assert_gt(_session.grid.place("mitochondria", Vector2i(4, 4), _session.wallet), 0)
	assert_true(_flow.layout_dirty(), "the edit shows at once and is not saved yet")
	var committed: Dictionary = _server_profile()
	committed["layout"] = LivingBaseFlow._layout_payload(_session.grid.to_layout())
	(committed["wallet"] as Dictionary)["atp"] = 1000 - cost
	_backend.respond("base_commit", {"ok": true, "error": "", "job_id": "c1"})
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": committed}})
	var saving_log: Array[bool] = []
	_flow.saving_changed.connect(func(v: bool) -> void: saving_log.append(v))
	var res: Dictionary = await _flow.commit_if_dirty()
	assert_true(res["ok"])
	assert_eq(saving_log, [true, false] as Array[bool])
	assert_false(_flow.layout_dirty())
	assert_eq(_session.wallet.get_amount("atp"), 1000 - cost)
	var sent: Array = _backend.calls[_backend.calls.size() - 2]["payload"]["layout"] as Array
	assert_eq(sent.size(), 2)
	assert_eq(_messages, [] as Array[String])


func test_rejected_commit_restores_the_server_copy_and_shows_a_message() -> void:
	await _enter(_server_profile())
	assert_gt(_session.grid.place("mitochondria", Vector2i(4, 4), _session.wallet), 0)
	assert_eq(_session.grid.structures().size(), 2)
	_backend.respond("base_commit", {"ok": true, "error": "", "job_id": "c1"})
	_backend.respond("job_status", {"ok": true, "status": "failed", "job_error": "insufficient_funds"})
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _server_profile(), "job_id": "t"})
	var res: Dictionary = await _flow.commit_base()
	assert_false(res["ok"])
	assert_eq(res["error"], "insufficient_funds")
	assert_eq(_session.grid.structures().size(), 1, "back to the server layout")
	assert_false(_flow.layout_dirty())
	assert_eq(_messages, [NetCopy.error_text("insufficient_funds")] as Array[String])
	assert_eq(_session.wallet.get_amount("atp"), 1000)


func test_a_busy_server_is_retried() -> void:
	await _enter(_server_profile())
	assert_gt(_session.grid.place("mitochondria", Vector2i(4, 4), _session.wallet), 0)
	var committed: Dictionary = _server_profile()
	committed["layout"] = LivingBaseFlow._layout_payload(_session.grid.to_layout())
	_backend.respond_sequence("base_commit", [
		{"ok": false, "error": "busy"},
		{"ok": true, "error": "", "job_id": "c1"},
	])
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": committed}})
	var res: Dictionary = await _flow.commit_base()
	assert_true(res["ok"])
	assert_eq(_backend.call_names().count("base_commit"), 2)


func test_collect_goes_through_the_server() -> void:
	await _enter(_server_profile())
	var after: Dictionary = _server_profile()
	(after["wallet"] as Dictionary)["atp"] = 1025
	_backend.respond("collect", {"ok": true, "error": "", "job_id": "k"})
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": after, "collected": 25}})
	var amount: int = await _flow.collect_async()
	assert_eq(amount, 25)
	assert_eq(_session.wallet.get_amount("atp"), 1025)


func test_collect_saves_pending_edits_first() -> void:
	await _enter(_server_profile())
	assert_gt(_session.grid.place("mitochondria", Vector2i(4, 4), _session.wallet), 0)
	var committed: Dictionary = _server_profile()
	committed["layout"] = LivingBaseFlow._layout_payload(_session.grid.to_layout())
	_backend.respond("base_commit", {"ok": true, "error": "", "job_id": "c"})
	_backend.respond("collect", {"ok": true, "error": "", "job_id": "k"})
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": committed, "collected": 0}})
	await _flow.collect_async()
	var names: Array[String] = _backend.call_names()
	assert_lt(names.find("base_commit"), names.find("collect"))


func test_upgrade_buy_and_its_rejection() -> void:
	await _enter(_server_profile())
	var after: Dictionary = _server_profile()
	after["upgrades"] = {"memory_slot": 1}
	_backend.respond("upgrade_buy", {"ok": true, "error": "", "job_id": "u"})
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": after, "cost": {"amino_acids": 150}}})
	assert_true(await _flow.buy_upgrade_async("memory_slot"))
	assert_eq(BaseUpgrades.level(_session.profile.upgrades, "memory_slot"), 1)
	_backend.respond("job_status", {"ok": true, "status": "failed", "job_error": "maxed"})
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": after, "job_id": "t"})
	assert_false(await _flow.buy_upgrade_async("memory_slot"))
	assert_eq(_messages, [NetCopy.error_text("maxed")] as Array[String])


func test_a_slow_job_times_out() -> void:
	await _enter(_server_profile())
	_backend.respond("collect", {"ok": true, "error": "", "job_id": "k"})
	_backend.respond("job_status", {"ok": true, "status": "queued", "result": null})
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _server_profile(), "job_id": "t"})
	assert_eq(await _flow.collect_async(), 0)
	assert_eq(_messages, [NetCopy.error_text("timeout")] as Array[String])


func test_enter_online_reports_connection_failures() -> void:
	_backend.set_status_for_tests("offline")
	_backend.respond("connect_and_auth", {"ok": false, "error": "auth_failed"})
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	var flow := LivingBaseFlow.new(store)
	var api := ProfileApi.new(_backend)
	var res: Dictionary = await flow.enter_online(Session.new(_cfg), api)
	assert_false(res["ok"])
	assert_eq(res["error"], "auth_failed")
	assert_false(flow.is_online())


func test_update_required_is_reported() -> void:
	_backend.respond("profile_get", {"ok": false, "error": "update_required"})
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	var flow := LivingBaseFlow.new(store)
	var res: Dictionary = await flow.enter_online(Session.new(_cfg), ProfileApi.new(_backend))
	assert_eq(res["error"], "update_required")


func test_flag_off_flow_is_unchanged() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true}).config
	var store := LivingBaseStore.new()
	store.path = DIR + "/offline.json"
	var flow := LivingBaseFlow.new(store)
	var session := Session.new(cfg)
	flow.enter(session)
	assert_false(flow.is_online())
	assert_false(flow.layout_dirty())
	assert_eq(session.mode, Session.Mode.LIVING_BASE)
	assert_eq(store.path, DIR + "/offline.json")
