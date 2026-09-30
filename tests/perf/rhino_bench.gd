class_name RhinoBench
extends Control

## Frame-time bench for the procedural Rhinovirus painter (#67, docs/PERF_BASELINE.md): 200 Rhinoviruses
## spread evenly over the deploy ring of the 40x40 grid, attacking the walled Nucleus, through the full
## Infection view. The overlay reports the last 5 s. Open it from the debug overlay.
##
## Command line, for a scripted run on the desktop (needs a renderer, so not --headless):
##   godot --path . tests/perf/rhino_bench.tscn -- --bench-seconds=15 --bench-out=<absolute path to a .txt>
## After the warm-up and the requested seconds it writes the summary to the file and quits.

const UNIT_COUNT: int = 200
const BENCH_SEED: int = 67
const WINDOW_S: float = 5.0
const WARMUP_S: float = 2.0
const REFRESH_S: float = 0.25

@onready var infection_phase: InfectionPhase = $InfectionPhase
@onready var stats_label: Label = $StatsOverlay/MarginContainer/StatsLabel
@onready var btn_back: Button = get_node_or_null("BtnBack") as Button

var session: Session = null
var alive_units: int = 0

var _times: Array[float] = []
var _frame_ms: Array[float] = []
var _scratch: Array[float] = []
var _since_refresh: float = 0.0
var _clock: float = 0.0
var _run_s: float = -1.0
var _out_path: String = ""
var _summary: Dictionary = {}


## Walled Nucleus with `count` Rhinoviruses spread evenly over `ring`. Pure: the same inputs give the same setup.
static func build_setup(ring: Array[Vector2i], count: int, seed: int) -> BattleSetup:
	var base: BattleSetup = Scenarios.walled_nucleus(seed)
	var units: Array = []
	if not ring.is_empty():
		for i: int in range(count):
			units.append({"type": "rhinovirus", "cell": ring[i * ring.size() / count]})
	return BattleSetup.create(base.structures, units, seed)


## Average ms, p95 ms and the slowest frame's fps over a list of frame times in ms.
static func summarize(frame_ms: Array[float]) -> Dictionary:
	var out: Dictionary = {"avg_ms": 0.0, "p95_ms": 0.0, "min_fps": 0.0, "frames": frame_ms.size()}
	if frame_ms.is_empty():
		return out
	var sorted: Array[float] = frame_ms.duplicate()
	sorted.sort()
	var total: float = 0.0
	for v: float in sorted:
		total += v
	var idx: int = clampi(int(ceil(0.95 * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	out["avg_ms"] = total / float(sorted.size())
	out["p95_ms"] = sorted[idx]
	out["min_fps"] = 1000.0 / maxf(sorted[sorted.size() - 1], 0.001)
	return out


func _ready() -> void:
	var cfg: GameConfig = GameData.config if (GameData != null and GameData.config != null) else null
	if cfg == null:
		cfg = GameConfig.load_from_dir("res://data").config
	session = Session.new(cfg)
	_start_battle()
	if btn_back != null and not btn_back.pressed.is_connected(_on_btn_back_pressed):
		btn_back.pressed.connect(_on_btn_back_pressed)
	_parse_cli()
	_refresh()


func _start_battle() -> void:
	session.battle_setup = build_setup(session.grid.ring_cells(), UNIT_COUNT, BENCH_SEED)
	infection_phase.setup(session, null)


func _parse_cli() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-seconds="):
			_run_s = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--bench-out="):
			_out_path = arg.get_slice("=", 1)


func _process(delta: float) -> void:
	_clock += delta
	_times.append(_clock)
	_frame_ms.append(delta * 1000.0)
	while not _times.is_empty() and _times[0] < _clock - WINDOW_S:
		_times.remove_at(0)
		_frame_ms.remove_at(0)

	# A finished battle is restarted so the bench always measures a live fight.
	var runner: BattleRunner = infection_phase.runner
	if runner != null and runner.sim != null and runner.sim.finished:
		_start_battle()

	_since_refresh += delta
	if _since_refresh >= REFRESH_S:
		_since_refresh = 0.0
		_refresh()
	if _run_s >= 0.0 and _clock >= WARMUP_S + _run_s:
		_finish_cli_run()


func _refresh() -> void:
	alive_units = 0
	var runner: BattleRunner = infection_phase.runner
	if runner != null and runner.sim != null:
		for p: PathogenState in runner.sim.pathogens:
			if p != null and p.alive:
				alive_units += 1
	_summary = summarize(_frame_ms)
	_summary["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_summary["alive"] = alive_units
	if stats_label != null:
		stats_label.text = "Avg: %.2f ms\np95: %.2f ms\nMin FPS: %.1f\nDraw calls: %d\nAlive units: %d" % [
			_summary["avg_ms"], _summary["p95_ms"], _summary["min_fps"], _summary["draw_calls"], alive_units]


func _finish_cli_run() -> void:
	# Only the frames after the warm-up count.
	var kept: Array[float] = []
	for i: int in range(_times.size()):
		if _times[i] >= WARMUP_S:
			kept.append(_frame_ms[i])
	_refresh()
	var s: Dictionary = summarize(kept)
	if _out_path != "":
		var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		if f != null:
			f.store_string("avg_ms=%.3f\np95_ms=%.3f\nmin_fps=%.2f\nframes=%d\ndraw_calls=%d\nalive=%d\ntile_px=%.1f\nrenderer=%s\nadapter=%s\n" % [
				s["avg_ms"], s["p95_ms"], s["min_fps"], s["frames"], _summary["draw_calls"], alive_units, _tile_px(),
				RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
			f.close()
	get_tree().quit()


func _tile_px() -> float:
	var layer: UnitLayer = infection_phase.unit_layer
	return layer.projection.tile_px if (layer != null and layer.projection != null) else 0.0


func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://src/main.tscn")
