extends GutTest

const T0: int = 1800000000

var _cfg: GameConfig


func before_each() -> void:
	_cfg = _load({"living_base": true})


func _load(overrides: Dictionary) -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data", overrides)
	assert_true(res.is_ok())
	return res.config


func _job(cfg: GameConfig, type: String, payload: Dictionary) -> Dictionary:
	return {"job_id": "j", "type": type, "created_unix": T0, "config_hash": cfg.content_hash, "payload": payload}


func _new_profile(cfg: GameConfig = null) -> Dictionary:
	var c: GameConfig = cfg if cfg != null else _cfg
	var res: Dictionary = JobRules.process(c, _job(c, "profile_new", {"seed": 42, "now_unix": T0}))
	assert_true(res["ok"])
	return (res["result"] as Dictionary)["profile"] as Dictionary


func _run(cfg: GameConfig, type: String, profile: Dictionary, extra: Dictionary, now: int = T0) -> Dictionary:
	var payload: Dictionary = extra.duplicate(true)
	payload["profile"] = profile
	payload["now_unix"] = now
	return JobRules.process(cfg, _job(cfg, type, payload))


func _profile_of(res: Dictionary) -> Dictionary:
	return (res["result"] as Dictionary)["profile"] as Dictionary


func _entry(type: String, x: int, y: int) -> Dictionary:
	return {"type": type, "origin": [x, y]}


func _layout(entries: Array) -> Array:
	var out: Array = [_entry("nucleus", 18, 18)]
	out.append_array(entries)
	return out


func _mitos(n: int) -> Array:
	var out: Array = []
	for i: int in range(n):
		out.append(_entry("mitochondria", 4 + 4 * i, 4))
	return out


func test_profile_new_creates_a_start_profile_with_server_extras() -> void:
	var p: Dictionary = _new_profile()
	assert_eq(p["format"], LivingBaseProfile.FORMAT)
	assert_eq(int(p["seed"]), 42)
	assert_eq(int(p["last_clock_unix"]), T0)
	assert_eq(int((p["wallet"] as Dictionary)["atp"]), 1000)
	assert_eq(p["config_hash"], _cfg.content_hash)
	assert_eq(int(p["trophies"]), 0)
	assert_eq(p["unlocked_strains"], [])
	assert_eq(int(p["shield_until_unix"]), 0)


func test_profile_new_returns_the_public_snapshot() -> void:
	var res: Dictionary = JobRules.process(_cfg, _job(_cfg, "profile_new", {"seed": 1, "now_unix": T0}))
	var snap: Dictionary = (res["result"] as Dictionary)["snapshot"] as Dictionary
	assert_eq(snap["layout"], (_profile_of(res))["layout"])
	assert_eq(snap["stored_atp"], 0)
	assert_eq(snap["updated_unix"], T0)
	assert_false(snap.has("wallet"))


func test_unknown_profile_is_invalid() -> void:
	var res: Dictionary = _run(_cfg, "collect", {"format": "nope"}, {})
	assert_false(res["ok"])
	assert_eq(res["error"], "invalid_profile")


func test_base_commit_spends_the_diff_and_refunds_sells() -> void:
	var p: Dictionary = _new_profile()
	var bought: Dictionary = _run(_cfg, "base_commit", p, {"layout": _layout(_mitos(2))})
	assert_true(bought["ok"])
	assert_eq(int(((_profile_of(bought))["wallet"] as Dictionary)["atp"]), 700)
	assert_eq(int(((bought["result"] as Dictionary)["spent"] as Dictionary)["atp"]), 300)
	var sold: Dictionary = _run(_cfg, "base_commit", _profile_of(bought), {"layout": _layout(_mitos(1))})
	assert_true(sold["ok"])
	assert_eq(int(((_profile_of(sold))["wallet"] as Dictionary)["atp"]), 850)
	assert_eq(int(((sold["result"] as Dictionary)["refunded"] as Dictionary)["atp"]), 150)
	var same: Dictionary = _run(_cfg, "base_commit", _profile_of(sold), {"layout": _layout(_mitos(1))})
	assert_eq(int(((_profile_of(same))["wallet"] as Dictionary)["atp"]), 850)


func test_base_commit_rejects_what_the_wallet_cannot_afford() -> void:
	var p: Dictionary = _new_profile()
	var res: Dictionary = _run(_cfg, "base_commit", p, {"layout": _layout(_mitos(7))})
	assert_false(res["ok"])
	assert_eq(res["error"], "insufficient_funds")


func test_base_commit_rejects_invalid_layouts() -> void:
	var p: Dictionary = _new_profile()
	var overlap: Dictionary = _run(_cfg, "base_commit", p, {"layout": _layout([_entry("mucous_wall", 5, 5), _entry("mucous_wall", 5, 5)])})
	assert_eq(overlap["error"], "invalid_layout")
	var out_of_bounds: Dictionary = _run(_cfg, "base_commit", p, {"layout": _layout([_entry("mucous_wall", 99, 5)])})
	assert_eq(out_of_bounds["error"], "invalid_layout")
	var unknown: Dictionary = _run(_cfg, "base_commit", p, {"layout": _layout([_entry("bogus", 5, 5)])})
	assert_eq(unknown["error"], "invalid_layout")
	var not_a_list: Dictionary = _run(_cfg, "base_commit", p, {"layout": "x"})
	assert_eq(not_a_list["error"], "invalid_layout")


func test_base_commit_rejects_a_moved_nucleus_unless_the_flag_is_on() -> void:
	var p: Dictionary = _new_profile()
	var moved: Array = [_entry("nucleus", 10, 10)]
	assert_eq(_run(_cfg, "base_commit", p, {"layout": moved})["error"], "invalid_layout")
	var cfg_on: GameConfig = _load({"living_base": true, "move_nucleus": true})
	var p_on: Dictionary = _new_profile(cfg_on)
	assert_true(_run(cfg_on, "base_commit", p_on, {"layout": moved})["ok"])


func test_collect_uses_the_job_clock_not_the_system_clock() -> void:
	var p: Dictionary = _new_profile()
	var built: Dictionary = _run(_cfg, "base_commit", p, {"layout": _layout(_mitos(1))})
	var base: Dictionary = _profile_of(built)
	var later: Dictionary = _run(_cfg, "collect", base, {}, T0 + 3600)
	assert_true(later["ok"])
	var collected: int = int((later["result"] as Dictionary)["collected"])
	assert_gt(collected, 0)
	var wallet_atp: int = int(((_profile_of(later))["wallet"] as Dictionary)["atp"])
	assert_eq(wallet_atp, 850 + collected)
	assert_eq(int((_profile_of(later))["stored_atp"]), 0)
	assert_eq(int((_profile_of(later))["last_clock_unix"]), T0 + 3600)
	var again: Dictionary = _run(_cfg, "collect", base, {}, T0 + 3600)
	assert_eq(int((again["result"] as Dictionary)["collected"]), collected, "same job, same answer")


func test_profile_tick_only_advances_the_clock() -> void:
	var p: Dictionary = _new_profile()
	var built: Dictionary = _run(_cfg, "base_commit", p, {"layout": _layout(_mitos(1))})
	var tick: Dictionary = _run(_cfg, "profile_tick", _profile_of(built), {}, T0 + 3600)
	assert_true(tick["ok"])
	assert_gt(int((_profile_of(tick))["stored_atp"]), 0)
	assert_eq((_profile_of(tick))["wallet"], (_profile_of(built))["wallet"])


func test_server_extras_survive_every_job() -> void:
	var p: Dictionary = _new_profile()
	p["trophies"] = 123
	p["shield_until_unix"] = 999
	var res: Dictionary = _run(_cfg, "collect", p, {})
	assert_eq(int((_profile_of(res))["trophies"]), 123)
	assert_eq(int((_profile_of(res))["shield_until_unix"]), 999)


func test_upgrade_buy() -> void:
	var cfg: GameConfig = _load({"living_base": true, "amino_upgrades": true})
	var p: Dictionary = _new_profile(cfg)
	(p["wallet"] as Dictionary)["amino_acids"] = 160
	var bought: Dictionary = _run(cfg, "upgrade_buy", p, {"id": "memory_slot"})
	assert_true(bought["ok"])
	assert_eq(int(((_profile_of(bought))["upgrades"] as Dictionary)["memory_slot"]), 1)
	assert_eq(int(((_profile_of(bought))["wallet"] as Dictionary)["amino_acids"]), 10)
	var poor: Dictionary = _run(cfg, "upgrade_buy", _profile_of(bought), {"id": "memory_slot"})
	assert_eq(poor["error"], "insufficient_funds")
	var rich: Dictionary = _profile_of(bought)
	(rich["wallet"] as Dictionary)["amino_acids"] = 100000
	var second: Dictionary = _run(cfg, "upgrade_buy", rich, {"id": "memory_slot"})
	assert_true(second["ok"])
	var maxed: Dictionary = _run(cfg, "upgrade_buy", _profile_of(second), {"id": "memory_slot"})
	assert_eq(maxed["error"], "maxed")
	assert_eq(_run(cfg, "upgrade_buy", rich, {"id": "nope"})["error"], "unknown_upgrade")


func test_upgrade_buy_needs_its_flag() -> void:
	var p: Dictionary = _new_profile()
	(p["wallet"] as Dictionary)["amino_acids"] = 1000
	assert_eq(_run(_cfg, "upgrade_buy", p, {"id": "memory_slot"})["error"], "unknown_upgrade")


func test_receptor_upgrade_widens_the_pools() -> void:
	var cfg: GameConfig = _load({"living_base": true, "amino_upgrades": true, "coevolution": true})
	var p: Dictionary = _new_profile(cfg)
	(p["wallet"] as Dictionary)["amino_acids"] = 300
	var res: Dictionary = _run(cfg, "upgrade_buy", p, {"id": "receptor_slot"})
	assert_true(res["ok"])
	var pools: Dictionary = (_profile_of(res))["populations"] as Dictionary
	assert_false(pools.is_empty(), "tower pools are created and widened")
	for type_id: Variant in pools.keys():
		assert_true(cfg.structures.has(str(type_id)))


func _local_profile(layout: Array, extras: Dictionary = {}) -> Dictionary:
	var local: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 7, T0)
	var grid := GridModel.new(_cfg)
	assert_eq(grid.load_layout(layout, LivingBaseProfile.unlimited_wallet()), GridModel.PlaceError.OK)
	local.layout = grid.to_layout()
	var d: Dictionary = local.to_dict()
	for k: Variant in extras.keys():
		d[k] = extras[k]
	return d


func test_profile_import_takes_layout_and_memory_only() -> void:
	var p: Dictionary = _new_profile()
	var local: Dictionary = _local_profile(_layout(_mitos(2)), {
		"wallet": {"atp": 999999, "amino_acids": 999999, "dna": 999999},
		"populations": {"macrophage": {"junk": true}},
		"upgrades": {"memory_slot": 2},
		"raid_counter": 50,
		"opponents": [{"id": "x"}],
	})
	var res: Dictionary = _run(_cfg, "profile_import", p, {"local_profile": local})
	assert_true(res["ok"])
	var out: Dictionary = _profile_of(res)
	assert_eq(int((out["wallet"] as Dictionary)["atp"]), 700, "start wallet minus the layout cost")
	assert_eq(int((out["wallet"] as Dictionary)["amino_acids"]), 0)
	assert_eq(int((out["wallet"] as Dictionary)["dna"]), 0)
	assert_eq(out["populations"], {})
	assert_eq(out["upgrades"], {})
	assert_eq(int(out["raid_counter"]), 0)
	assert_eq(out["opponents"], [])
	assert_eq((out["layout"] as Array).size(), 3, "nucleus plus two mitochondria")


func test_profile_import_rejects_a_profile_that_is_not_fresh() -> void:
	var p: Dictionary = _new_profile()
	p["raid_counter"] = 1
	var res: Dictionary = _run(_cfg, "profile_import", p, {"local_profile": _local_profile(_layout([]))})
	assert_eq(res["error"], "profile_not_fresh")
	var q: Dictionary = _new_profile()
	q["ai_raid_counter"] = 2
	assert_eq(_run(_cfg, "profile_import", q, {"local_profile": _local_profile(_layout([]))})["error"], "profile_not_fresh")


func test_profile_import_rejects_a_layout_that_is_too_expensive() -> void:
	var p: Dictionary = _new_profile()
	var res: Dictionary = _run(_cfg, "profile_import", p, {"local_profile": _local_profile(_layout(_mitos(7)))})
	assert_eq(res["error"], "layout_too_expensive")


func test_profile_import_rejects_garbage() -> void:
	var p: Dictionary = _new_profile()
	assert_eq(_run(_cfg, "profile_import", p, {"local_profile": {"format": "x"}})["error"], "invalid_profile")
	assert_eq(_run(_cfg, "profile_import", p, {})["error"], "invalid_profile")
