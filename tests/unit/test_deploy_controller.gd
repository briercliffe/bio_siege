extends GutTest

func _load_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	return res.config

func _create_session(cfg: GameConfig = null) -> Session:
	var config: GameConfig = cfg if cfg != null else _load_config()
	return Session.new(config)

func _setup_components(session: Session) -> Dictionary:
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config, session.army)
	grid_view.deploy_mode = true

	var hud: HudSpawn = HudSpawn.new()
	add_child_autofree(hud)
	hud.setup(session)

	var toast: Toast = Toast.new()
	add_child_autofree(toast)

	var controller: DeployController = DeployController.new()
	add_child_autofree(controller)
	controller.setup(session, grid_view, hud, toast)

	return {
		"grid_view": grid_view,
		"hud": hud,
		"toast": toast,
		"controller": controller
	}

# 1. Press on ring cell with reserve deploys 1.
func test_press_on_ring_cell_with_reserve_deploys_1() -> void:
	var session: Session = _create_session()
	var comps: Dictionary = _setup_components(session)
	var gv: GridView = comps["grid_view"]
	var controller: DeployController = comps["controller"]

	# Put 1 rhinovirus in reserve
	session.army.buy("rhinovirus", session.wallet)
	assert_eq(session.army.reserve_count("rhinovirus"), 1)
	assert_eq(session.army.deployed_count("rhinovirus"), 0)

	controller.select_deploy_type("rhinovirus")
	var ring_cell := Vector2i(0, 0)
	assert_true(session.grid.is_deploy_zone(ring_cell))

	gv.cell_pressed.emit(ring_cell)
	gv.cell_released.emit(ring_cell)

	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	assert_eq(session.army.deployed_count("rhinovirus"), 1)
	assert_eq(session.army.deployed_at(ring_cell), ["rhinovirus"])

# 2. Press with empty reserve and enough ATP auto-buys and deploys.
func test_press_with_empty_reserve_and_enough_atp_auto_buys_and_deploys() -> void:
	var session: Session = _create_session()
	var comps: Dictionary = _setup_components(session)
	var gv: GridView = comps["grid_view"]
	var controller: DeployController = comps["controller"]

	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	var initial_atp: int = session.wallet.get_amount("atp")
	controller.select_deploy_type("rhinovirus")

	var ring_cell := Vector2i(0, 1)
	gv.cell_pressed.emit(ring_cell)
	gv.cell_released.emit(ring_cell)

	# Rhinovirus costs 10 ATP
	assert_eq(session.wallet.get_amount("atp"), initial_atp - 10)
	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	assert_eq(session.army.deployed_count("rhinovirus"), 1)
	assert_eq(session.army.deployed_at(ring_cell), ["rhinovirus"])

# 3. Press with empty reserve and no ATP does nothing.
func test_press_with_empty_reserve_and_no_atp_does_nothing() -> void:
	var session: Session = _create_session()
	session.wallet.reset({"atp": 0})
	var comps: Dictionary = _setup_components(session)
	var gv: GridView = comps["grid_view"]
	var controller: DeployController = comps["controller"]
	var toast: Toast = comps["toast"]

	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	controller.select_deploy_type("rhinovirus")

	var ring_cell := Vector2i(0, 2)
	gv.cell_pressed.emit(ring_cell)
	gv.cell_released.emit(ring_cell)

	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	assert_eq(session.army.deployed_count("rhinovirus"), 0)
	assert_eq(session.army.deployments.size(), 0)
	assert_eq(toast.last_message, "Not enough ATP")

# 4. Press on interior deploys nothing.
func test_press_on_interior_deploys_nothing() -> void:
	var session: Session = _create_session()
	var comps: Dictionary = _setup_components(session)
	var gv: GridView = comps["grid_view"]
	var controller: DeployController = comps["controller"]
	var toast: Toast = comps["toast"]

	session.army.buy("rhinovirus", session.wallet)
	controller.select_deploy_type("rhinovirus")

	var interior_cell := Vector2i(5, 5)
	assert_false(session.grid.is_deploy_zone(interior_cell))

	gv.cell_pressed.emit(interior_cell)
	gv.cell_released.emit(interior_cell)

	assert_eq(session.army.reserve_count("rhinovirus"), 1)
	assert_eq(session.army.deployed_count("rhinovirus"), 0)
	assert_eq(toast.last_message, "Deploy on the green ring")

# 5. Recall on cell with 2 units leaves 1.
func test_recall_on_cell_with_2_units_leaves_1() -> void:
	var session: Session = _create_session()
	var comps: Dictionary = _setup_components(session)
	var gv: GridView = comps["grid_view"]
	var controller: DeployController = comps["controller"]

	var ring_cell := Vector2i(0, 0)
	session.army.buy("rhinovirus", session.wallet)
	session.army.deploy("rhinovirus", ring_cell)
	session.army.buy("bacteriophage", session.wallet)
	session.army.deploy("bacteriophage", ring_cell)

	assert_eq(session.army.deployed_at(ring_cell).size(), 2)

	controller.select_recall_tool(true)
	assert_true(controller.recall_mode)

	gv.cell_pressed.emit(ring_cell)
	gv.cell_released.emit(ring_cell)

	# Recalled bacteriophage (LIFO) leaving rhinovirus
	var remaining: Array[String] = session.army.deployed_at(ring_cell)
	assert_eq(remaining.size(), 1)
	assert_eq(remaining[0], "rhinovirus")
	assert_eq(session.army.reserve_count("bacteriophage"), 1)

# 6. Launch with 3 rhinoviruses and 1 bacteriophage in reserve with default_seed 12345 (battle_count 1)
func test_launch_auto_placement_and_battle_setup() -> void:
	var cfg1: GameConfig = _load_config()
	cfg1.default_seed = 12345
	var session1: Session = _create_session(cfg1)
	session1.battle_count = 0
	session1.army.reserve["rhinovirus"] = 3
	session1.army.reserve["bacteriophage"] = 1

	var comps1: Dictionary = _setup_components(session1)
	var hud1: HudSpawn = comps1["hud"]
	hud1.launch_requested.emit()

	assert_eq(session1.battle_count, 1)
	assert_eq(session1.seed, 12346)
	assert_eq(session1.army.reserve_count("rhinovirus"), 0)
	assert_eq(session1.army.reserve_count("bacteriophage"), 0)
	assert_eq(session1.army.deployments.size(), 4)

	# Verify all 4 deployed on ring cells
	for dep: Dictionary in session1.army.deployments:
		assert_true(session1.grid.is_deploy_zone(dep["cell"]), "Deployed unit must be on ring")

	# Bacteriophage deployed first (alphabetical order)
	assert_eq(session1.army.deployments[0]["type"], "bacteriophage")
	assert_eq(session1.army.deployments[1]["type"], "rhinovirus")
	assert_eq(session1.army.deployments[2]["type"], "rhinovirus")
	assert_eq(session1.army.deployments[3]["type"], "rhinovirus")

	# Deterministic: running a second session identically yields identical deployments
	var cfg2: GameConfig = _load_config()
	cfg2.default_seed = 12345
	var session2: Session = _create_session(cfg2)
	session2.battle_count = 0
	session2.army.reserve["rhinovirus"] = 3
	session2.army.reserve["bacteriophage"] = 1

	var comps2: Dictionary = _setup_components(session2)
	var hud2: HudSpawn = comps2["hud"]
	hud2.launch_requested.emit()

	assert_eq(session1.army.deployments, session2.army.deployments, "Auto-placement must be deterministic")

	# 7. battle_setup.structures == grid.to_layout(), battle_setup.seed == 12346
	assert_not_null(session1.battle_setup)
	assert_eq(session1.battle_setup.structures, session1.grid.to_layout())
	assert_eq(session1.battle_setup.seed, 12346)
	assert_eq(session1.battle_setup.units, session1.army.deployments)

	var validation_errors: PackedStringArray = session1.battle_setup.validate(session1.config)
	assert_eq(validation_errors.size(), 0, "Validation of battle_setup should pass with 0 errors")

# 8. Hold to deploy repeatedly and drag to new cell
func test_hold_to_deploy_and_drag() -> void:
	var session: Session = _create_session()
	session.config.deploy_hold_interval_s = 0.1
	var comps: Dictionary = _setup_components(session)
	var gv: GridView = comps["grid_view"]
	var controller: DeployController = comps["controller"]

	controller.select_deploy_type("rhinovirus")

	var cell_a := Vector2i(0, 0)
	var cell_b := Vector2i(0, 1)

	# Initial press deploys 1 at cell_a
	gv.cell_pressed.emit(cell_a)
	assert_eq(session.army.deployments.size(), 1)
	assert_eq(session.army.deployed_at(cell_a).size(), 1)

	# Hold for 1 interval -> deploys 2nd at cell_a
	controller._process(0.1)
	assert_eq(session.army.deployments.size(), 2)
	assert_eq(session.army.deployed_at(cell_a).size(), 2)

	# Drag to cell_b
	gv.cell_dragged.emit(cell_b)

	# Hold for 1 interval -> deploys 3rd at cell_b
	controller._process(0.1)
	assert_eq(session.army.deployments.size(), 3)
	assert_eq(session.army.deployed_at(cell_b).size(), 1)

	# Release stops hold
	gv.cell_released.emit(cell_b)
	controller._process(0.2)
	assert_eq(session.army.deployments.size(), 3, "No further deployments after release")

# 9. Rng unit tests
func test_rng_methods() -> void:
	var rng1 := Rng.new(999)
	var rng2 := Rng.new(999)

	for i in range(20):
		var val1: int = rng1.next_int(10)
		var val2: int = rng2.next_int(10)
		assert_true(val1 >= 0 and val1 < 10)
		assert_eq(val1, val2)

	var r_val: int = rng1.next_range(5, 12)
	assert_true(r_val >= 5 and r_val <= 12)

# 10. BattleSetup validation unit tests
func test_battle_setup_validation() -> void:
	var cfg: GameConfig = _load_config()
	var valid_setup: BattleSetup = BattleSetup.create(
		[{"type": "nucleus", "origin": Vector2i(9, 9)}],
		[{"type": "rhinovirus", "cell": Vector2i(0, 0)}],
		123
	)
	var errs: PackedStringArray = valid_setup.validate(cfg)
	assert_eq(errs.size(), 0)

	# Unknown structure type
	var bad_struct: BattleSetup = BattleSetup.create(
		[{"type": "laser_cannon", "origin": Vector2i(9, 9)}],
		[],
		123
	)
	var bad_struct_errs: PackedStringArray = bad_struct.validate(cfg)
	assert_true(bad_struct_errs.size() > 0)

	# Missing core (0 cores)
	var no_core: BattleSetup = BattleSetup.create(
		[{"type": "mucous_wall", "origin": Vector2i(5, 5)}],
		[],
		123
	)
	var no_core_errs: PackedStringArray = no_core.validate(cfg)
	assert_true(no_core_errs.has("Expected exactly 1 core structure, found 0"))

	# Overlapping structures
	var overlap_setup: BattleSetup = BattleSetup.create(
		[
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "mucous_wall", "origin": Vector2i(9, 9)}
		],
		[],
		123
	)
	var overlap_errs: PackedStringArray = overlap_setup.validate(cfg)
	assert_true(overlap_errs.size() > 0)

	# Out of bounds structure
	var oob_struct: BattleSetup = BattleSetup.create(
		[
			{"type": "nucleus", "origin": Vector2i(9, 9)},
			{"type": "mucous_wall", "origin": Vector2i(-1, 5)}
		],
		[],
		123
	)
	var oob_struct_errs: PackedStringArray = oob_struct.validate(cfg)
	assert_true(oob_struct_errs.size() > 0)

	# Out of bounds unit
	var oob_unit: BattleSetup = BattleSetup.create(
		[{"type": "nucleus", "origin": Vector2i(9, 9)}],
		[{"type": "rhinovirus", "cell": Vector2i(100, 100)}],
		123
	)
	var oob_unit_errs: PackedStringArray = oob_unit.validate(cfg)
	assert_true(oob_unit_errs.size() > 0)

	# Unknown pathogen type
	var bad_unit: BattleSetup = BattleSetup.create(
		[{"type": "nucleus", "origin": Vector2i(9, 9)}],
		[{"type": "alien_virus", "cell": Vector2i(0, 0)}],
		123
	)
	var bad_unit_errs: PackedStringArray = bad_unit.validate(cfg)
	assert_true(bad_unit_errs.size() > 0)
