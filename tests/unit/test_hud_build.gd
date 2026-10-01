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


func _find_buttons(node: Node, out: Array[BaseButton]) -> void:
	for child: Node in node.get_children():
		if child is BaseButton:
			out.append(child as BaseButton)
		_find_buttons(child, out)


func _all_labels_text(node: Node) -> String:
	var text: String = ""
	if node is Label:
		text += (node as Label).text + "\n"
	for child: Node in node.get_children():
		text += _all_labels_text(child)
	return text

func test_hud_setup_with_real_session() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]

	assert_eq(hud.session, session)
	assert_eq(hud.controller, bc)
	assert_not_null(hud.atp_label)
	assert_eq(hud.atp_label.text, "1000")
	assert_not_null(hud.phase_pill)
	assert_string_contains(_all_labels_text(hud.phase_pill), "PHASE 1 · SYNTHESIS")
	assert_string_contains(_all_labels_text(hud.phase_pill), "Build your defense")
	assert_not_null(hud.btn_finalize)
	assert_eq(hud.btn_finalize.text, "Finalize Base")
	assert_eq(hud.btn_finalize.variant, PillButton.Variant.PRIMARY)
	assert_true(hud.btn_finalize.custom_minimum_size.y >= 48.0)
	assert_not_null(hud.confirmation_dialog)
	assert_false(hud.confirmation_dialog.visible)

func test_atp_label_updates_on_spend() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	assert_eq(hud.atp_label.text, "1000")

	var ok: bool = session.wallet.spend({"atp": 150})
	assert_true(ok)
	assert_eq(session.wallet.get_amount("atp"), 850)
	assert_eq(hud.atp_label.text, "850")

	session.wallet.spend({"atp": 350})
	assert_eq(session.wallet.get_amount("atp"), 500)
	assert_eq(hud.atp_label.text, "500")

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
		assert_eq(card.title, sdef.display_name)
		assert_eq(card.cost_text, "%d ATP" % card.cost_atp)
		assert_eq(card.icon_id, id)
		assert_eq(card.custom_minimum_size, TrayCard.ITEM_SIZE)

	var sell_card: HudCard = cards[cards.size() - 1]
	assert_true(sell_card.is_sell)
	assert_eq(sell_card.tool_id, "sell")
	assert_eq(sell_card.title, "Sell")
	assert_eq(sell_card.subtitle, "Nothing to sell")
	assert_eq(sell_card.custom_minimum_size, TrayCard.SELL_SIZE)

	session.grid.place("mucous_wall", Vector2i(2, 2), session.wallet)
	assert_eq(sell_card.subtitle, "100% refund")
	session.grid.sell(session.grid.structure_id_at(Vector2i(2, 2)), session.wallet)
	assert_eq(sell_card.subtitle, "Nothing to sell")

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
	assert_eq(wall_card.border_width(), 3)
	assert_eq(macro_card.border_width(), 2)

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

	# Tapping a card selects the tool on the controller
	wall_card.emit_signal("pressed")
	assert_eq(bc.tool, "mucous_wall")
	assert_true(wall_card.is_selected)

func test_unaffordable_cards_are_muted_and_not_tappable() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]

	var wall_card: HudCard = hud.get_card("mucous_wall") # 5 ATP
	var macro_card: HudCard = hud.get_card("macrophage")  # 100 ATP
	var bcell_card: HudCard = hud.get_card("b_cell")     # 150 ATP
	var sell_card: HudCard = hud.get_card("sell")        # 0 cost

	for c: HudCard in [wall_card, macro_card, bcell_card, sell_card]:
		assert_true(c.affordable)
		assert_false(c.disabled)

	# Spend down to 50 ATP
	session.wallet.spend({"atp": 950})
	assert_eq(session.wallet.get_amount("atp"), 50)

	assert_true(wall_card.affordable)
	assert_false(macro_card.affordable)
	assert_true(macro_card.disabled)
	assert_false(bcell_card.affordable)
	assert_true(sell_card.affordable)
	assert_true(is_equal_approx(macro_card.self_modulate.a, 0.55))

	# Spend down to 4 ATP (below the 5 ATP wall cost)
	session.wallet.spend({"atp": 46})
	assert_eq(session.wallet.get_amount("atp"), 4)
	assert_false(wall_card.affordable)
	assert_true(sell_card.affordable)

	# Refunds make them tappable again
	session.wallet.refund({"atp": 996})
	assert_true(bcell_card.affordable)
	assert_false(bcell_card.disabled)

# --- left card -------------------------------------------------------------------------------------

func test_left_card_shows_getting_started_until_a_tool_is_selected() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]

	assert_true(hud.start_box.visible)
	assert_false(hud.selection_box.visible)
	assert_eq(hud.start_title_label.text, "Protect the Nucleus.")
	var text: String = _all_labels_text(hud.start_box)
	assert_string_contains(text, "GETTING STARTED")
	assert_string_contains(text, "Pick a structure below.")
	assert_string_contains(text, "Tap the island to place it.")
	assert_string_contains(text, "Use Sell to take any piece back for a full refund.")

	bc.select_tool("b_cell")
	assert_false(hud.start_box.visible)
	assert_true(hud.selection_box.visible)
	assert_eq(hud.selection_name_label.text, "B-Cell")
	assert_eq(hud.selection_role_label.text, "Sniper, 12-tile range")
	var interval: StatTile = hud.selection_tiles["interval"]
	assert_eq(interval.label_text(), "Fire interval")
	assert_eq(interval.value_text(), "1.2 s")
	var footprint: StatTile = hud.selection_tiles["footprint"]
	assert_eq(footprint.label_text(), "Footprint")
	assert_eq(footprint.value_text(), "3 × 3")
	var bcell: StructureDef = session.config.structures["b_cell"]
	assert_eq((hud.selection_tiles["health"] as StatTile).value_text(), str(bcell.hp))
	assert_eq((hud.selection_tiles["damage"] as StatTile).value_text(), str(bcell.attack_damage))
	assert_eq(hud.cost_badge_label.text, "150 ATP")
	assert_true(hud.cost_badge.visible)
	assert_eq(hud.selection_desc_label.text, UnitCopy.description("b_cell"))

	bc.select_tool("b_cell")
	assert_true(hud.start_box.visible, "deselecting returns to Getting started")

func test_selection_card_shows_dashes_for_a_wall() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]
	bc.select_tool("mucous_wall")
	assert_eq(hud.selection_name_label.text, "Mucous Wall")
	assert_eq((hud.selection_tiles["damage"] as StatTile).value_text(), "—")
	assert_eq((hud.selection_tiles["interval"] as StatTile).value_text(), "—")
	assert_eq((hud.selection_tiles["footprint"] as StatTile).value_text(), "1 × 1")
	assert_eq(hud.cost_badge_label.text, "5 ATP")

func test_selection_card_for_sell_and_move_tools() -> void:
	var session: Session = _create_session()
	session.config.feature_flags["move_nucleus"] = true
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]
	bc.select_tool("sell")
	assert_true(hud.selection_box.visible)
	assert_eq(hud.selection_name_label.text, "Sell")
	assert_eq(hud.selection_desc_label.text, "Tap any of your pieces for a 100% refund. The Nucleus can't be sold.")
	assert_false(hud.tile_grid.visible)
	assert_false(hud.cost_badge.visible)
	bc.select_tool(BuildController.TOOL_MOVE_NUCLEUS)
	assert_eq(hud.selection_name_label.text, "Move Nucleus")
	assert_eq(hud.selection_desc_label.text, "Drag the Nucleus to a new spot. It's free.")

func test_unit_copy_covers_the_structures() -> void:
	for id: String in ["mucous_wall", "macrophage", "b_cell", "nucleus"]:
		assert_ne(UnitCopy.description(id), "", id)
	assert_eq(UnitCopy.description("nothing"), "")

# --- right card ---------------------------------------------------------------------------------------

func test_status_card_on_a_new_base() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_eq(hud.spent_text(), "Spent 0")
	assert_eq(hud.spent_total_label.text, "of 1000 ATP")
	assert_eq(hud.spent_track.value, 0.0)
	assert_false(hud.stays_label.visible)
	assert_eq(hud.tiles_text(), "Tiles used 16 of 1296")
	assert_eq(hud.chips.size(), 0)
	assert_true(hud.empty_legend.visible)
	assert_false(hud.placing_legend.visible)
	assert_string_contains(_all_labels_text(hud.empty_legend), "The Nucleus is free. Destroy it to win.")
	assert_string_contains(_all_labels_text(hud.empty_legend), "The outer band is the deploy zone.")

func test_tiles_used_counts_the_nucleus_and_every_piece() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_eq(session.grid.buildable_cell_count(), 1296)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	assert_eq(hud.tiles_text(), "Tiles used 25 of 1296")
	session.grid.place("mucous_wall", Vector2i(10, 10), session.wallet)
	assert_eq(hud.tiles_text(), "Tiles used 26 of 1296")
	assert_false(hud.empty_legend.visible)

func test_status_card_after_spending() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	session.wallet.spend({"atp": 610})
	assert_eq(hud.spent_text(), "Spent 610")
	assert_almost_eq(hud.spent_track.value, 0.61, 0.001)
	assert_true(hud.stays_label.visible)
	assert_eq(hud.stays_label.text, "390 ATP stays as your attack budget.")

func test_status_chips_count_and_pluralise() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	for i: int in range(3):
		session.grid.place("mucous_wall", Vector2i(10 + i, 10), session.wallet)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.grid.place("macrophage", Vector2i(3, 8), session.wallet)
	session.grid.place("b_cell", Vector2i(8, 3), session.wallet)
	assert_eq(hud.chip_text("mucous_wall"), "3 Walls")
	assert_eq(hud.chip_text("macrophage"), "2 Macrophages")
	assert_eq(hud.chip_text("b_cell"), "1 B-Cell")
	assert_eq(hud.chip_text("nucleus"), "", "the Nucleus has no chip")
	assert_eq(hud.chips.size(), 3)
	session.grid.sell(session.grid.structure_id_at(Vector2i(10, 10)), session.wallet)
	assert_eq(hud.chip_text("mucous_wall"), "2 Walls")
	session.grid.sell(session.grid.structure_id_at(Vector2i(3, 8)), session.wallet)
	assert_eq(hud.chip_text("macrophage"), "1 Macrophage")
	session.grid.sell(session.grid.structure_id_at(Vector2i(8, 3)), session.wallet)
	assert_eq(hud.chip_text("b_cell"), "")

func test_status_legend_follows_the_tool() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var bc: BuildController = ctx["controller"]
	bc.select_tool("b_cell")
	assert_true(hud.placing_legend.visible)
	assert_false(hud.empty_legend.visible)
	assert_string_contains(_all_labels_text(hud.placing_legend), "Green: you can build here")
	assert_string_contains(_all_labels_text(hud.placing_legend), "Red: blocked or too expensive")
	bc.select_tool("b_cell")
	assert_false(hud.placing_legend.visible)
	assert_true(hud.empty_legend.visible)

# --- finalize dialog ------------------------------------------------------------------------------------

func test_finalize_button_opens_the_dialog_with_base_and_army_budget() -> void:
	var session: Session = _create_session()
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.grid.place("b_cell", Vector2i(8, 3), session.wallet)

	var emitted: Array[int] = [0]
	hud.finalize_requested.connect(func() -> void: emitted[0] += 1)
	hud.btn_finalize.emit_signal("pressed")

	var dialog: ConfirmationPopup = hud.confirmation_dialog
	assert_true(dialog.visible)
	assert_eq(emitted[0], 0, "nothing is finalized before the player confirms")
	assert_eq(dialog.kicker_label.text, "READY TO SWITCH SIDES?")
	assert_eq(dialog.title_label.text, "Finalize this base?")
	assert_eq(dialog.dialog_text, HudBuild.FINALIZE_BODY)
	assert_eq(dialog.tile_label(0), "Base")
	assert_eq(dialog.tile_value(0), "%d ATP" % int(session.grid.total_cost()["atp"]))
	assert_eq(dialog.tile_value(0), "250 ATP")
	assert_eq(dialog.tile_label(1), "Army budget")
	assert_eq(dialog.tile_value(1), "%d ATP" % session.wallet.get_amount("atp"))
	assert_eq(dialog.tile_value(1), "750 ATP")
	assert_false(dialog.warning_label.visible)
	assert_eq(dialog.btn_cancel.text, "Keep building")
	assert_eq(dialog.btn_ok.text, "Finalize")
	assert_gte(dialog.btn_cancel.custom_minimum_size.y, 58.0)
	assert_gte(dialog.btn_ok.custom_minimum_size.y, 58.0)
	assert_eq(dialog.btn_ok.variant, PillButton.Variant.PRIMARY)
	assert_eq(dialog.btn_cancel.variant, PillButton.Variant.SECONDARY)

	dialog.get_cancel_button().emit_signal("pressed")
	assert_false(dialog.visible, "Keep building closes the dialog")
	assert_eq(emitted[0], 0)

	hud.btn_finalize.emit_signal("pressed")
	assert_true(dialog.visible)
	dialog.get_ok_button().emit_signal("pressed")
	assert_false(dialog.visible)
	assert_eq(emitted[0], 1, "Finalize emits finalize_requested")

func test_finalize_dialog_warns_when_the_army_budget_buys_nothing() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	var cheapest: int = hud.get_cheapest_pathogen_cost()
	assert_eq(cheapest, 10)
	session.wallet.spend({"atp": 995})
	hud.btn_finalize.emit_signal("pressed")
	var dialog: ConfirmationPopup = hud.confirmation_dialog
	assert_true(dialog.visible)
	assert_true(dialog.warning_label.visible)
	assert_eq(dialog.warning_label.text, "You have 5 ATP left, which is not enough for any pathogen (cheapest costs 10). Finalize anyway?")
	assert_eq(dialog.warning_label.get_theme_color("font_color"), UiPalette.color(false, "danger"))
	assert_eq(dialog.tile_value(1), "5 ATP")

func test_confirmation_popup_generic_setters() -> void:
	var dialog := ConfirmationPopup.new()
	add_child_autofree(dialog)
	dialog.set_kicker("KICK")
	dialog.set_title("Title")
	dialog.set_body("Body text")
	dialog.set_tiles([{"label": "A", "value": "1", "color": Color.WHITE}])
	dialog.set_buttons("No", "Yes")
	assert_true(dialog.kicker_label.visible)
	assert_eq(dialog.kicker_label.text, "KICK")
	assert_eq(dialog.title_label.text, "Title")
	assert_eq(dialog.dialog_text, "Body text")
	assert_eq(dialog.tile_value(0), "1")
	assert_eq(dialog.btn_cancel.text, "No")
	assert_eq(dialog.btn_ok.text, "Yes")
	dialog.set_tiles([])
	assert_false(dialog.tiles_row.visible)
	dialog.night = true
	assert_true(dialog.btn_ok.night)
	assert_true(dialog.backdrop.night)
	watch_signals(dialog)
	dialog.show_dialog("Again")
	assert_true(dialog.visible)
	dialog.btn_cancel.pressed.emit()
	assert_signal_emitted(dialog, "canceled")
	assert_false(dialog.visible)

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
	assert_not_null(phase.background)
	assert_false(phase.background.night)
	fsm.phase = GameStateMachine.Phase.SYNTHESIS

	phase.hud_build.finalize_requested.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)

# --- layout -----------------------------------------------------------------------------------------------

func test_cards_and_pills_are_pinned_to_the_reference_positions() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_eq(hud.atp_pill.position, Vector2(20.0, 14.0))
	assert_eq(hud.left_card.position, Vector2(20.0, 96.0))
	assert_eq(hud.left_card.custom_minimum_size.x, 300.0)
	assert_eq(hud.right_card.anchor_left, 1.0)
	assert_eq(hud.right_card.offset_right, -20.0)
	assert_eq(hud.right_card.offset_top, 96.0)
	assert_eq(hud.btn_finalize.offset_left, -184.0)
	assert_eq(hud.btn_finalize.offset_right, -20.0)
	assert_eq(hud.btn_finalize.offset_top, 12.0)
	assert_eq(hud.btn_menu.offset_right, -196.0)
	assert_eq(hud.btn_menu.offset_top, 12.0)
	assert_eq(hud.phase_pill.anchor_left, 0.5)
	assert_eq(hud.phase_pill.offset_left, -170.0)
	assert_eq(hud.phase_pill.offset_top, 10.0)
	assert_eq(hud.tray.anchor_left, 0.5)
	assert_eq(hud.tray.anchor_top, 1.0)
	assert_eq(hud.tray.offset_bottom, -16.0)
	assert_eq(hud.tray.offset_top, -88.0)

func test_touch_buttons_minimum_sizes() -> void:
	var session: Session = _create_session()
	session.config.feature_flags["move_nucleus"] = true
	var ctx: Dictionary = _setup_hud(session)
	var hud: HudBuild = ctx["hud"]
	var buttons: Array[BaseButton] = []
	_find_buttons(hud, buttons)
	assert_gt(buttons.size(), 10)
	for b: BaseButton in buttons:
		assert_gte(b.custom_minimum_size.x, 48.0, "%s width" % b.name)
		assert_gte(b.custom_minimum_size.y, 48.0, "%s height" % b.name)

# --- menu sheet --------------------------------------------------------------------------------------------

func test_menu_sheet_lists_the_items_and_opens_from_the_button() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_false(hud.menu_open())
	hud.btn_menu.pressed.emit()
	assert_true(hud.menu_open())
	assert_true(hud.menu_catcher.visible)
	var expected: Dictionary = {
		HudBuild.MENU_HOW_TO_PLAY: "How to play",
		HudBuild.MENU_SOUND: "Sound: On",
		HudBuild.MENU_SAVE: "Save base…",
		HudBuild.MENU_IMPORT: "Import…",
		HudBuild.MENU_SETTINGS: "Settings",
		HudBuild.MENU_QUIT: "Quit to title",
	}
	for id: int in expected.keys():
		var b: PillButton = hud.menu_button(id)
		assert_not_null(b, "item %d" % id)
		assert_eq(b.text, expected[id])
		assert_eq(b.variant, PillButton.Variant.SECONDARY)
		assert_gte(b.custom_minimum_size.y, 48.0)
	assert_eq(hud.menu_buttons.size(), expected.size())
	hud.btn_menu.pressed.emit()
	assert_false(hud.menu_open(), "the MENU button toggles the sheet")

func test_tapping_outside_the_menu_sheet_closes_it() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	hud.open_menu()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	hud.menu_catcher.gui_input.emit(touch)
	assert_false(hud.menu_open())
	assert_false(hud.menu_catcher.visible)

func test_menu_items_route_to_their_actions() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	watch_signals(hud)
	hud.open_menu()
	hud.menu_button(HudBuild.MENU_IMPORT).pressed.emit()
	assert_signal_emitted_with_parameters(hud, "library_requested", ["base"])
	assert_false(hud.menu_open(), "choosing an item closes the sheet")
	hud.menu_button(HudBuild.MENU_SETTINGS).pressed.emit()
	assert_signal_emitted(hud, "settings_requested")
	hud.menu_button(HudBuild.MENU_HOW_TO_PLAY).pressed.emit()
	assert_signal_emitted(hud, "help_requested")

func test_quit_to_title_requests_the_title_phase() -> void:
	var session: Session = _create_session()
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autofree(fsm)
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)
	fsm.phase = GameStateMachine.Phase.SYNTHESIS
	phase.hud_build.menu_button(HudBuild.MENU_QUIT).pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.TITLE)

func test_settings_item_pushes_the_settings_screen() -> void:
	var session: Session = _create_session()
	var fsm: GameStateMachine = GameStateMachine.new()
	add_child_autofree(fsm)
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	fsm.screen_stack = stack
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)
	phase.hud_build.menu_button(HudBuild.MENU_SETTINGS).pressed.emit()
	assert_eq(stack.top_id(), "settings")

func test_save_base_asks_for_a_name_and_saves_to_the_library() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	hud.saves_root = SAVES_ROOT
	session.grid.place("mucous_wall", Vector2i(2, 2), session.wallet)
	hud.menu_button(HudBuild.MENU_SAVE).pressed.emit()
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



func test_undo_button_follows_the_history_and_undoes() -> void:
	var session: Session = _create_session()
	var parts: Dictionary = _setup_hud(session)
	var hud: HudBuild = parts["hud"]
	var bc: BuildController = parts["controller"]
	var grid_view: GridView = parts["grid_view"]
	assert_true(hud.btn_undo.disabled)
	assert_gte(hud.btn_undo.size.y, 48.0)
	bc.select_tool("mucous_wall")
	grid_view.cell_pressed.emit(Vector2i(3, 3))
	grid_view.cell_released.emit(Vector2i(3, 3))
	assert_false(hud.btn_undo.disabled)
	hud.btn_undo.pressed.emit()
	assert_eq(session.grid.tile_state(Vector2i(3, 3)), GridModel.TileState.EMPTY)
	assert_true(hud.btn_undo.disabled)

# --- Living Base (#158) -----------------------------------------------------------------------------------

const LB_DIR: String = "user://test_hud_lb"

func _living_base_session() -> Session:
	var cfg: GameConfig = _load_config()
	cfg.feature_flags["living_base"] = true
	DirAccess.make_dir_recursive_absolute(LB_DIR)
	var store := LivingBaseStore.new()
	store.path = LB_DIR + "/living_base.json"
	var session := Session.new(cfg)
	LivingBaseFlow.new(store).enter(session)
	return session

func _clean_lb_dir() -> void:
	var d: DirAccess = DirAccess.open(LB_DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(LB_DIR)

func test_lab_hud_shows_none_of_the_living_base_widgets() -> void:
	var session: Session = _create_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_false(hud.aa_pill.visible)
	assert_false(hud.dna_pill.visible)
	assert_false(hud.mito_box.visible)
	assert_true(hud.btn_finalize.visible)
	assert_false(hud.btn_raid.visible)
	assert_false(hud.lb_buttons.visible)
	assert_true(hud.lb_timer.is_stopped())

func test_living_base_hud_swaps_finalize_for_hidden_raid_and_shows_amino_pill() -> void:
	var session: Session = _living_base_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_false(hud.btn_finalize.visible)
	assert_false(hud.btn_raid.visible, "Raid stays hidden until LB-08")
	assert_true(hud.aa_pill.visible)
	assert_eq(hud.aa_label.text, "0")
	assert_false(hud.dna_pill.visible, "DNA is hidden at 0 without debug_dna")
	assert_false(hud.mito_box.visible, "no Mitochondria yet")
	assert_false(hud.btn_defense_log.visible)
	assert_false(hud.btn_upgrades.visible)
	_clean_lb_dir()

func test_dna_pill_shows_with_dna_or_the_debug_flag() -> void:
	var session: Session = _living_base_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	session.wallet.set_amount("dna", 3)
	assert_true(hud.dna_pill.visible)
	assert_eq(hud.dna_label.text, "3")
	session.wallet.set_amount("dna", 0)
	assert_false(hud.dna_pill.visible)
	session.config.feature_flags["debug_dna"] = true
	hud._update_living_base()
	assert_true(hud.dna_pill.visible)
	_clean_lb_dir()

func test_collect_button_follows_mitochondria_and_stored_atp() -> void:
	var session: Session = _living_base_session()
	var parts: Dictionary = _setup_hud(session)
	var hud: HudBuild = parts["hud"]
	assert_false(hud.mito_box.visible)
	assert_gte(hud.btn_collect.custom_minimum_size.x, 48.0)
	assert_gte(hud.btn_collect.custom_minimum_size.y, 48.0)
	assert_true(session.grid.place("mitochondria", Vector2i(10, 10), session.wallet) > 0)
	assert_true(hud.mito_box.visible)
	assert_eq(hud.mito_label.text, "Stored 0 / 300 ATP")
	assert_true(hud.btn_collect.disabled)
	session.profile.stored_atp = 120
	hud._update_living_base()
	assert_eq(hud.mito_label.text, "Stored 120 / 300 ATP")
	assert_false(hud.btn_collect.disabled)
	var before: int = session.wallet.get_amount("atp")
	hud.btn_collect.pressed.emit()
	assert_eq(session.wallet.get_amount("atp"), before + 120)
	assert_eq(hud.mito_label.text, "Stored 0 / 300 ATP")
	assert_true(hud.btn_collect.disabled)
	_clean_lb_dir()

func test_test_in_lab_is_a_menu_item_only_in_living_base() -> void:
	var lab: HudBuild = _setup_hud(_create_session())["hud"]
	lab.open_menu()
	assert_null(lab.menu_button(HudBuild.MENU_TEST_IN_LAB))
	var session: Session = _living_base_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	hud.open_menu()
	var b: PillButton = hud.menu_button(HudBuild.MENU_TEST_IN_LAB)
	assert_not_null(b)
	assert_eq(b.text, "Test in Lab")
	assert_gte(b.custom_minimum_size.y, 48.0)
	watch_signals(hud)
	b.pressed.emit()
	assert_signal_emitted(hud, "test_in_lab_requested")
	_clean_lb_dir()

func test_living_base_timer_runs_and_banks_atp() -> void:
	var session: Session = _living_base_session()
	var hud: HudBuild = _setup_hud(session)["hud"]
	assert_false(hud.lb_timer.is_stopped())
	session.grid.place("mitochondria", Vector2i(10, 10), session.wallet)
	session.living_flow.sync_profile_from_session()
	session.profile.last_clock_unix = LivingBaseStore.now_unix() - 3600
	hud._on_lb_timer()
	assert_between(session.profile.stored_atp, 60, 61)
	_clean_lb_dir()
