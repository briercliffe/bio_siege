class_name StressBattle
extends Control

@onready var infection_phase: InfectionPhase = $InfectionPhase
@onready var fps_label: Label = $FpsOverlay/MarginContainer/VBoxContainer/FpsLabel
@onready var pool_label: Label = $FpsOverlay/MarginContainer/VBoxContainer/PoolLabel
@onready var btn_back: Button = get_node_or_null("BtnBack") as Button

var session: Session = null
var _fps_history_times: Array[float] = []
var _fps_history_values: Array[int] = []


func _ready() -> void:
	var cfg: GameConfig = GameData.config if (GameData != null and GameData.config != null) else null
	if cfg == null:
		var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
		cfg = res.config

	session = Session.new(cfg)
	session.battle_setup = Scenarios.stress()

	if infection_phase == null:
		infection_phase = get_node_or_null("InfectionPhase") as InfectionPhase

	if infection_phase != null:
		infection_phase.setup(session, null)

	if btn_back != null and not btn_back.pressed.is_connected(_on_btn_back_pressed):
		btn_back.pressed.connect(_on_btn_back_pressed)

	_update_overlay()


func _process(_delta: float) -> void:
	var current_fps: int = Engine.get_frames_per_second()
	var now: float = float(Time.get_ticks_msec()) / 1000.0

	_fps_history_times.append(now)
	_fps_history_values.append(current_fps)

	var cutoff: float = now - 5.0
	while not _fps_history_times.is_empty() and _fps_history_times[0] < cutoff:
		_fps_history_times.remove_at(0)
		_fps_history_values.remove_at(0)

	_update_overlay()


func _update_overlay() -> void:
	var current_fps: int = Engine.get_frames_per_second()
	var lowest_fps: int = current_fps
	for v: int in _fps_history_values:
		if v < lowest_fps:
			lowest_fps = v

	var items_drawn: int = 0
	var alive_count: int = 0

	if infection_phase != null:
		if infection_phase.unit_layer != null:
			items_drawn = infection_phase.unit_layer.last_item_count

		if infection_phase.runner != null and infection_phase.runner.sim != null:
			for p: PathogenState in infection_phase.runner.sim.pathogens:
				if p != null and p.alive:
					alive_count += 1

	if fps_label != null:
		fps_label.text = "FPS: %d\nLowest (5s): %d\nAlive Pathogens: %d" % [
			current_fps,
			lowest_fps,
			alive_count
		]

	if pool_label != null:
		var nodes: int = infection_phase.unit_layer.get_child_count() if (infection_phase != null and infection_phase.unit_layer != null) else 0
		pool_label.text = "Draw items: %d\nUnit layer nodes: %d" % [items_drawn, nodes]


func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://src/main.tscn")
