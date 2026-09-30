extends GutTest

const HowToPlayScene: PackedScene = preload("res://src/ui/screens/how_to_play_screen.tscn")
const TEST_PATH: String = "user://test_how_to_play_screen.cfg"

const STEP_CHIPS: Array[String] = ["1 · SYNTHESIS", "2 · INCUBATION", "3 · INFECTION", "4 · RESULTS"]
const STEP_TITLES: Array[String] = ["Build", "Deploy", "Siege", "Iterate"]
const STEP_BODIES: Array[String] = [
	"Spend ATP on walls, Macrophages and B-Cells around your Nucleus. Sell anything for a full refund.",
	"Switch sides. Buy pathogens with the ATP you kept, then tap the glowing band to send them in.",
	"Launch and watch the battle play out. Destroy the Nucleus to win. You have three minutes.",
	"Re-raid the same base, edit your defenses or start over. ATP spent on defense is missing from your army.",
]
const RULES: Array[String] = [
	"Walls block paths. Pathogens walk around when the detour is short and break through when it is long.",
	"Bacteriophages hit defenses hard. Triple damage against Macrophages and B-Cells.",
	"Out of time means the defense wins. The timer stops the battle at 3:00.",
]


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _config() -> GameConfig:
	return GameConfig.load_from_dir("res://data").config


## A screen laid out at the 1280x720 design size (the headless viewport is square).
func _make_screen(cfg: GameConfig = null, fsm: GameStateMachine = null) -> HowToPlayScreen:
	var host := Control.new()
	host.size = HowToPlayScreen.DESIGN_SIZE
	add_child_autofree(host)
	var screen: HowToPlayScreen = HowToPlayScene.instantiate() as HowToPlayScreen
	host.add_child(screen)
	screen.setup(TEST_PATH, fsm, cfg if cfg != null else _config())
	return screen


func _start_fsm() -> GameStateMachine:
	var fsm := GameStateMachine.new()
	fsm.settings_path = TEST_PATH
	add_child_autoqfree(fsm)
	fsm.start()
	return fsm


func test_four_step_cards_and_three_rules_with_the_specified_copy() -> void:
	var screen := _make_screen()
	assert_eq(screen.cards.size(), 4)
	assert_eq(screen.rule_cards.size(), 3)
	for i: int in range(4):
		assert_eq(screen.chips[i].text, STEP_CHIPS[i])
		assert_eq(screen.step_titles[i].text, STEP_TITLES[i])
		assert_eq(screen.step_bodies[i].text, STEP_BODIES[i])
	for i: int in range(3):
		assert_eq(screen.rule_labels[i].get_parsed_text(), RULES[i])
	assert_string_contains(screen.rule_labels[0].text, "[b]Walls block paths.[/b]")
	assert_eq(screen.kicker_label.text, "ONE LOOP, FOUR STEPS")
	assert_eq(screen.title_label.text, "How to play")
	assert_eq(screen.start_button.text, "Start building")


func test_chip_colours() -> void:
	var screen := _make_screen()
	var expected: Array[Color] = [Color("#1e5aa8"), Color("#178a4b"), Color("#178a4b"), Color("#576574")]
	for i: int in range(4):
		assert_eq(screen.chips[i].fill, expected[i])
		assert_eq(screen.chips[i].custom_minimum_size.y, 30.0)


func test_timeout_copy_follows_the_config() -> void:
	var cfg := _config()
	cfg.battle_timeout_ticks = 120 * cfg.tick_rate
	var screen := _make_screen(cfg)
	assert_eq(screen.rule_labels[2].get_parsed_text(),
			"Out of time means the defense wins. The timer stops the battle at 2:00.")
	assert_string_ends_with(screen.step_bodies[2].text, "You have two minutes.")


func test_phage_multiplier_copy_follows_the_config() -> void:
	var cfg := _config()
	(cfg.pathogens["bacteriophage"] as PathogenDef).damage_multipliers_pct["defense"] = 200
	var screen := _make_screen(cfg)
	assert_eq(screen.rule_labels[1].get_parsed_text(),
			"Bacteriophages hit defenses hard. Double damage against Macrophages and B-Cells.")


func test_number_words() -> void:
	assert_eq(HowToPlayScreen.multiplier_word(300), "Triple")
	assert_eq(HowToPlayScreen.multiplier_word(200), "Double")
	assert_eq(HowToPlayScreen.multiplier_word(400), "4x")
	assert_eq(HowToPlayScreen.multiplier_word(250), "2.5x")
	assert_eq(HowToPlayScreen.duration_text(60), "one minute")
	assert_eq(HowToPlayScreen.duration_text(300), "five minutes")
	assert_eq(HowToPlayScreen.duration_text(360), "6 minutes")
	assert_eq(HowToPlayScreen.duration_text(90), "90 seconds")
	assert_eq(HowToPlayScreen.clock_text(180), "3:00")
	assert_eq(HowToPlayScreen.clock_text(95), "1:35")


func test_start_building_remembers_the_screen_was_seen() -> void:
	var screen := _make_screen()
	assert_true(HowToPlayScreen.should_show_on_launch(TEST_PATH))
	watch_signals(screen)
	screen.start_button.pressed.emit()
	assert_signal_emitted(screen, "back_requested")
	assert_false(HowToPlayScreen.should_show_on_launch(TEST_PATH))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TEST_PATH), OK)
	assert_eq(cfg.get_value(GameSettings.SECTION_GAME, GameSettings.KEY_SEEN_HOW_TO_PLAY), true)


func test_start_building_on_the_title_goes_to_synthesis() -> void:
	var fsm := _start_fsm()
	assert_eq(fsm.phase, GameStateMachine.Phase.TITLE)
	var screen := _make_screen(null, fsm)
	screen.start_button.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	await wait_process_frames(1)


func test_start_building_from_a_hud_only_closes() -> void:
	var fsm := _start_fsm()
	fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	var screen := _make_screen(null, fsm)
	watch_signals(screen)
	screen.start_button.pressed.emit()
	assert_signal_emitted(screen, "back_requested")
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)


func test_back_emits_back_requested_without_saving() -> void:
	var screen := _make_screen()
	watch_signals(screen)
	screen.back_button.pressed.emit()
	assert_signal_emitted(screen, "back_requested")
	assert_true(HowToPlayScreen.should_show_on_launch(TEST_PATH))


func test_every_button_is_at_least_48px() -> void:
	var screen := _make_screen()
	await get_tree().process_frame
	var buttons: Array[Node] = screen.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 2)
	for node: Node in buttons:
		var b: Button = node as Button
		assert_gte(b.size.x, 48.0, "%s width" % b.name)
		assert_gte(b.size.y, 48.0, "%s height" % b.name)
	for c: Control in screen.tappable_controls():
		assert_true(buttons.has(c))
	assert_eq(screen.back_button.size, IconButton.BACK_SIZE)
	assert_eq(screen.start_button.size, HowToPlayScreen.START_SIZE)


func test_layout_matches_the_mockup() -> void:
	var screen := _make_screen()
	await get_tree().process_frame
	assert_eq(screen.back_button.position, Vector2(32.0, 28.0))
	for i: int in range(4):
		assert_eq(screen.cards[i].position, Vector2(48.0 + 301.0 * float(i), 112.0))
		assert_eq(screen.cards[i].size, HowToPlayScreen.CARD_SIZE)
	for i: int in range(3):
		assert_eq(screen.rule_cards[i].position, Vector2(48.0 + 400.0 * float(i), 560.0))
		assert_eq(screen.rule_cards[i].size, HowToPlayScreen.RULE_SIZE)
	assert_eq(screen.start_button.position, Vector2(520.0, 640.0))
	assert_eq(screen.mouse_filter, Control.MOUSE_FILTER_STOP, "blocks the screen underneath")


func test_mini_islands_are_static_demo_bases() -> void:
	var screen := _make_screen()
	await get_tree().process_frame
	assert_eq(screen.grid_views.size(), 4)
	var nights: Array[bool] = [false, true, true, true]
	for i: int in range(4):
		var view: GridView = screen.grid_views[i]
		assert_eq(view.night, nights[i])
		assert_eq(view.deploy_mode, i == 1)
		assert_false(view.is_processing_unhandled_input(), "island %d takes no input" % i)
		assert_false(view.is_processing(), "island %d is not animated" % i)
		assert_eq(view.grid.count_by_type().get("nucleus", 0), 1)
		assert_gt(view.grid.count_by_type().get("mucous_wall", 0), 0)
		assert_eq(screen.islands[i].custom_minimum_size, HowToPlayScreen.ISLAND_SIZE)
	var full: int = int(screen.grid_views[0].grid.count_by_type()["mucous_wall"])
	assert_eq(int(screen.grid_views[3].grid.count_by_type()["mucous_wall"]), full - 3, "breached wall")
	var army: Army = screen.grid_views[1].army
	assert_not_null(army)
	assert_eq(army.deployments.size(), 3)
	var grid: GridModel = screen.grid_views[1].grid
	for dep: Dictionary in army.deployments:
		assert_true(grid.is_deploy_zone(dep["cell"] as Vector2i), "markers sit on the band")


func test_islands_do_not_touch_the_session() -> void:
	var fsm := _start_fsm()
	var screen := _make_screen(null, fsm)
	for view: GridView in screen.grid_views:
		assert_ne(view.grid, fsm.session.grid)
	assert_eq(fsm.session.grid.count_by_type().get("mucous_wall", 0), 0)
	assert_eq(fsm.session.army.deployments.size(), 0)


func test_siege_units_stand_outside_the_wall_in_depth_order() -> void:
	var grid: GridModel = HowToPlayScreen.build_scene_grid(_config(), HowToPlayScreen.Scene.SIEGE)
	var last: int = -1
	for entry: Dictionary in HowToPlayScreen.SIEGE_UNITS:
		var cell: Vector2i = entry["cell"]
		assert_eq(grid.structure_id_at(cell), 0, "%s is on open ground" % cell)
		assert_gte(cell.x + cell.y, last, "back to front")
		last = cell.x + cell.y
