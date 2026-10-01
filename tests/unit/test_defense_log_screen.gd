extends GutTest

const DIR: String = "user://test_lb_log"

var _cfg: GameConfig = null
var _store: LivingBaseStore = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_store = LivingBaseStore.new()
	_store.path = DIR + "/living_base.json"


func after_each() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _entry(index: int, outcome: String, extra: Dictionary = {}) -> Dictionary:
	var e: Dictionary = {
		"raid_index": index, "outcome": outcome, "ticks": 100, "atp_lost": 0, "amino_gained": 0,
		"memory_changes": [], "evolution": [], "army": {"rhinovirus": 3},
	}
	e.merge(extra, true)
	return e


func _screen(log: Array[Dictionary]) -> Dictionary:
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	session.profile.defense_log = log
	var screen := DefenseLogScreen.new()
	add_child_autofree(screen)
	screen.setup(session, null)
	return {"screen": screen, "session": session}


func test_three_entries_render_three_rows_newest_first() -> void:
	var log: Array[Dictionary] = [_entry(2, "attacker", {"live": true}), _entry(1, "defender"), _entry(0, "defender")]
	var screen: DefenseLogScreen = _screen(log)["screen"]
	assert_eq(screen.rows.size(), 3)
	assert_false(screen.empty_label.visible)
	assert_eq(screen.rows[0]["row"].find_child("RaidLabel", true, false).text, "Raid #3 · live")
	assert_eq(screen.rows[1]["row"].find_child("RaidLabel", true, false).text, "Raid #2")
	assert_eq(screen.rows[2]["row"].find_child("RaidLabel", true, false).text, "Raid #1")
	assert_eq(screen.rows[0]["row"].find_child("OutcomeChip", true, false).text, "Infected")
	assert_eq(screen.rows[1]["row"].find_child("OutcomeChip", true, false).text, "Held")


func test_the_watch_button_is_touch_sized() -> void:
	var screen: DefenseLogScreen = _screen([_entry(0, "defender", {"battle": {}})] as Array[Dictionary])["screen"]
	var watch: PillButton = screen.rows[0]["watch"]
	assert_gte(watch.custom_minimum_size.x, 48.0)
	assert_gte(watch.custom_minimum_size.y, 48.0)
	assert_false(watch.disabled)
	var no_replay: DefenseLogScreen = _screen([_entry(0, "defender")] as Array[Dictionary])["screen"]
	assert_true((no_replay.rows[0]["watch"] as PillButton).disabled, "an entry without a recorded battle cannot be watched")


func test_the_empty_state_shows_when_the_log_is_empty() -> void:
	var screen: DefenseLogScreen = _screen([] as Array[Dictionary])["screen"]
	assert_true(screen.empty_label.visible)
	assert_eq(screen.empty_label.text, "No raids yet. Your base is safe for now.")
	assert_eq(screen.rows.size(), 0)
	assert_false(screen.scroll.visible)


func test_row_text() -> void:
	var cfg: GameConfig = _cfg
	assert_eq(DefenseLogScreen.army_text({"rhinovirus": 18, "staphylococcus": 4}, cfg), "18 Rhinovirus · 4 Staphylococcus")
	assert_eq(DefenseLogScreen.army_text({}, cfg), "No army")
	assert_eq(DefenseLogScreen.result_text({"atp_lost": 80, "amino_gained": 12}), "-80 ATP · +12 Amino Acids")
	assert_eq(DefenseLogScreen.result_text({}), "Nothing lost")
	assert_eq(DefenseLogScreen.learning_text([{"reason": "learned", "strain_key": "rhinovirus/wild", "to": 2}, {"reason": "waned", "strain_key": "a/b", "to": 1}], cfg), "Learned Rhinovirus/wild → level 2")
	assert_eq(DefenseLogScreen.learning_text([], cfg), "")
	assert_eq(DefenseLogScreen.evolution_text([{"type_id": "b_cell", "bred": true, "generation": 3}, {"type_id": "rhinovirus", "bred": true, "generation": 9}, {"type_id": "macrophage", "bred": false, "generation": 1}], cfg), "B-Cell pool: generation 3")
	assert_eq(DefenseLogScreen.raid_text({"raid_index": 11}), "Raid #12")


func test_learning_and_evolution_lines_show_only_when_present() -> void:
	var log: Array[Dictionary] = [
		_entry(1, "defender", {"memory_changes": [{"reason": "learned", "strain_key": "rhinovirus/wild", "to": 1}], "evolution": [{"type_id": "b_cell", "bred": true, "generation": 2}]}),
		_entry(0, "defender"),
	]
	var screen: DefenseLogScreen = _screen(log)["screen"]
	var first: Control = screen.rows[0]["row"]
	assert_not_null(first.find_child("LearningLabel", true, false))
	assert_not_null(first.find_child("EvolutionLabel", true, false))
	var second: Control = screen.rows[1]["row"]
	assert_null(second.find_child("LearningLabel", true, false))
	assert_null(second.find_child("EvolutionLabel", true, false))


func test_the_hud_defense_log_button_opens_the_screen() -> void:
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
	assert_true(phase.hud_build.btn_defense_log.visible)
	phase.hud_build.btn_defense_log.pressed.emit()
	assert_eq(stack.top_id(), "defense_log")
	assert_true(stack.top_screen() is DefenseLogScreen)


func test_the_lab_hud_has_no_defense_log_button() -> void:
	var lab := Session.new(_cfg)
	var hud: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
	add_child_autofree(hud)
	hud.setup(lab, null)
	assert_false(hud.btn_defense_log.visible)
