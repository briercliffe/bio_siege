extends GutTest


func _session(enabled: bool) -> Session:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	cfg.feature_flags["immune_memory"] = enabled
	cfg.feature_flags["bcell_analysis"] = enabled
	cfg.feature_flags["strains"] = true
	return Session.new(cfg)


func test_empty_state_and_rows() -> void:
	var session: Session = _session(true)
	var panel := MemoryPanel.new()
	add_child_autofree(panel)
	panel.setup(session)
	assert_true(panel.empty_label.visible)
	assert_eq(panel.empty_label.text, "No memory yet. B-Cells remember strains they fully analyze.")

	session.memory.entries["staphylococcus/wild"] = {"level": 1, "absent": 1, "since": 1}
	session.memory.entries["rhinovirus/capsid_hardening"] = {"level": 2, "absent": 0, "since": 2}
	panel.refresh()
	assert_false(panel.empty_label.visible)
	assert_eq(panel.rows_box.get_child_count(), 2)
	var first: Label = panel.rows_box.get_child(0).get_child(0) as Label
	assert_true(first.text.begins_with("Rhinovirus · "))
	assert_not_null(panel.rows_box.get_child(1).get_node_or_null("FadingLabel"))
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_hud_shows_panel_only_when_enabled() -> void:
	for enabled: bool in [false, true]:
		var session: Session = _session(enabled)
		var hud := HudSpawn.new()
		add_child_autofree(hud)
		hud.setup(session)
		assert_eq(hud.memory_panel != null and hud.memory_panel.visible, enabled)


func test_remembered_hint_on_strain_card() -> void:
	var session: Session = _session(true)
	session.memory.entries["rhinovirus/wild"] = {"level": 3, "absent": 0, "since": 1}
	var hud := HudSpawn.new()
	add_child_autofree(hud)
	hud.setup(session)
	var found: bool = false
	for c: HudSpawnCard in hud.cards:
		if c.type_id == "rhinovirus":
			found = c.memory_hint_label != null and c.memory_hint_label.visible and c.memory_hint_label.text == "Remembered L3"
	assert_true(found)
