class_name GameStateMachine
extends Node

enum Phase { NONE, SYNTHESIS, INCUBATION, INFECTION, RESULTS }

signal phase_changed(from: Phase, to: Phase)
signal config_applied(summary: Dictionary)
## A HUD "?" button was pressed; Main shows the How to play overlay.
signal how_to_play_requested

const PHASE_SCENE_PATHS: Dictionary = {
	Phase.SYNTHESIS: "res://src/game/phases/synthesis_phase.tscn",
	Phase.INCUBATION: "res://src/game/phases/incubation_phase.tscn",
	Phase.INFECTION: "res://src/game/phases/infection_phase.tscn",
	Phase.RESULTS: "res://src/game/phases/results_phase.tscn",
}

var phase: Phase = Phase.NONE
var previous_phase: Phase = Phase.NONE
var session: Session = null

var phase_root: Control = null
var current_phase_scene: Control = null

func _enter_tree() -> void:
	_ensure_phase_root()

func _ready() -> void:
	_ensure_phase_root()

func _ensure_phase_root() -> Control:
	if phase_root != null and is_instance_valid(phase_root):
		return phase_root
	if has_node("PhaseRoot"):
		phase_root = get_node("PhaseRoot") as Control
		return phase_root
	phase_root = Control.new()
	phase_root.name = "PhaseRoot"
	phase_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	phase_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	phase_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	phase_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(phase_root)
	return phase_root

static func get_phase_name(p: Phase) -> String:
	match p:
		Phase.NONE:
			return "NONE"
		Phase.SYNTHESIS:
			return "SYNTHESIS"
		Phase.INCUBATION:
			return "INCUBATION"
		Phase.INFECTION:
			return "INFECTION"
		Phase.RESULTS:
			return "RESULTS"
		_:
			return "UNKNOWN"

func can_transition(from: Phase, to: Phase) -> bool:
	match from:
		Phase.NONE:
			return to == Phase.SYNTHESIS
		Phase.SYNTHESIS:
			return to == Phase.INCUBATION
		Phase.INCUBATION:
			return to == Phase.SYNTHESIS or to == Phase.INFECTION
		Phase.INFECTION:
			return to == Phase.RESULTS
		Phase.RESULTS:
			return to == Phase.INCUBATION or to == Phase.SYNTHESIS
		_:
			return false

func start() -> void:
	if session == null:
		var cfg: GameConfig = GameData.config if GameData != null else null
		session = Session.new(cfg)
	if GameData != null and not GameData.config_reloaded.is_connected(on_config_reloaded):
		GameData.config_reloaded.connect(on_config_reloaded)
	request_transition(Phase.SYNTHESIS)

## Hot reload entry point (#27). The running BattleSim keeps its own config
## reference, so a reload during INFECTION is queued and applied when the phase ends.
func on_config_reloaded(new_config: GameConfig) -> void:
	if session == null or new_config == null:
		return
	if phase == Phase.INFECTION:
		session.pending_config = new_config
		return
	_apply_config(new_config)

func _apply_config(new_config: GameConfig) -> void:
	var summary: Dictionary = session.apply_new_config(new_config)
	if current_phase_scene != null and is_instance_valid(current_phase_scene) and current_phase_scene.has_method("on_config_changed"):
		current_phase_scene.call("on_config_changed", summary)
	config_applied.emit(summary)

func request_transition(to: Phase) -> bool:
	if not can_transition(phase, to):
		push_warning("GameStateMachine: invalid transition requested from %s to %s" % [get_phase_name(phase), get_phase_name(to)])
		return false
	_apply_transition(to)
	return true

func force_transition(to: Phase) -> void:
	_apply_transition(to)

var _phase_enter_time_ms: int = 0

func _apply_transition(to: Phase) -> void:
	if phase != Phase.NONE:
		var duration_ms: int = Time.get_ticks_msec() - _phase_enter_time_ms
		if SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("phase_exit", {
				"phase": get_phase_name(phase).to_lower(),
				"duration_ms": duration_ms
			})

	previous_phase = phase
	phase = to
	_phase_enter_time_ms = Time.get_ticks_msec()

	if to != Phase.NONE:
		if SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("phase_enter", {
				"phase": get_phase_name(to).to_lower()
			})

	var root: Control = _ensure_phase_root()
	if current_phase_scene != null and is_instance_valid(current_phase_scene):
		if current_phase_scene.get_parent() == root:
			root.remove_child(current_phase_scene)
		current_phase_scene.queue_free()
		current_phase_scene = null

	if previous_phase == Phase.INFECTION and to != Phase.INFECTION and session != null and session.pending_config != null:
		_apply_config(session.pending_config)

	if PHASE_SCENE_PATHS.has(to):
		var scene_path: String = PHASE_SCENE_PATHS[to]
		var scene_res: PackedScene = load(scene_path) as PackedScene
		if scene_res != null:
			var phase_scene: Node = scene_res.instantiate()
			if phase_scene.has_method("setup"):
				phase_scene.call("setup", session, self)
			root.add_child(phase_scene)
			current_phase_scene = phase_scene as Control

	phase_changed.emit(previous_phase, phase)
