extends GutTest

## Amino Acid base upgrades (#168): breadth only.

const DIR: String = "user://test_lb_upgrades"

var _cfg: GameConfig = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true
	_cfg.feature_flags["amino_upgrades"] = true
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func test_config_block_loaded_and_there_is_no_flat_stat_upgrade() -> void:
	assert_eq(_cfg.upgrade_defs.keys(), ["memory_slot", "analysis_speed", "memory_retention", "receptor_slot"])
	assert_eq(_cfg.upgrade_defs["analysis_speed"]["per_level"], 90)
	assert_eq(_cfg.upgrade_defs["memory_slot"]["costs"], [{"amino_acids": 150}, {"amino_acids": 400}])
	for id: Variant in _cfg.upgrade_defs.keys():
		assert_false(str(id).contains("hp") or str(id).contains("damage"))
	assert_false(GameConfig.load_from_dir("res://data").config.flag("amino_upgrades"))


func test_costs_by_level_and_maxed_returns_empty() -> void:
	var ups: Dictionary = {}
	assert_eq(BaseUpgrades.next_cost(_cfg, ups, "memory_slot"), {"amino_acids": 150})
	ups["memory_slot"] = 1
	assert_eq(BaseUpgrades.next_cost(_cfg, ups, "memory_slot"), {"amino_acids": 400})
	ups["memory_slot"] = 2
	assert_eq(BaseUpgrades.next_cost(_cfg, ups, "memory_slot"), {})
	assert_eq(BaseUpgrades.next_cost(_cfg, {}, "unknown"), {})
	assert_eq(BaseUpgrades.max_level(_cfg, "analysis_speed"), 3)
	assert_eq(BaseUpgrades.level({"memory_slot": -3}, "memory_slot"), 0)


func test_buy_is_all_or_nothing_on_the_wallet() -> void:
	var wallet := Wallet.new({"amino_acids": 149, "atp": 50})
	var ups: Dictionary = {}
	assert_false(BaseUpgrades.buy(_cfg, ups, "memory_slot", wallet))
	assert_eq(wallet.get_amount("amino_acids"), 149)
	assert_true(ups.is_empty())
	wallet.refund({"amino_acids": 1})
	assert_true(BaseUpgrades.buy(_cfg, ups, "memory_slot", wallet))
	assert_eq(wallet.get_amount("amino_acids"), 0)
	assert_eq(ups, {"memory_slot": 1})
	assert_eq(wallet.get_amount("atp"), 50, "other currencies are untouched")
	wallet.refund({"amino_acids": 1000})
	assert_true(BaseUpgrades.buy(_cfg, ups, "memory_slot", wallet))
	assert_false(BaseUpgrades.buy(_cfg, ups, "memory_slot", wallet), "maxed")
	assert_eq(ups["memory_slot"], 2)


func test_the_flag_gates_buying_and_effects() -> void:
	var off: GameConfig = GameConfig.load_from_dir("res://data").config
	var ups: Dictionary = {"memory_slot": 2, "analysis_speed": 3, "memory_retention": 1}
	assert_false(BaseUpgrades.buy(off, {}, "memory_slot", Wallet.new({"amino_acids": 999})))
	assert_eq(BaseUpgrades.memory_slots(off, ups), off.memory_slots)
	assert_eq(BaseUpgrades.memory_decay_raids(off, ups), off.memory_decay_raids)
	assert_eq(BaseUpgrades.analysis_threshold_pct(off, ups), 100)


func test_effective_numbers() -> void:
	assert_eq(BaseUpgrades.memory_slots(_cfg, {}), _cfg.memory_slots)
	assert_eq(BaseUpgrades.memory_slots(_cfg, {"memory_slot": 2}), _cfg.memory_slots + 2)
	assert_eq(BaseUpgrades.memory_decay_raids(_cfg, {"memory_retention": 1}), _cfg.memory_decay_raids + 1)
	assert_eq(BaseUpgrades.memory_slots(_cfg, {"memory_slot": 9}), _cfg.memory_slots + 2, "capped at the max level")


func test_analysis_threshold_pct_is_100_90_81_72() -> void:
	assert_eq(BaseUpgrades.analysis_threshold_pct(_cfg, {}), 100)
	assert_eq(BaseUpgrades.analysis_threshold_pct(_cfg, {"analysis_speed": 1}), 90)
	assert_eq(BaseUpgrades.analysis_threshold_pct(_cfg, {"analysis_speed": 2}), 81)
	assert_eq(BaseUpgrades.analysis_threshold_pct(_cfg, {"analysis_speed": 3}), 72)


# --- the effects reach the rules ---

func test_a_slot_override_keeps_more_strains() -> void:
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	var keys: Array[String] = ["a/wild", "b/wild", "c/wild", "d/wild"]
	var plain := ImmuneMemory.new()
	plain.update_after_raid(keys, keys, _cfg)
	assert_eq(plain.entries.size(), _cfg.memory_slots, "the config's 3 slots evict the rest")
	var bigger := ImmuneMemory.new()
	bigger.update_after_raid(keys, keys, _cfg, 4)
	assert_eq(bigger.entries.size(), 4)
	var from_dict: ImmuneMemory = ImmuneMemory.from_dict(bigger.to_dict(), _cfg, 4)
	assert_eq(from_dict.entries.size(), 4)
	assert_eq(ImmuneMemory.from_dict(bigger.to_dict(), _cfg).entries.size(), _cfg.memory_slots)


func test_a_decay_override_keeps_memory_longer() -> void:
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	var plain := ImmuneMemory.new()
	var longer := ImmuneMemory.new()
	var rv: Array[String] = ["rhinovirus/wild"]
	var none: Array[String] = []
	plain.update_after_raid(rv, rv, _cfg)
	longer.update_after_raid(rv, rv, _cfg)
	for i: int in range(_cfg.memory_decay_raids):
		plain.update_after_raid(none, none, _cfg)
		longer.update_after_raid(none, none, _cfg, -1, _cfg.memory_decay_raids + 1)
	assert_eq(plain.level_of("rhinovirus/wild"), 0, "forgotten after decay_raids absent raids")
	assert_eq(longer.level_of("rhinovirus/wild"), 1)


func _analysis_sim(mods: Dictionary) -> BattleSim:
	_cfg.feature_flags["bcell_analysis"] = true
	var structs: Array = [
		{"type": "b_cell", "origin": Vector2i(10, 3)},
		{"type": "nucleus", "origin": Vector2i(18, 18)},
	]
	var units: Array = [{"type": "staphylococcus", "cell": Vector2i(10, 6)}]
	var sim := BattleSim.new(_cfg, BattleSetup.create(structs, units, 1, {}, {}, mods))
	for p: PathogenState in sim.pathogens:
		sim.status.add(StatusEffects.key_pathogen(p.id), StatusEffects.Kind.ROOTED, 1, 100000, "root")
		p.hp = 100000
		p.max_hp = 100000
	return sim


func _ticks_to_analyze(sim: BattleSim) -> int:
	for i: int in range(1000):
		sim.step()
		if not sim.structure(1).analyzed.is_empty():
			return i + 1
	return -1


func test_defender_mods_shorten_the_analysis() -> void:
	var base: int = _ticks_to_analyze(_analysis_sim({}))
	var half: int = _ticks_to_analyze(_analysis_sim({"analysis_threshold_pct": 50}))
	assert_gt(base, 0)
	assert_lte(absi(half * 2 - base), 2, "half the ticks (%d vs %d)" % [half, base])


func test_empty_mods_keep_todays_hash() -> void:
	var a: BattleSim = _analysis_sim({})
	var b: BattleSim = _analysis_sim({})
	for i: int in range(40):
		a.step()
		b.step()
	assert_eq(a.state_hash(), b.state_hash())
	assert_eq(a.structure(1).analysis_threshold_ticks, _cfg.structures["b_cell"].analysis_threshold_ticks)


func test_defender_mods_round_trip_and_are_absent_when_empty() -> void:
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(18, 18)}]
	var with_mods: BattleSetup = BattleSetup.create(structs, [], 1, {}, {}, {"analysis_threshold_pct": 81})
	assert_eq(with_mods.to_dict()["defender_mods"], {"analysis_threshold_pct": 81})
	assert_eq(BattleSetup.from_dict(with_mods.to_dict()).defender_mods, {"analysis_threshold_pct": 81})
	assert_eq(with_mods.duplicate_setup().defender_mods, {"analysis_threshold_pct": 81})
	var plain: BattleSetup = BattleSetup.create(structs, [], 1)
	assert_false(plain.to_dict().has("defender_mods"))
	# The replay carries them.
	var sim := BattleSim.new(_cfg, with_mods)
	var text: String = SnapshotIO.to_json(SnapshotIO.battle_to_dict(_cfg, with_mods, sim))
	var parsed: Dictionary = SnapshotIO.parse_battle(text, _cfg)
	assert_true(parsed["ok"], str(parsed))
	assert_eq((parsed["setup"] as BattleSetup).defender_mods, {"analysis_threshold_pct": 81})
	var plain_text: String = SnapshotIO.to_json(SnapshotIO.battle_to_dict(_cfg, plain, BattleSim.new(_cfg, plain)))
	assert_false(plain_text.contains("defender_mods"))


func test_invalid_defender_mods_fail_validation() -> void:
	var structs: Array = [{"type": "nucleus", "origin": Vector2i(18, 18)}]
	assert_eq(BattleSetup.create(structs, [], 1, {}, {}, {"analysis_threshold_pct": 0}).validate(_cfg).size(), 1)
	assert_eq(BattleSetup.create(structs, [], 1, {}, {}, {"hp_pct": 150}).validate(_cfg).size(), 1)
	assert_eq(BattleSetup.create(structs, [], 1, {}, {}, {"analysis_threshold_pct": 72}).validate(_cfg).size(), 0)


func test_the_players_defense_uses_upgrades_and_ai_bases_do_not() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 11, 0)
	p.upgrades = {"analysis_speed": 2}
	var setup: BattleSetup = DefenseRunner.build_setup(_cfg, p, 0)
	assert_eq(setup.defender_mods, {"analysis_threshold_pct": 81})
	p.upgrades = {}
	assert_true(DefenseRunner.build_setup(_cfg, p, 0).defender_mods.is_empty())
	var off: GameConfig = GameConfig.load_from_dir("res://data").config
	off.feature_flags["living_base"] = true
	p.upgrades = {"analysis_speed": 2}
	assert_true(DefenseRunner.build_setup(off, p, 0).defender_mods.is_empty(), "flag off")


func test_a_saved_profile_keeps_the_extra_memory_slots() -> void:
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 1, 0)
	p.upgrades = {"memory_slot": 1}
	var mem := ImmuneMemory.new()
	var keys: Array[String] = ["a/wild", "b/wild", "c/wild", "d/wild"]
	mem.update_after_raid(keys, keys, _cfg, 4)
	p.memory = mem.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(p.to_dict()))
	var q: LivingBaseProfile = LivingBaseProfile.from_dict(json, _cfg)["profile"]
	assert_eq((q.memory["entries"] as Dictionary).size(), 4)
	assert_eq(q.upgrades, {"memory_slot": 1})


func test_the_upgrades_screen_rows_buy_and_refresh() -> void:
	var store := LivingBaseStore.new()
	store.path = DIR + "/living_base.json"
	var session := Session.new(_cfg)
	LivingBaseFlow.new(store).enter(session)
	session.wallet.set_amount("amino_acids", 160)
	var screen := UpgradesScreen.new()
	add_child_autofree(screen)
	screen.setup(session, null)
	assert_eq(screen.rows.size(), 4)
	var buy: PillButton = screen.rows["memory_slot"]["buy"]
	assert_gte(buy.custom_minimum_size.x, 48.0)
	assert_gte(buy.custom_minimum_size.y, 48.0)
	assert_false(buy.disabled)
	assert_eq(buy.text, "Buy · 150 AA")
	assert_true(screen.rows["analysis_speed"]["buy"].disabled == false)
	assert_true((screen.rows["memory_retention"]["buy"] as PillButton).disabled, "200 AA is out of reach")
	assert_eq((screen.rows["memory_slot"]["effect"] as Label).text, "Remembers 3 strains")
	assert_eq((screen.rows["memory_slot"]["level"] as Label).text, "Level 0 / 2")
	watch_signals(screen)
	buy.pressed.emit()
	assert_signal_emitted_with_parameters(screen, "upgrade_bought", ["memory_slot"])
	assert_eq(session.wallet.get_amount("amino_acids"), 10)
	assert_eq(session.profile.upgrades["memory_slot"], 1)
	assert_eq((screen.rows["memory_slot"]["effect"] as Label).text, "Remembers 4 strains")
	assert_eq(screen.amino_label.text, "Amino Acids: 10")
	assert_true((screen.rows["analysis_speed"]["buy"] as PillButton).disabled, "now too poor for 100 AA")
	# Saved: a fresh session sees the level.
	var again := Session.new(_cfg)
	LivingBaseFlow.new(store).enter(again)
	assert_eq(again.profile.upgrades["memory_slot"], 1)
	assert_eq(again.wallet.get_amount("amino_acids"), 10)
	session.wallet.set_amount("amino_acids", 1000)
	screen.refresh()
	assert_eq(screen.rows["memory_slot"]["buy"].text, "Buy · 400 AA")
	screen.rows["memory_slot"]["buy"].pressed.emit()
	assert_eq(screen.rows["memory_slot"]["buy"].text, "Maxed")
	assert_true(screen.rows["memory_slot"]["buy"].disabled)


func test_effect_texts() -> void:
	assert_eq(UpgradesScreen.effect_text(_cfg, {"analysis_speed": 2}, "analysis_speed"), "Analysis 19% faster")
	assert_eq(UpgradesScreen.effect_text(_cfg, {}, "analysis_speed"), "Analysis at normal speed")
	assert_eq(UpgradesScreen.effect_text(_cfg, {"memory_retention": 1}, "memory_retention"), "Memory lasts 3 raids")


func test_the_hud_shows_upgrades_only_with_the_flag_and_opens_the_screen() -> void:
	var store := LivingBaseStore.new()
	store.path = DIR + "/living_base.json"
	var session := Session.new(_cfg)
	LivingBaseFlow.new(store).enter(session)
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	fsm.screen_stack = stack
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	phase.setup(session, fsm)
	add_child_autofree(phase)
	assert_true(phase.hud_build.btn_upgrades.visible)
	assert_gte(phase.hud_build.btn_upgrades.custom_minimum_size.y, 48.0)
	phase.hud_build.btn_upgrades.pressed.emit()
	assert_eq(stack.top_id(), "upgrades")
	assert_true(stack.top_screen() is UpgradesScreen)
	_cfg.feature_flags["amino_upgrades"] = false
	phase.hud_build._update_living_base()
	assert_false(phase.hud_build.btn_upgrades.visible)


func test_the_memory_panel_shows_the_slot_count_after_a_slot_upgrade() -> void:
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	var store := LivingBaseStore.new()
	store.path = DIR + "/living_base.json"
	var session := Session.new(_cfg)
	LivingBaseFlow.new(store).enter(session)
	var panel := MemoryPanel.new()
	add_child_autofree(panel)
	panel.setup(session)
	assert_false(panel.slots_label.visible)
	session.profile.upgrades["memory_slot"] = 1
	session.memory.entries["rhinovirus/wild"] = {"level": 1, "absent": 0, "since": 1}
	panel.refresh()
	assert_true(panel.slots_label.visible)
	assert_eq(panel.slots_label.text, "1 / 4 slots")


func _load_rules(mutate: Callable) -> ConfigLoadResult:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_rules.json"))
	mutate.call(rules)
	return GameConfig.load_from_strings(JSON.stringify(rules),
		FileAccess.get_file_as_string("res://data/structures.json"),
		FileAccess.get_file_as_string("res://data/pathogens.json"))


func _has_error(res: ConfigLoadResult, fragment: String) -> bool:
	for e: String in res.errors:
		if e.find(fragment) != -1:
			return true
	return false


func test_validation_errors() -> void:
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["hp_boost"] = {}), "game_rules.json: upgrades.hp_boost: unknown key (got hp_boost)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"]["per_level"] = 0), "game_rules.json: upgrades.memory_slot.per_level: must be > 0 (got 0)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"]["costs"] = []), "game_rules.json: upgrades.memory_slot.costs: must be a non-empty array"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"]["costs"][0] = {"gold": 5}), "game_rules.json: upgrades.memory_slot.costs[0].gold: unknown currency (got gold)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"]["costs"][0] = {"amino_acids": -1}), "costs[0].amino_acids: must be >= 0 (got -1)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"]["display_name"] = ""), "game_rules.json: upgrades.memory_slot.display_name: must be a non-empty string"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"]["bogus"] = 1), "game_rules.json: upgrades.memory_slot.bogus: unknown key (got bogus)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"].erase("costs")), "game_rules.json: upgrades.memory_slot.costs: missing required field (got null)"))
	assert_true(_has_error(_load_rules(func(d: Dictionary) -> void: d["upgrades"]["memory_slot"]["per_level"] = 1.5), "upgrades.memory_slot.per_level: must be an integer"))


func test_block_required_only_when_the_flag_is_on() -> void:
	assert_true(_load_rules(func(d: Dictionary) -> void: d.erase("upgrades")).is_ok())
	var r: ConfigLoadResult = _load_rules(func(d: Dictionary) -> void:
		d.erase("upgrades")
		d["feature_flags"]["amino_upgrades"] = true)
	assert_true(_has_error(r, "game_rules.json: upgrades: required when feature_flags.amino_upgrades is true"))


func test_buying_receptor_slot_widens_the_player_tower_pools_only() -> void:
	_cfg.feature_flags["coevolution"] = true
	var store := LivingBaseStore.new()
	store.path = DIR + "/living_base.json"
	var session := Session.new(_cfg)
	LivingBaseFlow.new(store).enter(session)
	session.wallet.set_amount("amino_acids", 300)
	var rhino_before: Dictionary = session.population("rhinovirus").to_dict()
	assert_true(session.living_flow.buy_upgrade("receptor_slot"))
	assert_eq(session.wallet.get_amount("amino_acids"), 0)
	for type_id: String in ["macrophage", "b_cell"]:
		var pool: BreedPool = session.populations[type_id] as BreedPool
		assert_eq(pool.receptor_slots, _cfg.coevo_receptor_slots + 1)
		assert_eq(pool.genomes[0].receptors.size(), _cfg.coevo_receptor_slots + 1)
	assert_eq(session.population("rhinovirus").to_dict(), rhino_before, "the pathogen pool is untouched")
	assert_false(session.populations.has("rhinovirus"))
	# Saved and reloaded.
	var again := Session.new(_cfg)
	LivingBaseFlow.new(store).enter(again)
	assert_eq((again.populations["b_cell"] as BreedPool).receptor_slots, _cfg.coevo_receptor_slots + 1)
	assert_eq(again.profile.upgrades["receptor_slot"], 1)
	assert_false(session.living_flow.buy_upgrade("receptor_slot"), "one level only")


func test_widen_receptor_pools_keeps_existing_alleles() -> void:
	_cfg.feature_flags["coevolution"] = true
	var pools: Dictionary = {}
	var existing: BreedPool = BreedPool.wild_pool("macrophage", _cfg)
	existing.genomes[0] = Genome.from_slots([], ["binder_a", "hook_b"], _cfg)
	pools["macrophage"] = existing
	BaseUpgrades.widen_receptor_pools(_cfg, pools)
	assert_eq((pools["macrophage"] as BreedPool).genomes[0].receptors, ["binder_a", "hook_b", ""] as Array[String])
	assert_true(pools.has("b_cell"), "a missing tower pool is created wild first")
	assert_eq((pools["b_cell"] as BreedPool).receptor_slots, 3)
	assert_false(pools.has("rhinovirus"))


func test_the_receptor_effect_text_and_bonus() -> void:
	assert_eq(BaseUpgrades.receptor_slot_bonus(_cfg, {"receptor_slot": 1}), 1)
	assert_eq(BaseUpgrades.receptor_slot_bonus(_cfg, {}), 0)
	assert_eq(UpgradesScreen.effect_text(_cfg, {}, "receptor_slot"), "Macrophage and B-Cell carry 2 receptors")
	assert_eq(UpgradesScreen.effect_text(_cfg, {"receptor_slot": 1}, "receptor_slot"), "Macrophage and B-Cell carry 3 receptors")
