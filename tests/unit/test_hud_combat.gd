extends GutTest

func _load_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	return res.config

func _create_session() -> Session:
	var cfg: GameConfig = _load_config()
	return Session.new(cfg)

func _setup_hud(session: Session, runner: BattleRunner = null) -> HudCombat:
	var hud_scene: PackedScene = load("res://src/ui/hud_combat.tscn")
	assert_not_null(hud_scene)
	var hud: HudCombat = hud_scene.instantiate() as HudCombat
	add_child_autofree(hud)
	hud.setup(session, runner)
	return hud

func test_hud_timer_at_tick_3000_shows_30s_and_red_color() -> void:
	var session: Session = _create_session()
	var setup: BattleSetup = Scenarios.open_field(42)
	session.battle_setup = setup
	var sim := BattleSim.new(session.config, setup)
	sim.tick = 3000

	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.sim = sim
	runner.config = session.config

	var hud: HudCombat = _setup_hud(session, runner)

	# 3600 - 3000 = 600 ticks. 600 / 20 = 30 s. Formatted as "0:30"
	assert_eq(hud.timer_label.text, "0:30")
	assert_eq(hud.timer_color, Color("#e74c3c"))
	assert_eq(hud.timer_label.modulate, Color("#e74c3c"))

func test_hud_timer_initial_above_30s_not_red() -> void:
	var session: Session = _create_session()
	var setup: BattleSetup = Scenarios.open_field(42)
	session.battle_setup = setup
	var sim := BattleSim.new(session.config, setup)
	sim.tick = 0

	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.sim = sim
	runner.config = session.config

	var hud: HudCombat = _setup_hud(session, runner)

	# 3600 ticks / 20 = 180 s -> "3:00"
	assert_eq(hud.timer_label.text, "3:00")
	assert_ne(hud.timer_color, Color("#e74c3c"))
	assert_eq(hud.timer_color, Color.WHITE)

func test_hud_nucleus_hp_display_and_bar_color() -> void:
	var session: Session = _create_session()
	var setup: BattleSetup = Scenarios.open_field(42)
	session.battle_setup = setup
	var sim := BattleSim.new(session.config, setup)

	var nuc: StructureState = sim.structure(sim.nucleus_id)
	assert_not_null(nuc)
	nuc.max_hp = 2000
	nuc.hp = 1450

	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.sim = sim
	runner.config = session.config

	var hud: HudCombat = _setup_hud(session, runner)

	# Nucleus at 1450 hp shows NUCLEUS 1450 / 2000
	assert_eq(hud.nucleus_label.text, "NUCLEUS 1450 / 2000")
	assert_eq(hud.nucleus_bar.value, 1450.0)
	assert_eq(hud.nucleus_bar.max_value, 2000.0)
	# Ratio 1450 / 2000 = 0.725 > 0.5 -> green #2ecc71
	assert_eq(hud.nucleus_bar_color, Color("#2ecc71"))

	# Yellow range (25..50%): hp = 800 (ratio 0.40)
	nuc.hp = 800
	hud.update_display()
	assert_eq(hud.nucleus_label.text, "NUCLEUS 800 / 2000")
	assert_eq(hud.nucleus_bar_color, Color("#f1c40f"))

	# Red range (<25%): hp = 400 (ratio 0.20)
	nuc.hp = 400
	hud.update_display()
	assert_eq(hud.nucleus_label.text, "NUCLEUS 400 / 2000")
	assert_eq(hud.nucleus_bar_color, Color("#e74c3c"))

func test_hud_pathogens_alive_count() -> void:
	var session: Session = _create_session()
	var setup: BattleSetup = Scenarios.open_field(42)
	session.battle_setup = setup
	var sim := BattleSim.new(session.config, setup)

	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.sim = sim
	runner.config = session.config

	var hud: HudCombat = _setup_hud(session, runner)

	var total: int = sim.pathogens.size()
	assert_eq(hud.pathogens_label.text, "Pathogens %d / %d" % [total, total])

	# Kill 2 pathogens
	if total >= 2:
		sim.pathogens[0].alive = false
		sim.pathogens[1].alive = false
		hud.update_display()
		assert_eq(hud.pathogens_label.text, "Pathogens %d / %d" % [total - 2, total])

func test_hud_intent_lines_button_toggle() -> void:
	var session: Session = _create_session()
	session.intent_lines_enabled = true
	var hud: HudCombat = _setup_hud(session)

	assert_not_null(hud.btn_intent)
	assert_true(hud.btn_intent.custom_minimum_size.y >= 48.0)
	assert_eq(hud.btn_intent.text, "Intent lines: ON")

	# Click toggle button
	hud.btn_intent.emit_signal("pressed")
	assert_false(session.intent_lines_enabled)
	assert_eq(hud.btn_intent.text, "Intent lines: OFF")

	# Click toggle button again
	hud.btn_intent.emit_signal("pressed")
	assert_true(session.intent_lines_enabled)
	assert_eq(hud.btn_intent.text, "Intent lines: ON")

func test_structure_view_breached_and_crack_count_logic() -> void:
	var sv := StructureView.new()
	add_child_autofree(sv)

	assert_false(sv.is_breached)
	sv.set_breached(true)
	assert_true(sv.is_breached)
	sv.set_breached(false)
	assert_false(sv.is_breached)

	# Crack count logic: max_hp = 300
	sv.max_hp = 300
	# 1 crack above 66% hp (hp > 200)
	sv.hp = 250
	assert_eq(sv.get_crack_count(), 1)
	sv.hp = 201
	assert_eq(sv.get_crack_count(), 1)

	# 2 cracks from 33% to 66% (hp > 100 and hp <= 200)
	sv.hp = 200
	assert_eq(sv.get_crack_count(), 2)
	sv.hp = 150
	assert_eq(sv.get_crack_count(), 2)
	sv.hp = 101
	assert_eq(sv.get_crack_count(), 2)

	# 3 cracks below 33% (hp <= 100)
	sv.hp = 100
	assert_eq(sv.get_crack_count(), 3)
	sv.hp = 50
	assert_eq(sv.get_crack_count(), 3)
	sv.hp = 1
	assert_eq(sv.get_crack_count(), 3)

func test_intent_lines_view_visibility() -> void:
	var session: Session = _create_session()
	session.intent_lines_enabled = true
	var ilv := IntentLinesView.new()
	add_child_autofree(ilv)
	ilv.setup(session, null, {}, {})

	ilv._process(0.016)
	assert_true(ilv.visible)

	session.intent_lines_enabled = false
	ilv._process(0.016)
	assert_false(ilv.visible)

func test_hud_combat_ticked_signal_updates() -> void:
	var session: Session = _create_session()
	var setup: BattleSetup = Scenarios.open_field(42)
	session.battle_setup = setup
	var runner := BattleRunner.new()
	add_child_autofree(runner)
	runner.start(session.config, setup)

	var hud: HudCombat = _setup_hud(session, runner)
	assert_eq(hud.timer_label.text, "3:00")

	# Advance sim tick and emit ticked signal
	runner.sim.tick = 3000
	runner.ticked.emit()

	assert_eq(hud.timer_label.text, "0:30")
	assert_eq(hud.timer_color, Color("#e74c3c"))
