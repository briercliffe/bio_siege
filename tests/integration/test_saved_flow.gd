extends GutTest

## Saved bases and armies wiring: Main opens the library from the Title and the HUD menus, and a base
## saved from the Synthesis menu loads back exactly.

const SETTINGS_PATH: String = "user://test_saved_flow.cfg"
const ROOT: String = "user://test_saved_flow_saves"

var _sfx_path: String = ""


func before_each() -> void:
	_cleanup()
	_sfx_path = Sfx.settings_path
	Sfx.settings_path = SETTINGS_PATH
	GameSettings.set_bool(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY, true, SETTINGS_PATH)


func after_each() -> void:
	Sfx.settings_path = _sfx_path
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	_remove_tree(ROOT)


static func _remove_tree(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for sub: String in DirAccess.get_directories_at(dir_path):
		_remove_tree("%s/%s" % [dir_path, sub])
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute("%s/%s" % [dir_path, file_name])
	DirAccess.remove_absolute(dir_path)


func _make_main() -> Node:
	var main_node: Node = (load("res://src/main.tscn") as PackedScene).instantiate()
	main_node.set("settings_path", SETTINGS_PATH)
	main_node.set("saves_root", ROOT)
	add_child_autofree(main_node)
	return main_node


func _stack(main_node: Node) -> ScreenStack:
	return main_node.get_node("ScreenStack") as ScreenStack


func _fsm(main_node: Node) -> GameStateMachine:
	return main_node.get_node("GameStateMachine") as GameStateMachine


static func _layout_of(grid: GridModel) -> Array:
	var out: Array = []
	for entry: Dictionary in grid.to_layout():
		out.append([entry["type"], entry["origin"]])
	out.sort()
	return out


func test_title_opens_the_library_with_the_injected_folder() -> void:
	var main_node := _make_main()
	var fsm := _fsm(main_node)
	(fsm.current_phase_scene as TitleScreen).btn_saved.pressed.emit()
	var screen: SavedScreen = _stack(main_node).top_screen() as SavedScreen
	assert_not_null(screen, "the real screen, not the placeholder")
	assert_eq(screen.library.root, ROOT)
	assert_eq(screen.fsm, fsm)
	assert_eq(screen.kind, "base")
	screen.back_button.pressed.emit()
	assert_false(_stack(main_node).is_open())
	await wait_process_frames(1)


func test_hud_import_opens_the_library_on_the_right_tab() -> void:
	var main_node := _make_main()
	var fsm := _fsm(main_node)
	var stack := _stack(main_node)
	fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	var synth: SynthesisPhase = fsm.current_phase_scene as SynthesisPhase
	assert_eq(synth.hud_build.saves_root, ROOT, "the FSM hands the folder to the phase and its HUD")
	synth.hud_build.menu_button(HudBuild.MENU_IMPORT).pressed.emit()
	assert_eq(stack.top_id(), "saved")
	assert_eq((stack.top_screen() as SavedScreen).kind, "base")

	fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_false(stack.is_open(), "a phase change closes the screen")
	var incubation: IncubationPhase = fsm.current_phase_scene as IncubationPhase
	assert_eq(incubation.hud_spawn.saves_root, ROOT)
	incubation.hud_spawn.popup_menu.id_pressed.emit(HudSpawn.MENU_IMPORT)
	var screen: SavedScreen = stack.top_screen() as SavedScreen
	assert_eq(screen.kind, "army")
	assert_eq(screen.tabs.selected_index, 1)
	await wait_process_frames(1)


func test_saved_base_loads_back_exactly() -> void:
	var main_node := _make_main()
	var fsm := _fsm(main_node)
	var stack := _stack(main_node)
	fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	var session: Session = fsm.session
	var demo: GridModel = TitleScreen.build_demo_grid(session.config)
	session.grid.load_layout(demo.to_layout(), session.wallet)
	var saved_layout: Array = _layout_of(session.grid)
	var saved_atp: int = session.wallet.get_amount("atp")
	var hud: HudBuild = (fsm.current_phase_scene as SynthesisPhase).hud_build
	hud.open_save_dialog()
	hud.save_dialog.name_edit.text = "Ring fort"
	hud.save_dialog.btn_save.pressed.emit()
	assert_eq(hud.last_toast_message, "Saved 'Ring fort'")

	session.wallet.reset(session.config.start_wallet)
	session.grid.reset_with_nucleus()
	assert_ne(_layout_of(session.grid), saved_layout)

	hud.menu_button(HudBuild.MENU_IMPORT).pressed.emit()
	var screen: SavedScreen = stack.top_screen() as SavedScreen
	assert_eq(screen.slot_cards.size(), 1)
	assert_eq(screen.slot_cards[0].name_label.text, "Ring fort")
	screen.slot_cards[0].load_button.pressed.emit()
	assert_false(stack.is_open(), "Load closes the library")
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(_layout_of(session.grid), saved_layout, "the base is restored exactly")
	assert_eq(session.wallet.get_amount("atp"), saved_atp)
	await wait_process_frames(1)
