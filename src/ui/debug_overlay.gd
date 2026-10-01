class_name DebugOverlay
extends Control

@onready var dbg_button: Button = $DbgButton
@onready var panel: Control = $Panel
@onready var phase_label: Label = $Panel/VBoxContainer/PhaseLabel
@onready var btn_title: Button = $Panel/VBoxContainer/BtnTitle
@onready var btn_synthesis: Button = $Panel/VBoxContainer/BtnSynthesis
@onready var btn_incubation: Button = $Panel/VBoxContainer/BtnIncubation
@onready var btn_infection: Button = $Panel/VBoxContainer/BtnInfection
@onready var btn_results: Button = $Panel/VBoxContainer/BtnResults
@onready var btn_stress: Button = $Panel/VBoxContainer/BtnStress
@onready var btn_rhino_bench: Button = $Panel/VBoxContainer/BtnRhinoBench
@onready var chk_impact_ticks: CheckButton = $Panel/VBoxContainer/ChkImpactTicks
@onready var btn_replay: Button = $Panel/VBoxContainer/BtnReplay
@onready var replay_status_label: Label = $Panel/VBoxContainer/ReplayStatusLabel
@onready var btn_export_logs: Button = $Panel/VBoxContainer/BtnExportLogs

# Playtest flags (#217): a FLAGS button next to DBG opens a panel of feature flag switches.
const FLAGS_PANEL_WIDTH: float = 300.0
const FLAG_ROW_HEIGHT: float = 48.0
const FLAGS_NOTE: String = "Applies now. A battle in progress keeps its flags until it ends."

## The config owner: GameData by default. Needs `config`, `flag_override_error` and set_flag_overrides().
var data_source: Node = null
var flags_button: Button = null
var flags_panel: PanelContainer = null
var flags_status_label: Label = null
var btn_identity_on: Button = null
var btn_reset_flags: Button = null
## flag name -> CheckButton
var flag_switches: Dictionary = {}

var fsm: GameStateMachine = null:
	set(val):
		if fsm != null and fsm.phase_changed.is_connected(_on_phase_changed):
			fsm.phase_changed.disconnect(_on_phase_changed)
		fsm = val
		if fsm != null:
			if not fsm.phase_changed.is_connected(_on_phase_changed):
				fsm.phase_changed.connect(_on_phase_changed)
			_update_phase_label(fsm.phase)

var is_open: bool:
	get:
		var p: Control = _get_panel()
		return p.visible if p != null else false
	set(val):
		var p: Control = _get_panel()
		if p != null:
			p.visible = val

func _ready() -> void:
	if not check_debug_build():
		return
	_ensure_nodes()
	_build_flags_ui()
	_build_touch_readout()
	if dbg_button != null and not dbg_button.pressed.is_connected(toggle):
		dbg_button.pressed.connect(toggle)
	if btn_title != null and not btn_title.pressed.is_connected(_on_btn_title_pressed):
		btn_title.pressed.connect(_on_btn_title_pressed)
	if btn_synthesis != null and not btn_synthesis.pressed.is_connected(_on_btn_synthesis_pressed):
		btn_synthesis.pressed.connect(_on_btn_synthesis_pressed)
	if btn_incubation != null and not btn_incubation.pressed.is_connected(_on_btn_incubation_pressed):
		btn_incubation.pressed.connect(_on_btn_incubation_pressed)
	if btn_infection != null and not btn_infection.pressed.is_connected(_on_btn_infection_pressed):
		btn_infection.pressed.connect(_on_btn_infection_pressed)
	if btn_results != null and not btn_results.pressed.is_connected(_on_btn_results_pressed):
		btn_results.pressed.connect(_on_btn_results_pressed)
	if btn_stress != null and not btn_stress.pressed.is_connected(_on_btn_stress_pressed):
		btn_stress.pressed.connect(_on_btn_stress_pressed)
	if btn_rhino_bench != null and not btn_rhino_bench.pressed.is_connected(_on_btn_rhino_bench_pressed):
		btn_rhino_bench.pressed.connect(_on_btn_rhino_bench_pressed)
	if chk_impact_ticks != null:
		chk_impact_ticks.button_pressed = ImpactRings.enabled
		if not chk_impact_ticks.toggled.is_connected(_on_impact_ticks_toggled):
			chk_impact_ticks.toggled.connect(_on_impact_ticks_toggled)
	if btn_replay != null and not btn_replay.pressed.is_connected(_on_btn_replay_pressed):
		btn_replay.pressed.connect(_on_btn_replay_pressed)
	if btn_export_logs != null and not btn_export_logs.pressed.is_connected(_on_btn_export_logs_pressed):
		btn_export_logs.pressed.connect(_on_btn_export_logs_pressed)

	if fsm != null:
		_update_phase_label(fsm.phase)
	elif phase_label != null:
		phase_label.text = "NONE"

func check_debug_build(is_debug: bool = OS.is_debug_build()) -> bool:
	if not is_debug:
		visible = false
		queue_free()
		return false
	visible = true
	return true

func setup(p_fsm: GameStateMachine) -> void:
	fsm = p_fsm

func toggle() -> void:
	var p: Control = _get_panel()
	if p != null:
		p.visible = not p.visible
		if p.visible and flags_panel != null:
			flags_panel.visible = false


# --- playtest flags (#217) ------------------------------------------------------

func toggle_flags() -> void:
	if flags_panel == null:
		return
	flags_panel.visible = not flags_panel.visible
	if flags_panel.visible:
		var p: Control = _get_panel()
		if p != null:
			p.visible = false
		refresh_flags()


func _source() -> Node:
	if data_source == null:
		data_source = get_node_or_null("/root/GameData")
	return data_source


func _source_config() -> GameConfig:
	var src: Node = _source()
	if src == null or not "config" in src:
		return null
	return src.config as GameConfig


# --- touch readout (#226) -------------------------------------------------------
# Shows what Godot receives for touches, to diagnose multi-touch on the Android emulator.

var touch_label: Label = null
## touch index -> device id, for the fingers currently down
var touch_down: Dictionary = {}
var touch_events: int = 0
var touch_last: String = "none"


func _build_touch_readout() -> void:
	if touch_label != null:
		return
	touch_label = Label.new()
	touch_label.name = "TouchReadout"
	touch_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	touch_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	touch_label.offset_top = -120.0
	touch_label.offset_bottom = -80.0
	touch_label.add_theme_color_override("font_color", Color.BLACK)
	touch_label.add_theme_color_override("font_outline_color", Color.WHITE)
	touch_label.add_theme_constant_override("outline_size", 6)
	add_child(touch_label)
	_refresh_touch_readout()


func _input(event: InputEvent) -> void:
	if touch_label == null:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			touch_down[t.index] = t.device
		else:
			touch_down.erase(t.index)
		touch_last = "touch %s idx=%d dev=%d" % ["down" if t.pressed else "up", t.index, t.device]
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		touch_last = "drag idx=%d dev=%d" % [d.index, d.device]
	else:
		return
	touch_events += 1
	_refresh_touch_readout()


func _refresh_touch_readout() -> void:
	touch_label.text = "fingers down: %d %s | events: %d | last: %s" % [touch_down.size(), str(touch_down), touch_events, touch_last]


func _build_flags_ui() -> void:
	if flags_button != null:
		return
	flags_button = Button.new()
	flags_button.name = "FlagsButton"
	flags_button.text = "FLAGS"
	flags_button.custom_minimum_size = Vector2(72.0, 48.0)
	flags_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	flags_button.offset_left = 68.0
	flags_button.offset_right = 140.0
	flags_button.offset_top = -60.0
	flags_button.offset_bottom = -12.0
	flags_button.pressed.connect(toggle_flags)
	add_child(flags_button)

	flags_panel = PanelContainer.new()
	flags_panel.name = "FlagsPanel"
	flags_panel.visible = false
	flags_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	flags_panel.offset_left = 12.0
	flags_panel.offset_right = 12.0 + FLAGS_PANEL_WIDTH
	flags_panel.offset_top = -708.0
	flags_panel.offset_bottom = -68.0
	add_child(flags_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	flags_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "Rows"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Playtest flags"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	flags_status_label = Label.new()
	flags_status_label.name = "FlagsStatus"
	flags_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(flags_status_label)
	btn_identity_on = _flag_action_button("BtnIdentityOn", "All identity on", _on_identity_on_pressed)
	box.add_child(btn_identity_on)
	btn_reset_flags = _flag_action_button("BtnResetFlags", "Reset to shipped", _on_reset_flags_pressed)
	box.add_child(btn_reset_flags)

	var cfg: GameConfig = _source_config()
	for flag_name: String in FlagOverrides.listed_flags(cfg):
		var sw := CheckButton.new()
		sw.name = "Flag_" + flag_name
		sw.text = flag_name
		sw.custom_minimum_size = Vector2(0.0, FLAG_ROW_HEIGHT)
		sw.toggled.connect(_on_flag_toggled.bind(flag_name))
		box.add_child(sw)
		flag_switches[flag_name] = sw

	var note := Label.new()
	note.text = FLAGS_NOTE
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	refresh_flags()


func _flag_action_button(node_name: String, label: String, handler: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = label
	b.custom_minimum_size = Vector2(48.0, 48.0)
	b.pressed.connect(handler)
	return b


## Shows the live flag values, marks overridden ones with "*", and reports dropped overrides.
func refresh_flags() -> void:
	var cfg: GameConfig = _source_config()
	if cfg == null:
		return
	for flag_name: Variant in flag_switches.keys():
		var sw: CheckButton = flag_switches[flag_name]
		sw.set_pressed_no_signal(cfg.flag(str(flag_name)))
		sw.text = str(flag_name) + (" *" if cfg.flag_overrides.has(flag_name) else "")
	if flags_status_label == null:
		return
	var src: Node = _source()
	var err: String = str(src.get("flag_override_error")) if src != null and "flag_override_error" in src else ""
	if err != "" and err != "<null>":
		flags_status_label.text = "Overrides ignored (invalid):\n" + err
	elif cfg.flag_overrides.is_empty():
		flags_status_label.text = "Shipped flags (no overrides)"
	else:
		flags_status_label.text = "%d overridden (*)" % cfg.flag_overrides.size()


## The overrides that turn the live flags into `wanted`, for every listed flag.
func _apply_wanted(wanted: Dictionary) -> void:
	var cfg: GameConfig = _source_config()
	var src: Node = _source()
	if cfg == null or src == null or not src.has_method("set_flag_overrides"):
		return
	var full: Dictionary = {}
	for flag_name: String in FlagOverrides.listed_flags(cfg):
		full[flag_name] = wanted.get(flag_name, cfg.flag(flag_name))
	src.call("set_flag_overrides", FlagOverrides.diff(full, cfg.file_feature_flags))
	refresh_flags()


func _on_flag_toggled(on: bool, flag_name: String) -> void:
	_apply_wanted({flag_name: on})


func _on_identity_on_pressed() -> void:
	var wanted: Dictionary = {}
	for flag_name: String in FlagOverrides.IDENTITY_FLAGS:
		wanted[flag_name] = true
	_apply_wanted(wanted)


func _on_reset_flags_pressed() -> void:
	var src: Node = _source()
	if src != null and src.has_method("set_flag_overrides"):
		src.call("set_flag_overrides", {})
	refresh_flags()

func _unhandled_input(event: InputEvent) -> void:
	_handle_input_event(event)

func _handle_input_event(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			toggle()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()

func _on_btn_title_pressed() -> void:
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.TITLE)

func _on_btn_synthesis_pressed() -> void:
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.SYNTHESIS)

func _on_btn_incubation_pressed() -> void:
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.INCUBATION)

func _on_btn_infection_pressed() -> void:
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.INFECTION)

func _on_btn_results_pressed() -> void:
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.RESULTS)

func _on_btn_stress_pressed() -> void:
	get_tree().change_scene_to_file("res://tests/perf/stress_battle.tscn")

func _on_btn_rhino_bench_pressed() -> void:
	get_tree().change_scene_to_file("res://tests/perf/rhino_bench.tscn")

func _on_phase_changed(_from: GameStateMachine.Phase, to: GameStateMachine.Phase) -> void:
	_update_phase_label(to)

func _update_phase_label(p: GameStateMachine.Phase) -> void:
	var lbl: Label = _get_phase_label()
	if lbl != null:
		lbl.text = GameStateMachine.get_phase_name(p)

func _get_panel() -> Control:
	if panel != null and is_instance_valid(panel):
		return panel
	return get_node_or_null("Panel") as Control

func _get_phase_label() -> Label:
	if phase_label != null and is_instance_valid(phase_label):
		return phase_label
	return get_node_or_null("Panel/VBoxContainer/PhaseLabel") as Label

func _ensure_nodes() -> void:
	if dbg_button == null:
		dbg_button = get_node_or_null("DbgButton") as Button
	if panel == null:
		panel = get_node_or_null("Panel") as Control
	if phase_label == null:
		phase_label = get_node_or_null("Panel/VBoxContainer/PhaseLabel") as Label
	if btn_title == null:
		btn_title = get_node_or_null("Panel/VBoxContainer/BtnTitle") as Button
	if btn_synthesis == null:
		btn_synthesis = get_node_or_null("Panel/VBoxContainer/BtnSynthesis") as Button
	if btn_incubation == null:
		btn_incubation = get_node_or_null("Panel/VBoxContainer/BtnIncubation") as Button
	if btn_infection == null:
		btn_infection = get_node_or_null("Panel/VBoxContainer/BtnInfection") as Button
	if btn_results == null:
		btn_results = get_node_or_null("Panel/VBoxContainer/BtnResults") as Button
	if btn_stress == null:
		btn_stress = get_node_or_null("Panel/VBoxContainer/BtnStress") as Button
	if btn_rhino_bench == null:
		btn_rhino_bench = get_node_or_null("Panel/VBoxContainer/BtnRhinoBench") as Button
	if chk_impact_ticks == null:
		chk_impact_ticks = get_node_or_null("Panel/VBoxContainer/ChkImpactTicks") as CheckButton
	if btn_replay == null:
		btn_replay = get_node_or_null("Panel/VBoxContainer/BtnReplay") as Button
	if replay_status_label == null:
		replay_status_label = get_node_or_null("Panel/VBoxContainer/ReplayStatusLabel") as Label
	if btn_export_logs == null:
		btn_export_logs = get_node_or_null("Panel/VBoxContainer/BtnExportLogs") as Button

func _on_impact_ticks_toggled(on: bool) -> void:
	ImpactRings.enabled = on


func _on_btn_export_logs_pressed() -> void:
	ResultsPhase.export_playtest_logs()


func replay_last_battle() -> Dictionary:
	_ensure_nodes()
	var dir := DirAccess.open("user://battles")
	if dir == null:
		_show_replay_status(false, "No battle logs directory")
		return {"ok": false, "error": "No battle logs directory"}

	var files: Array[String] = []
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while not fn.is_empty():
		if not dir.current_is_dir() and fn.ends_with(".json"):
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()

	if files.is_empty():
		_show_replay_status(false, "No battle logs found")
		return {"ok": false, "error": "No battle logs found"}

	files.sort_custom(func(a: String, b: String) -> bool:
		var time_a: int = FileAccess.get_modified_time("user://battles/" + a)
		var time_b: int = FileAccess.get_modified_time("user://battles/" + b)
		if time_a != time_b:
			return time_a > time_b # newest first
		return a > b
	)

	var newest_path: String = "user://battles/" + files[0]
	var file := FileAccess.open(newest_path, FileAccess.READ)
	if file == null:
		_show_replay_status(false, "Failed to read %s" % files[0])
		return {"ok": false, "error": "Failed to read battle log"}
	var text: String = file.get_as_text()
	file.close()

	var cfg: GameConfig = null
	if fsm != null and fsm.session != null and fsm.session.config != null:
		cfg = fsm.session.config
	else:
		var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
		if res.is_ok():
			cfg = res.config

	var result: Dictionary = Replay.verify(text, cfg)
	var is_match: bool = result.get("match", false)
	var exp_h: String = str(result.get("expected_hash", ""))
	var act_h: String = str(result.get("actual_hash", ""))
	var exp_short: String = exp_h.substr(0, 8) if exp_h.length() >= 8 else exp_h
	var act_short: String = act_h.substr(0, 8) if act_h.length() >= 8 else act_h

	if is_match:
		_show_replay_status(true, "✓ Match: %s" % act_short)
	else:
		var err_detail: String = str(result.get("error", "Mismatch"))
		_show_replay_status(false, "✗ Mismatch (%s vs %s): %s" % [exp_short, act_short, err_detail])

	return result


func _show_replay_status(ok: bool, msg: String) -> void:
	if replay_status_label != null:
		replay_status_label.text = msg
		replay_status_label.add_theme_color_override("font_color", Color("#2ecc71") if ok else Color("#e74c3c"))
	var t: Toast = get_tree().root.find_child("Toast", true, false) as Toast if get_tree() != null else null
	if t != null:
		t.show_message(msg)


func _on_btn_replay_pressed() -> void:
	replay_last_battle()

