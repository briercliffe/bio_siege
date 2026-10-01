class_name BattleRunner
extends Node

signal ticked                       # after each sim step
signal battle_finished(sim: BattleSim)

var sim: BattleSim
var alpha: float = 0.0              # 0..1 interpolation factor for views
var config: GameConfig = null
var setup: BattleSetup = null
var is_running: bool = false
## Pause menu: while true the sim is not stepped and no time accumulates, so resuming changes nothing.
var paused: bool = false
var _accumulator: float = 0.0
var _tick_dt: float = 0.05          # 1.0 / config.tick_rate
var _finish_timer: float = 0.0
var _finish_delay: float = 1.5
var _finished_emitted: bool = false


func start(p_config: GameConfig, p_setup: BattleSetup) -> void:
	config = p_config
	setup = p_setup
	if config != null and config.tick_rate > 0:
		_tick_dt = 1.0 / float(config.tick_rate)
	else:
		_tick_dt = 0.05

	sim = BattleSim.new(config, setup)
	_accumulator = 0.0
	_finish_timer = 0.0
	_finished_emitted = false
	alpha = 0.0
	is_running = true


func _process(delta: float) -> void:
	if not is_running or sim == null or paused:
		return

	if not sim.finished:
		_accumulator += delta
		var steps: int = 0
		while _accumulator >= _tick_dt and steps < 5:
			sim.step()
			_accumulator -= _tick_dt
			steps += 1
			ticked.emit()
			if sim.finished:
				break

	if not sim.finished:
		alpha = clampf(_accumulator / _tick_dt, 0.0, 1.0)
	else:
		alpha = 1.0
		if not _finished_emitted:
			_finish_timer += delta
			if _finish_timer >= _finish_delay:
				_finished_emitted = true
				is_running = false
				battle_finished.emit(sim)
