extends GutTest

## Redraw policy (#72, docs/MODEL_PIPELINE_PLAN.md section 6): the battle layers repaint every frame only
## while the battle runs and is not paused, and once more when the projection moves.

var config: GameConfig


func before_each() -> void:
	config = GameConfig.load_from_dir("res://data").config


class Counter extends RefCounted:
	var n: int = 0

	func bump() -> void:
		n += 1


## Draws per counter over the same `frames` frames.
func _draws_over(frames: int, counters: Array[Counter]) -> Array[int]:
	var start: Array[int] = []
	for c: Counter in counters:
		start.append(c.n)
	await wait_process_frames(frames)
	var out: Array[int] = []
	for i: int in range(counters.size()):
		out.append(counters[i].n - start[i])
	return out


func test_battle_layers_redraw_only_while_running_and_not_paused() -> void:
	var sim: BattleSim = SimFixtures.make_sim(
		[{"type": "macrophage", "origin": Vector2i(10, 10)}],
		[{"type": "rhinovirus", "cell": Vector2i(3, 3)}],
		1, config)
	var snaps := BattleSnapshotBuffer.new()
	snaps.capture(sim)
	var runner := BattleRunner.new()
	runner.set_process(false)
	add_child_autofree(runner)
	runner.sim = sim
	runner.is_running = true
	var projection := IsoProjection.new(14.0, Vector2(400.0, 100.0))
	var units := UnitLayer.new()
	units.name = "UnitLayer"
	var effects := EffectLayer.new()
	effects.name = "EffectLayer"
	var overlay := BattleOverlay.new()
	overlay.name = "BattleOverlay"
	add_child_autofree(units)
	add_child_autofree(effects)
	add_child_autofree(overlay)
	units.setup(sim, config, projection, snaps, runner)
	effects.setup(EffectModel.new(), sim, projection, snaps, runner, false)
	overlay.setup(sim, config, projection, snaps, runner)
	var layers: Array[CanvasItem] = [units, effects, overlay]
	var counters: Array[Counter] = []
	for layer: CanvasItem in layers:
		var c := Counter.new()
		layer.draw.connect(c.bump)
		counters.append(c)

	await wait_process_frames(2)
	var draws: Array[int] = await _draws_over(4, counters)
	for i: int in range(layers.size()):
		assert_gte(draws[i], 3, "%s redraws every frame while running" % layers[i].name)

	runner.paused = true
	units.paused = true
	await wait_process_frames(2)
	var view_time: float = units.view_time
	draws = await _draws_over(4, counters)
	for i: int in range(layers.size()):
		assert_eq(draws[i], 0, "%s is still while paused" % layers[i].name)
	assert_eq(units.view_time, view_time, "the view clock is frozen")

	projection.origin += Vector2(10.0, 0.0)
	draws = await _draws_over(4, counters)
	for i: int in range(layers.size()):
		assert_eq(draws[i], 1, "%s redraws once after the projection moves" % layers[i].name)

	runner.paused = false
	units.paused = false
	runner.is_running = false
	draws = await _draws_over(4, counters)
	for i: int in range(layers.size()):
		assert_eq(draws[i], 0, "%s is still once the battle has stopped" % layers[i].name)
	assert_false(units.is_live())
	assert_eq(get_logger().get_errors().size(), 0)


func test_layers_without_a_runner_keep_redrawing() -> void:
	var units := UnitLayer.new()
	autofree(units)
	assert_true(units.is_live(), "tests and tools drive the layer without a battle clock")
	var effects := EffectLayer.new()
	autofree(effects)
	assert_true(effects.is_live())
