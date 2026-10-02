extends GutTest

var _cfg: GameConfig = null

func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	_cfg = res.config
	_cfg.feature_flags["living_base"] = true

func _profile_with_two_mitochondria() -> LivingBaseProfile:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 42, 1000)
	p.layout.append({"type": "mitochondria", "origin": Vector2i(2, 2)})
	p.layout.append({"type": "mitochondria", "origin": Vector2i(10, 2)})
	return p

func test_create_new() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 42, 1000)
	assert_eq(p.seed, 42)
	assert_eq(p.layout.size(), 1)
	assert_eq(p.layout[0]["type"], "nucleus")
	assert_eq(p.wallet, {"atp": 1000, "amino_acids": 0, "dna": 0})
	assert_eq(p.stored_atp, 0)
	assert_eq(p.last_clock_unix, 1000)

func test_advance_clock_generates_and_ignores_clock_going_back() -> void:
	var p: LivingBaseProfile = _profile_with_two_mitochondria()
	assert_eq(p.advance_clock(_cfg, 1000 + 1800), 60)
	assert_eq(p.stored_atp, 60)
	assert_eq(p.advance_clock(_cfg, 2800 - 500), 0)
	assert_eq(p.stored_atp, 60)
	assert_eq(p.last_clock_unix, 2300)

func test_advance_clock_caps_offline_time() -> void:
	var p: LivingBaseProfile = _profile_with_two_mitochondria()
	p.advance_clock(_cfg, 1000 + 365 * 86400)
	# 24 h at 120/h would be 2880, but storage is 600.
	assert_eq(p.stored_atp, 600)

func test_collect() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 1, 0)
	p.stored_atp = 75
	assert_eq(p.collect(), 75)
	assert_eq(p.stored_atp, 0)
	assert_eq(p.wallet["atp"], 1075)
	assert_eq(p.collect(), 0)

func test_round_trip_every_field() -> void:
	var p: LivingBaseProfile = _profile_with_two_mitochondria()
	p.wallet["amino_acids"] = 12
	p.stored_atp = 33
	p.atp_carry = 1234
	p.last_clock_unix = 5555
	var mem := ImmuneMemory.new()
	mem.raids = 3
	mem.entries = {"rhinovirus:a": {"level": 1, "absent": 0, "since": 2}}
	p.memory = mem.to_dict()
	p.populations = {"b_cell": BreedPool.wild_pool("b_cell", _cfg).to_dict()}
	p.upgrades = {"memory_slot": 2}
	p.opponents = [{"id": 1}]
	p.ai_army_populations = {"rhinovirus": BreedPool.wild_pool("rhinovirus", _cfg).to_dict()}
	p.raid_counter = 4
	p.ai_raid_counter = 2
	p.last_ai_raid_unix = 4444
	p.push_defense_log({"t": 1}, _cfg)
	var json: Variant = JSON.parse_string(JSON.stringify(p.to_dict()))
	var res: Dictionary = LivingBaseProfile.from_dict(json, _cfg)
	assert_true(res["ok"], str(res["error"]))
	var q: LivingBaseProfile = res["profile"]
	assert_eq(JSON.stringify(q.to_dict()), JSON.stringify(p.to_dict()))
	assert_eq(q.seed, 42)
	assert_eq(q.layout.size(), 3)
	assert_eq(q.stored_atp, 33)
	assert_eq(q.atp_carry, 1234)
	assert_eq(q.upgrades, {"memory_slot": 2})
	assert_eq(q.raid_counter, 4)
	assert_eq(q.ai_raid_counter, 2)
	assert_eq(q.last_ai_raid_unix, 4444)
	assert_eq(q.defense_log.size(), 1)
	assert_eq((res["notices"] as Array).size(), 0)

func test_unknown_structure_dropped_with_notice() -> void:
	var d: Dictionary = LivingBaseProfile.create_new(_cfg, 1, 0).to_dict()
	(d["layout"] as Array).append({"type": "laser_turret", "origin": [3, 3]})
	var res: Dictionary = LivingBaseProfile.from_dict(d, _cfg)
	assert_true(res["ok"])
	assert_eq((res["profile"] as LivingBaseProfile).layout.size(), 1)
	assert_true((res["notices"] as Array).has("1 structures removed (no longer in the game)"))

func test_disabled_structure_dropped_with_notice() -> void:
	var p: LivingBaseProfile = _profile_with_two_mitochondria()
	var d: Dictionary = p.to_dict()
	_cfg.feature_flags["living_base"] = false
	var res: Dictionary = LivingBaseProfile.from_dict(d, _cfg)
	assert_true(res["ok"])
	assert_eq((res["profile"] as LivingBaseProfile).layout.size(), 1)
	assert_true((res["notices"] as Array).has("2 structures removed (no longer in the game)"))

func test_wrong_format_and_future_version_fail() -> void:
	var d: Dictionary = LivingBaseProfile.create_new(_cfg, 1, 0).to_dict()
	d["format"] = "something.else"
	var r1: Dictionary = LivingBaseProfile.from_dict(d, _cfg)
	assert_false(r1["ok"])
	assert_true(str(r1["error"]).contains("Not a Living Base save"))
	d["format"] = LivingBaseProfile.FORMAT
	d["version"] = 2
	var r2: Dictionary = LivingBaseProfile.from_dict(d, _cfg)
	assert_false(r2["ok"])
	assert_true(str(r2["error"]).contains("newer than this game supports"))

func test_wallet_is_clamped_and_cleaned() -> void:
	var d: Dictionary = LivingBaseProfile.create_new(_cfg, 1, 0).to_dict()
	d["wallet"] = {"atp": -5, "gold": 9, "dna": 3}
	var res: Dictionary = LivingBaseProfile.from_dict(d, _cfg)
	var q: LivingBaseProfile = res["profile"]
	assert_eq(q.wallet, {"atp": 0, "dna": 3})
	assert_eq((res["notices"] as Array).size(), 2)

func test_push_defense_log_caps_newest_first() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 1, 0)
	for i: int in range(_cfg.lb_defense_log_size + 5):
		p.push_defense_log({"n": i}, _cfg)
	assert_eq(p.defense_log.size(), _cfg.lb_defense_log_size)
	assert_eq(p.defense_log[0]["n"], _cfg.lb_defense_log_size + 4)

func test_config_block_loaded() -> void:
	assert_eq(_cfg.lb_start_wallet["atp"], 1000)
	assert_eq(_cfg.lb_max_offline_s, 24 * 3600)
	assert_eq(_cfg.lb_defense_log_size, 20)


# --- AI opponents (#161) ---

func test_ensure_opponents_fills_the_slots_deterministically() -> void:
	var a: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 42, 0)
	var b: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 42, 0)
	a.ensure_opponents(_cfg)
	b.ensure_opponents(_cfg)
	assert_eq(a.opponents.size(), 3)
	assert_eq(a.opponents, b.opponents)
	assert_eq(a.opponent_counter, 3)
	assert_eq(str(a.opponents[0]["id"]), "cold-0")
	assert_eq(str(a.opponents[2]["tier"]), "pneumonia")
	assert_eq(int(a.opponents[1]["seed"]), 42 + 7919)
	assert_eq(int(a.opponents[2]["stored_atp"]), 500)
	assert_eq(int(a.opponents[0]["raids"]), 0)
	a.ensure_opponents(_cfg)
	assert_eq(a.opponents.size(), 3, "nothing is added when the slots are full")


func test_replace_opponent_changes_the_layout_and_keeps_the_tier() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 42, 0)
	p.ensure_opponents(_cfg)
	var old: Dictionary = (p.opponents[1] as Dictionary).duplicate(true)
	assert_true(p.replace_opponent("flu-1", _cfg))
	assert_eq(str(p.opponents[1]["tier"]), "flu")
	assert_eq(str(p.opponents[1]["id"]), "flu-3")
	assert_ne(p.opponents[1]["layout"], old["layout"])
	assert_eq(p.opponents.size(), 3)
	assert_false(p.replace_opponent("nope", _cfg))


func test_opponents_survive_a_json_round_trip() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 42, 0)
	p.ensure_opponents(_cfg)
	p.opponents[0]["raids"] = 2
	p.memory = ImmuneMemory.new().to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(p.to_dict()))
	var res: Dictionary = LivingBaseProfile.from_dict(json, _cfg)
	var q: LivingBaseProfile = res["profile"]
	assert_eq(q.opponent_counter, 3)
	assert_eq(q.opponents.size(), 3)
	assert_eq(int(q.opponents[0]["raids"]), 2)
	assert_eq(JSON.stringify(q.to_dict()), JSON.stringify(p.to_dict()))
	var grid := GridModel.new(_cfg)
	assert_eq(grid.load_layout(q.opponents[1]["layout"], LivingBaseProfile.unlimited_wallet()), GridModel.PlaceError.OK)

func test_overlapping_structures_drop_only_the_offender() -> void:
	var d: Dictionary = LivingBaseProfile.create_new(_cfg, 1, 0).to_dict()
	(d["layout"] as Array).append({"type": "mucous_wall", "origin": [3, 3]})
	(d["layout"] as Array).append({"type": "mucous_wall", "origin": [3, 3]})
	(d["layout"] as Array).append({"type": "mucous_wall", "origin": [8, 8]})
	var res: Dictionary = LivingBaseProfile.from_dict(d, _cfg)
	assert_true(res["ok"])
	assert_eq((res["profile"] as LivingBaseProfile).layout.size(), 3)
	assert_true((res["notices"] as Array).has("1 structures removed (no longer fit the base)"))
