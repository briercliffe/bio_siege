extends GutTest


func _session(enabled: bool, memory: bool = false) -> Session:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["coevolution"] = enabled
	cfg.feature_flags["immune_memory"] = memory
	cfg.feature_flags["bcell_analysis"] = memory
	return Session.new(cfg)


func _pool(session: Session, type_id: String, genomes: Array) -> BreedPool:
	var pool: BreedPool = BreedPool.wild_pool(type_id, session.config)
	for i: int in range(genomes.size()):
		var g: Dictionary = genomes[i]
		pool.genomes[i] = Genome.from_slots(g.get("antigens", []), g.get("receptors", []), session.config)
	return pool


func test_should_show_type() -> void:
	var session: Session = _session(true)
	assert_false(CoevolutionPanel.should_show_type(BreedPool.wild_pool("b_cell", session.config)))
	assert_false(CoevolutionPanel.should_show_type(null))
	var pool: BreedPool = _pool(session, "b_cell", [{"antigens": ["capsule_a", ""]}])
	assert_true(CoevolutionPanel.should_show_type(pool))


func test_modal_allele_and_ties() -> void:
	var session: Session = _session(true)
	var pool: BreedPool = _pool(session, "b_cell", [
		{"receptors": ["binder_a", ""]},
		{"receptors": ["binder_b", ""]},
		{"receptors": ["binder_a", ""]},
		{"receptors": ["binder_a", "binder_b"], "antigens": ["capsule_a", ""]},
	])
	assert_eq(CoevolutionPanel.row_text("b_cell", pool, {}, session.config), "B-Cell: Binder A vs Capsule A")
	# Two slots each: the earlier catalog entry wins. Two copies on one genome count twice.
	var tie: BreedPool = _pool(session, "b_cell", [
		{"receptors": ["binder_b", "binder_b"]},
		{"receptors": ["binder_a", "binder_a"]},
	])
	assert_eq(CoevolutionPanel.row_text("b_cell", tie, {}, session.config), "B-Cell: Binder A vs no marker")


func test_no_binder_and_parent_clause() -> void:
	var session: Session = _session(true)
	var pool: BreedPool = _pool(session, "rhinovirus", [{"antigens": ["spike_b", ""]}])
	var summary: Dictionary = {"bred": true, "top_count": 5, "pool_size": 8}
	assert_eq(CoevolutionPanel.row_text("rhinovirus", pool, summary, session.config), "Rhinovirus: no binder vs Spike B · parent 5/8")
	assert_eq(CoevolutionPanel.row_text("rhinovirus", pool, {}, session.config), "Rhinovirus: no binder vs Spike B")
	assert_eq(CoevolutionPanel.row_text("rhinovirus", pool, {"bred": false}, session.config), "Rhinovirus: no binder vs Spike B")


func test_empty_state_and_rows() -> void:
	var session: Session = _session(true)
	var panel := CoevolutionPanel.new()
	add_child_autofree(panel)
	panel.setup(session)
	assert_true(panel.empty_label.visible)
	assert_eq(panel.empty_label.text, "No mutations yet. The fittest fighters parent the next generation.")
	assert_eq(panel.title_label.text, "Populations")
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	session.populations["staphylococcus"] = _pool(session, "staphylococcus", [{"receptors": ["latch_a", ""]}])
	session.populations["b_cell"] = _pool(session, "b_cell", [{"antigens": ["coat_b", ""]}])
	session.last_result["evolution"] = [{"type_id": "b_cell", "bred": true, "top_count": 5, "pool_size": 8}]
	panel.refresh()
	assert_false(panel.empty_label.visible)
	assert_eq(panel.rows_box.get_child_count(), 2)
	assert_eq((panel.rows_box.get_child(0) as Label).text, "B-Cell: no binder vs Coat B · parent 5/8")
	assert_eq((panel.rows_box.get_child(1) as Label).text, "Staphylococcus: Latch A vs no marker")


func test_hud_shows_panel_only_when_enabled() -> void:
	for enabled: bool in [false, true]:
		var spawn := HudSpawn.new()
		add_child_autofree(spawn)
		spawn.setup(_session(enabled))
		assert_eq(spawn.coevolution_panel != null and spawn.coevolution_panel.visible, enabled, "spawn hud")
		var session: Session = _session(enabled)
		var grid_view := GridView.new()
		add_child_autofree(grid_view)
		grid_view.setup(session.grid, session.config)
		var controller := BuildController.new()
		add_child_autofree(controller)
		controller.setup(session, grid_view)
		var build: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
		add_child_autofree(build)
		build.setup(session, controller)
		assert_eq(build.coevolution_panel != null and build.coevolution_panel.visible, enabled, "build hud")


func test_panel_stacks_under_memory_panel() -> void:
	var spawn := HudSpawn.new()
	add_child_autofree(spawn)
	spawn.setup(_session(true, true))
	assert_not_null(spawn.memory_panel)
	assert_not_null(spawn.coevolution_panel)
	assert_eq(spawn.coevolution_panel.get_parent(), spawn.memory_panel.get_parent())
	assert_eq(spawn.coevolution_panel.get_index(), spawn.memory_panel.get_index() + 1)


func test_evolution_line() -> void:
	var cfg: GameConfig = _session(true).config
	var entries: Array = [
		{"type_id": "b_cell", "bred": true, "top_count": 5, "pool_size": 8},
		{"type_id": "macrophage", "bred": false, "top_count": 0, "pool_size": 8},
		{"type_id": "rhinovirus", "bred": true, "top_count": 6, "pool_size": 8},
	]
	assert_eq(ResultsPhase.evolution_line(entries, cfg), "Populations: B-Cell parent 5/8 · Rhinovirus parent 6/8")
	assert_eq(ResultsPhase.evolution_line([{"type_id": "b_cell", "bred": false}], cfg), "")
	assert_eq(ResultsPhase.evolution_line([], cfg), "")
