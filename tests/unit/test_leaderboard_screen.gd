extends GutTest


func _screen(backend: OfflineBackend) -> LeaderboardScreen:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true}).config
	var screen := LeaderboardScreen.new()
	add_child_autofree(screen)
	screen.setup(Session.new(cfg), backend)
	return screen


func test_it_lists_the_players_and_the_own_rank() -> void:
	var b := OfflineBackend.new()
	b.respond("leaderboard_top", {"ok": true, "error": "", "records": [
		{"rank": 1, "user_id": "a", "name": "Ada", "trophies": 160},
		{"rank": 2, "user_id": "b", "name": "", "trophies": 140},
	], "me": {"rank": 2, "trophies": 140}})
	var screen: LeaderboardScreen = _screen(b)
	await get_tree().process_frame
	assert_eq(screen.rows.size(), 2)
	assert_true(screen.scroll.visible)
	assert_eq(screen.me_label.text, "You: #2 · 140 trophies")
	assert_eq(b.call_names(), ["leaderboard_top"] as Array[String])
	var texts: String = ""
	for r: Dictionary in screen.rows:
		for l: Node in (r["row"] as Node).find_children("*", "Label", true, false):
			texts += (l as Label).text + "|"
	assert_true(texts.contains("Ada"))
	assert_true(texts.contains("Player"), "an unnamed player is shown as Player")
	for r: Dictionary in screen.rows:
		assert_gte((r["row"] as Control).custom_minimum_size.y, 48.0)


func test_an_empty_board_and_an_error_show_text() -> void:
	var b := OfflineBackend.new()
	b.respond("leaderboard_top", {"ok": true, "error": "", "records": [], "me": {"rank": 0, "trophies": 0}})
	var screen: LeaderboardScreen = _screen(b)
	await get_tree().process_frame
	assert_true(screen.status_label.visible)
	assert_eq(screen.status_label.text, LeaderboardScreen.EMPTY_TEXT)
	assert_false(screen.me_label.visible)
	var bad := OfflineBackend.new()
	bad.respond("leaderboard_top", {"ok": false, "error": "rate_limited"})
	var s2: LeaderboardScreen = _screen(bad)
	await get_tree().process_frame
	assert_eq(s2.status_label.text, NetCopy.error_text("rate_limited"))


func test_back_is_a_screen_contract_signal() -> void:
	var screen: LeaderboardScreen = _screen(OfflineBackend.new())
	watch_signals(screen)
	screen.btn_back.pressed.emit()
	assert_signal_emitted(screen, "back_requested")


func test_the_hud_shows_the_leaderboard_button_only_online() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true}).config
	var store := LivingBaseStore.new()
	store.path = "user://test_lb_screen.json"
	var session := Session.new(cfg)
	var flow := LivingBaseFlow.new(store)
	flow.enter(session)
	var grid_view := GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, cfg)
	var bc := BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)
	var hud: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
	add_child_autofree(hud)
	hud.setup(session, bc)
	assert_false(hud.btn_leaderboard.visible)
	flow.online = true
	hud._update_living_base()
	assert_true(hud.btn_leaderboard.visible)
	assert_gte(hud.btn_leaderboard.custom_minimum_size.y, 48.0)
	if FileAccess.file_exists(store.path):
		DirAccess.remove_absolute(store.path)
