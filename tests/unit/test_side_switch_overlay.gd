extends GutTest


func _overlay() -> SideSwitchOverlay:
	var overlay: SideSwitchOverlay = (load("res://src/ui/side_switch_overlay.tscn") as PackedScene).instantiate() as SideSwitchOverlay
	add_child_autofree(overlay)
	watch_signals(overlay)
	return overlay


func _touch(pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.position = Vector2(100.0, 100.0)
	return ev


func test_play_shows_copy_and_countdown() -> void:
	var overlay: SideSwitchOverlay = _overlay()
	overlay.play(240)
	assert_true(overlay.visible)
	assert_eq(overlay.kicker_label.text, "END OF SYNTHESIS")
	assert_eq(overlay.title_label.text, "Switching sides")
	assert_eq(overlay.subtitle_label.text, "You are now the Pathogen")
	assert_string_contains(overlay.body_label.text, "240 ATP")
	assert_string_contains(overlay.countdown_label.text, "3 s")
	assert_eq(overlay.btn_begin.text, "Begin Incubation")


func test_countdown_ticks_down_each_second() -> void:
	var overlay: SideSwitchOverlay = _overlay()
	overlay.play(10)
	for i: int in range(4):
		overlay._process(0.25)
	assert_string_contains(overlay.countdown_label.text, "2 s")
	for i: int in range(4):
		overlay._process(0.25)
	assert_string_contains(overlay.countdown_label.text, "1 s")


func test_begin_button_skips() -> void:
	var overlay: SideSwitchOverlay = _overlay()
	overlay.play(10)
	overlay.btn_begin.pressed.emit()
	await wait_seconds(0.4)
	assert_signal_emitted_with_parameters(overlay, "finished", [_duration(overlay), true])
	assert_false(overlay.visible)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func _duration(overlay: SideSwitchOverlay) -> int:
	var params: Array = get_signal_parameters(overlay, "finished", 0)
	return params[0] as int


func test_running_out_finishes_unskipped() -> void:
	var overlay: SideSwitchOverlay = _overlay()
	overlay.play(10)
	for i: int in range(13):
		overlay._process(0.25)
	await wait_seconds(0.4)
	assert_signal_emit_count(overlay, "finished", 1)
	var params: Array = get_signal_parameters(overlay, "finished", 0)
	assert_false(params[1] as bool)


func test_mouse_button_does_nothing_and_touch_dismisses() -> void:
	var overlay: SideSwitchOverlay = _overlay()
	overlay.play(10)
	var mb := InputEventMouseButton.new()
	mb.pressed = true
	mb.button_index = MOUSE_BUTTON_LEFT
	overlay._gui_input(mb)
	await wait_seconds(0.4)
	assert_signal_not_emitted(overlay, "finished")
	assert_true(overlay.visible)
	overlay._gui_input(_touch(true))
	await wait_seconds(0.4)
	assert_signal_emit_count(overlay, "finished", 1)
	var params: Array = get_signal_parameters(overlay, "finished", 0)
	assert_true(params[1] as bool)


func test_button_is_tappable_size() -> void:
	var overlay: SideSwitchOverlay = _overlay()
	overlay.play(10)
	assert_gte(overlay.btn_begin.custom_minimum_size.y, 48.0)
	assert_gte(overlay.btn_begin.custom_minimum_size.y, 60.0)
