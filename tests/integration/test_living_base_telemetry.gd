extends GutTest

## Living Base telemetry events (#172): what each call site logs. Reads the SessionLogger autoload's output.

const DIR: String = "user://test_lb_telemetry"
const HOUR: int = 3600

var _saved_consent: bool = true
var _cfg: GameConfig = null
var _store: LivingBaseStore = null


func before_all() -> void:
	_saved_consent = SessionLogger.has_consent()
	SessionLogger.set_consent(true)


func after_all() -> void:
	SessionLogger.set_consent(_saved_consent)


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true
	_cfg.feature_flags["amino_upgrades"] = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_store = LivingBaseStore.new()
	_store.path = DIR + "/living_base.json"


func after_each() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


## Every logged event with this name, oldest first.
func _events(name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for line: String in SessionLogger.all_sessions_text().split("\n"):
		if line.contains("\"event\":\"%s\"" % name):
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				found.append(parsed as Dictionary)
	return found


func _last(name: String) -> Dictionary:
	var all: Array[Dictionary] = _events(name)
	return all.back() if not all.is_empty() else {}


func test_session_start_reports_the_time_away_and_the_raids() -> void:
	var first := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(first)
	first.grid.place("mitochondria", Vector2i(10, 10), first.wallet)
	first.living_flow.sync_profile_from_session()
	first.profile.last_clock_unix = LivingBaseStore.now_unix() - 2 * HOUR
	first.profile.last_ai_raid_unix = LivingBaseStore.now_unix() - 17 * HOUR
	_store.save_profile(first.profile)
	var before: int = _events("lb_session_start").size()
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	assert_eq(_events("lb_session_start").size(), before + 1)
	var ev: Dictionary = _last("lb_session_start")
	assert_between(int(ev["offline_s"]), 2 * HOUR, 2 * HOUR + 60)
	assert_eq(int(ev["atp_generated"]), 120)
	assert_eq(int(ev["raids_resolved"]), 2)
	assert_eq(int(ev["raids_held"]), int(session.living_flow.away_summary["held"]))


func test_a_deferred_session_start_waits_for_the_raids() -> void:
	var first := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(first)
	first.profile.last_ai_raid_unix = LivingBaseStore.now_unix() - 9 * HOUR
	_store.save_profile(first.profile)
	var before: int = _events("lb_session_start").size()
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session, true)
	assert_eq(_events("lb_session_start").size(), before, "not yet")
	flow.resolve_next_raid()
	assert_eq(_events("lb_session_start").size(), before + 1)
	assert_eq(int(_last("lb_session_start")["raids_resolved"]), 1)
	assert_eq(_events("lb_defense_end").size() > 0, true)
	assert_false(bool(_last("lb_defense_end")["live"]))


func test_collect_and_upgrade_events() -> void:
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	session.profile.stored_atp = 30
	session.living_flow.collect()
	assert_eq(int(_last("lb_collect")["amount"]), 30)
	session.wallet.set_amount("amino_acids", 150)
	assert_true(session.living_flow.buy_upgrade("memory_slot"))
	var up: Dictionary = _last("lb_upgrade")
	assert_eq(up["id"], "memory_slot")
	assert_eq(int(up["level"]), 1)
	assert_eq(int(up["cost"]), 150)


func test_raid_end_carries_the_opponent_and_the_army() -> void:
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	var opp_id: String = str(session.profile.opponents[0]["id"])
	session.living_flow.begin_raid(opp_id)
	for i: int in range(5):
		session.army.buy("rhinovirus", session.wallet)
	var dc := DeployController.new()
	add_child_autoqfree(dc)
	var gv := GridView.new()
	add_child_autoqfree(gv)
	gv.setup(session.attack_grid(), session.config, session.army)
	dc.setup(session, gv, null, null, null)
	dc._on_hud_launch_requested()
	var sim := BattleSim.new(_cfg, session.battle_setup)
	sim.finished = true
	sim.outcome = "defender"
	session.living_flow.finish_raid(sim)
	var ev: Dictionary = _last("lb_raid_end")
	assert_eq(ev["opponent_id"], opp_id)
	assert_eq(ev["opponent_tier"], "cold")
	assert_eq(int(ev["opponent_raids"]), 0, "raids on this base before this one")
	assert_eq(ev["outcome"], "defender")
	assert_eq(int(ev["army_atp"]), 50)
	assert_eq(int(ev["army_counts"]["rhinovirus"]), 5)
	assert_gt(int(ev["base_value"]), 0)
	assert_eq(int(ev["atp_looted"]), 0)


func test_live_defense_and_replay_events() -> void:
	var first := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(first)
	first.profile.last_ai_raid_unix = LivingBaseStore.now_unix() - 9 * HOUR
	_store.save_profile(first.profile)
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_true(flow.begin_replay(0))
	assert_eq(int(_last("lb_replay_watched")["raid_index"]), 0)
	flow.end_replay()
	assert_true(flow.begin_live_defense())
	var sim := BattleSim.new(_cfg, session.battle_setup)
	sim.run_to_end()
	flow.finish_live_defense(sim)
	var ev: Dictionary = _last("lb_defense_end")
	assert_true(bool(ev["live"]))
	assert_true(ev.has("outcome") and ev.has("atp_lost") and ev.has("amino_gained"))


func test_session_start_now_carries_the_wall_clock() -> void:
	var text: String = SessionLogger.all_sessions_text()
	assert_true(text.contains("\"unix_s\":"), "session_start has a unix timestamp")
