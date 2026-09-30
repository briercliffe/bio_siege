extends GutTest

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
	assert_not_null(hud.atp_label)
	assert_eq(hud.atp_label.text, "ATP 1000")
	assert_not_null(hud.btn_back)
	assert_true(hud.btn_back.custom_minimum_size.x >= 48.0)
	assert_true(hud.btn_back.custom_minimum_size.y >= 48.0)
	assert_eq(hud.btn_back.text, "◀ Back to base")

	assert_not_null(hud.title_label)
	assert_eq(hud.title_label.text, "INCUBATION: Build your army")

	assert_not_null(hud.btn_launch)
	assert_true(hud.btn_launch.custom_minimum_size.x >= 48.0)
	assert_true(hud.btn_launch.custom_minimum_size.y >= 48.0)
	assert_eq(hud.btn_launch.text, "Launch Attack")

func test_bottom_tray_card_order_and_sizes() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	# In data/pathogens.json:
	# rhinovirus (10 atp), bacteriophage (40 atp), staphylococcus (100 atp)
	# Then recall card at the end.
	assert_eq(hud.cards.size(), 4)

	var card_rhino: HudSpawnCard = hud.cards[0]
	assert_eq(card_rhino.type_id, "rhinovirus")
	assert_false(card_rhino.is_recall)
	assert_eq(card_rhino.cost_atp, 10)
	assert_eq(card_rhino.custom_minimum_size, Vector2(140.0, 130.0))
	assert_true(card_rhino.btn_minus.custom_minimum_size.x >= 48.0)
	assert_true(card_rhino.btn_minus.custom_minimum_size.y >= 48.0)
	assert_true(card_rhino.btn_plus.custom_minimum_size.x >= 48.0)
	assert_true(card_rhino.btn_plus.custom_minimum_size.y >= 48.0)

	var card_phage: HudSpawnCard = hud.cards[1]
	assert_eq(card_phage.type_id, "bacteriophage")
	assert_false(card_phage.is_recall)
	assert_eq(card_phage.cost_atp, 40)
	assert_eq(card_phage.custom_minimum_size, Vector2(140.0, 130.0))

	var card_staphy: HudSpawnCard = hud.cards[2]
	assert_eq(card_staphy.type_id, "staphylococcus")
	assert_false(card_staphy.is_recall)
	assert_eq(card_staphy.cost_atp, 100)
	assert_eq(card_staphy.custom_minimum_size, Vector2(140.0, 130.0))

	var card_recall: HudSpawnCard = hud.cards[3]
	assert_true(card_recall.is_recall)
	assert_eq(card_recall.type_id, "")
	assert_eq(card_recall.name_label.text, "Recall")
	assert_eq(card_recall.custom_minimum_size, Vector2(140.0, 130.0))

func test_card_plus_and_minus_buttons() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus")
	assert_not_null(card_rhino)

	# Initially reserve count is 0, so minus button is disabled
	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	assert_true(card_rhino.btn_minus.disabled)
	assert_false(card_rhino.btn_plus.disabled)
	assert_eq(card_rhino.count_badge.text, "0 · 0 deployed")

	# Tap plus button: buys 1 rhinovirus (10 ATP)
	card_rhino.btn_plus.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 990)
	assert_eq(session.army.reserve_count("rhinovirus"), 1)
	assert_eq(hud.atp_label.text, "ATP 990")
	assert_eq(card_rhino.count_badge.text, "1 · 0 deployed")
	assert_false(card_rhino.btn_minus.disabled, "Minus button should now be enabled")

	# Tap plus button again: buys 2nd rhinovirus
	card_rhino.btn_plus.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 980)
	assert_eq(session.army.reserve_count("rhinovirus"), 2)
	assert_eq(card_rhino.count_badge.text, "2 · 0 deployed")

	# Tap minus button: unbuys 1 rhinovirus
	card_rhino.btn_minus.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 990)
	assert_eq(session.army.reserve_count("rhinovirus"), 1)
	assert_eq(card_rhino.count_badge.text, "1 · 0 deployed")
	assert_false(card_rhino.btn_minus.disabled)

	# Tap minus button again: unbuys 2nd rhinovirus -> 0 in reserve
	card_rhino.btn_minus.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 1000)
	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	assert_eq(card_rhino.count_badge.text, "0 · 0 deployed")
	assert_true(card_rhino.btn_minus.disabled, "Minus button should be disabled when reserve is 0")

func test_card_plus_disabled_when_cannot_afford() -> void:
	var session: Session = _create_session()
	# Set wallet to 20 ATP
	session.wallet.reset({"atp": 20})
	var hud: HudSpawn = _setup_hud(session)

	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus") # 10 ATP
	var card_phage: HudSpawnCard = hud.get_card("bacteriophage") # 40 ATP
	var card_staphy: HudSpawnCard = hud.get_card("staphylococcus") # 100 ATP

	assert_false(card_rhino.btn_plus.disabled)
	assert_true(card_phage.btn_plus.disabled)
	assert_true(card_staphy.btn_plus.disabled)

	# Buy one rhinovirus -> 10 ATP left
	card_rhino.btn_plus.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 10)
	assert_false(card_rhino.btn_plus.disabled)

	# Buy another rhinovirus -> 0 ATP left
	card_rhino.btn_plus.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 0)
	assert_true(card_rhino.btn_plus.disabled, "Plus should be disabled when wallet cannot afford 10 ATP")

func test_launch_attack_button_enabled_disabled() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	watch_signals(hud)

	# Initially army is empty: Launch button should be disabled with tooltip hint
	assert_true(hud.btn_launch.disabled)
	assert_eq(hud.btn_launch.tooltip_text, "Buy at least one pathogen")

	# Clicking disabled button should not emit launch_requested
	hud.btn_launch.pressed.emit()
	assert_signal_not_emitted(hud, "launch_requested")

	# Buy 1 unit
	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus")
	card_rhino.btn_plus.pressed.emit()
	assert_false(hud.btn_launch.disabled, "Launch button should be enabled once army has >= 1 unit")
	assert_eq(hud.btn_launch.tooltip_text, "")

	# Clicking enabled launch button emits launch_requested
	hud.btn_launch.pressed.emit()
	assert_signal_emitted(hud, "launch_requested")

	# If we unbuy the unit, launch button disables again
	card_rhino.btn_minus.pressed.emit()
	assert_true(hud.btn_launch.disabled)
	assert_eq(hud.btn_launch.tooltip_text, "Buy at least one pathogen")

func test_back_to_base_refunds_all_and_emits_signal() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	watch_signals(hud)

	# Buy several units (10 + 40 + 100 = 150 ATP)
	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus")
	var card_phage: HudSpawnCard = hud.get_card("bacteriophage")
	var card_staphy: HudSpawnCard = hud.get_card("staphylococcus")

	card_rhino.btn_plus.pressed.emit()
	card_phage.btn_plus.pressed.emit()
	card_staphy.btn_plus.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), 850)
	assert_eq(session.army.total_count(), 3)

	# Deploy one unit
	session.army.deploy("rhinovirus", Vector2i(0, 0))
	assert_eq(session.army.reserve_count("rhinovirus"), 0)
	assert_eq(session.army.deployed_count("rhinovirus"), 1)

	# Click Back to base
	hud.btn_back.pressed.emit()

	assert_signal_emitted(hud, "back_requested")
	assert_eq(session.wallet.get_amount("atp"), 1000, "All ATP should be refunded to wallet")
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.army.reserve.size(), 0)
	assert_eq(session.army.deployments.size(), 0)

func test_card_selection_and_recall_tool() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	watch_signals(hud)

	var card_rhino: HudSpawnCard = hud.get_card("rhinovirus")
	var card_phage: HudSpawnCard = hud.get_card("bacteriophage")
	var card_recall: HudSpawnCard = hud.get_recall_card()

	# Tap rhinovirus card body
	card_rhino.pressed.emit()
	assert_signal_emitted_with_parameters(hud, "deploy_type_selected", ["rhinovirus"])
	assert_true(card_rhino.is_card_selected)
	assert_false(card_phage.is_card_selected)
	assert_false(card_recall.is_card_selected)
	assert_false(hud.recall_active)
	assert_eq(hud.selected_type_id, "rhinovirus")

	# Tap recall card
	card_recall.pressed.emit()
	assert_signal_emitted_with_parameters(hud, "recall_tool_selected", [true])
	assert_true(card_recall.is_card_selected)
	assert_false(card_rhino.is_card_selected)
	assert_true(hud.recall_active)
	assert_eq(hud.selected_type_id, "")

	# Tap recall card again to toggle off
	card_recall.pressed.emit()
	assert_signal_emitted_with_parameters(hud, "recall_tool_selected", [false])
	assert_false(card_recall.is_card_selected)
	assert_false(hud.recall_active)

	# Tap bacteriophage card body: selects phage and turns off recall
	card_phage.pressed.emit()
	assert_signal_emitted_with_parameters(hud, "deploy_type_selected", ["bacteriophage"])
	assert_true(card_phage.is_card_selected)
	assert_false(card_rhino.is_card_selected)
	assert_false(card_recall.is_card_selected)
	assert_false(hud.recall_active)
	assert_eq(hud.selected_type_id, "bacteriophage")

func test_side_switch_overlay() -> void:
	var overlay_scene: PackedScene = load("res://src/ui/side_switch_overlay.tscn")
	assert_not_null(overlay_scene)
	var overlay: SideSwitchOverlay = overlay_scene.instantiate() as SideSwitchOverlay
	add_child_autofree(overlay)
	watch_signals(overlay)

	overlay.play(750)
	assert_true(overlay.visible)
	assert_eq(overlay.title_label.text, "Switching sides")
	assert_eq(overlay.subtitle_label.text, "You are now the Pathogen")
	assert_eq(overlay.body_label.text, "Spend your remaining 750 ATP on an army and raid the base you just built.")
	assert_not_null(overlay.background_rect.texture)

	# Simulate tap to dismiss immediately
	overlay.dismiss(true)
	await wait_seconds(0.35)
	assert_false(overlay.visible)
	assert_signal_emitted(overlay, "finished")

func test_incubation_phase_wiring_and_overlay_visibility() -> void:
	var cfg: GameConfig = _load_config()
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autoqfree(fsm)

	# 1. Entering INCUBATION from SYNTHESIS should show SideSwitchOverlay
	fsm.start() # enters SYNTHESIS
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	var ok: bool = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_true(ok)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

	var incubation: IncubationPhase = fsm.current_phase_scene as IncubationPhase
	assert_not_null(incubation)
	assert_not_null(incubation.grid_view)
	assert_true(incubation.grid_view.deploy_mode)
	assert_not_null(incubation.hud_spawn)
	assert_not_null(incubation.toast)
	assert_not_null(incubation.side_switch_overlay)
	assert_true(incubation.side_switch_overlay.visible, "Overlay should be visible when entering from SYNTHESIS")

	# Test hud_spawn.back_requested transitions back to SYNTHESIS
	incubation.hud_spawn.btn_back.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)

	# Re-enter INCUBATION
	ok = fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_true(ok)
	incubation = fsm.current_phase_scene as IncubationPhase

	# Buy a unit and test launch_requested transitions to INFECTION
	incubation.hud_spawn.get_card("rhinovirus").btn_plus.pressed.emit()
	assert_false(incubation.hud_spawn.btn_launch.disabled)
	incubation.hud_spawn.btn_launch.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INFECTION)

	await wait_process_frames(2)


func test_menu_button_size() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)
	assert_not_null(hud.btn_menu)
	assert_true(hud.btn_menu.custom_minimum_size.x >= 48.0)
	assert_true(hud.btn_menu.custom_minimum_size.y >= 48.0)


func test_export_army() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	session.army.buy("rhinovirus", session.wallet)
	session.army.deploy("rhinovirus", Vector2i(0, 5))

	var json_str: String = hud.export_army()
	assert_gt(json_str.length(), 0)

	var parsed: Dictionary = SnapshotIO.parse_army(json_str, session.config)
	assert_true(parsed["ok"])
	assert_eq(hud.last_toast_message, "Army copied to clipboard")


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


func test_predict_button_and_workflow() -> void:
	var session: Session = _create_session()
	var hud: HudSpawn = _setup_hud(session)

	assert_not_null(hud.btn_predict)
	assert_true(hud.btn_predict.custom_minimum_size.y >= 48.0)
	assert_eq(hud.btn_predict.text, "Predict")

	var gv := GridView.new()
	add_child_autoqfree(gv)
	gv.setup(session.grid, session.config, session.army)

	var dc := DeployController.new()
	add_child_autoqfree(dc)
	dc.setup(session, gv, hud)

	# Tap Predict button
	hud.btn_predict.pressed.emit()
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

	# Tap Predict again and tap macrophage cell
	hud.btn_predict.pressed.emit()
	assert_true(hud.predict_active)
	gv.cell_pressed.emit(Vector2i(5, 5))
	assert_eq(session.prediction_structure_id, tower_id)
	assert_eq(gv.predicted_structure_id, tower_id)
	assert_false(hud.predict_active)



func _strain_session(flag_on: bool) -> Session:
	var cfg: GameConfig = _load_config()
	cfg.feature_flags["strains"] = flag_on
	return Session.new(cfg)

func test_no_strain_button_when_flag_off() -> void:
	var hud: HudSpawn = _setup_hud(_strain_session(false))
	for c: HudSpawnCard in hud.cards:
		assert_null(c.find_child("StrainButton", true, false))

func test_strain_button_cycles() -> void:
	var session: Session = _strain_session(true)
	var hud: HudSpawn = _setup_hud(session)
	var card: HudSpawnCard = hud.get_card("rhinovirus")
	var btn: Button = card.find_child("StrainButton", true, false) as Button
	assert_not_null(btn)
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
	var btn: Button = card.find_child("StrainButton", true, false) as Button
	btn.pressed.emit()
	btn.pressed.emit()
	assert_eq(session.army.strain_of("rhinovirus"), "rapid_replication")
	assert_eq(card.cost_label.text, "%d ATP" % int(session.army.unit_cost("rhinovirus")["atp"]))
	assert_true(session.army.buy("rhinovirus", session.wallet))
	btn.pressed.emit()
	assert_eq(session.army.strain_of("rhinovirus"), "rapid_replication")
	assert_eq(hud.last_toast_message, "Remove all %ss to change strain" % session.config.pathogens["rhinovirus"].display_name)
