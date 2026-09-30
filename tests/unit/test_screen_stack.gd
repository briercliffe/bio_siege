extends GutTest

const MISSING_PATH: String = "res://tests/unit/no_such_screen.tscn"


func _make_stack() -> ScreenStack:
	var stack := ScreenStack.new()
	add_child_autofree(stack)
	# Keeps the placeholder tests valid once #75, #76 and #77 add the real scenes.
	for id: String in ScreenStack.SCREENS.keys():
		stack.scene_paths[id] = MISSING_PATH
	return stack


func test_starts_empty_and_passes_input_through() -> void:
	var stack := _make_stack()
	assert_false(stack.is_open())
	assert_eq(stack.top_id(), "")
	assert_eq(stack.depth(), 0)
	assert_eq(stack.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_screens_table_names_the_menu_scenes() -> void:
	assert_eq(ScreenStack.SCREENS["how_to_play"], "res://src/ui/screens/how_to_play_screen.tscn")
	assert_eq(ScreenStack.SCREENS["saved"], "res://src/ui/screens/saved_screen.tscn")
	assert_eq(ScreenStack.SCREENS["settings"], "res://src/ui/screens/settings_screen.tscn")


func test_push_then_pop_restores_empty_stack() -> void:
	var stack := _make_stack()
	watch_signals(stack)
	stack.push("settings")
	assert_true(stack.is_open())
	assert_eq(stack.top_id(), "settings")
	assert_eq(stack.depth(), 1)
	assert_signal_emitted_with_parameters(stack, "screen_opened", ["settings"])
	var screen: Control = stack.top_screen()
	assert_eq(screen.get_parent(), stack)

	stack.pop()
	assert_false(stack.is_open())
	assert_eq(stack.top_id(), "")
	assert_true(screen.is_queued_for_deletion())
	assert_signal_emitted_with_parameters(stack, "screen_closed", ["settings"])


func test_screens_stack_last_in_first_out() -> void:
	var stack := _make_stack()
	stack.push("settings")
	stack.push("how_to_play")
	assert_eq(stack.top_id(), "how_to_play")
	assert_eq(stack.depth(), 2)
	stack.pop()
	assert_eq(stack.top_id(), "settings")
	stack.pop()
	assert_false(stack.is_open())


func test_pop_on_empty_stack_is_a_noop() -> void:
	var stack := _make_stack()
	watch_signals(stack)
	stack.pop()
	assert_false(stack.is_open())
	assert_signal_not_emitted(stack, "screen_closed")


func test_unknown_id_is_a_noop() -> void:
	var stack := _make_stack()
	watch_signals(stack)
	stack.push("no_such_screen")
	assert_push_warning("unknown screen id 'no_such_screen'")
	assert_false(stack.is_open())
	assert_eq(stack.get_child_count(), 0)
	assert_signal_not_emitted(stack, "screen_opened")


func test_missing_scene_shows_placeholder_and_back_pops_it() -> void:
	var stack := _make_stack()
	watch_signals(stack)
	stack.push("saved")
	var placeholder: PlaceholderScreen = stack.top_screen() as PlaceholderScreen
	assert_not_null(placeholder, "a missing scene file opens the placeholder")
	assert_eq(placeholder.title_label.text, "Saved bases and armies")
	assert_eq(placeholder.mouse_filter, Control.MOUSE_FILTER_STOP, "blocks the Title underneath")
	assert_gte(placeholder.back_button.custom_minimum_size.x, 48.0)
	assert_gte(placeholder.back_button.custom_minimum_size.y, 48.0)

	placeholder.back_button.pressed.emit()
	assert_false(stack.is_open())
	assert_signal_emitted_with_parameters(stack, "screen_closed", ["saved"])


func test_back_from_a_lower_screen_does_not_pop_the_top() -> void:
	var stack := _make_stack()
	stack.push("settings")
	var lower: PlaceholderScreen = stack.top_screen() as PlaceholderScreen
	stack.push("how_to_play")
	lower.back_requested.emit()
	assert_eq(stack.top_id(), "how_to_play")
	assert_eq(stack.depth(), 2)


func test_placeholder_titles() -> void:
	var stack := _make_stack()
	stack.push("how_to_play")
	assert_eq((stack.top_screen() as PlaceholderScreen).title_label.text, "How to play")
	stack.push("settings")
	assert_eq((stack.top_screen() as PlaceholderScreen).title_label.text, "Settings")


func test_fallback_replaces_placeholder_while_scene_is_missing() -> void:
	var stack := _make_stack()
	var calls: Array[int] = [0]
	stack.fallbacks["how_to_play"] = func() -> void: calls[0] += 1
	stack.push("how_to_play")
	assert_eq(calls[0], 1)
	assert_false(stack.is_open(), "the fallback opens its own overlay, not a stack entry")


func test_clear_closes_every_screen() -> void:
	var stack := _make_stack()
	stack.push("settings")
	stack.push("saved")
	var screens: Array[Control] = [stack.top_screen()]
	watch_signals(stack)
	stack.clear()
	assert_false(stack.is_open())
	assert_eq(stack.top_id(), "")
	assert_signal_emit_count(stack, "screen_closed", 2)
	assert_true(screens[0].is_queued_for_deletion())
	stack.clear()
	assert_signal_emit_count(stack, "screen_closed", 2, "clearing an empty stack is a no-op")


func test_non_control_scene_root_falls_back_to_placeholder() -> void:
	var root := Node.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	var path: String = "user://test_node_root_screen.tscn"
	assert_eq(ResourceSaver.save(packed, path), OK)
	var stack := _make_stack()
	stack.scene_paths["settings"] = path
	stack.push("settings")
	assert_push_warning("is not a Control")
	assert_true(stack.top_screen() is PlaceholderScreen)
	assert_eq(stack.top_id(), "settings")
	DirAccess.remove_absolute(path)
