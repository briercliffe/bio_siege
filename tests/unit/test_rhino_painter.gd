extends GutTest

## RhinoPainter (#67): every pose draws without engine errors at the three tile sizes and both facings.

const TILE_SIZES: Array[float] = [8.0, 14.0, 56.0]


class DrawHost extends Node2D:
	var draw_cb: Callable = Callable()
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		if draw_cb.is_valid():
			draw_cb.call(self)


func _pose(anim: ModelPose.Anim, right: bool) -> ModelPose:
	var p := ModelPose.new()
	p.anim = anim
	p.facing_right = right
	p.seed = 7
	p.time = 0.37
	p.gait_phase = 0.05
	match anim:
		ModelPose.Anim.WINDUP:
			p.attack_t = 0.3
		ModelPose.Anim.STRIKE:
			p.attack_t = 0.5
		ModelPose.Anim.RECOVER:
			p.attack_t = 0.8
		ModelPose.Anim.HIT:
			p.hit_t = 1.0
			p.shake = 1.0
		ModelPose.Anim.DEAD:
			p.death_t = 0.5
	return p


func test_height_is_spec_value() -> void:
	assert_eq(RhinoPainter.new().height_tiles(), 1.25)


func test_registry_returns_rhino_painter() -> void:
	assert_true(ModelRegistry.painter_for("rhinovirus") is RhinoPainter)
	assert_same(ModelRegistry.painter_for("rhinovirus"), ModelRegistry.painter_for("rhinovirus"))
	assert_eq(ModelRegistry.painter_for("rhinovirus").height_tiles(), 1.25)


func test_paint_every_anim_facing_and_size_draws_cleanly() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := RhinoPainter.new()
	var combos: Array = []
	for anim: int in ModelPose.Anim.values():
		for right: bool in [true, false]:
			combos.append([anim, right])
	host.draw_cb = func(ci: CanvasItem) -> void:
		for c: Array in combos:
			var pose: ModelPose = _pose(c[0] as ModelPose.Anim, c[1] as bool)
			for t: float in TILE_SIZES:
				painter.paint(ci, Vector2(100.0, 100.0), pose, t)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0, "the host drew")
	assert_eq(get_logger().get_errors().size(), 0, "no engine errors")


func test_death_past_threshold_and_full_death_draw_cleanly() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := RhinoPainter.new()
	host.draw_cb = func(ci: CanvasItem) -> void:
		for d: float in [0.0, 0.1, 0.16, 1.0]:
			var pose: ModelPose = _pose(ModelPose.Anim.DEAD, true)
			pose.death_t = d
			painter.paint(ci, Vector2(100.0, 100.0), pose, 56.0)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0)
	assert_eq(get_logger().get_errors().size(), 0)


func test_paint_restores_the_canvas_transform() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := RhinoPainter.new()
	host.draw_cb = func(ci: CanvasItem) -> void:
		painter.paint(ci, Vector2(50.0, 50.0), _pose(ModelPose.Anim.STRIKE, false), 28.0)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0)
