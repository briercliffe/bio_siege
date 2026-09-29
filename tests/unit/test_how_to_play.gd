extends GutTest

const TEST_PATH: String = "user://test_how_to_play.cfg"

var _overlay: HowToPlay = null


func before_each() -> void:
	_cleanup()
	_overlay = (load("res://src/ui/how_to_play.tscn") as PackedScene).instantiate() as HowToPlay
	_overlay.settings_path = TEST_PATH
	add_child_autofree(_overlay)


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _touch(pressed: bool, x: float) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = pressed
	ev.position = Vector2(x, 100.0)
	return ev


func _drag(x: float) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = Vector2(x, 100.0)
	return ev


func test_hidden_until_opened() -> void:
	assert_false(_overlay.visible)
	_overlay.open()
	assert_true(_overlay.visible)
	assert_eq(_overlay.page, 0)


func test_shows_on_first_launch_and_got_it_dismisses_for_good() -> void:
	assert_true(HowToPlay.should_show_on_launch(TEST_PATH))
	_overlay.open()
	watch_signals(_overlay)
	_overlay.btn_got_it.pressed.emit()
	assert_false(_overlay.visible)
	assert_signal_emitted(_overlay, "dismissed")
	assert_false(HowToPlay.should_show_on_launch(TEST_PATH))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TEST_PATH), OK)
	assert_eq(cfg.get_value("game", "seen_how_to_play"), true)


func test_reopening_via_help_does_not_need_the_flag() -> void:
	_overlay.got_it()
	assert_false(_overlay.visible)
	_overlay.open()
	assert_true(_overlay.visible)
	assert_eq(_overlay.page, 0, "reopens on the first panel")


func test_four_pages_with_the_specified_copy() -> void:
	assert_eq(HowToPlay.PAGE_COUNT, 4)
	assert_eq(HowToPlay.PAGES.size(), 4)
	assert_eq(HowToPlay.PAGES[0]["body"], "Build your immune system. Walls block paths, Macrophages splash nearby pathogens, B-Cells snipe from range. Everything costs ATP.")
	assert_eq(HowToPlay.PAGES[1]["body"], "When you finalize, you become the Pathogen. Whatever ATP you didn't spend on your base is your army budget.")
	assert_eq(HowToPlay.PAGES[2]["body"], "Buy pathogens and tap the green ring to deploy them. Rhinoviruses swarm, Bacteriophages hunt defenses, Staphylococcus tanks damage.")
	assert_eq(HowToPlay.PAGES[3]["body"], "Watch the attack. Destroy the Nucleus to win. Faint lines show where each pathogen is heading.")


func test_next_and_back_walk_the_panels() -> void:
	_overlay.open()
	assert_true(_overlay.btn_back.disabled, "no Back on the first panel")
	for expected in [1, 2, 3]:
		_overlay.btn_next.pressed.emit()
		assert_eq(_overlay.page, expected)
		assert_eq(_overlay.body_label.text, HowToPlay.PAGES[expected]["body"])
		assert_eq(_overlay.diagram.page, expected)
	assert_true(_overlay.btn_next.disabled, "no Next on the last panel")
	assert_false(_overlay.btn_back.disabled)
	_overlay.btn_next.pressed.emit()
	assert_eq(_overlay.page, 3, "does not run past the end")
	_overlay.btn_back.pressed.emit()
	assert_eq(_overlay.page, 2)
	_overlay.go_to(0)
	_overlay.btn_back.pressed.emit()
	assert_eq(_overlay.page, 0, "does not run before the start")


func test_all_buttons_are_at_least_48px() -> void:
	for button: Button in [_overlay.btn_back, _overlay.btn_next, _overlay.btn_got_it]:
		assert_gte(button.custom_minimum_size.x, 48.0)
		assert_gte(button.custom_minimum_size.y, 48.0)


func test_swipe_left_goes_next_and_right_goes_back() -> void:
	_overlay.open()
	_overlay._gui_input(_touch(true, 500.0))
	_overlay._gui_input(_drag(480.0))
	assert_eq(_overlay.page, 0, "a short drag is not a swipe")
	_overlay._gui_input(_drag(400.0))
	assert_eq(_overlay.page, 1)
	_overlay._gui_input(_drag(300.0))
	assert_eq(_overlay.page, 1, "one swipe moves one panel")
	_overlay._gui_input(_touch(false, 300.0))

	_overlay._gui_input(_touch(true, 300.0))
	_overlay._gui_input(_drag(400.0))
	assert_eq(_overlay.page, 0)


func test_drag_without_touch_start_is_ignored() -> void:
	_overlay.open()
	_overlay._gui_input(_drag(900.0))
	assert_eq(_overlay.page, 0)


func test_every_page_draws_a_diagram_without_config() -> void:
	# Fallback shapes are used when no config is available.
	_overlay.open()
	_overlay.diagram.config = null
	_overlay.diagram.size = Vector2(640.0, 200.0)
	for i in range(HowToPlay.PAGE_COUNT):
		_overlay.diagram.page = i
		assert_eq(_overlay.diagram.page, i)
		_overlay.diagram.queue_redraw()
	await wait_process_frames(2)
	assert_true(is_instance_valid(_overlay.diagram))


func test_diagram_takes_shapes_from_config() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	_overlay.diagram.config = res.config
	assert_eq(_overlay.diagram._shape_of("macrophage"), res.config.structures["macrophage"].placeholder_shape)
	assert_eq(_overlay.diagram._color_of("rhinovirus"), res.config.pathogens["rhinovirus"].placeholder_color)
	assert_eq(_overlay.diagram._cost_of("b_cell"), int(res.config.structures["b_cell"].cost["atp"]))


func test_help_button_factory_is_48px() -> void:
	var button: Button = HowToPlay.create_help_button()
	add_child_autofree(button)
	assert_eq(button.text, "?")
	assert_gte(button.custom_minimum_size.x, 48.0)
	assert_gte(button.custom_minimum_size.y, 48.0)
