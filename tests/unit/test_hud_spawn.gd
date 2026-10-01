extends GutTest

const SAVES_ROOT: String = "user://test_hud_spawn_saves"

func after_each() -> void:
	_remove_tree(SAVES_ROOT)

static func _remove_tree(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for sub: String in DirAccess.get_directories_at(dir_path):
		_remove_tree("%s/%s" % [dir_path, sub])
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute("%s/%s" % [dir_path, file_name])
	DirAccess.remove_absolute(dir_path)

func _load_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	return res.config

func _create_session() -> Session:
	var cfg: GameConfig = _load_config()
	return Session.new(cfg)

func _setup_hud(session: Session) -> HudSpawn:
	var hud_scene: PackedScene = load("res://src/ui/hud_spawn.tscn")
	assert_not_null(hud_scene)
	var hud: HudSpawn = hud_scene.instantiate() as HudSpawn
	add_child_autofree(hud)
	hud.setup(session)
	return hud

func test_hud_setup_with_real_session() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	assert_eq(hud.session, session)
	assert_eq(hud.atp_label.text, "1000")
	assert_eq(hud.btn_back.text, "Edit base")
	assert_eq(hud.btn_launch.text, "Launch Attack")
	assert_eq(hud.phase_pill.get_child(0).get_child(0).text, "PHASE 2 · INCUBATION")
	assert_eq(hud.phase_pill.get_child(0).get_child(1).text, "Deploy your army")
	assert_true(hud.phase_pill.night)
	assert_true(hud.left_card.night and hud.right_card.night)
	assert_eq(hud.theme.resource_path, "res://src/ui/theme_night.tres")

func test_every_button_is_at_least_48_by_48() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	var buttons: Array[Button] = [hud.btn_back, hud.btn_launch, hud.btn_menu]
	for id: Variant in hud.menu_buttons.keys():
		buttons.append(hud.menu_button(int(id)))
	for card: HudSpawnCard in hud.cards:
		buttons.append(card.plus_button)
		buttons.append(card.minus_button)
	for b: Button in buttons:
		assert_gte(b.custom_minimum_size.x, 48.0, b.name)
		assert_gte(b.custom_minimum_size.y, 48.0, b.name)
	for card: HudSpawnCard in hud.cards:
		assert_gte(card.custom_minimum_size.y, 48.0)

func test_top_bar_layout_does_not_overlap() -> void:
	var session: Session = _create_session()
	var holder := Control.new()
	holder.size = Vector2(1280.0, 720.0)
	add_child_autofree(holder)
	var hud: HudSpawn = (load("res://src/ui/hud_spawn.tscn") as PackedScene).instantiate() as HudSpawn
	holder.add_child(hud)
	hud.setup(session)
	await wait_process_frames(2)
	var menu_rect: Rect2 = hud.btn_menu.get_global_rect()
	assert_gt(menu_rect.position.x, hud.phase_pill.get_global_rect().end.x, "Menu sits right after the phase pill")
	assert_lt(menu_rect.end.x, hud.btn_back.get_global_rect().position.x, "...and clear of Edit base")
	assert_eq(hud.btn_back.get_global_rect().size, Vector2(112.0, 52.0))
	assert_eq(hud.btn_launch.get_global_rect().size, Vector2(164.0, 52.0))
	assert_eq(hud.right_card.get_global_rect().end.x, 1260.0)
	assert_eq(hud.left_card.get_global_rect().position, Vector2(20.0, 96.0))

func test_bottom_tray_card_order_and_sizes() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	# In data/pathogens.json:
	# rhinovirus (10 atp), bacteriophage (40 atp), staphylococcus (100 atp), in cost order.
	assert_eq(hud.cards.size(), 3)
	var expected: Array[String] = ["rhinovirus", "bacteriophage", "staphylococcus"]
	var costs: Array[int] = [10, 40, 100]
	for i: int in range(3):
		assert_eq(hud.cards[i].type_id, expected[i])
		assert_eq(hud.cards[i].cost_atp, costs[i])
		assert_eq(hud.cards[i].cost_label.text, "%d ATP" % costs[i])
		assert_eq(hud.cards[i].custom_minimum_size, Vector2(330.0, 72.0))
		assert_true(hud.cards[i].night)
	assert_eq(hud.tray.get_child_count(), 3)

func test_card_plus_and_minus_buttons() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus")
	assert_not_null(card_rhino)

	# Initially nothing is owned, so minus is disabled
	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	assert_true(card_rhino.minus_button.disabled)
	assert_false(card_rhino.plus_button.disabled)
	assert_eq(card_rhino.count, 0)

	# Tap plus: buys 1 rhinovirus (10 ATP)
	card_rhino.plus_button.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 990)
	assert_eq(session.army.reserve_count("rhinovirus"), 1)
	assert_eq(hud.atp_label.text, "990")
	assert_eq(card_rhino.count, 1)
	assert_false(card_rhino.minus_button.disabled, "Minus button should now be enabled")

	card_rhino.plus_button.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 980)
	assert_eq(card_rhino.count, 2)

	# Tap minus: unbuys 1 rhinovirus
	card_rhino.minus_button.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 990)
	assert_eq(session.army.reserve_count("rhinovirus"), 1)
	assert_eq(card_rhino.count, 1)

	card_rhino.minus_button.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 1000)
	assert_eq(card_rhino.count, 0)
	assert_true(card_rhino.minus_button.disabled, "Minus button should be disabled at 0")

func test_card_count_is_reserve_plus_deployed() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	for i: int in range(5):
		session.army.buy("rhinovirus", session.wallet)
	for i: int in range(3):
		session.army.deploy("rhinovirus", Vector2i(0, i))
	var card: HudSpawnCard = hud.get_card("rhinovirus")
	assert_eq(card.count, 5)
	assert_false(card.minus_button.disabled, "Two units are still in the reserve")
	session.army.deploy("rhinovirus", Vector2i(0, 3))
	session.army.deploy("rhinovirus", Vector2i(0, 4))
	assert_eq(card.count, 5)
	assert_true(card.minus_button.disabled, "Nothing in the reserve to take back")

func test_card_plus_disabled_when_cannot_afford() -> void:
	var session: Session = _create_session()
	session.wallet.reset({"atp": 20})
	var hud: HudSpawn = _setup_hud(session)

	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus") # 10 ATP
	var card_phage: HudSpawnCard = hud.get_card("bacteriophage") # 40 ATP
	var card_staphy: HudSpawnCard = hud.get_card("staphylococcus") # 100 ATP

	assert_false(card_rhino.plus_button.disabled)
	assert_true(card_phage.plus_button.disabled)
	assert_true(card_staphy.plus_button.disabled)

	card_rhino.plus_button.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 10)
	assert_false(card_rhino.plus_button.disabled)

	card_rhino.plus_button.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 0)
	assert_true(card_rhino.plus_button.disabled, "Plus should be disabled when wallet cannot afford 10 ATP")

func test_launch_is_visible_but_disabled_with_an_empty_army() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	watch_signals(hud)

	assert_true(hud.btn_launch.visible, "Launch stays visible")
	assert_true(hud.btn_launch.disabled)
	assert_eq(hud.btn_launch.tooltip_text, "Buy at least one pathogen")

	hud.btn_launch.pressed.emit()
	assert_signal_not_emitted(hud, "launch_requested")

	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus")
	card_rhino.plus_button.pressed.emit()
	assert_false(hud.btn_launch.disabled, "Launch is enabled once the army has a unit")
	assert_eq(hud.btn_launch.tooltip_text, "")

	hud.btn_launch.pressed.emit()
	assert_signal_emitted(hud, "launch_requested")

	card_rhino.minus_button.pressed.emit()
	assert_true(hud.btn_launch.disabled)
	assert_eq(hud.btn_launch.tooltip_text, "Buy at least one pathogen")

func test_edit_base_refunds_all_and_emits_signal() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	watch_signals(hud)

	# Buy several units (10 + 40 + 100 = 150 ATP)
	hud.get_card("rhinovirus").plus_button.pressed.emit()
	hud.get_card("bacteriophage").plus_button.pressed.emit()
	hud.get_card("staphylococcus").plus_button.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 850)
	assert_eq(session.army.total_count(), 3)

	session.army.deploy("rhinovirus", Vector2i(0, 0))
	assert_eq(session.army.deployed_count("rhinovirus"), 1)

	hud.btn_back.pressed.emit()

	assert_signal_emitted(hud, "back_requested")
	assert_eq(session.wallet.get_amount("atp"), 1000, "All ATP should be refunded to wallet")
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.army.reserve.size(), 0)
	assert_eq(session.army.deployments.size(), 0)

func test_card_selection_toggles_and_drives_the_left_card() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	watch_signals(hud)

	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus")
	var card_phage: HudSpawnCard = hud.get_card("bacteriophage")
	assert_true(hud.turn_box.visible, "Your turn shows while nothing is selected")
	assert_false(hud.unit_box.visible)

	card_rhino.selected.emit()
	assert_signal_emitted_with_parameters(hud, "deploy_type_selected", ["rhinovirus"])
	assert_true(card_rhino.is_card_selected)
	assert_false(card_phage.is_card_selected)
	assert_eq(hud.selected_type_id, "rhinovirus")
	assert_true(hud.unit_box.visible)
	assert_false(hud.turn_box.visible)

	card_phage.selected.emit()
	assert_signal_emitted_with_parameters(hud, "deploy_type_selected", ["bacteriophage"])
	assert_true(card_phage.is_card_selected)
	assert_false(card_rhino.is_card_selected)
	assert_eq(hud.unit_name_label.text, "Bacteriophage")

	card_phage.selected.emit()
	assert_signal_emitted_with_parameters(hud, "deploy_type_selected", [""])
	assert_false(card_phage.is_card_selected)
	assert_eq(hud.selected_type_id, "")
	assert_true(hud.turn_box.visible)

func test_your_turn_card_quotes_the_budget() -> void:
	var session: Session = _create_session()
	session.wallet.reset({"atp": 240})
	var hud: HudSpawn = _setup_hud(session)
	var expected: String = "Spend the 240 ATP you kept on an army, then break your own defense."
	assert_eq(hud.turn_title_label.text, "You are the pathogen now.")
	assert_eq(hud.turn_body_label.get_parsed_text(), expected)
	hud.get_card("rhinovirus").plus_button.pressed.emit()
	assert_eq(hud.turn_body_label.get_parsed_text(), expected, "N is the wallet at the start of Incubation")

func test_unit_card_shows_rhinovirus_stats() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	hud.get_card("rhinovirus").selected.emit()
	assert_eq(hud.unit_name_label.text, "Rhinovirus")
	assert_eq(hud.unit_role_label.text, "Fast swarm")
	var health: StatTile = hud.unit_tiles["health"] as StatTile
	var speed: StatTile = hud.unit_tiles["speed"] as StatTile
	var damage: StatTile = hud.unit_tiles["damage"] as StatTile
	var cost: StatTile = hud.unit_tiles["cost"] as StatTile
	assert_eq("%s %s" % [health.label_text(), health.value_text()], "Health 30")
	assert_eq("%s %s" % [speed.label_text(), speed.value_text()], "Speed 2.8 tiles/s", "1.4 in the JSON times grid_scale 2")
	assert_eq("%s %s" % [damage.label_text(), damage.value_text()], "Damage 6 / 0.5 s")
	assert_eq("%s %s" % [cost.label_text(), cost.value_text()], "Cost 10 ATP")
	assert_true(cost.accent_value, "The cost is green")
	assert_eq(hud.unit_desc_label.text, "Heads for the nearest structure. Quick and cheap, but Macrophage splash shreds them.")

func test_unit_card_description_builds_the_bacteriophage_multiplier_from_config() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	hud.get_card("bacteriophage").selected.emit()
	assert_eq(hud.unit_desc_label.text, "Hunts defenses first and hits them three times as hard. Fragile, so send it behind a tank.")
	session.config.pathogens["bacteriophage"].damage_multipliers_pct["defense"] = 200
	hud.refresh_config()
	assert_eq(hud.unit_desc_label.text, "Hunts defenses first and hits them twice as hard. Fragile, so send it behind a tank.")
	hud.get_card("staphylococcus").selected.emit()
	assert_eq(hud.unit_desc_label.text, "Soaks up damage while the swarm gets through. Slow, so give it a head start.")

func test_army_card_is_empty_until_a_unit_is_bought() -> void:
	var session: Session = _create_session()
	session.wallet.reset({"atp": 240})
	var hud: HudSpawn = _setup_hud(session)
	assert_true(hud.empty_block.visible)
	assert_false(hud.owned_block.visible)
	assert_eq(hud.spent_text(), "Spent 0")
	assert_eq(hud.spent_total_label.text, "of 240 ATP")
	assert_eq(hud.spent_track.value, 0.0)
	hud.get_card("rhinovirus").plus_button.pressed.emit()
	assert_false(hud.empty_block.visible)
	assert_true(hud.owned_block.visible)

func test_army_card_lists_owned_types_with_deployed_of_owned() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	for i: int in range(5):
		session.army.buy("rhinovirus", session.wallet)
	for i: int in range(3):
		session.army.deploy("rhinovirus", Vector2i(0, i))
	assert_eq(hud.army_row_text("rhinovirus"), "3 of 5 out")
	assert_eq(hud.army_row_text("bacteriophage"), "", "Types that are not owned have no row")
	assert_eq(hud.deployed_text(), "Deployed 3")
	assert_eq(hud.deployed_total_label.text, "of 5 units")
	assert_almost_eq(hud.deployed_track.value, 0.6, 0.001)

	session.army.buy("bacteriophage", session.wallet)
	session.army.buy("bacteriophage", session.wallet)
	session.army.deploy("bacteriophage", Vector2i(1, 0))
	assert_eq(hud.army_row_text("bacteriophage"), "1 of 2 out")
	assert_eq(hud.deployed_text(), "Deployed 4")
	assert_eq(hud.deployed_total_label.text, "of 7 units")
	assert_eq(hud.rows_box.get_child_count(), 2)

func test_incubation_phase_wiring_and_overlay_visibility() -> void:
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)

	# 1. Entering INCUBATION from SYNTHESIS should show SideSwitchOverlay
	fsm.start() # enters TITLE
	fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	var ok: bool = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

	var incubation: IncubationPhase = fsm.current_phase_scene as IncubationPhase
	assert_not_null(incubation)
	assert_not_null(incubation.grid_view)
	assert_true(incubation.grid_view.deploy_mode)
	assert_true(incubation.grid_view.night)
	assert_not_null(incubation.hud_spawn)
	assert_not_null(incubation.toast)
	assert_not_null(incubation.side_switch_overlay)
	assert_true(incubation.background.night)
	assert_true(incubation.side_switch_overlay.visible, "Overlay should be visible when entering from SYNTHESIS")

	# Test hud_spawn.back_requested transitions back to SYNTHESIS
	incubation.hud_spawn.btn_back.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	# Re-enter INCUBATION
	ok = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_true(ok)
	incubation = fsm.current_phase_scene as IncubationPhase

	# Buy a unit and test launch_requested transitions to INFECTION
	incubation.hud_spawn.get_card("rhinovirus").plus_button.pressed.emit()
	assert_false(incubation.hud_spawn.btn_launch.disabled)
	incubation.hud_spawn.btn_launch.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)

	await wait_process_frames(2)

func test_incubation_island_fits_between_the_cards() -> void:
	var session: Session = _create_session()
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)
	var holder := Control.new()
	holder.size = Vector2(1280.0, 720.0)
	add_child_autofree(holder)
	var phase: IncubationPhase = (load("res://src/game/phases/incubation_phase.tscn") as PackedScene).instantiate() as IncubationPhase
	holder.add_child(phase)
	phase.setup(session, fsm)
	await wait_process_frames(2)
	var island: Vector2 = phase.grid_view.projection.island_size(session.grid.width, session.grid.height)
	assert_lte(island.x, 640.5, "The island fits the 640 px between the cards")
	assert_lte(island.y, 520.5)
	assert_gt(phase.grid_view.projection.origin.x, 320.0)
	assert_lt(phase.grid_view.projection.origin.x, 960.0)

func test_menu_sheet_offers_every_item() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	assert_false(hud.menu_open())
	hud.btn_menu.pressed.emit()
	assert_true(hud.menu_open())
	var texts: Array[String] = []
	for id: int in [HudSpawn.MENU_HOW_TO_PLAY, HudSpawn.MENU_SOUND, HudSpawn.MENU_PREDICT, HudSpawn.MENU_SAVE,
			HudSpawn.MENU_IMPORT, HudSpawn.MENU_SETTINGS, HudSpawn.MENU_QUIT]:
		texts.append(hud.menu_button(id).text)
	assert_eq(texts, ["How to play", "Sound: On", "Predict first to fall", "Save army…", "Import…", "Settings", "Quit to title"] as Array[String])
	hud.btn_menu.pressed.emit()
	assert_false(hud.menu_open())

func test_menu_items_emit_their_signals() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	watch_signals(hud)
	hud.open_menu()
	hud.menu_button(HudSpawn.MENU_HOW_TO_PLAY).pressed.emit()
	assert_signal_emit_count(hud, "help_requested", 1)
	assert_false(hud.menu_open(), "Choosing an item closes the sheet")
	hud.menu_button(HudSpawn.MENU_SETTINGS).pressed.emit()
	assert_signal_emit_count(hud, "settings_requested", 1)
	hud.menu_button(HudSpawn.MENU_QUIT).pressed.emit()
	assert_signal_emit_count(hud, "quit_requested", 1)
	hud.menu_button(HudSpawn.MENU_IMPORT).pressed.emit()
	assert_signal_emitted_with_parameters(hud, "library_requested", ["army"])

func test_save_army_asks_for_a_name_and_saves_to_the_library() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	hud.saves_root = SAVES_ROOT
	session.army.buy("rhinovirus", session.wallet)
	session.army.deploy("rhinovirus", Vector2i(0, 5))
	hud.menu_button(HudSpawn.MENU_SAVE).pressed.emit()
	assert_true(hud.save_dialog.visible)
	assert_eq(hud.save_dialog.name_edit.text, "Army 1")
	hud.save_dialog.btn_save.pressed.emit()
	assert_false(hud.save_dialog.visible)
	assert_eq(hud.last_toast_message, "Saved 'Army 1'")

	var lib := SaveLibrary.new(SAVES_ROOT)
	var slots: Array[Dictionary] = lib.list("army")
	assert_eq(slots.size(), 1)
	var parsed: Dictionary = SnapshotIO.parse_army(lib.export_json(slots[0]["path"]), session.config)
	assert_true(parsed["ok"])
	assert_eq(parsed["units"].size(), 1)

func test_import_army_success() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	var army_dict := {
		"format": "bio_siege.army",
		"version": 1,
		"units": [
			{"type": "rhinovirus", "cell": [0, 0]},
			{"type": "rhinovirus", "cell": [1, 0]},
		],
	}
	var json_str: String = SnapshotIO.to_json(army_dict)
	var ok: bool = hud.import_army(json_str)
	assert_true(ok)
	assert_eq(session.army.deployments.size(), 2)
	assert_eq(hud.last_toast_message, "Army loaded")

func test_import_army_partial_fit() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	# Reduce wallet to 15 ATP
	session.wallet.spend({"atp": 985})
	assert_eq(session.wallet.get_amount("atp"), 15)

	# 2 rhinovirus cost 20 ATP > 15 ATP
	var army_dict := {
		"format": "bio_siege.army",
		"version": 1,
		"units": [
			{"type": "rhinovirus", "cell": [0, 0]},
			{"type": "rhinovirus", "cell": [1, 0]},
		],
	}
	var json_str: String = SnapshotIO.to_json(army_dict)
	var ok: bool = hud.import_army(json_str)
	assert_true(ok)
	assert_eq(session.army.deployments.size(), 1)
	assert_eq(hud.last_toast_message, "Only 1 of 2 units fit your ATP")

func test_predict_menu_item_and_workflow() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	var gv := GridView.new()
	add_child_autoqfree(gv)
	gv.setup(session.grid, session.config, session.army)

	var dc := DeployController.new()
	add_child_autoqfree(dc)
	dc.setup(session, gv, hud)

	# Choose "Predict first to fall" in the menu
	hud.menu_button(HudSpawn.MENU_PREDICT).pressed.emit()
	assert_true(hud.predict_active)
	assert_true(dc.predict_mode)
	assert_eq(hud.last_toast_message, "Tap the structure you think falls first")

	# Tapping nucleus cell sets prediction
	var nucleus_cell: Vector2i = session.grid.default_nucleus_origin()
	var nucleus_id: int = session.grid.structure_id_at(nucleus_cell)
	assert_gt(nucleus_id, 0)

	gv.cell_pressed.emit(nucleus_cell)
	assert_eq(session.prediction_structure_id, nucleus_id)
	assert_eq(gv.predicted_structure_id, nucleus_id)
	assert_false(hud.predict_active, "Predict mode should exit after structure tap")
	assert_false(dc.predict_mode)

	# Place another structure and test replacing prediction
	var tower_id: int = session.grid.place("macrophage", Vector2i(5, 5), session.wallet)
	assert_gt(tower_id, 0)

	hud.menu_button(HudSpawn.MENU_PREDICT).pressed.emit()
	assert_true(hud.predict_active)
	gv.cell_pressed.emit(Vector2i(5, 5))
	assert_eq(session.prediction_structure_id, tower_id)
	assert_eq(gv.predicted_structure_id, tower_id)
	assert_false(hud.predict_active)

	# Choosing it twice turns it back off
	hud.menu_button(HudSpawn.MENU_PREDICT).pressed.emit()
	hud.menu_button(HudSpawn.MENU_PREDICT).pressed.emit()
	assert_false(hud.predict_active)

func _strain_session(flag_on: bool) -> Session:
	var cfg: GameConfig = _load_config()
	cfg.feature_flags["strains"] = flag_on
	return Session.new(cfg)

func test_no_strain_button_when_flag_off() -> void:
	var hud: HudSpawn = _setup_hud(_strain_session(false))
	hud.get_card("rhinovirus").selected.emit()
	assert_false(hud.strain_button.visible)

func test_strain_button_cycles() -> void:
	var session: Session = _strain_session(true)
	var hud: HudSpawn = _setup_hud(session)
	hud.get_card("rhinovirus").selected.emit()
	var btn: PillButton = hud.strain_button
	assert_true(btn.visible)
	assert_true(btn.custom_minimum_size.y >= 48.0)
	var def: PathogenDef = session.config.pathogens["rhinovirus"]
	var expected: Array[String] = ["capsid_hardening", "rapid_replication", "antigenic_masking", "wild"]
	for v: String in expected:
		btn.pressed.emit()
		assert_eq(session.army.strain_of("rhinovirus"), v)
		assert_eq(btn.text, def.strain(v).display_name)

func test_strain_button_refused_with_units_and_cost_label() -> void:
	var session: Session = _strain_session(true)
	var hud: HudSpawn = _setup_hud(session)
	var card: HudSpawnCard = hud.get_card("rhinovirus")
	card.selected.emit()
	var btn: PillButton = hud.strain_button
	btn.pressed.emit()
	btn.pressed.emit()
	assert_eq(session.army.strain_of("rhinovirus"), "rapid_replication")
	assert_eq(card.cost_label.text, "%d ATP" % int(session.army.unit_cost("rhinovirus")["atp"]))
	assert_true(session.army.buy("rhinovirus", session.wallet))
	btn.pressed.emit()
	assert_eq(session.army.strain_of("rhinovirus"), "rapid_replication")
	assert_eq(hud.last_toast_message, "Remove all %ss to change strain" % session.config.pathogens["rhinovirus"].display_name)
