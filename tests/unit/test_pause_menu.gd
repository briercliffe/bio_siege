extends GutTest

## Screen 12: the Infection Pause menu. Pausing stops the runner stepping the sim, the four buttons do
## what the issue says, and nothing here writes to the player's real settings, saves or battle logs.

const SettingsScene: PackedScene = preload("res://src/ui/screens/settings_screen.tscn")
const SessionLoggerScript = preload("res://src/telemetry/session_logger.gd")
const SETTINGS_PATH: String = "user://test_pause_menu.cfg"
const SAVES_ROOT: String = "user://test_pause_menu_saves"
const LOG_PATH: String = "user://telemetry/test_pause_menu_log.jsonl"
const FRAMES: int = 20


## Records push() calls instead of opening real screens. The pushed Settings screen is built off-tree
## against the test settings file so the night flag can be checked.
class RecordingStack extends ScreenStack:
	var pushed: Array[String] = []
	var last_screen: Control = null

	func push(id: String) -> void:
		pushed.append(id)
		if id == "settings":
			var screen: SettingsScreen = SettingsScene.instantiate() as SettingsScreen
			screen.setup(SETTINGS_PATH)
			last_screen = screen

	func top_screen() -> Control:
		return last_screen


var _config: GameConfig = null
var _logger: Node = null
var _sfx_path: String = ""


func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	_config = res.config


func before_each() -> void:
	_cleanup()
	_sfx_path = Sfx.settings_path
	Sfx.settings_path = SETTINGS_PATH
	# Kept out of the tree: _ready() would read the real consent and open a real session file.
	_logger = SessionLoggerScript.new()
	_logger.set("settings_path", SETTINGS_PATH)
	_logger.set_custom_file_path(LOG_PATH)


func after_each() -> void:
	Sfx.settings_path = _sfx_path
	var file: FileAccess = _logger.get("_file") as FileAccess
	if file != null:
		file.close()
	_logger.free()
	_logger = null
	_cleanup()


func _cleanup() -> void:
	for path: String in [SETTINGS_PATH, LOG_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SAVES_ROOT):
		for f: String in DirAccess.get_files_at(SAVES_ROOT):
			DirAccess.remove_absolute(SAVES_ROOT.path_join(f))
		DirAccess.remove_absolute(SAVES_ROOT)


## A running battle reached the way the game does: INCUBATION with a bought army, then INFECTION.
func _start_battle(ctx: Dictionary) -> InfectionPhase:
	var session := Session.new(_config, SETTINGS_PATH)
	ctx["wallet_before"] = session.wallet.get_amount("atp")
	for i: int in range(5):
		assert_true(session.army.buy("rhinovirus", session.wallet))
	assert_true(session.army.buy("bacteriophage", session.wallet))
	assert_lt(session.wallet.get_amount("atp"), int(ctx["wallet_before"]))
	session.battle_setup = Scenarios.mixed([], 7)

	var fsm := GameStateMachine.new()
	fsm.settings_path = SETTINGS_PATH
	fsm.saves_root = SAVES_ROOT
	fsm.session = session
	add_child_autoqfree(fsm)
	var stack := RecordingStack.new()
	add_child_autoqfree(stack)
	fsm.screen_stack = stack
	fsm.phase = GameStateMachine.Phase.INCUBATION
	assert_true(fsm.request_transition(GameStateMachine.Phase.INFECTION))

	var phase: InfectionPhase = fsm.current_phase_scene as InfectionPhase
	assert_not_null(phase)
	phase.logger = _logger
	ctx["session"] = session
	ctx["fsm"] = fsm
	ctx["stack"] = stack
	ctx["grid_cost"] = session.grid.total_cost().get("atp", 0)
	_frames(phase, 10)
	assert_gt(phase.runner.sim.tick, 0, "the battle is running")
	return phase


func _frames(phase: InfectionPhase, n: int) -> void:
	var dt: float = 1.0 / float(_config.tick_rate)
	for i: int in range(n):
		phase.runner._process(dt)
		phase.unit_layer._process(dt)
		phase._process(dt)


func _logged_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	(_logger.get("_file") as FileAccess).flush()
	var text: String = FileAccess.get_file_as_string(LOG_PATH)
	for line: String in text.split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed as Dictionary)
	return out


func _events_named(name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in _logged_events():
		if str(ev.get("event", "")) == name:
			out.append(ev)
	return out


func test_pause_sets_runner_paused_and_the_sim_does_not_advance() -> void:
	var phase: InfectionPhase = _start_battle({})
	phase.hud_combat.pause_button.pressed.emit()
	assert_true(phase.runner.paused)
	assert_true(phase.unit_layer.paused)
	assert_true(phase.pause_menu.visible)
	assert_false(phase.hud_combat.visible, "the HUD hides behind the Pause card, as in mockup 12")
	assert_false(get_tree().paused, "the tree is never paused, so the Pause UI keeps working")

	var tick: int = phase.runner.sim.tick
	var hash_before: String = phase.runner.sim.state_hash()
	var view_time: float = phase.unit_layer.view_time
	_frames(phase, FRAMES)
	assert_eq(phase.runner.sim.tick, tick)
	assert_eq(phase.runner.sim.state_hash(), hash_before)
	assert_eq(phase.unit_layer.view_time, view_time, "idle loops freeze too")


func test_resume_continues_the_battle() -> void:
	var phase: InfectionPhase = _start_battle({})
	phase.pause()
	var tick: int = phase.runner.sim.tick
	_frames(phase, FRAMES)
	phase.pause_menu.resume_button.pressed.emit()
	assert_false(phase.runner.paused)
	assert_false(phase.unit_layer.paused)
	assert_false(phase.pause_menu.visible)
	assert_true(phase.hud_combat.visible)
	var view_time: float = phase.unit_layer.view_time
	_frames(phase, FRAMES)
	assert_gt(phase.runner.sim.tick, tick)
	assert_gt(phase.unit_layer.view_time, view_time)


func test_restart_raid_refunds_the_army_and_goes_to_incubation() -> void:
	var ctx: Dictionary = {}
	var phase: InfectionPhase = _start_battle(ctx)
	var session: Session = ctx["session"] as Session
	var fsm: GameStateMachine = ctx["fsm"] as GameStateMachine
	var tick: int = phase.runner.sim.tick
	phase.pause()
	phase.pause_menu.restart_button.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)
	assert_eq(session.wallet.get_amount("atp"), int(ctx["wallet_before"]), "the ATP budget is as before launch")
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.grid.total_cost().get("atp", 0), ctx["grid_cost"], "the base is unchanged")
	var abandoned: Array[Dictionary] = _events_named("battle_abandoned")
	assert_eq(abandoned.size(), 1)
	if abandoned.size() == 1:
		assert_eq(abandoned[0].get("reason"), "restart")
		assert_eq(int(abandoned[0].get("tick", -1)), tick)
	assert_eq(_events_named("battle_end").size(), 0, "an abandoned battle logs no battle_end")
	assert_false(phase.runner.is_running, "the abandoned battle can no longer finish into Results")


func test_quit_to_menu_goes_to_title() -> void:
	var ctx: Dictionary = {}
	var phase: InfectionPhase = _start_battle(ctx)
	var session: Session = ctx["session"] as Session
	var fsm: GameStateMachine = ctx["fsm"] as GameStateMachine
	phase.pause()
	phase.pause_menu.quit_button.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.TITLE)
	assert_eq(session.wallet.get_amount("atp"), int(ctx["wallet_before"]))
	assert_eq(session.army.total_count(), 0)
	var abandoned: Array[Dictionary] = _events_named("battle_abandoned")
	assert_eq(abandoned.size(), 1)
	if abandoned.size() == 1:
		assert_eq(abandoned[0].get("reason"), "quit")
	assert_eq(_events_named("battle_end").size(), 0)


func test_settings_pushes_the_settings_screen_in_night_and_stays_paused() -> void:
	var ctx: Dictionary = {}
	var phase: InfectionPhase = _start_battle(ctx)
	var stack: RecordingStack = ctx["stack"] as RecordingStack
	phase.pause()
	phase.pause_menu.settings_button.pressed.emit()
	assert_eq(stack.pushed, ["settings"] as Array[String])
	var screen: SettingsScreen = stack.last_screen as SettingsScreen
	assert_not_null(screen)
	if screen != null:
		assert_true(screen.night, "Settings opens in the night theme from Pause")
		screen.free()
	assert_true(phase.runner.paused, "the battle stays paused behind Settings")
	assert_true(phase.pause_menu.visible)
	assert_eq((ctx["fsm"] as GameStateMachine).phase, GameStateMachine.Phase.INFECTION)


func test_every_button_is_at_least_48_px_tall() -> void:
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	add_child_autofree(host)
	var menu := PauseMenu.new()
	host.add_child(menu)
	await wait_process_frames(2)
	assert_eq(menu.buttons().size(), 4)
	for b: PillButton in menu.buttons():
		assert_gte(b.custom_minimum_size.y, 48.0, b.name)
		assert_gte(b.size.y, 48.0, b.name)
		assert_gte(b.size.x, 48.0, b.name)
	assert_eq(menu.resume_button.size.y, 60.0)
	assert_eq(menu.restart_button.size.y, 56.0)
	assert_eq(menu.card.size.x, 400.0)
	var card_rect: Rect2 = menu.card.get_global_rect()
	assert_almost_eq(card_rect.get_center().x, 640.0, 1.0, "the card is centred")
	assert_almost_eq(card_rect.get_center().y, 360.0, 1.0)


func test_pause_overlay_blocks_input_to_the_board() -> void:
	var menu := PauseMenu.new()
	add_child_autofree(menu)
	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(menu.dim.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(menu.dim.color, UiPalette.color(true, "dim_overlay"))


func test_losing_window_focus_auto_pauses() -> void:
	var phase: InfectionPhase = _start_battle({})
	phase.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(phase.runner.paused)
	assert_true(phase.pause_menu.visible)


func test_a_finished_battle_cannot_be_paused() -> void:
	var phase: InfectionPhase = _start_battle({})
	while not phase.runner.sim.finished:
		phase.runner.sim.step()
	phase._process(0.0)
	phase.pause()
	assert_false(phase.runner.paused)
	assert_false(phase.pause_menu.visible)
	assert_true(phase.hud_combat.pause_button.disabled)
