extends GutTest

const TEST_PATH: String = "user://test_playtest_hooks.cfg"

var _saved_path: String = ""
var _saved_muted: bool = false


func before_each() -> void:
	_saved_path = Sfx.settings_path
	_saved_muted = Sfx.muted
	Sfx.settings_path = TEST_PATH
	Sfx.muted = false
	Sfx._limiter.reset()


func after_each() -> void:
	Sfx.muted = _saved_muted
	Sfx.settings_path = _saved_path
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	for player: AudioStreamPlayer in Sfx._players:
		player.stop()


func _config() -> GameConfig:
	return GameConfig.load_from_dir("res://data").config


func _is_playing(clip_name: String) -> bool:
	for player: AudioStreamPlayer in Sfx._players:
		if player.playing and player.stream == Sfx._clips[clip_name]:
			return true
	return false


func _silence() -> void:
	for player: AudioStreamPlayer in Sfx._players:
		player.stop()
	Sfx._limiter.reset()


func _assert_button_ok(button: Button) -> void:
	assert_not_null(button)
	if button == null:
		return
	assert_gte(button.custom_minimum_size.x, 48.0)
	assert_gte(button.custom_minimum_size.y, 48.0)


# ---- HUD buttons -----------------------------------------------------------

func test_build_hud_has_help_and_mute_buttons() -> void:
	var hud: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
	add_child_autofree(hud)
	_assert_button_ok(hud.btn_help)
	_assert_button_ok(hud.btn_mute)
	assert_eq(hud.btn_help.text, "?")
	watch_signals(hud)
	hud.btn_help.pressed.emit()
	assert_signal_emit_count(hud, "help_requested", 1)


func test_spawn_hud_has_help_and_mute_buttons() -> void:
	var hud: HudSpawn = (load("res://src/ui/hud_spawn.tscn") as PackedScene).instantiate() as HudSpawn
	add_child_autofree(hud)
	_assert_button_ok(hud.btn_help)
	_assert_button_ok(hud.btn_mute)
	watch_signals(hud)
	hud.btn_help.pressed.emit()
	assert_signal_emit_count(hud, "help_requested", 1)


func test_combat_hud_has_pause_button() -> void:
	var hud: HudCombat = (load("res://src/ui/hud_combat.tscn") as PackedScene).instantiate() as HudCombat
	add_child_autofree(hud)
	_assert_button_ok(hud.pause_button)


func test_programmatic_huds_also_get_the_buttons() -> void:
	var build: HudBuild = HudBuild.new()
	add_child_autofree(build)
	_assert_button_ok(build.btn_help)
	_assert_button_ok(build.btn_mute)
	var spawn: HudSpawn = HudSpawn.new()
	add_child_autofree(spawn)
	_assert_button_ok(spawn.btn_help)
	_assert_button_ok(spawn.btn_mute)
	var combat: HudCombat = HudCombat.new()
	add_child_autofree(combat)
	_assert_button_ok(combat.pause_button)


func test_mute_button_toggles_sfx_and_stays_in_sync() -> void:
	var a: MuteButton = MuteButton.create()
	var b: MuteButton = MuteButton.create()
	add_child_autofree(a)
	add_child_autofree(b)
	_assert_button_ok(a)
	assert_false(Sfx.muted)
	a.pressed.emit()
	assert_true(Sfx.muted)
	assert_true(GameSettings.get_bool(GameSettings.SECTION_AUDIO, GameSettings.KEY_MUTED, false, TEST_PATH), "mute is saved")
	b.pressed.emit()
	assert_false(Sfx.muted)
	await wait_process_frames(2)
	assert_true(is_instance_valid(a), "icon redraw for both states did not error")


# ---- Controller signals ----------------------------------------------------

func test_build_controller_emits_placed_for_walls_and_towers() -> void:
	var session := Session.new(_config())
	var grid_view := GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)
	var bc := BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)
	var placed: Array[String] = []
	bc.placed.connect(func(type_id: String, _cell: Vector2i) -> void: placed.append(type_id))

	bc.select_tool("mucous_wall")
	grid_view.cell_pressed.emit(Vector2i(2, 2))
	grid_view.cell_dragged.emit(Vector2i(3, 2))
	grid_view.cell_released.emit(Vector2i(3, 2))
	assert_eq(placed, ["mucous_wall", "mucous_wall"] as Array[String])

	bc.select_tool("macrophage")
	grid_view.cell_pressed.emit(Vector2i(5, 5))
	grid_view.cell_released.emit(Vector2i(5, 5))
	assert_eq(placed.size(), 3)
	assert_eq(placed[2], "macrophage")


func test_build_controller_does_not_emit_placed_when_placement_fails() -> void:
	var session := Session.new(_config())
	var grid_view := GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)
	var bc := BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)
	watch_signals(bc)
	bc.select_tool("mucous_wall")
	grid_view.cell_pressed.emit(Vector2i(-1, -1))
	grid_view.cell_released.emit(Vector2i(-1, -1))
	assert_signal_not_emitted(bc, "placed")


func test_deploy_controller_emits_deployed() -> void:
	var session := Session.new(_config())
	var grid_view := GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config, session.army)
	grid_view.deploy_mode = true
	var hud := HudSpawn.new()
	add_child_autofree(hud)
	hud.setup(session)
	var dc := DeployController.new()
	add_child_autofree(dc)
	dc.setup(session, grid_view, hud)
	watch_signals(dc)

	dc.select_deploy_type("rhinovirus")
	grid_view.cell_pressed.emit(Vector2i(0, 0))
	grid_view.cell_released.emit(Vector2i(0, 0))
	assert_signal_emitted_with_parameters(dc, "deployed", ["rhinovirus", Vector2i(0, 0)])

	# Off the deploy ring nothing is deployed, so nothing sounds.
	var count_before: int = get_signal_emit_count(dc, "deployed")
	grid_view.cell_pressed.emit(Vector2i(10, 10))
	grid_view.cell_released.emit(Vector2i(10, 10))
	assert_signal_emit_count(dc, "deployed", count_before)


# ---- Phase hooks -----------------------------------------------------------

func test_synthesis_phase_plays_place_and_sell_sounds() -> void:
	var cfg: GameConfig = _config()
	var session := Session.new(cfg)
	var fsm := GameStateMachine.new()
	add_child_autofree(fsm)
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)

	_silence()
	phase.build_controller.placed.emit("mucous_wall", Vector2i(3, 3))
	assert_true(_is_playing("place"))
	_silence()
	phase.build_controller.sold.emit("mucous_wall", {"atp": 10}, Vector2i(3, 3))
	assert_true(_is_playing("sell"))


func test_synthesis_phase_plays_place_sound_on_nucleus_move() -> void:
	var cfg: GameConfig = _config()
	cfg.feature_flags["move_nucleus"] = true
	var session := Session.new(cfg)
	var fsm := GameStateMachine.new()
	add_child_autofree(fsm)
	var phase: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)
	assert_true(phase.build_controller.nucleus_moved.is_connected(phase._on_nucleus_moved))

	_silence()
	phase.build_controller.select_tool("move_nucleus")
	phase.grid_view.cell_pressed.emit(Vector2i(18, 18))
	phase.grid_view.cell_released.emit(Vector2i(4, 4))
	assert_eq(session.grid.get_structure(1).origin, Vector2i(4, 4))
	assert_true(_is_playing("place"))

	# A rejected drop makes no move sound.
	_silence()
	phase.build_controller.select_tool("move_nucleus")
	phase.grid_view.cell_pressed.emit(Vector2i(4, 4))
	phase.grid_view.cell_released.emit(Vector2i(0, 0))
	assert_false(_is_playing("place"))


func test_help_buttons_request_the_overlay_through_the_state_machine() -> void:
	var session := Session.new(_config())
	var fsm := GameStateMachine.new()
	add_child_autofree(fsm)
	watch_signals(fsm)

	var synthesis: SynthesisPhase = (load("res://src/game/phases/synthesis_phase.tscn") as PackedScene).instantiate() as SynthesisPhase
	add_child_autofree(synthesis)
	synthesis.setup(session, fsm)
	synthesis.hud_build.btn_help.pressed.emit()
	assert_signal_emit_count(fsm, "how_to_play_requested", 1)

	var incubation: IncubationPhase = (load("res://src/game/phases/incubation_phase.tscn") as PackedScene).instantiate() as IncubationPhase
	add_child_autofree(incubation)
	incubation.setup(session, fsm)
	incubation.hud_spawn.btn_help.pressed.emit()
	assert_signal_emit_count(fsm, "how_to_play_requested", 2)


func test_incubation_phase_plays_deploy_sound() -> void:
	var session := Session.new(_config())
	var fsm := GameStateMachine.new()
	add_child_autofree(fsm)
	var phase: IncubationPhase = (load("res://src/game/phases/incubation_phase.tscn") as PackedScene).instantiate() as IncubationPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)
	_silence()
	phase.deploy_controller.deployed.emit("rhinovirus", Vector2i(0, 0))
	assert_true(_is_playing("deploy"))


func _make_infection_phase() -> InfectionPhase:
	var cfg: GameConfig = _config()
	var session := Session.new(cfg)
	var fsm := GameStateMachine.new()
	fsm.phase = GameStateMachine.Phase.INFECTION
	add_child_autofree(fsm)
	session.battle_setup = Scenarios.open_field(42)
	var phase: InfectionPhase = (load("res://src/game/phases/infection_phase.tscn") as PackedScene).instantiate() as InfectionPhase
	add_child_autofree(phase)
	phase.setup(session, fsm)
	return phase


func test_infection_events_drive_sounds() -> void:
	var phase: InfectionPhase = _make_infection_phase()

	_silence()
	phase._route_event({"type": SimEvents.TOWER_FIRED, "structure_id": 0, "target_unit_id": 0})
	assert_true(_is_playing("tower_fire"))

	_silence()
	phase._route_event({"type": SimEvents.PATHOGEN_DAMAGED, "unit_id": 0, "amount": 1, "hp": 1})
	assert_true(_is_playing("hit"))

	_silence()
	phase._route_event({"type": SimEvents.STRUCTURE_DAMAGED, "structure_id": 0, "amount": 1, "hp": 1})
	assert_true(_is_playing("hit"))

	_silence()
	phase._route_event({"type": SimEvents.STRUCTURE_DESTROYED, "structure_id": 0})
	assert_true(_is_playing("destroy"))


func test_end_banner_plays_win_or_lose() -> void:
	var phase: InfectionPhase = _make_infection_phase()

	_silence()
	phase.runner.sim.end_reason = "nucleus_destroyed"
	phase._banner_shown = false
	phase._show_end_banner()
	assert_true(_is_playing("win"))
	assert_false(_is_playing("lose"))

	_silence()
	phase.runner.sim.end_reason = "timeout"
	phase._banner_shown = false
	phase._show_end_banner()
	assert_true(_is_playing("lose"))


func test_muted_sfx_makes_no_sound_from_hooks() -> void:
	var phase: InfectionPhase = _make_infection_phase()
	_silence()
	Sfx.muted = true
	phase._route_event({"type": SimEvents.STRUCTURE_DESTROYED, "structure_id": 0})
	assert_false(_is_playing("destroy"))


func test_sound_hooks_do_not_change_the_simulation() -> void:
	# The same battle, run with sound muted and unmuted, ends in an identical state hash.
	var hashes: Array[String] = []
	for muted in [true, false]:
		Sfx.muted = muted
		var phase: InfectionPhase = _make_infection_phase()
		var dt: float = 1.0 / float(phase.session.config.tick_rate)
		var steps: int = 0
		while not phase.runner.sim.finished and steps < 4000:
			phase.runner._process(dt)
			phase._process(dt)
			steps += 1
		hashes.append(phase.runner.sim.state_hash())
	assert_eq(hashes[0], hashes[1])
