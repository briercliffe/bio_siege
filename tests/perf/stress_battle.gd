class_name StressBattle
extends Control

## Command line, for a scripted run on the desktop (needs a renderer, so not --headless):
##   godot --path . tests/perf/stress_battle.tscn -- --bench-seconds=12 --bench-out=<absolute path to a .txt>
## Frames in the first WARMUP_S seconds are skipped; the summary has the same fields as RhinoBench's.

const WARMUP_S: float = 3.0

@onready var infection_phase: InfectionPhase = $InfectionPhase
@onready var fps_label: Label = $FpsOverlay/MarginContainer/VBoxContainer/FpsLabel
@onready var pool_label: Label = $FpsOverlay/MarginContainer/VBoxContainer/PoolLabel
@onready var btn_back: Button = get_node_or_null("BtnBack") as Button

var session: Session = null
var _fps_history_times: Array[float] = []
var _fps_history_values: Array[int] = []
var _clock: float = 0.0
var _run_s: float = -1.0
var _out_path: String = ""
var _kept_ms: Array[float] = []


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

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-seconds="):
			_run_s = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--bench-out="):
			_out_path = arg.get_slice("=", 1)
	_update_overlay()


func _process(delta: float) -> void:
	_clock += delta
	if _run_s >= 0.0:
		if _clock >= WARMUP_S:
			_kept_ms.append(delta * 1000.0)
		if _clock >= WARMUP_S + _run_s:
			_finish_cli_run()
			return
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


func _finish_cli_run() -> void:
	_run_s = -1.0
	var s: Dictionary = RhinoBench.summarize(_kept_ms)
	if _out_path != "":
		var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		if f != null:
			f.store_string("avg_ms=%.3f\np95_ms=%.3f\nmin_fps=%.2f\nframes=%d\ndraw_calls=%d\n" % [
				s["avg_ms"], s["p95_ms"], s["min_fps"], s["frames"],
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
			f.close()
	get_tree().quit()


func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://src/main.tscn")
