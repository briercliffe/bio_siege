extends Control

## Dev-only gallery: every UI kit component in both themes, side by side on AmbientBackground.
## Open tools/ui_kit_gallery.tscn and run it (F6) to eyeball the kit against the mockups.

const COLUMN_WIDTH: float = 640.0
const COLUMN_HEIGHT: float = 1420.0
const MARGIN: float = 20.0

var _config: GameConfig = null


func _ready() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	if res.is_ok():
		_config = res.config
	custom_minimum_size = Vector2(COLUMN_WIDTH * 2.0, COLUMN_HEIGHT)
	for i: int in range(2):
		var column: Control = _build_column(i == 1)
		column.position = Vector2(COLUMN_WIDTH * float(i), 0.0)
		add_child(column)


func _build_column(night: bool) -> Control:
	var column := Control.new()
	column.name = "Night" if night else "Day"
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, COLUMN_HEIGHT)
	column.size = column.custom_minimum_size
	column.clip_contents = true
	var bg := AmbientBackground.new()
	bg.night = night
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(MARGIN, MARGIN)
	box.size = Vector2(COLUMN_WIDTH - MARGIN * 2.0, COLUMN_HEIGHT - MARGIN * 2.0)
	box.add_theme_constant_override("separation", 16)
	column.add_child(box)

	var pal: Dictionary = UiPalette.for_theme(night)
	box.add_child(_heading("NIGHT THEME" if night else "DAY THEME", pal))

	box.add_child(_pills_row(night))
	box.add_child(_buttons_row(night))
	box.add_child(_icon_buttons_row(night))
	box.add_child(_card_and_tiles(night))
	box.add_child(_tray_row(night))
	box.add_child(_steppers(night))
	box.add_child(_controls_row(night))
	box.add_child(_list_rows(night))
	box.add_child(_dim_sample(night))
	return column


func _heading(text: String, pal: Dictionary) -> Label:
	var label := Label.new()
	label.text = text
	UiFonts.style_label(label, 14, 700, pal["muted"] as Color)
	return label


func _pills_row(night: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var atp := PillPanel.new()
	atp.night = night
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(IconSlot.new("atp", 24.0))
	var amount := Label.new()
	amount.text = "390"
	UiFonts.style_label(amount, 24, 800, UiPalette.color(night, "ink"))
	var unit := Label.new()
	unit.text = "ATP"
	UiFonts.style_label(unit, 14, 700, UiPalette.color(night, "muted"))
	inner.add_child(amount)
	inner.add_child(unit)
	atp.add_child(inner)
	row.add_child(atp)
	var phase := PillPanel.new()
	phase.night = night
	phase.set_phase("PHASE 1 · SYNTHESIS" if not night else "PHASE 2 · INCUBATION",
			"Build your defense" if not night else "Grow your army")
	row.add_child(phase)
	return row


func _buttons_row(night: bool) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	var primary := PillButton.new("Finalize Base" if not night else "Launch Attack")
	primary.night = night
	primary.custom_minimum_size.x = 164.0
	flow.add_child(primary)
	var disabled := PillButton.new("Launch Attack")
	disabled.night = night
	disabled.disabled = true
	disabled.custom_minimum_size.x = 164.0
	flow.add_child(disabled)
	var secondary := PillButton.new("Re-raid", PillButton.Variant.SECONDARY)
	secondary.night = night
	secondary.subtitle = "Same base, new army"
	secondary.custom_minimum_size.x = 210.0
	flow.add_child(secondary)
	var danger := PillButton.new("Quit", PillButton.Variant.DANGER_OUTLINE)
	danger.night = night
	flow.add_child(danger)
	return flow


func _icon_buttons_row(night: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for kind: IconButton.Kind in [IconButton.Kind.MENU, IconButton.Kind.PAUSE, IconButton.Kind.BACK,
			IconButton.Kind.CLOSE, IconButton.Kind.HELP, IconButton.Kind.SPEAKER]:
		var b := IconButton.new(kind)
		b.night = night
		row.add_child(b)
	var muted := IconButton.new(IconButton.Kind.SPEAKER)
	muted.night = night
	muted.muted = true
	row.add_child(muted)
	return row


func _card_and_tiles(night: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var card := FloatingCard.new()
	card.night = night
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "B-Cell"
	UiFonts.style_label(title, 22, 800, UiPalette.color(night, "ink"))
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for pair: Array in [["Health", "250", ""], ["Damage", "75", ""], ["Kills", "12", "of 52"], ["Footprint", "3 × 3", ""]]:
		var tile := StatTile.new(pair[0] as String, pair[1] as String, pair[2] as String)
		tile.night = night
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tile)
	col.add_child(grid)
	var track := ProgressTrack.new()
	track.night = night
	track.value = 0.61
	col.add_child(track)
	var split := ProgressTrack.new()
	split.night = night
	var segs: Array[Dictionary] = [
		{"frac": 0.5, "color": UiPalette.color(night, "accent")},
		{"frac": 0.3, "color": Color("#f1c40f")},
		{"frac": 0.2, "color": Color("#e74c3c")},
	]
	split.segments = segs
	col.add_child(split)
	card.add_child(col)
	row.add_child(card)
	var badges := VBoxContainer.new()
	badges.add_theme_constant_override("separation", 10)
	for i: int in range(1, 4):
		var b := NumberBadge.new(i)
		b.night = night
		badges.add_child(b)
	row.add_child(badges)
	return row


func _tray_row(night: bool) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	var specs: Array[Array] = [
		["mucous_wall", "Mucous Wall", "5 ATP", false, true],
		["macrophage", "Macrophage", "100 ATP", false, true],
		["b_cell", "B-Cell", "150 ATP", true, true],
		["nucleus", "Nucleus", "400 ATP", false, false],
	]
	for spec: Array in specs:
		var card := TrayCard.new()
		card.night = night
		card.config = _config
		card.icon_id = spec[0] as String
		card.title = spec[1] as String
		card.cost_text = spec[2] as String
		card.set_selected(spec[3] as bool)
		card.affordable = spec[4] as bool
		flow.add_child(card)
	var sell := TrayCard.new(TrayCard.Variant.SELL)
	sell.night = night
	sell.title = "Sell"
	sell.subtitle = "100% refund"
	flow.add_child(sell)
	var empty_sell := TrayCard.new(TrayCard.Variant.SELL)
	empty_sell.night = night
	empty_sell.title = "Sell"
	empty_sell.subtitle = "Nothing to sell"
	empty_sell.affordable = false
	flow.add_child(empty_sell)
	return flow


func _steppers(night: bool) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	var a := StepperCard.new()
	a.night = night
	a.config = _config
	a.setup("rhinovirus", "Rhinovirus", "10 ATP", 3)
	a.is_chosen = true
	flow.add_child(a)
	var b := StepperCard.new()
	b.night = night
	b.config = _config
	b.setup("staphylococcus", "Staphylococcus", "40 ATP", 0)
	b.plus_enabled = false
	flow.add_child(b)
	return flow


func _controls_row(night: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 16)
	var on := ToggleSwitch.new()
	on.night = night
	on.button_pressed = true
	var off := ToggleSwitch.new()
	off.night = night
	toggles.add_child(on)
	toggles.add_child(off)
	var slider := VolumeSlider.new()
	slider.night = night
	slider.custom_minimum_size.x = 260.0
	slider.value = 0.6
	toggles.add_child(slider)
	col.add_child(toggles)
	var labels: Array[String] = ["Base", "Army", "Raid"]
	var tabs := SegmentedTabs.new(labels)
	tabs.night = night
	col.add_child(tabs)
	return col


func _list_rows(night: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var row_a := ListRow.new()
	row_a.night = night
	row_a.setup("rhinovirus", "Rhinovirus", 3, 5, _config)
	col.add_child(row_a)
	var row_b := ListRow.new()
	row_b.night = night
	row_b.setup("bacteriophage", "Bacteriophage", 1, 2, _config)
	col.add_child(row_b)
	return col


func _dim_sample(night: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(300.0, 70.0)
	holder.clip_contents = true
	var swatch := ColorRect.new()
	swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	swatch.color = UiPalette.color(night, "chip")
	holder.add_child(swatch)
	var dim := DimOverlay.new()
	dim.night = night
	holder.add_child(dim)
	var label := Label.new()
	label.text = "DimOverlay"
	label.position = Vector2(12.0, 20.0)
	UiFonts.style_label(label, 14, 700, UiPalette.color(night, "ink"))
	holder.add_child(label)
	return holder
