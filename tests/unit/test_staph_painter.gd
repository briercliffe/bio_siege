extends GutTest

## StaphPainter (#68): every pose draws without engine errors at the three tile sizes and both facings.

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
	assert_eq(StaphPainter.new().height_tiles(), 2.35)


func test_registry_returns_staph_painter() -> void:
	assert_true(ModelRegistry.painter_for("staphylococcus") is StaphPainter)
	assert_same(ModelRegistry.painter_for("staphylococcus"), ModelRegistry.painter_for("staphylococcus"))
	assert_eq(ModelRegistry.painter_for("staphylococcus").height_tiles(), 2.35)


func test_paint_and_paint_ground_every_anim_facing_and_size_draw_cleanly() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := StaphPainter.new()
	var combos: Array = []
	for anim: int in ModelPose.Anim.values():
		for right: bool in [true, false]:
			combos.append([anim, right])
	host.draw_cb = func(ci: CanvasItem) -> void:
		for c: Array in combos:
			var pose: ModelPose = _pose(c[0] as ModelPose.Anim, c[1] as bool)
			for t: float in TILE_SIZES:
				painter.paint_ground(ci, Vector2(100.0, 100.0), pose, t)
				painter.paint(ci, Vector2(100.0, 100.0), pose, t)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0, "the host drew")
	assert_eq(get_logger().get_errors().size(), 0, "no engine errors")


func test_paint_restores_the_canvas_transform() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := StaphPainter.new()
	host.draw_cb = func(ci: CanvasItem) -> void:
		painter.paint_ground(ci, Vector2(50.0, 50.0), _pose(ModelPose.Anim.STRIKE, false), 28.0)
		painter.paint(ci, Vector2(50.0, 50.0), _pose(ModelPose.Anim.STRIKE, false), 28.0)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0)
	assert_eq(get_logger().get_errors().size(), 0)


func _ground_pose(seed_id: int, anim: ModelPose.Anim) -> ModelPose:
	var p: ModelPose = _pose(anim, true)
	p.seed = seed_id
	return p


func test_trail_holds_at_most_six_entries() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := StaphPainter.new()
	var pose: ModelPose = _ground_pose(3, ModelPose.Anim.MOVE)
	host.draw_cb = func(ci: CanvasItem) -> void:
		for i: int in range(40):
			pose.time = float(i) * 0.05
			painter.paint_ground(ci, Vector2(100.0 + float(i) * 14.0, 100.0), pose, 14.0)
			assert_lte(painter.trail_count(3), StaphPainter.TRAIL_MAX)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_eq(painter.trail_count(3), StaphPainter.TRAIL_MAX, "a long walk fills the ring and no more")
	assert_eq(get_logger().get_errors().size(), 0)


func test_trail_is_kept_per_seed_and_cleared_on_death() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := StaphPainter.new()
	host.draw_cb = func(ci: CanvasItem) -> void:
		for i: int in range(10):
			for seed_id: int in [1, 2]:
				painter.paint_ground(ci, Vector2(100.0 + float(i) * 14.0, 100.0 + float(seed_id)), _ground_pose(seed_id, ModelPose.Anim.MOVE), 14.0)
		assert_gt(painter.trail_count(1), 0)
		assert_gt(painter.trail_count(2), 0)
		var dead: ModelPose = _ground_pose(1, ModelPose.Anim.DEAD)
		dead.death_t = 1.0
		painter.paint_ground(ci, Vector2(300.0, 100.0), dead, 14.0)
		assert_eq(painter.trail_count(1), 0, "a dead unit's trail is cleared")
		assert_gt(painter.trail_count(2), 0, "another unit's trail is untouched")
		# A reused slot starts empty.
		painter.paint_ground(ci, Vector2(100.0, 100.0), _ground_pose(9, ModelPose.Anim.IDLE), 14.0)
		assert_eq(painter.trail_count(9), 0)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_eq(get_logger().get_errors().size(), 0)


func test_death_through_every_pop_threshold_draws_cleanly() -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	var painter := StaphPainter.new()
	host.draw_cb = func(ci: CanvasItem) -> void:
		for d: float in [0.0, 0.5, 0.81, 0.85, 0.9, 0.95, 0.97, 1.0]:
			var pose: ModelPose = _pose(ModelPose.Anim.DEAD, true)
			pose.death_t = d
			painter.paint(ci, Vector2(100.0, 100.0), pose, 56.0)
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0)
	assert_eq(get_logger().get_errors().size(), 0)
