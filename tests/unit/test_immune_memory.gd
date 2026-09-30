extends GutTest

var cfg: GameConfig = null


func before_each() -> void:
	cfg = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["immune_memory"] = true
	cfg.feature_flags["bcell_analysis"] = true


func _keys(a: Array) -> Array[String]:
	var out: Array[String] = []
	for k: Variant in a:
		out.append(str(k))
	return out


func _raid(m: ImmuneMemory, seen: Array, analyzed: Array) -> Array[Dictionary]:
	return m.update_after_raid(_keys(seen), _keys(analyzed), cfg)


func test_worked_example() -> void:
	var m := ImmuneMemory.new()
	var rv: String = "rhinovirus/wild"
	var st: String = "staphylococcus/wild"

	var c1: Array[Dictionary] = _raid(m, [rv], [rv])
	assert_eq(c1, [{"strain_key": rv, "from": 0, "to": 1, "reason": "learned"}] as Array[Dictionary])
	assert_eq(m.level_of(rv), 1)
	var c2: Array[Dictionary] = _raid(m, [rv], [rv])
	assert_eq(c2, [{"strain_key": rv, "from": 1, "to": 2, "reason": "learned"}] as Array[Dictionary])
	_raid(m, [rv], [rv])
	assert_eq(m.level_of(rv), 3)
	assert_eq(m.effective_level("rhinovirus/capsid_hardening", cfg), 1)
	assert_eq(m.seed_pct("rhinovirus/capsid_hardening", cfg), 25)
	var c4: Array[Dictionary] = _raid(m, [rv], [rv])
	assert_eq(c4.size(), 0, "cap reached: no change recorded")
	assert_eq(m.level_of(rv), 3)
	assert_eq(m.raids, 4)

	var c5: Array[Dictionary] = _raid(m, [st], [st])
	assert_eq(m.level_of(rv), 3)
	assert_eq(int(m.entries[rv]["absent"]), 1)
	assert_eq(m.level_of(st), 1)
	assert_eq(c5, [{"strain_key": st, "from": 0, "to": 1, "reason": "learned"}] as Array[Dictionary])

	var c6: Array[Dictionary] = _raid(m, [st], [st])
	assert_eq(m.level_of(rv), 2)
	assert_eq(int(m.entries[rv]["absent"]), 0)
	assert_eq(m.level_of(st), 2)
	assert_eq(c6, [
		{"strain_key": rv, "from": 3, "to": 2, "reason": "waned"},
		{"strain_key": st, "from": 1, "to": 2, "reason": "learned"},
	] as Array[Dictionary])


func test_forgotten_when_level_reaches_zero() -> void:
	var m := ImmuneMemory.new()
	_raid(m, ["a/wild"], ["a/wild"])
	_raid(m, ["b/wild"], [])
	var changes: Array[Dictionary] = _raid(m, ["b/wild"], [])
	assert_eq(changes, [{"strain_key": "a/wild", "from": 1, "to": 0, "reason": "forgotten"}] as Array[Dictionary])
	assert_true(m.is_empty())


func test_eviction_lowest_level_then_oldest() -> void:
	var m := ImmuneMemory.new()
	m.raids = 3
	m.entries = {
		"a/wild": {"level": 2, "absent": 0, "since": 1},
		"b/wild": {"level": 1, "absent": 0, "since": 2},
		"c/wild": {"level": 1, "absent": 0, "since": 3},
	}
	var changes: Array[Dictionary] = _raid(m, ["a/wild", "b/wild", "c/wild", "d/wild"], ["d/wild"])
	assert_false(m.entries.has("b/wild"))
	assert_true(m.entries.has("a/wild") and m.entries.has("c/wild") and m.entries.has("d/wild"))
	assert_eq(changes[0], {"strain_key": "b/wild", "from": 1, "to": 0, "reason": "evicted"})
	assert_eq(changes[1], {"strain_key": "d/wild", "from": 0, "to": 1, "reason": "learned"})


func test_drift_same_type_only() -> void:
	var m := ImmuneMemory.new()
	m.entries["rhinovirus/wild"] = {"level": 3, "absent": 0, "since": 1}
	assert_eq(m.effective_level("rhinovirus/capsid_hardening", cfg), 1)
	assert_eq(m.seed_pct("rhinovirus/capsid_hardening", cfg), 25)
	assert_eq(m.effective_level("staphylococcus/wild", cfg), 0)
	assert_eq(m.effective_level("rhinovirus/wild", cfg), 3)


func test_seed_pct_capped_at_100() -> void:
	cfg.memory_seed_pct_per_level = 60
	var m := ImmuneMemory.new()
	m.entries["rhinovirus/wild"] = {"level": 3, "absent": 0, "since": 1}
	assert_eq(m.seed_pct("rhinovirus/wild", cfg), 100)


func test_seed_map_omits_zero() -> void:
	var m := ImmuneMemory.new()
	m.entries["rhinovirus/wild"] = {"level": 2, "absent": 0, "since": 1}
	var map: Dictionary = m.seed_map(_keys(["rhinovirus/wild", "staphylococcus/wild"]), cfg)
	assert_eq(map, {"rhinovirus/wild": 50})


func test_round_trip_and_malformed() -> void:
	var m := ImmuneMemory.new()
	_raid(m, ["rhinovirus/wild"], ["rhinovirus/wild"])
	var back: ImmuneMemory = ImmuneMemory.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), cfg)
	assert_eq(back.to_dict(), m.to_dict())

	var bad: Dictionary = {"raids": 4, "entries": {
		"ok/wild": {"level": 9, "absent": 0, "since": 1},
		"junk/wild": "nope",
		"zero/wild": {"level": 0, "absent": 0, "since": 1},
		"missing/wild": {"level": 1},
		"neg/wild": {"level": 1, "absent": -1, "since": 1},
	}}
	var parsed: ImmuneMemory = ImmuneMemory.from_dict(bad, cfg)
	assert_eq(parsed.entries.size(), 1)
	assert_eq(parsed.level_of("ok/wild"), cfg.memory_max_level)
	assert_eq(parsed.raids, 4)


func test_clamp_to_reduced_slots() -> void:
	var m := ImmuneMemory.new()
	m.entries = {
		"a/wild": {"level": 1, "absent": 0, "since": 1},
		"b/wild": {"level": 3, "absent": 0, "since": 2},
		"c/wild": {"level": 2, "absent": 0, "since": 3},
	}
	cfg.memory_slots = 1
	m.clamp_to(cfg)
	assert_eq(m.entries.keys(), ["b/wild"])
