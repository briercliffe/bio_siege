extends GutTest

const GALLERY: PackedScene = preload("res://tools/ui_kit_gallery.tscn")


func _touch(pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.position = pos
	ev.pressed = pressed
	return ev


func _all_nodes(root: Node, out: Array[Node]) -> void:
	out.append(root)
	for child: Node in root.get_children():
		_all_nodes(child, out)


func test_gallery_buttons_meet_touch_sizes() -> void:
	var gallery: Control = GALLERY.instantiate() as Control
	add_child_autofree(gallery)
	await wait_process_frames(2)
	var nodes: Array[Node] = []
	_all_nodes(gallery, nodes)
	var buttons: int = 0
	var primaries: int = 0
	for n: Node in nodes:
		var b: BaseButton = n as BaseButton
		if b == null:
			continue
		buttons += 1
		var min_size: Vector2 = b.get_combined_minimum_size()
		assert_gte(min_size.x, 48.0, "%s min width" % b.name)
		assert_gte(min_size.y, 48.0, "%s min height" % b.name)
		assert_gte(b.size.x, 48.0, "%s width" % b.name)
		assert_gte(b.size.y, 48.0, "%s height" % b.name)
		var pill: PillButton = b as PillButton
		if pill != null and pill.variant == PillButton.Variant.PRIMARY:
			primaries += 1
			assert_gte(min_size.y, 52.0, "primary pill min height")
			assert_gte(pill.size.y, 52.0, "primary pill height")
	assert_gt(buttons, 10, "gallery should contain many buttons")
	assert_gt(primaries, 0, "gallery should contain primary pills")


func test_gallery_contains_both_themes() -> void:
	var gallery: Control = GALLERY.instantiate() as Control
	add_child_autofree(gallery)
	await wait_process_frames(1)
	assert_not_null(gallery.get_node_or_null("Day"))
	assert_not_null(gallery.get_node_or_null("Night"))


func test_toggle_switch_touch_toggles() -> void:
	var toggle := ToggleSwitch.new()
	add_child_autofree(toggle)
	toggle.size = Vector2(64.0, 48.0)
	watch_signals(toggle)
	var inside := Vector2(32.0, 24.0)
	toggle._gui_input(_touch(inside, true))
	toggle._gui_input(_touch(inside, false))
	assert_true(toggle.button_pressed)
	assert_signal_emitted_with_parameters(toggle, "toggled", [true])
	toggle._gui_input(_touch(inside, true))
	toggle._gui_input(_touch(inside, false))
	assert_false(toggle.button_pressed)
	assert_signal_emitted_with_parameters(toggle, "toggled", [false])


func test_toggle_switch_release_outside_does_not_toggle() -> void:
	var toggle := ToggleSwitch.new()
	add_child_autofree(toggle)
	toggle.size = Vector2(64.0, 48.0)
	toggle._gui_input(_touch(Vector2(32.0, 24.0), true))
	toggle._gui_input(_touch(Vector2(200.0, 24.0), false))
	assert_false(toggle.button_pressed)


func test_toggle_switch_hit_area() -> void:
	var toggle := ToggleSwitch.new()
	add_child_autofree(toggle)
	assert_gte(toggle.custom_minimum_size.x, 64.0)
	assert_gte(toggle.custom_minimum_size.y, 48.0)


func test_stepper_card_plus_and_minus_emit() -> void:
	var card := StepperCard.new()
	add_child_autofree(card)
	watch_signals(card)
	card.plus_button.pressed.emit()
	assert_signal_emit_count(card, "plus_pressed", 1)
	card.minus_button.pressed.emit()
	assert_signal_emit_count(card, "minus_pressed", 1)
	assert_gte(card.plus_button.get_combined_minimum_size().x, 48.0)
	assert_gte(card.minus_button.get_combined_minimum_size().y, 48.0)


func test_stepper_card_plus_disabled_does_not_emit() -> void:
	var card := StepperCard.new()
	add_child_autofree(card)
	watch_signals(card)
	card.plus_enabled = false
	assert_true(card.plus_button.disabled)
	card.plus_button.pressed.emit()
	assert_signal_not_emitted(card, "plus_pressed")
	card.plus_enabled = true
	assert_false(card.plus_button.disabled)


func test_stepper_card_body_tap_emits_selected() -> void:
	var card := StepperCard.new()
	add_child_autofree(card)
	await wait_process_frames(2)
	watch_signals(card)
	card._on_gui_input(_touch(Vector2(40.0, 36.0), true))
	card._on_gui_input(_touch(Vector2(40.0, 36.0), false))
	assert_signal_emit_count(card, "selected", 1)


func test_tray_card_selected_border_is_three() -> void:
	var card := TrayCard.new()
	add_child_autofree(card)
	assert_eq(card.border_width(), 2)
	card.set_selected(true)
	assert_eq(card.border_width(), 3)
	card.set_selected(false)
	assert_eq(card.border_width(), 2)


func test_tray_card_disabled_stays_visible() -> void:
	var card := TrayCard.new()
	add_child_autofree(card)
	card.affordable = false
	assert_true(card.disabled)
	assert_true(card.visible)
	assert_gte(card.custom_minimum_size.x, 48.0)
	assert_eq(card.custom_minimum_size, TrayCard.ITEM_SIZE)


func test_tray_card_sell_variant_size() -> void:
	var card := TrayCard.new(TrayCard.Variant.SELL)
	add_child_autofree(card)
	assert_eq(card.custom_minimum_size, TrayCard.SELL_SIZE)


func test_pill_button_disabled_stays_visible() -> void:
	var b := PillButton.new("Launch Attack")
	add_child_autofree(b)
	b.disabled = true
	assert_true(b.visible)
	assert_gte(b.custom_minimum_size.y, 52.0)


func test_palette_tokens() -> void:
	assert_eq(UiPalette.for_theme(false)["ink"], Color("#12304f"))
	assert_eq(UiPalette.for_theme(true)["accent"], Color("#2ecc71"))
	assert_eq(UiPalette.for_theme(true)["on_accent"], Color("#0a2414"))
	assert_eq(UiPalette.for_theme(false)["accent"], Color("#1e5aa8"))


func test_fonts_cached_and_weighted() -> void:
	assert_eq(UiFonts.weight(800), UiFonts.weight(800))
	var bold: FontVariation = UiFonts.weight(800) as FontVariation
	var semi: FontVariation = UiFonts.weight(600) as FontVariation
	assert_almost_eq(bold.variation_embolden, 0.7, 0.0001)
	assert_almost_eq((UiFonts.weight(700) as FontVariation).variation_embolden, 0.35, 0.0001)
	assert_almost_eq(semi.variation_embolden, 0.0, 0.0001)


func test_ambient_cells_deterministic() -> void:
	var a: Array[Dictionary] = AmbientBackground.cells(1280.0, 720.0, false)
	var b: Array[Dictionary] = AmbientBackground.cells(1280.0, 720.0, false)
	assert_eq(a, b)
	assert_eq(a.size(), 14)
	for cell: Dictionary in a:
		assert_gte(cell["size"] as float, 40.0)
		assert_lt(cell["size"] as float, 190.0)
		assert_gte(cell["x"] as float, 0.0)
		assert_lt(cell["x"] as float, 1280.0)
		assert_gte(cell["y"] as float, 0.0)
		assert_lt(cell["y"] as float, 720.0)


func test_ambient_cells_min_count_and_theme_colours() -> void:
	assert_eq(AmbientBackground.cells(100.0, 100.0, true).size(), 6)
	var night_cells: Array[Dictionary] = AmbientBackground.cells(640.0, 360.0, true)
	var day_cells: Array[Dictionary] = AmbientBackground.cells(640.0, 360.0, false)
	assert_eq(night_cells[0]["x"], day_cells[0]["x"])
	assert_ne(night_cells[0]["fill"], day_cells[0]["fill"])


func _tri_area(pts: PackedVector2Array, idx: PackedInt32Array) -> float:
	var area: float = 0.0
	for i: int in range(0, idx.size(), 3):
		var a: Vector2 = pts[idx[i]]
		var b: Vector2 = pts[idx[i + 1]]
		var c: Vector2 = pts[idx[i + 2]]
		area += absf((b - a).cross(c - a)) * 0.5
	return area


func test_ambient_gradient_is_one_layer_of_flat_bands() -> void:
	var bg := AmbientBackground.new()
	bg.night = true
	bg._ensure_cache(1280.0, 720.0)
	var n: int = AmbientBackground.GRADIENT_SEGMENTS
	assert_eq(bg.triangle_counts().x, n + AmbientBackground.GRADIENT_STEPS * n * 2)
	# Non-overlapping: the band triangles add up to exactly the outer ellipse polygon, so each pixel is filled once.
	var rx: float = 640.0 * sqrt(2.0) * AmbientBackground.GRADIENT_OUTER_K
	var ry: float = 720.0 * 0.55 * sqrt(2.0) * AmbientBackground.GRADIENT_OUTER_K
	var polygon_area: float = 0.5 * float(n) * rx * ry * sin(TAU / float(n))
	assert_almost_eq(_tri_area(bg._grad_pts, bg._grad_idx), polygon_area, polygon_area * 0.0001)
	# Past the corners, so no full-screen rect is needed under it.
	assert_gt(rx * cos(PI / float(n)), 640.0 * sqrt(2.0))
	var pal: Dictionary = UiPalette.for_theme(true)
	assert_eq(bg._grad_cols[0], AmbientBackground.band_color(1, pal))
	assert_eq(bg._grad_cols[bg._grad_cols.size() - 1], pal["bg_edge"] as Color)
	assert_true(AmbientBackground.band_color(1, pal).is_equal_approx((pal["bg_center"] as Color).lerp(pal["bg_mid"] as Color, 0.5 / 24.0 / 0.55)))
	var tris: Vector2i = bg.triangle_counts()
	bg._ensure_cache(1280.0, 720.0)
	assert_eq(bg.triangle_counts(), tris, "cached per size and theme")
	bg.free()


func test_segmented_tabs_emit_tab_changed() -> void:
	var labels: Array[String] = ["A", "B", "C"]
	var tabs := SegmentedTabs.new(labels)
	add_child_autofree(tabs)
	watch_signals(tabs)
	tabs.select(2, true)
	assert_signal_emitted_with_parameters(tabs, "tab_changed", [2])
	assert_eq(tabs.selected_index, 2)


func test_dim_overlay_blocks_input() -> void:
	var dim := DimOverlay.new()
	add_child_autofree(dim)
	assert_eq(dim.mouse_filter, Control.MOUSE_FILTER_STOP)
	dim.night = true
	assert_eq(dim.color, UiPalette.color(true, "dim_overlay"))


func test_icon_painter_draws_every_icon() -> void:
	var canvas := Control.new()
	add_child_autofree(canvas)
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	assert_eq(IconPainter.ICON_IDS.size(), 8)
	# Drawing outside _draw() is not allowed, so exercise each id through a throwaway slot.
	for id: String in IconPainter.ICON_IDS:
		var slot := IconSlot.new(id, 34.0)
		slot.config = res.config
		canvas.add_child(slot)
	await wait_process_frames(2)
	assert_eq(canvas.get_child_count(), 8)


func test_theme_resources_load() -> void:
	for path: String in ["res://src/ui/theme_day.tres", "res://src/ui/theme_night.tres"]:
		var theme: Theme = load(path) as Theme
		assert_not_null(theme, path)
		assert_true(theme.has_stylebox("normal", "Button"))
		assert_true(theme.has_stylebox("panel", "PanelContainer"))
		assert_true(theme.has_stylebox("normal", "LineEdit"))
		assert_true(theme.has_color("font_color", "Label"))
