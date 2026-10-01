extends GutTest

const NUCLEUS_ORIGIN: Vector2i = Vector2i(18, 18)


## These tests read the SessionLogger autoload's output, so consent is forced on whatever the saved choice.
var _saved_consent: bool = true


func before_all() -> void:
	_saved_consent = SessionLogger.has_consent()
	SessionLogger.set_consent(true)


func after_all() -> void:
	SessionLogger.set_consent(_saved_consent)


var _signal_log: Array[String] = []

func _load_config(move_nucleus: bool = false) -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	var cfg: GameConfig = res.config
	cfg.feature_flags["move_nucleus"] = move_nucleus
	return cfg

func _make_grid(cfg: GameConfig) -> GridModel:
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()
	return grid

func _make_session(move_nucleus: bool = true) -> Session:
	return Session.new(_load_config(move_nucleus))

func _make_controller(session: Session) -> Dictionary:
	var grid_view: GridView = GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)
	var bc: BuildController = BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)
	return {"grid_view": grid_view, "controller": bc}

func _make_hud(session: Session) -> Dictionary:
	var ctx: Dictionary = _make_controller(session)
	var hud: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
	add_child_autofree(hud)
	hud.setup(session, ctx["controller"])
	ctx["hud"] = hud
	return ctx

func _assert_nucleus_cells(grid: GridModel, origin: Vector2i, expected: GridModel.TileState) -> void:
	for y in range(origin.y, origin.y + 4):
		for x in range(origin.x, origin.x + 4):
			assert_eq(grid.tile_state(Vector2i(x, y)), expected, "cell (%d,%d)" % [x, y])

# ---------------------------------------------------------------------------
# GridModel.move_structure
# ---------------------------------------------------------------------------

func test_config_flag_defaults_off_and_can_be_enabled() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_false(res.config.move_nucleus_enabled())
	res.config.feature_flags["move_nucleus"] = true
	assert_true(res.config.move_nucleus_enabled())
	res.config.feature_flags.erase("move_nucleus")
	assert_false(res.config.move_nucleus_enabled())

func test_move_nucleus_to_new_spot() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	var atp_before: int = wallet.get_amount("atp")

	var err: GridModel.PlaceError = grid.move_structure(1, Vector2i(3, 3))
	assert_eq(err, GridModel.PlaceError.OK)
	assert_eq(grid.get_structure(1).origin, Vector2i(3, 3))
	assert_eq(grid.tile_state(NUCLEUS_ORIGIN), GridModel.TileState.EMPTY)
	assert_eq(grid.tile_state(Vector2i(21, 21)), GridModel.TileState.EMPTY)
	_assert_nucleus_cells(grid, Vector2i(3, 3), GridModel.TileState.NUCLEUS)
	assert_eq(grid.structure_id_at(Vector2i(4, 4)), 1)
	assert_eq(grid.structure_id_at(NUCLEUS_ORIGIN), 0)
	assert_eq(wallet.get_amount("atp"), atp_before, "Wallet is never touched by a move")

func test_move_one_cell_right_overlapping_own_cells() -> void:
	var grid: GridModel = _make_grid(_load_config())
	var err: GridModel.PlaceError = grid.move_structure(1, Vector2i(19, 18))
	assert_eq(err, GridModel.PlaceError.OK)
	assert_eq(grid.get_structure(1).origin, Vector2i(19, 18))
	assert_eq(grid.tile_state(Vector2i(18, 18)), GridModel.TileState.EMPTY)
	assert_eq(grid.tile_state(Vector2i(18, 19)), GridModel.TileState.EMPTY)
	_assert_nucleus_cells(grid, Vector2i(19, 18), GridModel.TileState.NUCLEUS)

func test_move_onto_deploy_ring_rejected() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	var err: GridModel.PlaceError = grid.move_structure(1, Vector2i(1, 5))
	assert_eq(err, GridModel.PlaceError.DEPLOY_ZONE)
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN)
	_assert_nucleus_cells(grid, NUCLEUS_ORIGIN, GridModel.TileState.NUCLEUS)
	assert_eq(grid.tile_state(Vector2i(1, 5)), GridModel.TileState.EMPTY)
	assert_eq(wallet.get_amount("atp"), cfg.start_wallet["atp"])

func test_move_partially_onto_deploy_ring_rejected() -> void:
	var grid: GridModel = _make_grid(_load_config())
	# Footprint (1,3)-(4,6) touches the band column x = 1.
	assert_eq(grid.move_structure(1, Vector2i(1, 3)), GridModel.PlaceError.DEPLOY_ZONE)
	# Footprint (35,3)-(38,6) touches the band column x = 38.
	assert_eq(grid.move_structure(1, Vector2i(35, 3)), GridModel.PlaceError.DEPLOY_ZONE)
	# Footprint (3,35)-(6,38) touches the band row y = 38.
	assert_eq(grid.move_structure(1, Vector2i(3, 35)), GridModel.PlaceError.DEPLOY_ZONE)
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN)

func test_move_next_to_ring_is_allowed() -> void:
	var grid: GridModel = _make_grid(_load_config())
	assert_eq(grid.move_structure(1, Vector2i(2, 2)), GridModel.PlaceError.OK)
	assert_eq(grid.move_structure(1, Vector2i(34, 34)), GridModel.PlaceError.OK)
	assert_eq(grid.get_structure(1).origin, Vector2i(34, 34))

func test_move_onto_wall_rejected() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	var wall_id: int = grid.place("mucous_wall", Vector2i(3, 3), wallet)
	assert_gt(wall_id, 0)
	var atp_after_wall: int = wallet.get_amount("atp")

	# The wall sits in the bottom-right cell of the target footprint.
	var err: GridModel.PlaceError = grid.move_structure(1, Vector2i(2, 2))
	assert_eq(err, GridModel.PlaceError.OCCUPIED)
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN)
	_assert_nucleus_cells(grid, NUCLEUS_ORIGIN, GridModel.TileState.NUCLEUS)
	assert_eq(grid.tile_state(Vector2i(3, 3)), GridModel.TileState.WALL)
	assert_eq(grid.structure_id_at(Vector2i(3, 3)), wall_id)
	assert_eq(wallet.get_amount("atp"), atp_after_wall)

func test_move_out_of_bounds_rejected() -> void:
	var grid: GridModel = _make_grid(_load_config())
	assert_eq(grid.move_structure(1, Vector2i(-1, 5)), GridModel.PlaceError.OUT_OF_BOUNDS)
	assert_eq(grid.move_structure(1, Vector2i(5, -3)), GridModel.PlaceError.OUT_OF_BOUNDS)
	assert_eq(grid.move_structure(1, Vector2i(39, 5)), GridModel.PlaceError.OUT_OF_BOUNDS)
	assert_eq(grid.move_structure(1, Vector2i(5, 39)), GridModel.PlaceError.OUT_OF_BOUNDS)
	assert_eq(grid.move_structure(1, Vector2i(99, 99)), GridModel.PlaceError.OUT_OF_BOUNDS)
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN)

func test_move_unknown_id_rejected() -> void:
	var grid: GridModel = _make_grid(_load_config())
	assert_eq(grid.move_structure(99, Vector2i(3, 3)), GridModel.PlaceError.UNKNOWN_TYPE)
	assert_eq(grid.move_structure(0, Vector2i(3, 3)), GridModel.PlaceError.UNKNOWN_TYPE)
	assert_eq(grid.check_move(99, Vector2i(3, 3)), GridModel.PlaceError.UNKNOWN_TYPE)
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN)

func test_move_keeps_id_and_type() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	var wall_id: int = grid.place("mucous_wall", Vector2i(3, 3), wallet)

	assert_eq(grid.move_structure(1, Vector2i(5, 5)), GridModel.PlaceError.OK)
	var moved: GridModel.PlacedStructure = grid.get_structure(1)
	assert_eq(moved.id, 1)
	assert_eq(moved.type_id, "nucleus")
	assert_eq(moved.footprint, Vector2i(4, 4))
	assert_eq(grid.count_by_type(), {"nucleus": 1, "mucous_wall": 1})
	assert_eq(grid.structures().size(), 2)

	# New placements keep counting from where they were.
	var next_id: int = grid.place("mucous_wall", Vector2i(3, 4), wallet)
	assert_eq(next_id, wall_id + 1)

func test_move_works_for_any_structure() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	var tower_id: int = grid.place("macrophage", Vector2i(3, 3), wallet)
	var atp: int = wallet.get_amount("atp")

	assert_eq(grid.move_structure(tower_id, Vector2i(4, 4)), GridModel.PlaceError.OK)
	assert_eq(grid.get_structure(tower_id).origin, Vector2i(4, 4))
	assert_eq(grid.tile_state(Vector2i(3, 3)), GridModel.TileState.EMPTY)
	assert_eq(grid.tile_state(Vector2i(4, 4)), GridModel.TileState.TOWER)
	assert_eq(grid.move_structure(tower_id, Vector2i(18, 18)), GridModel.PlaceError.OCCUPIED)
	assert_eq(wallet.get_amount("atp"), atp)

func test_move_has_no_cost_check() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	var tower_id: int = grid.place("macrophage", Vector2i(3, 3), wallet)
	wallet.spend({"atp": wallet.get_amount("atp")})
	assert_eq(wallet.get_amount("atp"), 0)

	assert_eq(grid.move_structure(tower_id, Vector2i(4, 4)), GridModel.PlaceError.OK)
	assert_eq(grid.move_structure(1, Vector2i(10, 10)), GridModel.PlaceError.OK)
	assert_eq(wallet.get_amount("atp"), 0)

func test_move_to_current_origin_is_silent_noop() -> void:
	var grid: GridModel = _make_grid(_load_config())
	_signal_log.clear()
	grid.structure_removed.connect(func(_s: GridModel.PlacedStructure) -> void: _signal_log.append("removed"))
	grid.structure_placed.connect(func(_s: GridModel.PlacedStructure) -> void: _signal_log.append("placed"))
	assert_eq(grid.move_structure(1, NUCLEUS_ORIGIN), GridModel.PlaceError.OK)
	assert_eq(_signal_log, [])
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN)

func test_move_signal_order_removed_then_placed() -> void:
	var grid: GridModel = _make_grid(_load_config())
	_signal_log.clear()
	var origins: Array[Vector2i] = []
	grid.structure_removed.connect(func(s: GridModel.PlacedStructure) -> void:
		_signal_log.append("removed")
		origins.append(s.origin)
		assert_eq(s.id, 1)
	)
	grid.structure_placed.connect(func(s: GridModel.PlacedStructure) -> void:
		_signal_log.append("placed")
		origins.append(s.origin)
		assert_eq(s.id, 1)
	)

	assert_eq(grid.move_structure(1, Vector2i(3, 3)), GridModel.PlaceError.OK)
	assert_eq(_signal_log, ["removed", "placed"])
	assert_eq(origins, [NUCLEUS_ORIGIN, Vector2i(3, 3)] as Array[Vector2i])

func test_failed_move_emits_no_signals() -> void:
	var grid: GridModel = _make_grid(_load_config())
	_signal_log.clear()
	grid.structure_removed.connect(func(_s: GridModel.PlacedStructure) -> void: _signal_log.append("removed"))
	grid.structure_placed.connect(func(_s: GridModel.PlacedStructure) -> void: _signal_log.append("placed"))
	assert_eq(grid.move_structure(1, Vector2i(0, 5)), GridModel.PlaceError.DEPLOY_ZONE)
	assert_eq(_signal_log, [])

func test_check_move_matches_move_structure() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	grid.place("mucous_wall", Vector2i(3, 3), wallet)
	for origin: Vector2i in [Vector2i(3, 3), Vector2i(0, 0), Vector2i(-1, 4), Vector2i(19, 18), Vector2i(6, 6)]:
		assert_eq(grid.check_move(1, origin), grid.move_structure(1, origin), str(origin))

func test_find_core() -> void:
	var grid: GridModel = _make_grid(_load_config())
	assert_eq(grid.find_core().id, 1)
	assert_eq(grid.find_core().type_id, "nucleus")
	assert_null(GridModel.new(_load_config()).find_core())

# ---------------------------------------------------------------------------
# load_layout / to_layout with a moved Nucleus
# ---------------------------------------------------------------------------

func test_load_layout_honors_nucleus_origin() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var layout: Array = [{"type": "nucleus", "origin": Vector2i(3, 3)}]
	assert_eq(grid.load_layout(layout), GridModel.PlaceError.OK)
	assert_eq(grid.get_structure(1).origin, Vector2i(3, 3))
	assert_eq(grid.tile_state(Vector2i(18, 18)), GridModel.TileState.EMPTY)
	_assert_nucleus_cells(grid, Vector2i(3, 3), GridModel.TileState.NUCLEUS)
	assert_eq(grid.count_by_type(), {"nucleus": 1})

func test_load_layout_accepts_array_origin_and_default_when_no_core() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	assert_eq(grid.load_layout([{"type": "nucleus", "origin": [4, 5]}]), GridModel.PlaceError.OK)
	assert_eq(grid.get_structure(1).origin, Vector2i(4, 5))
	assert_eq(grid.load_layout([{"type": "mucous_wall", "origin": Vector2i(2, 2)}], Wallet.new(cfg.start_wallet)), GridModel.PlaceError.OK)
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN, "No core entry keeps the default origin")

func test_load_layout_places_structures_on_old_nucleus_cells() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	var layout: Array = [
		{"type": "mucous_wall", "origin": Vector2i(18, 18)},
		{"type": "nucleus", "origin": Vector2i(3, 3)},
	]
	assert_eq(grid.load_layout(layout, wallet), GridModel.PlaceError.OK)
	assert_eq(grid.tile_state(Vector2i(18, 18)), GridModel.TileState.WALL)
	assert_eq(grid.get_structure(1).origin, Vector2i(3, 3))

func test_load_layout_rejects_invalid_nucleus_origin() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	assert_eq(grid.load_layout([{"type": "nucleus", "origin": Vector2i(0, 0)}]), GridModel.PlaceError.DEPLOY_ZONE)
	assert_eq(grid.get_structure(1).origin, NUCLEUS_ORIGIN)
	assert_eq(grid.load_layout([{"type": "nucleus", "origin": Vector2i(37, 3)}]), GridModel.PlaceError.OUT_OF_BOUNDS)

func test_layout_round_trip_with_moved_nucleus() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	grid.place("mucous_wall", Vector2i(18, 18), wallet)
	grid.move_structure(1, Vector2i(3, 3))
	grid.place("macrophage", Vector2i(10, 10), wallet)
	var layout: Array[Dictionary] = grid.to_layout()

	var other: GridModel = GridModel.new(cfg)
	other.reset_with_nucleus()
	assert_eq(other.load_layout(layout, Wallet.new(cfg.start_wallet)), GridModel.PlaceError.OK)
	assert_eq(other.to_layout(), layout)
	assert_eq(other.get_structure(1).origin, Vector2i(3, 3))

# ---------------------------------------------------------------------------
# Snapshots, replays and battles with a moved Nucleus
# ---------------------------------------------------------------------------

func test_snapshot_round_trip_with_moved_nucleus() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	var wallet: Wallet = Wallet.new(cfg.start_wallet)
	grid.move_structure(1, Vector2i(3, 3))
	grid.place("macrophage", Vector2i(18, 18), wallet)

	var json_str: String = SnapshotIO.to_json(SnapshotIO.base_to_dict(grid))
	var parsed: Dictionary = SnapshotIO.parse_base(json_str, cfg)
	assert_true(parsed["ok"], str(parsed["error"]))
	assert_eq(parsed["layout"], grid.to_layout())

	var restored: GridModel = GridModel.new(cfg)
	restored.reset_with_nucleus()
	assert_eq(restored.load_layout(parsed["layout"], Wallet.new(cfg.start_wallet)), GridModel.PlaceError.OK)
	assert_eq(restored.get_structure(1).origin, Vector2i(3, 3))
	assert_eq(restored.tile_state(Vector2i(18, 18)), GridModel.TileState.TOWER)
	assert_eq(SnapshotIO.to_json(SnapshotIO.base_to_dict(restored)), json_str)

func _moved_nucleus_setup(grid: GridModel) -> BattleSetup:
	var units: Array = []
	for i in range(6):
		units.append({"type": "rhinovirus", "cell": Vector2i(0, 3 + i % 3)})
	return BattleSetup.create(grid.to_layout(), units, 7)

func test_battle_and_replay_with_moved_nucleus() -> void:
	var cfg: GameConfig = _load_config()
	var grid: GridModel = _make_grid(cfg)
	grid.move_structure(1, Vector2i(3, 3))
	var setup: BattleSetup = _moved_nucleus_setup(grid)
	assert_eq(setup.validate(cfg).size(), 0)

	var sim := BattleSim.new(cfg, setup)
	var nucleus: StructureState = sim.structure(sim.nucleus_id)
	assert_not_null(nucleus)
	assert_eq(nucleus.origin, Vector2i(3, 3))
	sim.run_to_end()
	assert_true(sim.finished)
	assert_eq(sim.end_reason, "nucleus_destroyed", "Pathogens must path to the off-center Nucleus")

	var log_json: String = SnapshotIO.to_json(SnapshotIO.battle_to_dict(cfg, setup, sim))
	var verify: Dictionary = Replay.verify(log_json, cfg)
	assert_true(verify["ok"], str(verify.get("error", "")))
	assert_true(verify["match"], "Replay of a moved-Nucleus battle must match")
	assert_true(verify["config_matches"])

func test_moved_nucleus_changes_battle_outcome_state() -> void:
	var cfg: GameConfig = _load_config()
	var centered: GridModel = _make_grid(cfg)
	var moved: GridModel = _make_grid(cfg)
	moved.move_structure(1, Vector2i(3, 3))
	var sim_a := BattleSim.new(cfg, _moved_nucleus_setup(centered))
	var sim_b := BattleSim.new(cfg, _moved_nucleus_setup(moved))
	sim_a.run_to_end()
	sim_b.run_to_end()
	assert_ne(sim_a.state_hash(), sim_b.state_hash())
	assert_lt(sim_b.tick, sim_a.tick, "Nucleus next to the units' spawn ring falls sooner")

# ---------------------------------------------------------------------------
# HUD card
# ---------------------------------------------------------------------------

func test_hud_has_move_card_when_flag_on() -> void:
	var session: Session = _make_session(true)
	var hud: HudBuild = _make_hud(session)["hud"]
	var cards: Array[HudCard] = hud.get_cards()
	var buildable: int = session.config.buildable_structure_ids().size()
	assert_eq(cards.size(), buildable + 2)
	assert_true(cards[buildable].is_sell, "Sell stays before the Move card")
	var move_card: HudCard = cards[cards.size() - 1]
	assert_true(move_card.is_move_nucleus)
	assert_false(move_card.is_structure_card())
	assert_eq(move_card.tool_id, "move_nucleus")
	assert_eq(move_card.title, "Move Nucleus")
	assert_eq(move_card.cost_atp, 0)
	assert_eq(move_card.icon_id, "nucleus")
	assert_true(move_card.custom_minimum_size.x >= 48.0)
	assert_true(move_card.custom_minimum_size.y >= 48.0)
	assert_eq(hud.get_card("move_nucleus"), move_card)

func test_hud_has_no_move_card_when_flag_off() -> void:
	var session: Session = _make_session(false)
	var ctx: Dictionary = _make_hud(session)
	var hud: HudBuild = ctx["hud"]
	var cards: Array[HudCard] = hud.get_cards()
	assert_eq(cards.size(), session.config.buildable_structure_ids().size() + 1)
	assert_null(hud.get_card("move_nucleus"))
	for c in cards:
		assert_false(c.is_move_nucleus)
	assert_true(cards[cards.size() - 1].is_sell, "Sell remains the last card")

	# The tool cannot be selected either.
	var bc: BuildController = ctx["controller"]
	bc.select_tool("move_nucleus")
	assert_eq(bc.tool, "")

func test_move_card_press_selects_tool_and_stays_full_opacity() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]
	var move_card: HudCard = hud.get_card("move_nucleus")

	session.wallet.set_amount("atp", -50)
	assert_lt(session.wallet.get_amount("atp"), 0)
	hud.refresh_config()
	assert_eq(move_card.modulate.a, 1.0, "Free tool is never dimmed")

	move_card.pressed.emit()
	assert_eq(bc.tool, "move_nucleus")
	assert_true(move_card.is_selected)
	move_card.pressed.emit()
	assert_eq(bc.tool, "")
	assert_false(move_card.is_selected)

func test_refresh_config_adds_and_removes_move_card() -> void:
	var session: Session = _make_session(false)
	var ctx: Dictionary = _make_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]

	session.config.feature_flags["move_nucleus"] = true
	hud.refresh_config()
	await get_tree().process_frame
	assert_not_null(hud.get_card("move_nucleus"))

	bc.select_tool("move_nucleus")
	assert_eq(bc.tool, "move_nucleus")
	session.config.feature_flags["move_nucleus"] = false
	hud.refresh_config()
	await get_tree().process_frame
	assert_null(hud.get_card("move_nucleus"))
	assert_eq(bc.tool, "", "Tool deselects when the flag is switched off")

func test_move_card_icon_draws_without_error() -> void:
	var session: Session = _make_session(true)
	var hud: HudBuild = _make_hud(session)["hud"]
	var move_card: HudCard = hud.get_card("move_nucleus")
	move_card.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(move_card.is_move_nucleus)

# ---------------------------------------------------------------------------
# BuildController move mode
# ---------------------------------------------------------------------------

func test_controller_move_drag_and_release_moves_nucleus() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]
	var atp_before: int = session.wallet.get_amount("atp")

	var events: Array = []
	bc.nucleus_moved.connect(func(from: Vector2i, to: Vector2i) -> void: events.append([from, to]))
	var tool_events: Array[String] = []
	bc.tool_changed.connect(func(t: String) -> void: tool_events.append(t))

	bc.select_tool("move_nucleus")
	assert_eq(bc.tool, "move_nucleus")

	# Grab the bottom-right nucleus cell (21,21); the ghost keeps that grab offset.
	grid_view.cell_pressed.emit(Vector2i(21, 21))
	assert_true(grid_view._has_ghost)
	assert_eq(grid_view._ghost_type_id, "nucleus")
	assert_eq(grid_view._ghost_origin, NUCLEUS_ORIGIN)
	assert_true(grid_view._ghost_valid)

	grid_view.cell_dragged.emit(Vector2i(6, 7))
	assert_eq(grid_view._ghost_origin, Vector2i(3, 4))
	assert_true(grid_view._ghost_valid)
	assert_eq(session.grid.get_structure(1).origin, NUCLEUS_ORIGIN, "Nothing moves until release")

	grid_view.cell_released.emit(Vector2i(6, 7))
	assert_eq(session.grid.get_structure(1).origin, Vector2i(3, 4))
	assert_eq(session.grid.tile_state(Vector2i(18, 18)), GridModel.TileState.EMPTY)
	assert_false(grid_view._has_ghost)
	assert_eq(events, [[NUCLEUS_ORIGIN, Vector2i(3, 4)]])
	assert_eq(session.wallet.get_amount("atp"), atp_before)
	assert_eq(bc.tool, "", "Tool deselects after a successful move")
	assert_eq(tool_events, ["move_nucleus", ""])

func test_controller_ghost_red_when_invalid() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]
	session.grid.place("mucous_wall", Vector2i(10, 10), session.wallet)

	bc.select_tool("move_nucleus")
	grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	grid_view.cell_dragged.emit(Vector2i(0, 5))
	assert_eq(grid_view._ghost_origin, Vector2i(0, 5))
	assert_false(grid_view._ghost_valid, "Ring is red")
	grid_view.cell_dragged.emit(Vector2i(10, 10))
	assert_false(grid_view._ghost_valid, "Wall overlap is red")
	grid_view.cell_dragged.emit(Vector2i(19, 18))
	assert_true(grid_view._ghost_valid, "Overlapping its own cells is green")
	grid_view.cell_dragged.emit(Vector2i(3, 3))
	assert_true(grid_view._ghost_valid)

func test_controller_invalid_release_toasts_and_keeps_nucleus() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]
	session.grid.place("mucous_wall", Vector2i(10, 10), session.wallet)
	var atp_before: int = session.wallet.get_amount("atp")

	var toast: Toast = Toast.new()
	add_child_autofree(toast)
	var reasons: Array[int] = []
	bc.place_failed.connect(func(reason: int) -> void:
		reasons.append(reason)
		toast.show_message(Toast.message_for_place_error(reason))
	)
	var moved_events: Array = []
	bc.nucleus_moved.connect(func(from: Vector2i, to: Vector2i) -> void: moved_events.append([from, to]))

	bc.select_tool("move_nucleus")

	grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	grid_view.cell_dragged.emit(Vector2i(0, 5))
	grid_view.cell_released.emit(Vector2i(0, 5))
	assert_eq(reasons, [int(GridModel.PlaceError.DEPLOY_ZONE)])
	assert_eq(toast.last_message, "The outer ring is reserved for pathogen deployment")
	assert_eq(session.grid.get_structure(1).origin, NUCLEUS_ORIGIN)
	assert_false(grid_view._has_ghost)
	assert_eq(bc.tool, "move_nucleus", "Tool stays selected after a failed drop")

	grid_view.cell_pressed.emit(Vector2i(21, 21))
	grid_view.cell_released.emit(Vector2i(12, 12))
	assert_eq(reasons.back(), int(GridModel.PlaceError.OCCUPIED))
	assert_eq(toast.last_message, "That tile is taken")
	assert_eq(session.grid.get_structure(1).origin, NUCLEUS_ORIGIN)
	_assert_nucleus_cells(session.grid, NUCLEUS_ORIGIN, GridModel.TileState.NUCLEUS)
	assert_eq(moved_events.size(), 0)
	assert_eq(session.wallet.get_amount("atp"), atp_before)

func test_controller_press_off_nucleus_does_not_pick_up() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]
	var reasons: Array[int] = []
	bc.place_failed.connect(func(reason: int) -> void: reasons.append(reason))

	bc.select_tool("move_nucleus")
	grid_view.cell_pressed.emit(Vector2i(4, 4))
	assert_false(grid_view._has_ghost)
	grid_view.cell_dragged.emit(Vector2i(5, 5))
	assert_false(grid_view._has_ghost)
	grid_view.cell_released.emit(Vector2i(5, 5))
	assert_eq(session.grid.get_structure(1).origin, NUCLEUS_ORIGIN)
	assert_eq(reasons.size(), 0)
	assert_eq(bc.tool, "move_nucleus")

func test_controller_release_to_same_spot_deselects_without_event() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]
	var moved_events: Array = []
	bc.nucleus_moved.connect(func(from: Vector2i, to: Vector2i) -> void: moved_events.append([from, to]))

	bc.select_tool("move_nucleus")
	grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	grid_view.cell_released.emit(NUCLEUS_ORIGIN)
	assert_eq(moved_events.size(), 0)
	assert_eq(session.grid.get_structure(1).origin, NUCLEUS_ORIGIN)
	assert_eq(bc.tool, "")

func test_controller_switching_tool_cancels_pickup() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]

	bc.select_tool("move_nucleus")
	grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	assert_true(grid_view._has_ghost)
	bc.select_tool("sell")
	assert_false(grid_view._has_ghost)
	bc.select_tool("move_nucleus")
	grid_view.cell_released.emit(Vector2i(4, 4))
	assert_eq(session.grid.get_structure(1).origin, NUCLEUS_ORIGIN, "A release without a pickup moves nothing")

func test_controller_flag_off_ignores_move_tool() -> void:
	var session: Session = _make_session(false)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]
	var tool_events: Array[String] = []
	bc.tool_changed.connect(func(t: String) -> void: tool_events.append(t))

	bc.select_tool("move_nucleus")
	assert_eq(bc.tool, "")
	assert_eq(tool_events.size(), 0)
	grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	grid_view.cell_released.emit(Vector2i(4, 4))
	assert_eq(session.grid.get_structure(1).origin, NUCLEUS_ORIGIN)

func test_controller_move_logs_nucleus_moved_event() -> void:
	var session: Session = _make_session(true)
	var ctx: Dictionary = _make_controller(session)
	var bc: BuildController = ctx["controller"]
	var grid_view: GridView = ctx["grid_view"]
	var before: int = SessionLogger.all_sessions_text().count("\"event\":\"nucleus_moved\"")

	bc.select_tool("move_nucleus")
	grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	grid_view.cell_released.emit(Vector2i(3, 4))
	# A rejected drop must not log.
	bc.select_tool("move_nucleus")
	grid_view.cell_pressed.emit(Vector2i(3, 4))
	grid_view.cell_released.emit(Vector2i(0, 0))

	var text: String = SessionLogger.all_sessions_text()
	assert_eq(text.count("\"event\":\"nucleus_moved\""), before + 1)
	var found: Dictionary = {}
	for line: String in text.split("\n"):
		if line.contains("\"event\":\"nucleus_moved\""):
			found = JSON.parse_string(line) as Dictionary
	assert_eq(found.get("from"), [18.0, 18.0])
	assert_eq(found.get("to"), [3.0, 4.0])

func test_synthesis_phase_move_flow_and_toast() -> void:
	var session: Session = _make_session(true)
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autofree(fsm)
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)

	assert_not_null(phase.hud_build.get_card("move_nucleus"))
	phase.hud_build.get_card("move_nucleus").pressed.emit()
	assert_eq(phase.build_controller.tool, "move_nucleus")

	phase.grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	phase.grid_view.cell_released.emit(Vector2i(0, 0))
	assert_eq(phase.toast.last_message, "The outer ring is reserved for pathogen deployment")

	phase.grid_view.cell_pressed.emit(NUCLEUS_ORIGIN)
	phase.grid_view.cell_released.emit(Vector2i(6, 6))
	assert_eq(session.grid.get_structure(1).origin, Vector2i(6, 6))
	assert_eq(phase.build_controller.tool, "")
	assert_false(phase.hud_build.get_card("move_nucleus").is_selected)
