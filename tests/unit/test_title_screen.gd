extends GutTest


class StubStack extends ScreenStack:
	var pushed: Array[String] = []

	func push(id: String) -> void:
		pushed.append(id)


func _start_fsm() -> GameStateMachine:
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.start()
	return fsm


## A title laid out at the 1280x720 design size (the headless viewport is square).
func _design_title(fsm: GameStateMachine) -> TitleScreen:
	var holder := Control.new()
	holder.size = TitleScreen.DESIGN_SIZE
	add_child_autofree(holder)
	var title: TitleScreen = (load("res://src/ui/title.tscn") as PackedScene).instantiate() as TitleScreen
	title.setup(fsm.session, fsm)
	holder.add_child(title)
	return title


func _title(fsm: GameStateMachine) -> TitleScreen:
	var title: TitleScreen = fsm.current_phase_scene as TitleScreen
	assert_not_null(title, "start() lands on the Title")
	return title


func test_play_moves_fsm_to_synthesis() -> void:
	var fsm := _start_fsm()
	var session: Session = fsm.session
	_title(fsm).btn_play.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.session, session)


func test_menu_buttons_push_their_screens() -> void:
	var fsm := _start_fsm()
	var stub := StubStack.new()
	add_child_autofree(stub)
	fsm.screen_stack = stub
	var title := _title(fsm)
	title.btn_saved.pressed.emit()
	title.btn_how_to_play.pressed.emit()
	title.btn_settings.pressed.emit()
	assert_eq(stub.pushed, ["saved", "how_to_play", "settings"] as Array[String])
	assert_eq(fsm.phase, GameStateMachine.Phase.TITLE)


func test_menu_buttons_open_screens_on_a_real_stack() -> void:
	var fsm := _start_fsm()
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	fsm.screen_stack = stack
	var title := _title(fsm)
	title.btn_settings.pressed.emit()
	assert_eq(stack.top_id(), "settings")
	stack.pop()
	title.btn_saved.pressed.emit()
	assert_eq(stack.top_id(), "saved")


func test_buttons_are_touch_sized() -> void:
	var fsm := _start_fsm()
	var title := _design_title(fsm)
	await get_tree().process_frame
	assert_eq(title.size, TitleScreen.DESIGN_SIZE)
	var buttons: Array[Node] = title.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 4)
	for node: Node in buttons:
		var b: Button = node as Button
		assert_gte(b.size.x, 48.0, "%s width" % b.name)
		assert_gte(b.size.y, 48.0, "%s height" % b.name)
	assert_gte(title.btn_play.size.y, 52.0)
	assert_eq(title.btn_play.size, TitleScreen.PLAY_SIZE)
	assert_eq(title.btn_saved.size, TitleScreen.WIDE_SIZE)
	assert_eq(title.btn_how_to_play.size, TitleScreen.HALF_SIZE)
	assert_eq(title.btn_settings.size, TitleScreen.HALF_SIZE)


func test_layout_matches_the_mockup() -> void:
	var fsm := _start_fsm()
	var title := _design_title(fsm)
	await get_tree().process_frame
	assert_eq(title.size, TitleScreen.DESIGN_SIZE)
	assert_eq(title.night_panel.position, Vector2(600.0, 0.0))
	assert_eq(title.night_panel.size, Vector2(680.0, 720.0))
	assert_eq(title.day_background.size, Vector2(700.0, 720.0))
	assert_true(title.night_background.night)
	assert_false(title.day_background.night)
	assert_eq(Rect2(title.island.position, title.island.size), TitleScreen.ISLAND_RECT)
	assert_eq(title.island.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(title.grid_view.is_processing_unhandled_input(), "the backdrop takes no input")
	assert_true(title.grid_view.night)
	assert_eq(title.column.position, Vector2(80.0, 80.0))
	assert_almost_eq(title.footer_label.position.y + title.footer_label.size.y, 690.0, 0.5)


func test_demo_base_layout() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var grid: GridModel = TitleScreen.build_demo_grid(cfg)
	var counts: Dictionary = grid.count_by_type()
	assert_eq(counts.get("nucleus", 0), 1)
	assert_eq(counts.get("b_cell", 0), 2)
	assert_eq(counts.get("macrophage", 0), 1)
	# A 16x16 ring has 60 cells; the gap removes 8 of them.
	assert_eq(counts.get("mucous_wall", 0), 52)
	assert_eq(grid.structure_id_at(Vector2i(27, 20)), 0, "gap on the right side")
	assert_ne(grid.structure_id_at(Vector2i(27, 24)), 0)
	assert_eq(grid.get_structure(grid.structure_id_at(Vector2i(14, 14))).type_id, "b_cell")
	assert_eq(grid.get_structure(grid.structure_id_at(Vector2i(23, 23))).type_id, "b_cell")
	assert_eq(grid.get_structure(grid.structure_id_at(Vector2i(14, 23))).type_id, "macrophage")


func test_demo_base_does_not_touch_the_session() -> void:
	var fsm := _start_fsm()
	var title := _title(fsm)
	assert_ne(title.demo_grid, fsm.session.grid)
	assert_eq(fsm.session.grid.count_by_type().get("mucous_wall", 0), 0)
	assert_eq(title.grid_view.grid, title.demo_grid)


func test_footer_shows_dev_without_build_info() -> void:
	assert_eq(TitleScreen.footer_text_for("res://no_such_build_info.txt"), "Playtest build 0.1 · dev")
	var fsm := _start_fsm()
	var title := _title(fsm)
	title.build_info_path = "res://no_such_build_info.txt"
	title.refresh_footer()
	assert_eq(title.footer_label.text, "Playtest build 0.1 · dev")


func test_footer_shows_build_sha() -> void:
	var path: String = "user://test_build_info.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("abc1234\n")
	f.close()
	assert_eq(TitleScreen.footer_text_for(path), "Playtest build 0.1 · abc1234")
	assert_eq(BuildInfo.read(path), "abc1234")
	DirAccess.remove_absolute(path)


func test_icon_row_and_copy() -> void:
	var fsm := _start_fsm()
	var title := _title(fsm)
	var icons: Array[Node] = title.find_children("*", "IconSlot", true, false)
	var ids: Array[String] = []
	for node: Node in icons:
		ids.append((node as IconSlot).icon_id)
	assert_eq(ids, ["macrophage", "b_cell", "nucleus", "rhinovirus", "bacteriophage"] as Array[String])
	assert_eq(title.kicker_label.text, "BIOLOGICAL REVERSE TOWER DEFENSE")
	assert_eq(title.wordmark.lines, ["BIO", "SIEGE"] as Array[String])
	assert_eq(title.btn_play.variant, PillButton.Variant.PRIMARY)
	assert_eq(title.btn_saved.variant, PillButton.Variant.SECONDARY)


func test_wider_viewport_moves_the_night_side_with_the_right_edge() -> void:
	var fsm := _start_fsm()
	var title := _design_title(fsm)
	(title.get_parent() as Control).size = Vector2(1600.0, 720.0)
	await get_tree().process_frame
	assert_eq(title.night_panel.position.x, 920.0)
	assert_eq(title.night_panel.size.x, 680.0)
	assert_eq(title.island.position.x, 991.0)
	assert_eq(title.column.position, Vector2(80.0, 80.0))


# --- Living Base mode sheet (#158) -------------------------------------------------------------------------

const LB_PATH: String = "user://test_title_lb.json"


func _start_fsm_with_flag(on: bool) -> GameStateMachine:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["living_base"] = on
	var fsm := GameStateMachine.new()
	fsm.session = Session.new(cfg)
	add_child_autoqfree(fsm)
	fsm.start()
	return fsm


func _remove_lb_file() -> void:
	DirAccess.remove_absolute(LB_PATH)


func test_flag_off_play_goes_straight_to_synthesis_in_lab() -> void:
	var fsm := _start_fsm_with_flag(false)
	_title(fsm).btn_play.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.session.mode, Session.Mode.LAB)
	assert_null(_title_node_or_null(fsm))


func _title_node_or_null(fsm: GameStateMachine) -> TitleScreen:
	return fsm.current_phase_scene as TitleScreen


func test_flag_on_play_opens_the_mode_sheet() -> void:
	var fsm := _start_fsm_with_flag(true)
	var title := _title(fsm)
	title.btn_play.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.TITLE)
	assert_true(title.mode_sheet_open())
	assert_gte(title.btn_mode_living.custom_minimum_size.y, 48.0)
	assert_gte(title.btn_mode_lab.custom_minimum_size.y, 48.0)
	assert_gte(title.btn_mode_close.custom_minimum_size.y, 48.0)
	title.btn_mode_close.pressed.emit()
	assert_false(title.mode_sheet_open())
	assert_eq(fsm.phase, GameStateMachine.Phase.TITLE)


func test_choosing_living_base_sets_the_mode_and_enters_synthesis() -> void:
	_remove_lb_file()
	var fsm := _start_fsm_with_flag(true)
	var session: Session = fsm.session
	var title := _title(fsm)
	title.living_base_path = LB_PATH
	title.btn_play.pressed.emit()
	title.btn_mode_living.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(session.mode, Session.Mode.LIVING_BASE)
	assert_not_null(session.profile)
	_remove_lb_file()


func test_choosing_lab_sets_lab_and_enters_synthesis() -> void:
	var fsm := _start_fsm_with_flag(true)
	var title := _title(fsm)
	title.btn_play.pressed.emit()
	title.btn_mode_lab.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.session.mode, Session.Mode.LAB)
