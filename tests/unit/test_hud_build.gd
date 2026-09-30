extends GutTest

const SAVES_ROOT: String = "user://test_hud_build_saves"

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

func _setup_hud(session: Session) -> Dictionary:
	var grid_view := GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)

	var bc := BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)

	var hud_scene: PackedScene = load("res://src/ui/hud_build.tscn")
	assert_not_null(hud_scene)
	var hud: HudBuild = hud_scene.instantiate() as HudBuild
	add_child_autofree(hud)
	hud.setup(session, bc)

	return {
		"hud": hud,
		"grid_view": grid_view,
		"controller": bc
	}

func test_hud_setup_with_real_session() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]

	assert_eq(hud.session, session)
	assert_eq(hud.controller, bc)
	assert_not_null(hud.atp_label)
	assert_eq(hud.atp_label.text, "ATP 1000")
	assert_not_null(hud.stats_label)
	assert_eq(hud.stats_label.text, "Structures: 0 · Walls: 0")
	assert_not_null(hud.title_label)
	assert_eq(hud.title_label.text, "SYNTHESIS: Build your immune system")
	assert_not_null(hud.btn_finalize)
	assert_true(hud.btn_finalize.custom_minimum_size.y >= 48.0)
	assert_not_null(hud.confirmation_dialog)
	assert_false(hud.confirmation_dialog.visible)

	# Test stats label updates on placing structures
	session.grid.place("mucous_wall", Vector2i(2, 2), session.wallet)
	assert_eq(hud.stats_label.text, "Structures: 0 · Walls: 1")

	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	assert_eq(hud.stats_label.text, "Structures: 1 · Walls: 1")

	session.grid.place("b_cell", Vector2i(7, 3), session.wallet)
	assert_eq(hud.stats_label.text, "Structures: 2 · Walls: 1")

func test_atp_label_updates_on_spend() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	assert_eq(hud.atp_label.text, "ATP 1000")

	var ok: bool = session.wallet.spend({"atp": 150})
	assert_true(ok)
	assert_eq(session.wallet.get_amount("atp"), 850)
	assert_eq(hud.atp_label.text, "ATP 850")

	session.wallet.spend({"atp": 350})
	assert_eq(session.wallet.get_amount("atp"), 500)
	assert_eq(hud.atp_label.text, "ATP 500")

func test_tray_contains_all_buildable_structures_plus_sell() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var buildable_ids: Array[String] = session.config.buildable_structure_ids()
	assert_eq(buildable_ids, ["mucous_wall", "macrophage", "b_cell"])

	var cards: Array[HudCard] = hud.get_cards()
	assert_eq(cards.size(), buildable_ids.size() + 1)

	for i in range(buildable_ids.size()):
		var card: HudCard = cards[i]
		var id: String = buildable_ids[i]
		var sdef: StructureDef = session.config.structures[id]
		assert_eq(card.tool_id, id)
		assert_false(card.is_sell)
		assert_eq(card.cost_atp, int(sdef.cost.get("atp", 0)))
		assert_eq(card.name_label.text, sdef.display_name)
		assert_eq(card.cost_label.text, "%d ATP" % card.cost_atp)
		assert_eq(card.role_label.text, sdef.role)
		assert_true(card.custom_minimum_size.x >= 120.0)
		assert_true(card.custom_minimum_size.y >= 120.0)

	var sell_card: HudCard = cards[cards.size() - 1]
	assert_true(sell_card.is_sell)
	assert_eq(sell_card.tool_id, "sell")
	assert_eq(sell_card.name_label.text, "Sell")
	assert_eq(sell_card.cost_label.text, "Full refund")
	assert_true(sell_card.custom_minimum_size.x >= 120.0)
	assert_true(sell_card.custom_minimum_size.y >= 120.0)

func test_card_selection_synchronizes_with_controller() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]

	var wall_card: HudCard = hud.get_card("mucous_wall")
	var macro_card: HudCard = hud.get_card("macrophage")
	var sell_card: HudCard = hud.get_card("sell")

	assert_not_null(wall_card)
	assert_not_null(macro_card)
	assert_not_null(sell_card)

	assert_false(wall_card.is_selected)
	assert_false(macro_card.is_selected)
	assert_false(sell_card.is_selected)

	bc.select_tool("mucous_wall")
	assert_true(wall_card.is_selected)
	assert_false(macro_card.is_selected)
	assert_false(sell_card.is_selected)

	bc.select_tool("macrophage")
	assert_false(wall_card.is_selected)
	assert_true(macro_card.is_selected)
	assert_false(sell_card.is_selected)

	bc.select_tool("sell")
	assert_false(wall_card.is_selected)
	assert_false(macro_card.is_selected)
	assert_true(sell_card.is_selected)

	bc.select_tool("sell")
	assert_false(wall_card.is_selected)
	assert_false(macro_card.is_selected)
	assert_false(sell_card.is_selected)

	# Test tapping card emits select_tool on controller
	wall_card.emit_signal("pressed")
	assert_eq(bc.tool, "mucous_wall")
	assert_true(wall_card.is_selected)

func test_card_opacity_drops_when_cost_greater_than_balance() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var wall_card: HudCard = hud.get_card("mucous_wall") # 5 ATP
	var macro_card: HudCard = hud.get_card("macrophage")  # 100 ATP
	var bcell_card: HudCard = hud.get_card("b_cell")     # 150 ATP
	var sell_card: HudCard = hud.get_card("sell")        # 0 cost

	assert_eq(wall_card.modulate.a, 1.0)
	assert_eq(macro_card.modulate.a, 1.0)
	assert_eq(bcell_card.modulate.a, 1.0)
	assert_eq(sell_card.modulate.a, 1.0)

	# Spend down to 50 ATP
	session.wallet.spend({"atp": 950})
	assert_eq(session.wallet.get_amount("atp"), 50)

	assert_eq(wall_card.modulate.a, 1.0)
	assert_true(is_equal_approx(macro_card.modulate.a, 0.4))
	assert_true(is_equal_approx(bcell_card.modulate.a, 0.4))
	assert_eq(sell_card.modulate.a, 1.0)

	# Spend down to 4 ATP (below the 5 ATP wall cost)
	session.wallet.spend({"atp": 46})
	assert_eq(session.wallet.get_amount("atp"), 4)

	assert_true(is_equal_approx(wall_card.modulate.a, 0.4))
	assert_true(is_equal_approx(macro_card.modulate.a, 0.4))
	assert_true(is_equal_approx(bcell_card.modulate.a, 0.4))
	assert_eq(sell_card.modulate.a, 1.0)

	# Cards are still clickable when dimmed
	wall_card.emit_signal("pressed")
	assert_eq(hud.controller.tool, "mucous_wall")

func test_finalize_logic_sufficient_atp_emits_finalize_requested() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var emitted := [false]
	hud.finalize_requested.connect(func() -> void: emitted[0] = true)

	assert_true(session.wallet.get_amount("atp") >= hud.get_cheapest_pathogen_cost())

	hud.btn_finalize.emit_signal("pressed")
	assert_true(emitted[0], "finalize_requested should be emitted directly when ATP is sufficient")
	assert_false(hud.confirmation_dialog.visible)

func test_finalize_logic_insufficient_atp_opens_confirmation_dialog() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var finalize_emitted_count := [0]
	hud.finalize_requested.connect(func() -> void: finalize_emitted_count[0] += 1)

	var cheapest: int = hud.get_cheapest_pathogen_cost()
	assert_eq(cheapest, 10)

	# Spend down to 5 ATP (< 10)
	session.wallet.spend({"atp": 995})
	assert_eq(session.wallet.get_amount("atp"), 5)

	# Press finalize button
	hud.btn_finalize.emit_signal("pressed")

	# Confirmation dialog should be open
	assert_true(hud.confirmation_dialog.visible)
	var expected_msg: String = "You have 5 ATP left, which is not enough for any pathogen (cheapest costs 10). Finalize anyway?"
	assert_eq(hud.confirmation_dialog.dialog_text, expected_msg)
	assert_eq(finalize_emitted_count[0], 0, "finalize_requested should not be emitted before confirmation")

	# Click "Keep building"
	hud.confirmation_dialog.get_cancel_button().emit_signal("pressed")
	assert_false(hud.confirmation_dialog.visible)
	assert_eq(finalize_emitted_count[0], 0)

	# Press finalize button again
	hud.btn_finalize.emit_signal("pressed")
	assert_true(hud.confirmation_dialog.visible)

	# Click "Finalize"
	hud.confirmation_dialog.get_ok_button().emit_signal("pressed")
	assert_false(hud.confirmation_dialog.visible)
	assert_eq(finalize_emitted_count[0], 1, "finalize_requested should be emitted after confirmation")

func test_synthesis_phase_wiring_to_fsm() -> void:
	var session: Session = _create_session()
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autofree(fsm)

	var phase_scene: PackedScene = load("res://src/game/phases/synthesis_phase.tscn")
	assert_not_null(phase_scene)
	var phase: SynthesisPhase = phase_scene.instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)

	assert_not_null(phase.hud_build)
	fsm.phase = GameStateMachine.Phase.SYNTHESIS

	phase.hud_build.finalize_requested.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

func test_touch_buttons_minimum_sizes() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	# Finalize button
	assert_true(hud.btn_finalize.custom_minimum_size.x >= 48.0)
	assert_true(hud.btn_finalize.custom_minimum_size.y >= 48.0)

	# Cards
	for card in hud.get_cards():
		assert_true(card.custom_minimum_size.x >= 48.0)
		assert_true(card.custom_minimum_size.y >= 48.0)

	# Dialog buttons
	assert_true(hud.confirmation_dialog.get_ok_button().custom_minimum_size.x >= 48.0)
	assert_true(hud.confirmation_dialog.get_ok_button().custom_minimum_size.y >= 48.0)
	assert_true(hud.confirmation_dialog.get_cancel_button().custom_minimum_size.x >= 48.0)
	assert_true(hud.confirmation_dialog.get_cancel_button().custom_minimum_size.y >= 48.0)

	# Menu button
	assert_not_null(hud.btn_menu)
	assert_true(hud.btn_menu.custom_minimum_size.x >= 48.0)
	assert_true(hud.btn_menu.custom_minimum_size.y >= 48.0)


func test_menu_offers_save_and_import() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_eq(hud.popup_menu.item_count, 2)
	assert_eq(hud.popup_menu.get_item_text(0), "Save base…")
	assert_eq(hud.popup_menu.get_item_text(1), "Import…")
	watch_signals(hud)
	hud.popup_menu.id_pressed.emit(HudBuild.MENU_IMPORT)
	assert_signal_emitted_with_parameters(hud, "library_requested", ["base"])


func test_save_base_asks_for_a_name_and_saves_to_the_library() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	hud.saves_root = SAVES_ROOT
	session.grid.place("mucous_wall", Vector2i(2, 2), session.wallet)
	hud.popup_menu.id_pressed.emit(HudBuild.MENU_SAVE)
	assert_true(hud.save_dialog.visible)
	assert_eq(hud.save_dialog.name_edit.text, "Base 1")
	assert_gte(hud.save_dialog.name_edit.custom_minimum_size.y, 48.0)
	hud.save_dialog.name_edit.text = "Wall test"
	hud.save_dialog.btn_save.pressed.emit()
	assert_false(hud.save_dialog.visible)
	assert_eq(hud.last_toast_message, "Saved 'Wall test'")

	var lib := SaveLibrary.new(SAVES_ROOT)
	var slots: Array[Dictionary] = lib.list("base")
	assert_eq(slots.size(), 1)
	assert_eq(slots[0]["name"], "Wall test")
	var loaded: Dictionary = lib.load_slot(slots[0]["path"], session.config)
	assert_true(loaded["ok"])
	assert_eq(loaded["parsed"]["layout"].size(), session.grid.structures().size())
	hud.open_save_dialog()
	assert_eq(hud.save_dialog.name_edit.text, "Base 2")


func test_save_base_shows_a_full_library_in_the_dialog() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	hud.saves_root = SAVES_ROOT
	var lib := SaveLibrary.new(SAVES_ROOT)
	for i: int in range(SaveLibrary.MAX_SLOTS):
		lib.save_base("Base", session.grid, session.config)
	hud.open_save_dialog()
	var res: Dictionary = hud.save_base("Base 13")
	assert_false(res["ok"])
	assert_true(hud.save_dialog.visible)
	assert_eq(hud.save_dialog.error_label.text, "Library is full (12). Delete a slot first.")


func test_import_base_valid() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var base_dict := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": 40, "height": 40},
		"structures": [
			{"type": "nucleus", "origin": [18, 18]},
			{"type": "mucous_wall", "origin": [3, 3]},
		],
	}
	var json_str: String = SnapshotIO.to_json(base_dict)
	var ok: bool = hud.import_base(json_str)
	assert_true(ok)
	assert_eq(session.grid.structure_id_at(Vector2i(3, 3)) > 0, true)
	assert_eq(hud.last_toast_message, "Base loaded")


func test_import_base_overbudget() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var structures: Array = [
		{"type": "nucleus", "origin": [18, 18]},
	]
	# 12 macrophages * 100 ATP = 1200 ATP > 1000 ATP
	for i in range(12):
		structures.append({"type": "macrophage", "origin": [2, 2 + 3 * i]})

	var base_dict := {
		"format": "bio_siege.base",
		"version": 1,
		"grid": {"width": 40, "height": 40},
		"structures": structures,
	}
	var json_str: String = SnapshotIO.to_json(base_dict)
	var ok: bool = hud.import_base(json_str)
	assert_false(ok)
	assert_true("budget" in hud.import_dialog.error_label.text)


func test_import_base_invalid_json() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var ok: bool = hud.import_base("not a valid json")
	assert_false(ok)
	assert_true(hud.import_dialog.error_label.visible)

