extends GutTest

func _make_banner() -> DevBanner:
	var banner: DevBanner = (load("res://src/ui/dev_banner.tscn") as PackedScene).instantiate() as DevBanner
	add_child_autoqfree(banner)
	return banner


func test_format_errors_shows_all_when_three_or_fewer() -> void:
	assert_eq(DevBanner.format_errors(PackedStringArray(["a"])), "a")
	assert_eq(DevBanner.format_errors(PackedStringArray(["a", "b", "c"])), "a · b · c")


func test_format_errors_summarises_the_rest() -> void:
	var errors: PackedStringArray = PackedStringArray(["a", "b", "c", "d", "e"])
	assert_eq(DevBanner.format_errors(errors), "a · b · c · +2 more")
	assert_eq(DevBanner.format_errors(PackedStringArray(["a", "b", "c", "d"])), "a · b · c · +1 more")


func test_banner_is_hidden_at_start() -> void:
	var banner: DevBanner = _make_banner()
	assert_false(banner.visible)
	assert_eq(banner.kind, DevBanner.Kind.NONE)


func test_banner_strip_is_40px_and_top_anchored() -> void:
	var banner: DevBanner = _make_banner()
	assert_eq(banner.anchor_left, 0.0)
	assert_eq(banner.anchor_right, 1.0)
	assert_eq(banner.anchor_top, 0.0)
	assert_eq(banner.offset_top, 0.0)
	assert_eq(banner.offset_bottom, 40.0)
	assert_eq(banner.strip.custom_minimum_size.y, 40.0)


func test_dismiss_button_is_at_least_48px() -> void:
	var banner: DevBanner = _make_banner()
	assert_gte(banner.btn_dismiss.custom_minimum_size.x, 48.0)
	assert_gte(banner.btn_dismiss.custom_minimum_size.y, 48.0)
	assert_eq(banner.btn_dismiss.text, "✕")


func test_info_banner_is_blue_and_auto_hides_after_3s() -> void:
	var banner: DevBanner = _make_banner()
	banner.show_info("Config reloaded (3 values changed)")
	assert_true(banner.visible)
	assert_eq(banner.kind, DevBanner.Kind.INFO)
	assert_eq(banner.message_label.text, "Config reloaded (3 values changed)")
	var style: StyleBoxFlat = banner.strip.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(style.bg_color, DevBanner.INFO_COLOR)
	assert_false(banner.hide_timer.is_stopped())
	assert_eq(banner.hide_timer.wait_time, DevBanner.INFO_HIDE_S)
	assert_eq(DevBanner.INFO_HIDE_S, 3.0)

	banner.hide_timer.timeout.emit()
	assert_false(banner.visible)
	assert_eq(banner.kind, DevBanner.Kind.NONE)


func test_error_banner_is_red_and_stays_until_dismissed() -> void:
	var banner: DevBanner = _make_banner()
	banner.show_errors(PackedStringArray(["e1", "e2", "e3", "e4"]))
	assert_true(banner.visible)
	assert_eq(banner.kind, DevBanner.Kind.ERROR)
	assert_eq(banner.message_label.text, "e1 · e2 · e3 · +1 more")
	var style: StyleBoxFlat = banner.strip.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(style.bg_color, DevBanner.ERROR_COLOR)
	assert_true(banner.hide_timer.is_stopped(), "error banners never auto-hide")

	banner.btn_dismiss.pressed.emit()
	assert_false(banner.visible)


func test_successful_reload_message_replaces_error_banner() -> void:
	var banner: DevBanner = _make_banner()
	banner.show_errors(PackedStringArray(["bad"]))
	banner.show_info("Config reloaded (1 value changed)")
	assert_eq(banner.kind, DevBanner.Kind.INFO)
	assert_eq(banner.message_label.text, "Config reloaded (1 value changed)")
	assert_false(banner.hide_timer.is_stopped())


func test_new_error_replaces_info_and_cancels_auto_hide() -> void:
	var banner: DevBanner = _make_banner()
	banner.show_info("Config reloaded (1 value changed)")
	banner.show_errors(PackedStringArray(["bad"]))
	assert_eq(banner.kind, DevBanner.Kind.ERROR)
	assert_true(banner.hide_timer.is_stopped())


func test_main_scene_has_banner_above_all_phases() -> void:
	var main_node: Node = (load("res://src/main.tscn") as PackedScene).instantiate()
	add_child_autoqfree(main_node)
	var banner: Node = main_node.get_node_or_null("DevBanner")
	assert_not_null(banner)
	assert_true(banner is DevBanner)
	var fsm: Node = main_node.get_node("GameStateMachine")
	assert_gt(banner.get_index(), fsm.get_index(), "drawn after (above) the phase root")
	assert_eq(banner.get_index(), main_node.get_child_count() - 1)
