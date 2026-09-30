extends GutTest

## MacrophagePainter, BCellPainter and NucleusPainter (#70): heights, every pose at the three tile sizes and
## both facings, and the pure helpers behind the Nucleus pulse and the B-Cell aim.

const TILE_SIZES: Array[float] = [8.0, 14.0, 56.0]
const AIMS: Array[Vector2] = [Vector2.ZERO, Vector2(0.8, 0.6), Vector2(-0.6, -0.8)]


class DrawHost extends Node2D:
	var draw_cb: Callable = Callable()
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		if draw_cb.is_valid():
			draw_cb.call(self)


func _painters() -> Array[ModelPainter]:
	return [MacrophagePainter.new(), BCellPainter.new(), NucleusPainter.new()]


func _pose(anim: ModelPose.Anim, right: bool, aim: Vector2) -> ModelPose:
	var p := ModelPose.new()
	p.anim = anim
	p.facing_right = right
	p.aim = aim
	p.seed = 11
	p.time = 0.83
	p.hp_frac = 0.4
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


func _draw_cleanly(cb: Callable) -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	host.draw_cb = cb
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0, "the host drew")
	assert_eq(get_logger().get_errors().size(), 0, "no engine errors")


func test_heights_are_the_spec_values() -> void:
	assert_eq(MacrophagePainter.new().height_tiles(), 3.0)
	assert_eq(BCellPainter.new().height_tiles(), 4.3)
	assert_eq(NucleusPainter.new().height_tiles(), 4.1)


func test_registry_returns_the_tower_painters() -> void:
	assert_true(ModelRegistry.painter_for("macrophage") is MacrophagePainter)
	assert_true(ModelRegistry.painter_for("b_cell") is BCellPainter)
	assert_true(ModelRegistry.painter_for("nucleus") is NucleusPainter)
	assert_same(ModelRegistry.painter_for("b_cell"), ModelRegistry.painter_for("b_cell"))


func test_paint_every_anim_facing_aim_and_size_draws_cleanly() -> void:
	var painters: Array[ModelPainter] = _painters()
	await _draw_cleanly(func(ci: CanvasItem) -> void:
		for painter: ModelPainter in painters:
			for anim: int in ModelPose.Anim.values():
				for right: bool in [true, false]:
					for aim: Vector2 in AIMS:
						var pose: ModelPose = _pose(anim as ModelPose.Anim, right, aim)
						for t: float in TILE_SIZES:
							painter.paint_ground(ci, Vector2(120.0, 200.0), pose, t)
							painter.paint(ci, Vector2(120.0, 200.0), pose, t)
	)


func test_both_sides_of_the_flat_threshold_draw_cleanly() -> void:
	var painters: Array[ModelPainter] = _painters()
	await _draw_cleanly(func(ci: CanvasItem) -> void:
		for painter: ModelPainter in painters:
			for t: float in [9.9, 10.0, 23.0, 27.9, 28.0]:
				painter.paint(ci, Vector2(120.0, 200.0), _pose(ModelPose.Anim.IDLE, true, Vector2.ZERO), t)
				painter.paint(ci, Vector2(120.0, 200.0), _pose(ModelPose.Anim.STRIKE, false, Vector2(1.0, 0.0)), t)
	)


func test_every_death_phase_draws_cleanly() -> void:
	var painters: Array[ModelPainter] = _painters()
	await _draw_cleanly(func(ci: CanvasItem) -> void:
		for painter: ModelPainter in painters:
			for d: float in [0.0, 0.19, 0.21, 0.45, 0.5, 0.61, 0.69, 0.71, 0.9, 1.0]:
				var pose: ModelPose = _pose(ModelPose.Anim.DEAD, true, Vector2.ZERO)
				pose.death_t = d
				for t: float in [14.0, 56.0]:
					painter.paint(ci, Vector2(120.0, 200.0), pose, t)
	)


func test_nucleus_pulse_rate_rises_as_hp_falls() -> void:
	assert_almost_eq(NucleusPainter.pulse_rate(1.0), 0.5, 0.0001)
	assert_almost_eq(NucleusPainter.pulse_rate(0.0), 2.0, 0.0001)
	assert_almost_eq(NucleusPainter.pulse_rate(0.5), 1.25, 0.0001)
	assert_gt(NucleusPainter.pulse_rate(0.2), NucleusPainter.pulse_rate(0.8), "faster when hurt")
	assert_almost_eq(NucleusPainter.pulse_rate(1.5), 0.5, 0.0001, "clamped above full health")
	assert_almost_eq(NucleusPainter.pulse_rate(-1.0), 2.0, 0.0001, "clamped below zero")


func test_nucleus_ring_height_oscillates_around_the_canvas_height() -> void:
	assert_almost_eq(NucleusPainter.ring_height(0.0), 1.7, 0.0001)
	assert_almost_eq(NucleusPainter.ring_height(0.75), 1.7 * 1.08, 0.0001, "peak at a quarter period")
	assert_almost_eq(NucleusPainter.ring_height(2.25), 1.7 * 0.92, 0.0001, "trough at three quarters")


func test_bcell_aim_angle_clamps_to_25_degrees() -> void:
	assert_almost_eq(BCellPainter.aim_angle(Vector2.RIGHT), deg_to_rad(25.0), 0.0001)
	assert_almost_eq(BCellPainter.aim_angle(Vector2.LEFT), deg_to_rad(-25.0), 0.0001)
	assert_eq(BCellPainter.aim_angle(Vector2.ZERO), 0.0)
	assert_almost_eq(BCellPainter.aim_angle(Vector2.UP), 0.0, 0.0001, "straight up stays upright")
	assert_almost_eq(BCellPainter.aim_angle(Vector2.DOWN), 0.0, 0.0001, "straight down stays upright")
	var small: Vector2 = Vector2(sin(deg_to_rad(10.0)), -cos(deg_to_rad(10.0)))
	assert_almost_eq(BCellPainter.aim_angle(small), deg_to_rad(10.0), 0.0001, "inside the limit it tracks exactly")


func test_bcell_tiers_collapse_top_down() -> void:
	assert_eq(BCellPainter.tier_fall(2, 0.0), 0.0)
	assert_gt(BCellPainter.tier_fall(2, 0.2), 0.0, "the top tier goes first")
	assert_eq(BCellPainter.tier_fall(1, 0.2), 0.0)
	assert_eq(BCellPainter.tier_fall(0, 0.2), 0.0)
	assert_gt(BCellPainter.tier_fall(1, 0.4), 0.0, "then the middle")
	assert_eq(BCellPainter.tier_fall(0, 0.4), 0.0)
	for i: int in range(3):
		assert_eq(BCellPainter.tier_fall(i, 1.0), 1.0, "all down by the end")


func test_macrophage_body_is_a_lumpy_24_point_ellipse() -> void:
	var pts: PackedVector2Array = MacrophagePainter.new().body_outline_tiles()
	assert_eq(pts.size(), 24)
	for i: int in range(pts.size()):
		var a: float = TAU * float(i) / 24.0
		var k: float = 1.0 + 0.04 * sin(3.0 * a + 0.7)
		assert_almost_eq(pts[i], Vector2(cos(a) * 1.0, sin(a) * 0.925) * k, Vector2(0.0001, 0.0001))
