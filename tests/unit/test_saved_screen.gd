extends GutTest

const SavedScene: PackedScene = preload("res://src/ui/screens/saved_screen.tscn")
const ROOT: String = "user://test_saved_screen"
const SETTINGS_PATH: String = "user://test_saved_screen.cfg"
const NOW: int = 1790726400
const DAY: int = 86400


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	_remove_tree(ROOT)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


static func _remove_tree(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for sub: String in DirAccess.get_directories_at(dir_path):
		_remove_tree("%s/%s" % [dir_path, sub])
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute("%s/%s" % [dir_path, file_name])
	DirAccess.remove_absolute(dir_path)


func _config() -> GameConfig:
	return GameConfig.load_from_dir("res://data").config


func _seed_bases(cfg: GameConfig, names: Array[String]) -> void:
	var lib := SaveLibrary.new(ROOT)
	var grid: GridModel = TitleScreen.build_demo_grid(cfg)
	for i: int in range(names.size()):
		lib.now_unix = NOW - i * DAY
		assert_true(lib.save_base(names[i], grid, cfg)["ok"])


func _seed_army(cfg: GameConfig, slot_name: String) -> void:
	var army := Army.new(cfg)
	var wallet := Wallet.new(cfg.start_wallet)
	for i: int in range(3):
		army.buy("rhinovirus", wallet)
		army.deploy("rhinovirus", Vector2i(0, 5 + i))
	var lib := SaveLibrary.new(ROOT)
	lib.now_unix = NOW
	assert_true(lib.save_army(slot_name, army, cfg)["ok"])


## A screen laid out at the 1280x720 design size (the headless viewport is square).
func _make_screen(cfg: GameConfig, fsm: GameStateMachine = null) -> SavedScreen:
	var host := Control.new()
	host.size = SavedScreen.DESIGN_SIZE
	add_child_autofree(host)
	var screen: SavedScreen = SavedScene.instantiate() as SavedScreen
	screen.now_unix = NOW
	host.add_child(screen)
	screen.setup(ROOT, fsm, cfg)
	return screen


func _start_fsm() -> GameStateMachine:
	var fsm := GameStateMachine.new()
	fsm.settings_path = SETTINGS_PATH
	fsm.saves_root = ROOT
	add_child_autoqfree(fsm)
	fsm.start()
	return fsm


func test_three_base_slots_show_three_cards_and_an_empty_card() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort", "Sniper cluster", "Double ring"] as Array[String])
	var screen := _make_screen(cfg)
	assert_eq(screen.slot_cards.size(), 3)
	assert_not_null(screen.empty_card)
	assert_eq(screen.grid_box.get_child_count(), 4, "3 slot cards plus 1 empty card")
	assert_eq(screen.grid_box.get_child(3), screen.empty_card, "the empty card comes last")
	assert_eq(screen.empty_card.body, "Build a base, then save it from the menu.")
	assert_eq(screen.slot_cards[0].name_label.text, "Ring fort")
	assert_eq(screen.slot_cards[0].time_label.text, "Saved today")
	assert_eq(screen.slot_cards[1].time_label.text, "Saved yesterday")
	assert_eq(screen.slot_cards[2].time_label.text, "Saved 2 days ago")
	var summary: Dictionary = SaveLibrary.summary_for_base(TitleScreen.build_demo_grid(cfg), cfg)
	assert_eq(screen.slot_cards[0].summary_label.text, SaveLibrary.summary_text("base", summary))
	assert_true(screen.slot_cards[0].thumb is SavedScreen.BaseThumb)
	assert_eq(screen.kicker_label.text, "YOUR LIBRARY")
	assert_eq(screen.title_label.text, "Saved bases and armies")
	assert_eq(screen.footer_label.text,
			"Shared files are versioned JSON, so friends and the balance tools can load them.")


func test_full_library_has_no_empty_card() -> void:
	var cfg := _config()
	var names: Array[String] = []
	for i: int in range(SaveLibrary.MAX_SLOTS):
		names.append("Base %d" % (i + 1))
	_seed_bases(cfg, names)
	var screen := _make_screen(cfg)
	assert_eq(screen.slot_cards.size(), 12)
	assert_null(screen.empty_card)
	assert_eq(screen.scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO, "more than 4 slots scroll")


func test_switching_tabs_shows_armies() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort", "Sniper cluster"] as Array[String])
	_seed_army(cfg, "Swarm")
	var screen := _make_screen(cfg)
	assert_eq(screen.slot_cards.size(), 2)
	var army_tab: Button = screen.tabs.get_child(1) as Button
	army_tab.pressed.emit()
	assert_eq(screen.kind, "army")
	assert_eq(screen.tabs.selected_index, 1)
	assert_eq(screen.slot_cards.size(), 1)
	assert_eq(screen.slot_cards[0].name_label.text, "Swarm")
	assert_eq(screen.slot_cards[0].summary_label.text, "%d ATP · 3 units" % (3 * int(cfg.pathogens["rhinovirus"].cost["atp"])))
	var thumb: SavedScreen.ArmyThumb = screen.slot_cards[0].thumb as SavedScreen.ArmyThumb
	assert_not_null(thumb, "an army shows its units, not an island")
	assert_eq(thumb.rows.size(), 1)
	assert_eq(int(thumb.rows[0]["count"]), 3)
	assert_eq(screen.empty_card.body, "Buy an army, then save it from the menu.")
	screen.open_tab("base")
	assert_eq(screen.tabs.selected_index, 0)
	assert_eq(screen.slot_cards.size(), 2)


func test_delete_asks_first_and_confirming_removes_the_card() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort", "Sniper cluster", "Double ring"] as Array[String])
	var screen := _make_screen(cfg)
	var path: String = str(screen.slot_cards[0].slot["path"])
	screen.slot_cards[0].delete_button.pressed.emit()
	assert_true(screen.confirm_popup.visible, "Del opens a confirmation")
	assert_eq(screen.confirm_popup.dialog_text, "Delete 'Ring fort'?")
	assert_eq(screen.slot_cards.size(), 3, "nothing is deleted before confirming")

	screen.confirm_popup.get_cancel_button().pressed.emit()
	assert_false(screen.confirm_popup.visible)
	assert_true(FileAccess.file_exists(path), "cancel keeps the slot")

	screen.slot_cards[0].delete_button.pressed.emit()
	screen.confirm_popup.get_ok_button().pressed.emit()
	assert_false(FileAccess.file_exists(path))
	assert_eq(screen.slot_cards.size(), 2)
	assert_eq(screen.slot_cards[0].name_label.text, "Sniper cluster")


func test_every_button_is_at_least_48x48() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort", "Sniper cluster", "Double ring"] as Array[String])
	var screen := _make_screen(cfg)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(screen.size, SavedScreen.DESIGN_SIZE)
	var checked: int = 0
	for node: Node in screen.find_children("*", "Button", true, false):
		var b: Button = node as Button
		if not b.is_visible_in_tree():
			continue
		assert_gte(b.size.x, 48.0, "%s width" % b.get_path())
		assert_gte(b.size.y, 48.0, "%s height" % b.get_path())
		checked += 1
	assert_eq(checked, screen.tappable_controls().size())
	assert_eq(checked, 2 + 2 + 3 * 3, "Back, Import, two tabs and three buttons per card")
	var card: SavedScreen.SlotCard = screen.slot_cards[0]
	assert_eq(card.share_button.size, SavedScreen.SHARE_SIZE)
	assert_eq(card.delete_button.size, SavedScreen.DELETE_SIZE)
	assert_gte(card.load_button.size.x, SavedScreen.LOAD_SIZE.x)
	assert_eq(screen.import_button.size, SavedScreen.IMPORT_SIZE)
	assert_eq(card.size, SavedScreen.CARD_SIZE)


func test_layout_matches_the_mockup_positions() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort"] as Array[String])
	var screen := _make_screen(cfg)
	await get_tree().process_frame
	assert_eq(screen.tabs.position, Vector2(490.0, 112.0))
	assert_eq(screen.tabs.size, Vector2(300.0, 56.0))
	assert_eq(screen.import_button.position, Vector2(1280.0 - 32.0 - 136.0, 28.0))
	assert_eq(screen.slot_cards[0].get_global_rect().position, Vector2(48.0, 196.0))
	assert_eq(screen.empty_card.get_global_rect().position, Vector2(48.0 + 281.0 + 20.0, 196.0))


func test_share_copies_to_the_clipboard_off_the_web() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort"] as Array[String])
	var screen := _make_screen(cfg)
	screen.slot_cards[0].share_button.pressed.emit()
	assert_eq(screen.toast.last_message, "Copied to clipboard")


func test_import_saves_a_new_slot_and_shows_errors_in_the_dialog() -> void:
	var cfg := _config()
	var screen := _make_screen(cfg)
	screen.import_button.pressed.emit()
	assert_true(screen.import_dialog.visible)
	assert_false(screen.import_text("{nope"))
	assert_true(screen.import_dialog.visible)
	assert_true(screen.import_dialog.error_label.visible)
	assert_string_starts_with(screen.import_dialog.error_label.text, "Invalid JSON")

	var army_json: String = SnapshotIO.to_json(SnapshotIO.army_to_dict([{"type": "rhinovirus", "cell": Vector2i(0, 5)}]))
	assert_true(screen.import_text(army_json))
	assert_false(screen.import_dialog.visible)
	assert_eq(screen.kind, "army", "shows the tab of what was imported")
	assert_eq(screen.slot_cards.size(), 1)
	assert_eq(screen.slot_cards[0].name_label.text, "Imported army 1")


func test_loading_a_base_from_the_title_goes_to_synthesis() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort"] as Array[String])
	var fsm := _start_fsm()
	var screen := _make_screen(fsm.session.config, fsm)
	screen.slot_cards[0].load_button.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	var demo: GridModel = TitleScreen.build_demo_grid(cfg)
	assert_eq(fsm.session.grid.structures().size(), demo.structures().size())
	assert_eq(fsm.session.wallet.get_amount("atp"),
			int(cfg.start_wallet["atp"]) - int(demo.total_cost().get("atp", 0)))


func test_loading_a_base_in_incubation_refunds_the_army_and_goes_to_synthesis() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort"] as Array[String])
	var fsm := _start_fsm()
	fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)
	assert_true(fsm.session.army.buy("rhinovirus", fsm.session.wallet))
	assert_true(fsm.session.army.deploy("rhinovirus", Vector2i(0, 5)))
	assert_true(fsm.session.army.buy("bacteriophage", fsm.session.wallet))
	var screen := _make_screen(fsm.session.config, fsm)
	screen.slot_cards[0].load_button.pressed.emit()
	assert_eq(fsm.phase, GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.session.army.total_count(), 0, "the army was refunded")
	var demo: GridModel = TitleScreen.build_demo_grid(cfg)
	assert_eq(fsm.session.grid.structures().size(), demo.structures().size())
	assert_eq(fsm.session.wallet.get_amount("atp"),
			int(cfg.start_wallet["atp"]) - int(demo.total_cost().get("atp", 0)),
			"the wallet is the start budget minus the base, with nothing left in the army")


func test_armies_load_only_in_incubation() -> void:
	var cfg := _config()
	_seed_army(cfg, "Swarm")
	var fsm := _start_fsm()
	var screen := _make_screen(fsm.session.config, fsm)
	screen.open_tab("army")
	screen.slot_cards[0].load_button.pressed.emit()
	assert_eq(screen.toast.last_message, "Load armies from the Incubation menu")
	assert_eq(fsm.session.army.total_count(), 0)

	fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
	fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	fsm.session.army.buy("bacteriophage", fsm.session.wallet)
	var screen2 := _make_screen(fsm.session.config, fsm)
	screen2.open_tab("army")
	watch_signals(screen2)
	screen2.slot_cards[0].load_button.pressed.emit()
	assert_signal_emitted(screen2, "back_requested", "the screen closes after loading")
	assert_eq(fsm.session.army.total_count(), 3, "the current army was refunded and replaced")
	assert_eq(fsm.session.army.deployed_count("rhinovirus"), 3)
	assert_eq(fsm.session.wallet.get_amount("atp"),
			int(cfg.start_wallet["atp"]) - 3 * int(cfg.pathogens["rhinovirus"].cost["atp"]))


func test_nothing_is_read_before_setup() -> void:
	var screen: SavedScreen = SavedScene.instantiate() as SavedScreen
	add_child_autofree(screen)
	assert_null(screen.library)
	assert_eq(screen.slot_cards.size(), 0)
	screen.setup(ROOT, null, _config())
	assert_true(screen.library.legacy_dirs.is_empty(), "the screen never migrates on its own")


func test_card_buttons_let_drags_reach_the_scroll() -> void:
	var cfg := _config()
	_seed_bases(cfg, ["Ring fort"] as Array[String])
	var screen := _make_screen(cfg)
	var card: SavedScreen.SlotCard = screen.slot_cards[0]
	for b: Button in [card.load_button, card.share_button, card.delete_button]:
		assert_eq(b.mouse_filter, Control.MOUSE_FILTER_PASS, b.name)
