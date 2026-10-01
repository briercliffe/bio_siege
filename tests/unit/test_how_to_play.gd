extends GutTest

## How to play wiring: first launch over the Title, the HUD "?" buttons, and the old overlay's removal.

const TEST_PATH: String = "user://test_how_to_play.cfg"

var _sfx_path: String = ""
var _bus_db: float = 0.0
var _bus_mute: bool = false


func before_each() -> void:
	_cleanup()
	_sfx_path = Sfx.settings_path
	Sfx.settings_path = TEST_PATH
	_bus_db = AudioServer.get_bus_volume_db(SettingsApply.MASTER_BUS)
	_bus_mute = AudioServer.is_bus_mute(SettingsApply.MASTER_BUS)


func after_each() -> void:
	Sfx.settings_path = _sfx_path
	AudioServer.set_bus_volume_db(SettingsApply.MASTER_BUS, _bus_db)
	AudioServer.set_bus_mute(SettingsApply.MASTER_BUS, _bus_mute)
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _make_main() -> Node:
	var main_node: Node = (load("res://src/main.tscn") as PackedScene).instantiate()
	main_node.set("settings_path", TEST_PATH)
	add_child_autofree(main_node)
	return main_node


func _stack(main_node: Node) -> ScreenStack:
	return main_node.get_node("ScreenStack") as ScreenStack


func _fsm(main_node: Node) -> GameStateMachine:
	return main_node.get_node("GameStateMachine") as GameStateMachine


func test_old_overlay_is_gone() -> void:
	assert_false(ResourceLoader.exists("res://src/ui/how_to_play.tscn"))
	assert_false(ResourceLoader.exists("res://src/ui/how_to_play_diagram.gd"))
	var main_node := _make_main()
	assert_null(main_node.get_node_or_null("HowToPlay"))
	assert_true(ResourceLoader.exists(ScreenStack.SCREENS["how_to_play"]))


func test_first_launch_opens_the_screen_over_the_title() -> void:
	var main_node := _make_main()
	var stack := _stack(main_node)
	assert_eq(_fsm(main_node).phase, GameStateMachine.Phase.TITLE)
	assert_eq(stack.top_id(), "how_to_play")
	var screen: HowToPlayScreen = stack.top_screen() as HowToPlayScreen
	assert_not_null(screen, "the real screen, not the placeholder")
	assert_eq(screen.settings_path, TEST_PATH)
	assert_eq(screen.fsm, _fsm(main_node))


func test_start_building_dismisses_for_good_and_goes_to_synthesis() -> void:
	var main_node := _make_main()
	var stack := _stack(main_node)
	var screen: HowToPlayScreen = stack.top_screen() as HowToPlayScreen
	screen.start_button.pressed.emit()
	assert_false(stack.is_open())
	assert_eq(_fsm(main_node).phase, GameStateMachine.Phase.SYNTHESIS)
	assert_false(HowToPlayScreen.should_show_on_launch(TEST_PATH))

	var again := _make_main()
	assert_false(_stack(again).is_open(), "not shown on the next launch")
	assert_eq(_fsm(again).phase, GameStateMachine.Phase.TITLE)
	await wait_process_frames(1)


func test_back_on_first_launch_stays_on_the_title() -> void:
	var main_node := _make_main()
	var stack := _stack(main_node)
	(stack.top_screen() as HowToPlayScreen).back_button.pressed.emit()
	assert_false(stack.is_open())
	assert_eq(_fsm(main_node).phase, GameStateMachine.Phase.TITLE)


func test_help_in_the_huds_reopens_it_and_returns_to_the_game() -> void:
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, TEST_PATH)
	var main_node := _make_main()
	var stack := _stack(main_node)
	var fsm := _fsm(main_node)
	assert_false(stack.is_open())
	for phase: GameStateMachine.Phase in [GameStateMachine.Phase.SYNTHESIS, GameStateMachine.Phase.INCUBATION]:
		fsm.force_transition(phase)
		fsm.how_to_play_requested.emit()
		assert_eq(stack.top_id(), "how_to_play")
		(stack.top_screen() as HowToPlayScreen).start_button.pressed.emit()
		assert_false(stack.is_open())
		assert_eq(fsm.phase, phase, "Start building from a HUD only closes the screen")
		fsm.how_to_play_requested.emit()
		(stack.top_screen() as HowToPlayScreen).back_button.pressed.emit()
		assert_false(stack.is_open())
		assert_eq(fsm.phase, phase)
	await wait_process_frames(1)


func test_help_button_factory_is_48px() -> void:
	var button: Button = HowToPlayScreen.create_help_button()
	add_child_autofree(button)
	assert_eq(button.text, "?")
	assert_gte(button.custom_minimum_size.x, 48.0)
	assert_gte(button.custom_minimum_size.y, 48.0)
