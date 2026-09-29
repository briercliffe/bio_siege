class_name HudCombat
extends Control

var session: Session = null
var runner: BattleRunner = null
var custom_sim: BattleSim = null

var top_bar: PanelContainer = null
var pathogens_label: Label = null
var nucleus_bar: ProgressBar = null
var nucleus_label: Label = null
var timer_label: Label = null
var btn_intent: Button = null

var timer_color: Color = Color.WHITE
var nucleus_bar_color: Color = Color("#2ecc71")
var _intent_lines_fallback: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_ensure_nodes()
	update_display()


func setup(p_session: Session, p_runner: BattleRunner) -> void:
	_ensure_nodes()
	session = p_session
	runner = p_runner
	if runner != null:
		if not runner.ticked.is_connected(_on_runner_ticked):
			runner.ticked.connect(_on_runner_ticked)
	update_display()


func set_sim(p_sim: BattleSim) -> void:
	custom_sim = p_sim
	update_display()


func get_sim() -> BattleSim:
	if custom_sim != null:
		return custom_sim
	if runner != null:
		return runner.sim
	return null


func _on_runner_ticked() -> void:
	update_display()


func _on_btn_intent_pressed() -> void:
	if session != null:
		session.intent_lines_enabled = not session.intent_lines_enabled
	else:
		_intent_lines_fallback = not _intent_lines_fallback
	_update_intent_button_text()


func _update_intent_button_text() -> void:
	if btn_intent == null:
		return
	var enabled: bool = session.intent_lines_enabled if session != null else _intent_lines_fallback
	btn_intent.text = "Intent lines: ON" if enabled else "Intent lines: OFF"


func update_display(p_sim: BattleSim = null) -> void:
	_ensure_nodes()
	if p_sim != null:
		custom_sim = p_sim
	_update_intent_button_text()

	var sim: BattleSim = get_sim()
	var cfg: GameConfig = null
	if sim != null and sim.config != null:
		cfg = sim.config
	elif runner != null and runner.config != null:
		cfg = runner.config
	elif runner != null and runner.sim != null and runner.sim.config != null:
		cfg = runner.sim.config
	elif session != null and session.config != null:
		cfg = session.config

	# Timer
	var tick_rate: int = cfg.tick_rate if (cfg != null and cfg.tick_rate > 0) else 20
	var timeout_ticks: int = cfg.battle_timeout_ticks if cfg != null else 3600
	var cur_tick: int = sim.tick if sim != null else 0
	var remaining_ticks: int = maxi(0, timeout_ticks - cur_tick)
	var remaining_s: int = remaining_ticks / tick_rate
	if timer_label != null:
		timer_label.text = "%d:%02d" % [remaining_s / 60, remaining_s % 60]
		var is_red: bool = remaining_s <= 30
		timer_color = Color("#e74c3c") if is_red else Color.WHITE
		timer_label.add_theme_color_override("font_color", timer_color)
		timer_label.modulate = timer_color

	# Nucleus HP
	var n_hp: int = 0
	var n_max_hp: int = 0
	if sim != null:
		var nuc: StructureState = null
		if sim.nucleus_id != 0:
			nuc = sim.structure(sim.nucleus_id)
		if nuc == null:
			for s: StructureState in sim.structures:
				if s.type_id == "nucleus" or (s.def != null and s.def.has_tag("core")):
					nuc = s
					break
		if nuc != null:
			n_hp = nuc.hp
			n_max_hp = nuc.max_hp
	elif session != null and session.config != null and session.config.structures.has("nucleus"):
		n_max_hp = session.config.structures["nucleus"].hp
		n_hp = n_max_hp

	if nucleus_label != null:
		nucleus_label.text = "NUCLEUS %d / %d" % [n_hp, n_max_hp]

	var ratio: float = clampf(float(n_hp) / float(n_max_hp), 0.0, 1.0) if n_max_hp > 0 else 0.0
	if ratio > 0.5:
		nucleus_bar_color = Color("#2ecc71")
	elif ratio >= 0.25:
		nucleus_bar_color = Color("#f1c40f")
	else:
		nucleus_bar_color = Color("#e74c3c")

	if nucleus_bar != null:
		nucleus_bar.min_value = 0.0
		nucleus_bar.max_value = float(n_max_hp) if n_max_hp > 0 else 1.0
		nucleus_bar.value = float(n_hp)
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = nucleus_bar_color
		nucleus_bar.add_theme_stylebox_override("fill", fill_style)
		nucleus_bar.modulate = nucleus_bar_color

	# Pathogens
	var pathogens_alive: int = 0
	var pathogens_total: int = 0
	if sim != null:
		pathogens_total = sim.pathogens.size()
		for p: PathogenState in sim.pathogens:
			if p != null and p.alive:
				pathogens_alive += 1
	if pathogens_label != null:
		pathogens_label.text = "Pathogens %d / %d" % [pathogens_alive, pathogens_total]


func _ensure_nodes() -> void:
	if top_bar != null:
		return

	top_bar = get_node_or_null("TopBar") as PanelContainer
	pathogens_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/LeftBox/PathogensLabel") as Label
	nucleus_bar = get_node_or_null("TopBar/MarginContainer/HBoxContainer/CenterBox/NucleusContainer/NucleusBar") as ProgressBar
	nucleus_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/CenterBox/NucleusContainer/NucleusLabel") as Label
	timer_label = get_node_or_null("TopBar/MarginContainer/HBoxContainer/CenterBox/TimerLabel") as Label
	btn_intent = get_node_or_null("TopBar/MarginContainer/HBoxContainer/RightBox/BtnIntent") as Button

	if btn_intent != null and not btn_intent.pressed.is_connected(_on_btn_intent_pressed):
		btn_intent.pressed.connect(_on_btn_intent_pressed)

	if top_bar != null:
		return

	_build_ui_programmatically()


func _build_ui_programmatically() -> void:
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(0.0, 64.0)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 64.0
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_bar)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 8)
	top_bar.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)

	var left_box := HBoxContainer.new()
	left_box.name = "LeftBox"
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_child(left_box)

	pathogens_label = Label.new()
	pathogens_label.name = "PathogensLabel"
	pathogens_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pathogens_label.add_theme_font_size_override("font_size", 18)
	pathogens_label.text = "Pathogens 0 / 0"
	left_box.add_child(pathogens_label)

	var center_box := VBoxContainer.new()
	center_box.name = "CenterBox"
	center_box.custom_minimum_size = Vector2(320.0, 0.0)
	center_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_theme_constant_override("separation", 2)
	hbox.add_child(center_box)

	var nuc_container := MarginContainer.new()
	nuc_container.name = "NucleusContainer"
	nuc_container.custom_minimum_size = Vector2(320.0, 20.0)
	nuc_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.add_child(nuc_container)

	nucleus_bar = ProgressBar.new()
	nucleus_bar.name = "NucleusBar"
	nucleus_bar.custom_minimum_size = Vector2(320.0, 20.0)
	nucleus_bar.show_percentage = false
	nuc_container.add_child(nucleus_bar)

	nucleus_label = Label.new()
	nucleus_label.name = "NucleusLabel"
	nucleus_label.custom_minimum_size = Vector2(320.0, 20.0)
	nucleus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nucleus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nucleus_label.add_theme_font_size_override("font_size", 13)
	nucleus_label.text = "NUCLEUS 0 / 0"
	nuc_container.add_child(nucleus_label)

	timer_label = Label.new()
	timer_label.name = "TimerLabel"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 18)
	timer_label.text = "3:00"
	center_box.add_child(timer_label)

	var right_box := HBoxContainer.new()
	right_box.name = "RightBox"
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(right_box)

	btn_intent = Button.new()
	btn_intent.name = "BtnIntent"
	btn_intent.custom_minimum_size = Vector2(160.0, 48.0)
	btn_intent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_intent.text = "Intent lines: ON"
	btn_intent.pressed.connect(_on_btn_intent_pressed)
	right_box.add_child(btn_intent)
