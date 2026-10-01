extends GutTest

const DIR: String = "user://test_lb_opponents"

var _cfg: GameConfig = null
var _store: LivingBaseStore = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_store = LivingBaseStore.new()
	_store.path = DIR + "/living_base.json"


func after_each() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _screen() -> Dictionary:
	var fsm := GameStateMachine.new()
	var session := Session.new(_cfg)
	fsm.session = session
	add_child_autoqfree(fsm)
	fsm.phase = GameStateMachine.Phase.SYNTHESIS
	LivingBaseFlow.new(_store).enter(session)
	var screen := OpponentScreen.new()
	add_child_autofree(screen)
	screen.setup(session, fsm)
	return {"screen": screen, "session": session, "fsm": fsm}


func test_one_card_per_opponent_with_loot_and_memory_text() -> void:
	var parts: Dictionary = _screen()
	var screen: OpponentScreen = parts["screen"]
	var session: Session = parts["session"]
	assert_eq(screen.cards.size(), 3)
	var first: OpponentScreen.OpponentCard = screen.cards[str(session.profile.opponents[0]["id"])]
	assert_gte(first.custom_minimum_size.y, 48.0)
	assert_gte(first.custom_minimum_size.x, 48.0)
	assert_eq(first.tier_label.text, "Common Cold")
	assert_eq(first.loot_label.text, "Loot: up to 75 ATP")
	assert_eq(first.raided_label.text, "Raided 0 times")
	assert_eq((first.memory_box.get_child(0) as Label).text, OpponentScreen.MEMORY_EMPTY_TEXT)


func test_memory_rows_show_what_the_base_remembers() -> void:
	var parts: Dictionary = _screen()
	var session: Session = parts["session"]
	session.profile.opponents[1]["memory"] = {"raids": 2, "entries": {"rhinovirus/wild": {"level": 2, "absent": 0, "since": 1}}}
	session.profile.opponents[1]["raids"] = 1
	var screen: OpponentScreen = parts["screen"]
	screen.setup(session, parts["fsm"])
	var card: OpponentScreen.OpponentCard = screen.cards[str(session.profile.opponents[1]["id"])]
	var row: HBoxContainer = card.memory_box.get_child(0) as HBoxContainer
	assert_eq((row.get_child(0) as Label).text, "Rhinovirus (wild)")
	assert_eq((row.get_child(1) as MemoryPanel.PipRow).level, 2)
	assert_eq(card.raided_label.text, "Raided 1 time")


func test_tapping_a_card_aims_the_session_and_goes_to_incubation() -> void:
	var parts: Dictionary = _screen()
	var screen: OpponentScreen = parts["screen"]
	var session: Session = parts["session"]
	var fsm: GameStateMachine = parts["fsm"]
	var opp: Dictionary = session.profile.opponents[1]
	watch_signals(screen)
	(screen.cards[str(opp["id"])] as Button).pressed.emit()
	assert_signal_emitted_with_parameters(screen, "opponent_chosen", [str(opp["id"])])
	assert_eq(session.attack_opponent_id, str(opp["id"]))
	assert_eq(session.attack_layout.size(), (opp["layout"] as Array).size())
	assert_not_null(session.attack_memory)
	assert_eq(fsm.phase, GameStateMachine.Phase.INCUBATION)


func test_screen_stack_opens_the_real_scene() -> void:
	assert_eq(ScreenStack.SCREENS["opponents"], "res://src/ui/screens/opponent_screen.tscn")
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	stack.push("opponents")
	assert_true(stack.top_screen() is OpponentScreen)
	(stack.top_screen() as OpponentScreen).back_requested.emit()
	assert_false(stack.is_open())


func test_hud_raid_button_opens_the_picker() -> void:
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	var fsm := GameStateMachine.new()
	fsm.session = session
	add_child_autoqfree(fsm)
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	fsm.screen_stack = stack
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	phase.setup(session, fsm)
	add_child_autofree(phase)
	phase.hud_build.btn_raid.pressed.emit()
	assert_eq(stack.top_id(), "opponents")
