extends GutTest

## The client side of a PvP raid with OfflineBackend canned responses: it sends intents, never results.

const DIR: String = "user://test_pvp_flow"
const T0: int = 1800000000

var _cfg: GameConfig
var _backend: OfflineBackend
var _flow: LivingBaseFlow
var _session: Session
var _messages: Array[String] = []


func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true}).config
	_backend = OfflineBackend.new()
	_backend.set_status_for_tests("online")
	_messages = []


func after_each() -> void:
	_clean()


func _clean() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _profile() -> Dictionary:
	return JSON.parse_string(JSON.stringify(LivingBaseProfile.create_new(_cfg, 5, T0).to_dict())) as Dictionary


func _enter() -> void:
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
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
	api.max_polls = 4
	var res: Dictionary = await _flow.enter_online(_session, api)
	assert_true(res["ok"])


func _start_response() -> Dictionary:
	return {"ok": true, "error": "", "raid_id": "raid-1", "seed": 4242, "expires_unix": T0 + 600, "defender_snapshot": {
		"layout": [{"type": "nucleus", "origin": [18, 18]}, {"type": "mitochondria", "origin": [10, 10]}],
		"memory": {}, "populations": {}, "stored_atp": 300, "trophies": 0, "updated_unix": T0}}


func test_begin_aims_the_session_at_the_server_snapshot_with_the_server_seed() -> void:
	await _enter()
	_backend.respond("raid_start", _start_response())
	var res: Dictionary = await _flow.begin_pvp_raid("defender-1")
	assert_true(res["ok"])
	assert_eq(_session.pvp_raid_id, "raid-1")
	assert_eq(_session.battle_seed_override, 4242)
	assert_eq(_session.pvp_expires_unix, T0 + 600)
	assert_true(_session.has_attack_target())
	assert_eq(_session.attack_grid().structures().size(), 2)
	assert_eq(_session.attack_opponent_id, "")
	assert_true(_flow.has_pvp_raid())
	assert_eq(_backend.calls[_backend.calls.size() - 1]["payload"], {"defender_id": "defender-1"})


func test_a_server_refusal_shows_readable_text_and_aims_nowhere() -> void:
	await _enter()
	_backend.respond("raid_start", {"ok": false, "error": "shielded"})
	var res: Dictionary = await _flow.begin_pvp_raid("defender-1")
	assert_false(res["ok"])
	assert_false(_session.has_attack_target())
	assert_eq(_session.battle_seed_override, -1)
	assert_eq(_messages.size(), 1)
	assert_ne(_messages[0], "")
	assert_false(_flow.has_pvp_raid())


func test_the_deploy_controller_launches_with_the_server_seed() -> void:
	await _enter()
	_backend.respond("raid_start", _start_response())
	await _flow.begin_pvp_raid("defender-1")
	assert_true(_session.army.buy("rhinovirus", _session.wallet))
	var fsm := GameStateMachine.new()
	fsm.session = _session
	add_child_autoqfree(fsm)
	var dc := DeployController.new()
	add_child_autoqfree(dc)
	var gv := GridView.new()
	add_child_autoqfree(gv)
	gv.setup(_session.grid, _session.config, _session.army)
	dc.setup(_session, gv, null, null, fsm)
	dc._on_hud_launch_requested()
	assert_eq(_session.seed, 4242)
	assert_eq(_session.battle_setup.seed, 4242)


func test_submit_sends_only_deployments_and_the_hash_then_follows_the_verdict() -> void:
	await _enter()
	_backend.respond("raid_start", _start_response())
	await _flow.begin_pvp_raid("defender-1")
	assert_true(_session.army.buy("rhinovirus", _session.wallet))
	assert_true(_session.army.deploy("rhinovirus", Vector2i(0, 0)))
	var setup := BattleSetup.create(_session.attack_grid().to_layout(), _session.army.deployments.duplicate(true), 4242)
	var sim := BattleSim.new(_cfg, setup)
	sim.run_to_end()
	_backend.respond("raid_submit", {"ok": true, "error": "", "job_id": "job-9"})
	_backend.respond("job_status", {"ok": true, "status": "done", "result": {"res": {"outcome": "attacker", "atp_looted": 40}}})
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
	var verdicts: Array[Dictionary] = []
	_flow.pvp_result_ready.connect(func(r: Dictionary) -> void: verdicts.append(r))
	var done: Dictionary = await _flow.submit_pvp_raid(sim)
	assert_true(done["ok"])
	assert_eq(verdicts.size(), 1)
	assert_eq(int((((done["result"] as Dictionary)["res"]) as Dictionary)["atp_looted"]), 40)
	var sent: Dictionary = {}
	for c: Dictionary in _backend.calls:
		if c["name"] == "raid_submit":
			sent = c["payload"] as Dictionary
	assert_eq(sent["raid_id"], "raid-1")
	assert_eq(sent["client_final_hash"], sim.state_hash())
	assert_eq(sent["army"], [{"type": "rhinovirus", "cell": [0, 0], "strain": "wild"}])
	var keys: Array = sent.keys()
	keys.sort()
	assert_eq(keys, ["army", "client_final_hash", "raid_id"], "no wallet, populations, memory or results")
	assert_eq(_backend.call_names().back(), "profile_get", "the server profile is reloaded after the verdict")


func test_a_rejected_raid_surfaces_the_error() -> void:
	await _enter()
	_backend.respond("raid_start", _start_response())
	await _flow.begin_pvp_raid("defender-1")
	var sim := BattleSim.new(_cfg, BattleSetup.create(_session.attack_grid().to_layout(), [], 4242))
	_backend.respond("raid_submit", {"ok": true, "error": "", "job_id": "job-9"})
	_backend.respond("job_status", {"ok": true, "status": "failed", "job_error": "invalid_army"})
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
	var done: Dictionary = await _flow.submit_pvp_raid(sim)
	assert_false(done["ok"])
	assert_eq(done["error"], "invalid_army")
	assert_eq(_messages.size(), 1)


func test_cancel_reports_the_army_and_clears_the_target() -> void:
	await _enter()
	_backend.respond("raid_start", _start_response())
	await _flow.begin_pvp_raid("defender-1")
	assert_true(_session.army.buy("rhinovirus", _session.wallet))
	assert_true(_session.army.deploy("rhinovirus", Vector2i(0, 0)))
	_backend.respond("raid_cancel", {"ok": true, "error": ""})
	_backend.respond("profile_get", {"ok": true, "error": "", "profile": _profile(), "job_id": "t"})
	var res: Dictionary = await _flow.cancel_pvp_raid()
	assert_true(res["ok"])
	assert_false(_session.has_attack_target())
	assert_eq(_session.pvp_raid_id, "")
	assert_eq(_session.battle_seed_override, -1)
	var cancel_call: Dictionary = {}
	for c: Dictionary in _backend.calls:
		if c["name"] == "raid_cancel":
			cancel_call = c["payload"] as Dictionary
	assert_eq((cancel_call["army"] as Array).size(), 1)


func test_clearing_the_attack_target_clears_the_pvp_state() -> void:
	var s := Session.new(_cfg)
	s.pvp_raid_id = "x"
	s.battle_seed_override = 5
	s.clear_attack_target()
	assert_eq(s.pvp_raid_id, "")
	assert_eq(s.battle_seed_override, -1)
