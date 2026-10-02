extends GutTest

## Dendritic Cell (#166): an always visible presenter that shares completed B-Cell analysis.

const KEY: String = "rhinovirus/wild"


func _cfg(dendritic: bool = true) -> GameConfig:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["bcell_analysis"] = true
	cfg.feature_flags["dendritic_cell"] = dendritic
	if not dendritic:
		# A flag-gated structure is rejected from a layout while its flag is off; drop the gate so the
		# flag-off tests can still place one and prove the sim ignores it.
		(cfg.structures["dendritic_cell"] as StructureDef).requires_flag = ""
	return cfg


func _bcell(x: int) -> Dictionary:
	return {"type": "b_cell", "origin": Vector2i(x, 10)}


func _dendritic(x: int) -> Dictionary:
	return {"type": "dendritic_cell", "origin": Vector2i(x, 10)}


## Structures are numbered in the order given (the Nucleus is appended last).
func _sim(cfg: GameConfig, structs: Array) -> BattleSim:
	return SimFixtures.make_sim(structs, [{"type": "rhinovirus", "cell": Vector2i(2, 30)}], 1, cfg)


## Makes structure `id` finish analysing the rhinovirus on its next accrual.
func _complete(sim: BattleSim, id: int) -> void:
	var s: StructureState = sim.structure(id)
	s.target_id = 1
	s.analysis_exposure[KEY] = s.def.analysis_threshold_ticks * 100 - 100
	sim._accrue_analysis(s)


func test_default_data_has_the_presenter_and_the_flag_is_off() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var d: StructureDef = cfg.structures["dendritic_cell"]
	assert_true(d.has_presenter)
	assert_eq(d.presenter_radius_mt, 4 * cfg.grid_scale * 1000)
	assert_true(d.has_tag("support"))
	assert_true(d.visible_to_attacker)
	assert_false(d.has_attack)
	assert_eq(d.requires_flag, "dendritic_cell")
	assert_false(cfg.flag("dendritic_cell"))
	assert_false(cfg.buildable_structure_ids().has("dendritic_cell"), "not in the tray with the flag off")
	cfg.feature_flags["dendritic_cell"] = true
	assert_true(cfg.buildable_structure_ids().has("dendritic_cell"))
	assert_false(cfg.is_breeding_type("dendritic_cell"))


func test_flag_off_shares_nothing() -> void:
	var sim: BattleSim = _sim(_cfg(false), [_bcell(6), _dendritic(10), _bcell(14)])
	_complete(sim, 1)
	assert_true(sim.structure(1).analyzed.has(KEY))
	assert_false(sim.structure(3).analyzed.has(KEY))
	assert_eq(sim.analyses_shared, 0)


func test_a_completed_analysis_reaches_every_bcell_in_the_radius_at_once() -> void:
	var sim: BattleSim = _sim(_cfg(), [_bcell(6), _dendritic(10), _bcell(14)])
	_complete(sim, 1)
	var b: StructureState = sim.structure(3)
	assert_true(b.analyzed.has(KEY))
	assert_eq(int(b.analysis_exposure[KEY]), b.def.analysis_threshold_ticks * 100)
	assert_eq(sim.analyses_shared, 1)
	var shared: Dictionary = {}
	for ev: Dictionary in sim.drain_events():
		if ev.get("type", "") == SimEvents.ANALYSIS_SHARED:
			shared = ev
	assert_false(shared.is_empty())
	assert_eq(int(shared["presenter_id"]), 2)
	assert_eq(int(shared["from_id"]), 1)
	assert_eq(int(shared["to_id"]), 3)
	assert_eq(shared["strain_key"], KEY)


func test_a_bcell_outside_the_radius_gets_nothing() -> void:
	var sim: BattleSim = _sim(_cfg(), [_bcell(6), _dendritic(10), _bcell(24)])
	_complete(sim, 1)
	assert_false(sim.structure(3).analyzed.has(KEY))
	assert_eq(sim.analyses_shared, 0)


func test_sharing_is_one_hop_and_never_chains() -> void:
	var sim: BattleSim = _sim(_cfg(), [_bcell(6), _dendritic(10), _bcell(14), _dendritic(18), _bcell(22)])
	_complete(sim, 1)
	assert_true(sim.structure(3).analyzed.has(KEY), "B is covered by the first Dendritic Cell")
	assert_false(sim.structure(5).analyzed.has(KEY), "C is only covered by the second, which A is outside")


func test_a_destroyed_dendritic_cell_shares_nothing() -> void:
	var sim: BattleSim = _sim(_cfg(), [_bcell(6), _dendritic(10), _bcell(14)])
	sim._damage_structure(sim.structure(2), 100000, 0)
	assert_false(sim.structure(2).alive)
	_complete(sim, 1)
	assert_false(sim.structure(3).analyzed.has(KEY))


func test_a_destroyed_bcell_receives_nothing() -> void:
	var sim: BattleSim = _sim(_cfg(), [_bcell(6), _dendritic(10), _bcell(14)])
	sim._damage_structure(sim.structure(3), 100000, 0)
	_complete(sim, 1)
	assert_false(sim.structure(3).analyzed.has(KEY))


func test_the_presenter_needs_bcell_analysis() -> void:
	var cfg: GameConfig = _cfg()
	cfg.feature_flags["bcell_analysis"] = false
	var sim: BattleSim = _sim(cfg, [_bcell(6), _dendritic(10), _bcell(14)])
	assert_false(sim._presenter_on)


func test_the_tray_text_quotes_the_radius() -> void:
	var cfg: GameConfig = _cfg()
	assert_eq(UnitCopy.description("dendritic_cell", cfg), "Shares B-Cell analysis within 8 tiles.")


func test_ghost_ring_uses_the_presenter_radius() -> void:
	var cfg: GameConfig = _cfg()
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	var view: GridView = (load("res://src/view/grid_view.tscn") as PackedScene).instantiate() as GridView
	add_child_autofree(view)
	view.setup(grid, cfg)
	view.fit_to_rect(Rect2(0.0, 0.0, 800.0, 600.0))
	view.set_ghost("dendritic_cell", Vector2i(10, 10), true)
	view._rebuild_ghost()
	assert_gt(view._g_range_dashes.size(), 0, "a dashed radius ring while placing")
	view.set_ghost("mucous_wall", Vector2i(10, 10), true)
	view._rebuild_ghost()
	assert_eq(view._g_range_dashes.size(), 0, "no ring for a wall")


func _load_structures(mutate: Callable) -> ConfigLoadResult:
	var structs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/structures.json"))
	mutate.call(structs)
	return GameConfig.load_from_strings(FileAccess.get_file_as_string("res://data/game_rules.json"),
		JSON.stringify(structs), FileAccess.get_file_as_string("res://data/pathogens.json"))


func _has_error(res: ConfigLoadResult, fragment: String) -> bool:
	for e: String in res.errors:
		if e.find(fragment) != -1:
			return true
	return false


func test_presenter_validation() -> void:
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["dendritic_cell"]["presenter"]["radius_tiles"] = 0), "structures.json: dendritic_cell.presenter.radius_tiles: must be > 0 (got 0)"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["dendritic_cell"]["presenter"]["radius_tiles"] = "far"), "structures.json: dendritic_cell.presenter.radius_tiles: must be a number"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["dendritic_cell"]["presenter"]["bogus"] = 1), "structures.json: dendritic_cell.presenter.bogus: unknown key"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["dendritic_cell"]["presenter"] = {}), "structures.json: dendritic_cell.presenter.radius_tiles: missing required field"))
	assert_true(_has_error(_load_structures(func(s: Dictionary) -> void: s["dendritic_cell"]["presenter"] = 3), "structures.json: dendritic_cell.presenter: must be a JSON object"))
	assert_true(_load_structures(func(s: Dictionary) -> void: s["dendritic_cell"].erase("presenter")).is_ok())


# --- antigen presentation (#167) ---

func _coevo_cfg(dendritic: bool = true) -> GameConfig:
	var cfg: GameConfig = _cfg(dendritic)
	cfg.feature_flags["coevolution"] = true
	return cfg


## A battle with a Dendritic Cell and one rhinovirus whose genome carries capsule_a and spike_b.
func _presenting_sim(cfg: GameConfig, unit_cell: Vector2i) -> BattleSim:
	var pops: Dictionary = {"rhinovirus": {"genomes": [{"antigens": ["capsule_a", "spike_b"], "receptors": ["", ""]}]}}
	var structs: Array = [_dendritic(10), {"type": "nucleus", "origin": Vector2i(18, 18)}]
	return BattleSim.new(cfg, BattleSetup.create(structs, [{"type": "rhinovirus", "cell": unit_cell}], 1, {}, pops))


func test_antigens_near_a_dendritic_cell_are_recorded() -> void:
	var sim: BattleSim = _presenting_sim(_coevo_cfg(), Vector2i(12, 10))
	sim.step()
	assert_eq(sim.presented_antigen_ids(), ["capsule_a", "spike_b"] as Array[String])


func test_antigens_out_of_radius_are_not_recorded() -> void:
	var sim: BattleSim = _presenting_sim(_coevo_cfg(), Vector2i(30, 30))
	sim.step()
	assert_true(sim.presented_antigen_ids().is_empty())


func test_nothing_is_recorded_without_the_flags() -> void:
	var off: BattleSim = _presenting_sim(_coevo_cfg(false), Vector2i(12, 10))
	off.step()
	assert_true(off.presented_antigen_ids().is_empty())
	var no_coevo: GameConfig = _cfg()
	var plain: BattleSim = _presenting_sim(no_coevo, Vector2i(12, 10))
	plain.step()
	assert_true(plain.presented_antigen_ids().is_empty())


func test_presentation_never_touches_analysis() -> void:
	var cfg: GameConfig = _coevo_cfg()
	var sim: BattleSim = _presenting_sim(cfg, Vector2i(12, 10))
	sim.step()
	assert_true(sim.analyzed_strain_keys().is_empty())
	for s: StructureState in sim.structures:
		assert_true(s.analyzed.is_empty())


func test_the_record_shows_in_the_hash_only_when_active() -> void:
	var on: BattleSim = _presenting_sim(_coevo_cfg(), Vector2i(12, 10))
	var near: BattleSim = _presenting_sim(_coevo_cfg(), Vector2i(30, 30))
	on.step()
	near.step()
	assert_ne(on.state_hash(), near.state_hash())
	var off_a: BattleSim = _presenting_sim(_coevo_cfg(false), Vector2i(12, 10))
	var off_b: BattleSim = _presenting_sim(_coevo_cfg(false), Vector2i(12, 10))
	off_a.step()
	off_b.step()
	assert_eq(off_a.state_hash(), off_b.state_hash())


func test_record_interval_is_one_second() -> void:
	var cfg: GameConfig = _cfg()
	assert_eq(cfg.presenter_record_interval_ticks, cfg.tick_rate)
