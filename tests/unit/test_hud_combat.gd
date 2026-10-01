extends GutTest

const HudScene: PackedScene = preload("res://src/ui/hud_combat.tscn")

var _config: GameConfig = null


func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	_config = res.config


func _session() -> Session:
	return Session.new(_config)


func _runner_with(sim: BattleSim) -> BattleRunner:
	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.sim = sim
	runner.config = _config
	return runner


func _setup_hud(session: Session, runner: BattleRunner = null) -> HudCombat:
	var hud: HudCombat = HudScene.instantiate() as HudCombat
	add_child_autofree(hud)
	hud.setup(session, runner)
	return hud


func _mixed_sim() -> BattleSim:
	return BattleSim.new(_config, Scenarios.mixed([], 42))


func _mmss(ticks: int) -> String:
	var s: int = maxi(ticks, 0) / _config.tick_rate
	return "%d:%02d" % [s / 60, s % 60]


func test_timer_shows_mm_ss_of_timeout_minus_tick() -> void:
	var sim: BattleSim = _mixed_sim()
	var hud: HudCombat = _setup_hud(_session(), _runner_with(sim))
	var timeout: int = _config.battle_timeout_ticks
	assert_eq(hud.timer_label.text, _mmss(timeout))
	for tick: int in [0, 1, timeout / 3, timeout - 25 * _config.tick_rate, timeout - 1, timeout, timeout + 50]:
		sim.tick = tick
		hud.update_display()
		assert_eq(hud.timer_label.text, _mmss(timeout - tick), "tick %d" % tick)


func test_timer_turns_danger_colour_below_20_seconds() -> void:
	var sim: BattleSim = _mixed_sim()
	var hud: HudCombat = _setup_hud(_session(), _runner_with(sim))
	var timeout: int = _config.battle_timeout_ticks
	sim.tick = timeout - 20 * _config.tick_rate
	hud.update_display()
	assert_eq(hud.timer_color, UiPalette.color(true, "ink"), "exactly 20 s left is not yet red")
	sim.tick = timeout - 20 * _config.tick_rate + _config.tick_rate
	hud.update_display()
	assert_eq(hud.timer_label.text, "0:19")
	assert_eq(hud.timer_color, Color("#ff8a7e"))
	assert_eq(hud.timer_label.get_theme_color("font_color"), Color("#ff8a7e"))


func test_alive_shows_alive_and_total_pathogens() -> void:
	var sim: BattleSim = _mixed_sim()
	var hud: HudCombat = _setup_hud(_session(), _runner_with(sim))
	var total: int = sim.pathogens.size()
	assert_gt(total, 2)
	assert_eq(hud.alive_value_label.text, str(total))
	assert_eq(hud.alive_total_label.text, "of %d" % total)
	sim.pathogens[0].alive = false
	sim.pathogens[3].alive = false
	hud.update_display()
	assert_eq(hud.alive_value_label.text, str(total - 2))
	assert_eq(hud.alive_total_label.text, "of %d" % total)


func test_army_rows_show_alive_of_launched_per_type() -> void:
	var sim: BattleSim = _mixed_sim()
	var hud: HudCombat = _setup_hud(_session(), _runner_with(sim))
	var launched: Dictionary = {}
	for p: PathogenState in sim.pathogens:
		launched[p.type_id] = int(launched.get(p.type_id, 0)) + 1
	assert_eq(hud.army_rows.size(), launched.size())
	for id: Variant in launched.keys():
		var row: ListRow = hud.army_rows[id] as ListRow
		assert_eq(row.count_text(), "%d of %d" % [launched[id], launched[id]], str(id))
	for p: PathogenState in sim.pathogens:
		if p.type_id == "rhinovirus":
			p.alive = false
			break
	hud.update_display()
	var rhino: int = int(launched["rhinovirus"])
	assert_eq((hud.army_rows["rhinovirus"] as ListRow).count_text(), "%d of %d" % [rhino - 1, rhino])
	assert_eq(hud.army_box.get_child_count(), launched.size(), "rows are reused, not re-added")


func test_walls_and_towers_tiles_count_after_destroying_one_of_each() -> void:
	var sim: BattleSim = _mixed_sim()
	var hud: HudCombat = _setup_hud(_session(), _runner_with(sim))
	var walls: Array[StructureState] = []
	var towers: Array[StructureState] = []
	for s: StructureState in sim.structures:
		if s.def.has_tag("wall"):
			walls.append(s)
		elif s.def.has_attack:
			towers.append(s)
	assert_gt(walls.size(), 0)
	assert_gt(towers.size(), 0)
	assert_eq(hud.walls_tile.value_text(), str(walls.size()))
	assert_eq(hud.walls_tile.suffix_text(), "of %d" % walls.size())
	assert_eq(hud.towers_tile.value_text(), str(towers.size()))
	assert_eq(hud.towers_tile.suffix_text(), "of %d" % towers.size())

	walls[0].alive = false
	towers[0].alive = false
	hud.update_display()
	assert_eq(hud.walls_tile.value_text(), str(walls.size() - 1))
	assert_eq(hud.walls_tile.suffix_text(), "of %d" % walls.size())
	assert_eq(hud.towers_tile.value_text(), str(towers.size() - 1))
	assert_eq(hud.towers_tile.suffix_text(), "of %d" % towers.size())


func test_nucleus_text_shows_hp_of_max_hp() -> void:
	var sim: BattleSim = _mixed_sim()
	var nuc: StructureState = sim.structure(sim.nucleus_id)
	assert_not_null(nuc)
	var hud: HudCombat = _setup_hud(_session(), _runner_with(sim))
	assert_eq(hud.nucleus_hp_label.text, str(nuc.max_hp))
	assert_eq(hud.nucleus_max_label.text, " / %d" % nuc.max_hp)
	assert_almost_eq(hud.nucleus_bar.ratio, 1.0, 0.0001)

	nuc.hp = nuc.max_hp * 2 / 3
	hud.update_display()
	assert_eq(hud.nucleus_hp_label.text, str(nuc.hp))
	assert_eq(hud.nucleus_max_label.text, " / %d" % nuc.max_hp)
	assert_almost_eq(hud.nucleus_bar.ratio, float(nuc.hp) / float(nuc.max_hp), 0.0001)


func test_nucleus_before_a_sim_uses_the_config_hp() -> void:
	var hud: HudCombat = _setup_hud(_session())
	var hp: int = (_config.structures["nucleus"] as StructureDef).hp
	assert_eq(hud.nucleus_hp_label.text, str(hp))
	assert_eq(hud.nucleus_max_label.text, " / %d" % hp)


func test_intent_toggle_flips_session_intent_lines() -> void:
	var session: Session = _session()
	session.intent_lines_enabled = true
	var hud: HudCombat = _setup_hud(session)
	assert_true(hud.intent_switch.button_pressed)
	assert_gte(hud.intent_switch.custom_minimum_size.y, 48.0)

	hud.intent_switch.button_pressed = false
	assert_false(session.intent_lines_enabled)
	hud.intent_switch.button_pressed = true
	assert_true(session.intent_lines_enabled)

	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = hud.intent_switch.custom_minimum_size * 0.5
	var release := InputEventScreenTouch.new()
	release.pressed = false
	release.position = press.position
	hud.intent_switch._gui_input(press)
	hud.intent_switch._gui_input(release)
	assert_false(session.intent_lines_enabled, "a tap on the switch turns intent lines off")


func test_switch_follows_session_changes_made_elsewhere() -> void:
	var session: Session = _session()
	session.intent_lines_enabled = true
	var hud: HudCombat = _setup_hud(session)
	session.intent_lines_enabled = false
	hud.update_display()
	assert_false(hud.intent_switch.button_pressed)
	assert_false(session.intent_lines_enabled, "syncing the switch does not write back")


func test_pause_button_is_52_px_and_emits_pause_requested() -> void:
	var hud: HudCombat = _setup_hud(_session())
	assert_eq(hud.pause_button.kind, IconButton.Kind.PAUSE)
	assert_gte(hud.pause_button.custom_minimum_size.x, 48.0)
	assert_gte(hud.pause_button.custom_minimum_size.y, 48.0)
	watch_signals(hud)
	hud.pause_button.pressed.emit()
	assert_signal_emit_count(hud, "pause_requested", 1)


func test_layout_matches_mockup_at_1280x720() -> void:
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	add_child_autofree(host)
	var hud: HudCombat = HudScene.instantiate() as HudCombat
	host.add_child(hud)
	hud.setup(_session(), _runner_with(_mixed_sim()))
	await wait_process_frames(2)
	assert_eq(hud.pause_button.get_rect(), Rect2(20.0, 14.0, 52.0, 52.0))
	assert_eq(hud.phase_pill.position, Vector2(84.0, 14.0))
	assert_eq(hud.timer_pill.get_rect(), Rect2(530.0, 10.0, 220.0, 56.0))
	assert_almost_eq(hud.alive_pill.get_rect().end.x, 1260.0, 0.5)
	assert_eq(hud.alive_pill.position.y, 14.0)
	assert_eq(hud.left_card.position, Vector2(20.0, 96.0))
	assert_eq(hud.left_card.size.x, 300.0)
	assert_almost_eq(hud.right_card.get_rect().end.x, 1260.0, 0.5)
	assert_eq(hud.right_card.position.y, 96.0)
	assert_eq(hud.right_card.size.x, 300.0)
	assert_eq(hud.nucleus_card.get_rect(), Rect2(226.0, 632.0, 828.0, 72.0))


func test_hud_combat_ticked_signal_updates() -> void:
	var session: Session = _session()
	var setup: BattleSetup = Scenarios.open_field(42)
	session.battle_setup = setup
	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.start(session.config, setup)
	var hud: HudCombat = _setup_hud(session, runner)
	assert_eq(hud.timer_label.text, _mmss(_config.battle_timeout_ticks))
	runner.sim.tick = _config.battle_timeout_ticks - 30 * _config.tick_rate
	runner.ticked.emit()
	assert_eq(hud.timer_label.text, "0:30")


func test_set_sim_overrides_the_runner_sim() -> void:
	var hud: HudCombat = _setup_hud(_session())
	var sim: BattleSim = _mixed_sim()
	sim.tick = _config.tick_rate * 60
	hud.set_sim(sim)
	assert_eq(hud.timer_label.text, _mmss(_config.battle_timeout_ticks - sim.tick))
	assert_eq(hud.alive_total_label.text, "of %d" % sim.pathogens.size())


func test_wall_crack_pulse_stays_between_0_6_and_1_on_a_0_8s_cycle() -> void:
	var lo: float = 2.0
	var hi: float = -1.0
	for i: int in range(80):
		var a: float = UnitLayer.crack_pulse_alpha(float(i) * 0.01)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	assert_almost_eq(lo, 0.6, 0.01)
	assert_almost_eq(hi, 1.0, 0.01)
	assert_almost_eq(UnitLayer.crack_pulse_alpha(0.1), UnitLayer.crack_pulse_alpha(0.9), 0.0001)


func test_intent_lines_view_visibility() -> void:
	var session: Session = _session()
	session.intent_lines_enabled = true
	var ilv := IntentLinesView.new()
	add_child_autofree(ilv)
	ilv.setup(session, null, null, null)

	ilv._process(0.016)
	assert_true(ilv.visible)

	session.intent_lines_enabled = false
	ilv._process(0.016)
	assert_false(ilv.visible)
