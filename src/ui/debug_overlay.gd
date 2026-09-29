class_name DebugOverlay
extends Control

@onready var dbg_button: Button = $DbgButton
@onready var panel: Control = $Panel
@onready var phase_label: Label = $Panel/VBoxContainer/PhaseLabel
@onready var btn_synthesis: Button = $Panel/VBoxContainer/BtnSynthesis
@onready var btn_incubation: Button = $Panel/VBoxContainer/BtnIncubation
@onready var btn_infection: Button = $Panel/VBoxContainer/BtnInfection
@onready var btn_results: Button = $Panel/VBoxContainer/BtnResults

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
	if dbg_button != null and not dbg_button.pressed.is_connected(toggle):
		dbg_button.pressed.connect(toggle)
	if btn_synthesis != null and not btn_synthesis.pressed.is_connected(_on_btn_synthesis_pressed):
		btn_synthesis.pressed.connect(_on_btn_synthesis_pressed)
	if btn_incubation != null and not btn_incubation.pressed.is_connected(_on_btn_incubation_pressed):
		btn_incubation.pressed.connect(_on_btn_incubation_pressed)
	if btn_infection != null and not btn_infection.pressed.is_connected(_on_btn_infection_pressed):
		btn_infection.pressed.connect(_on_btn_infection_pressed)
	if btn_results != null and not btn_results.pressed.is_connected(_on_btn_results_pressed):
		btn_results.pressed.connect(_on_btn_results_pressed)

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

func _unhandled_input(event: InputEvent) -> void:
	_handle_input_event(event)

func _handle_input_event(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			toggle()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()

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
	if btn_synthesis == null:
		btn_synthesis = get_node_or_null("Panel/VBoxContainer/BtnSynthesis") as Button
	if btn_incubation == null:
		btn_incubation = get_node_or_null("Panel/VBoxContainer/BtnIncubation") as Button
	if btn_infection == null:
		btn_infection = get_node_or_null("Panel/VBoxContainer/BtnInfection") as Button
	if btn_results == null:
		btn_results = get_node_or_null("Panel/VBoxContainer/BtnResults") as Button
