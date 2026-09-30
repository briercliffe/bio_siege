extends GutTest

func test_part_rect_scales_tile_units() -> void:
	var r: Rect2 = PaintKit.part_rect(Vector2(100.0, 200.0), 10.0, -0.5, -1.0, 1.0, 2.0)
	assert_eq(r, Rect2(95.0, 190.0, 10.0, 20.0))


class DrawProbe extends Node2D:
	var draws: int = 0

	func _draw() -> void:
		var rect := Rect2(0.0, 0.0, 20.0, 20.0)
		PaintKit.ellipse(self, rect, Color.RED)
		PaintKit.sphere(self, rect, Color.WHITE, Color.GREEN, Color.BLACK)
		PaintKit.bar(self, Vector2.ZERO, Vector2(10.0, 5.0), 3.0, Color.BLUE)
		PaintKit.hex(self, rect, Color.YELLOW)
		PaintKit.clip_poly(self, rect, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]), Color.CYAN)
		PaintKit.vertical_gradient_rect(self, rect, Color.WHITE, Color.BLACK)
		PaintKit.horizontal_gradient_rect(self, rect, Color.WHITE, Color.BLACK)
		var cols: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.WHITE]
		PaintKit.cylinder(self, Vector2(50.0, 50.0), 14.0, 1.0, 0.0, 0.75, cols)
		PaintKit.oval(self, Transform2D(0.0, Vector2(30.0, 30.0)), Vector2(0.0, -1.0), Vector2(2.0, 0.7), 14.0, Color.RED)
		PaintKit.oval(self, Transform2D.IDENTITY, Vector2.ZERO, Vector2(0.0, 1.0), 14.0, Color.RED)
		var ped: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.WHITE, Color.BLACK]
		for flat: bool in [false, true]:
			PaintKit.pedestal(self, Transform2D(0.0, Vector2(60.0, 60.0)), 14.0, 1.0, 0.75, ped, flat)
		draw_set_transform(Vector2.ZERO)
		var pose := ModelPose.new()
		pose.hit_t = 0.5
		pose.death_t = 0.25
		PlaceholderPainter.new().paint(self, Vector2(40.0, 40.0), pose, 14.0)
		draws += 1


func test_helpers_draw_without_errors() -> void:
	var probe := DrawProbe.new()
	add_child_autofree(probe)
	probe.queue_redraw()
	await wait_process_frames(2)
	assert_gt(probe.draws, 0, "the probe drew")


func test_stacked_alpha_adds_translucent_layers() -> void:
	assert_almost_eq(PaintKit.stacked_alpha([0.5, 0.5]), 0.75, 0.0001)
	assert_almost_eq(PaintKit.stacked_alpha([]), 0.0, 0.0001)
	assert_almost_eq(PaintKit.stacked_alpha([1.0, 0.2]), 1.0, 0.0001)


func test_glow_mesh_fades_from_full_to_zero() -> void:
	var g := PaintKit.GlowMesh.new(2.0)
	var rings: int = PaintKit.GlowMesh.RINGS
	assert_eq(g.falloff.size(), rings)
	assert_almost_eq(g.falloff[0], 1.0, 0.0001)
	assert_almost_eq(g.falloff[rings - 1], 0.0, 0.0001)
	for k: int in range(1, rings):
		assert_lt(g.falloff[k], g.falloff[k - 1], "alpha falls ring by ring")
	assert_eq(g.pts.size(), 1 + rings * PaintKit.GlowMesh.POINTS)
	assert_eq(g.indices.size(), PaintKit.GlowMesh.POINTS * (3 + 6 * (rings - 1)))
	for i: int in g.indices:
		assert_true(i >= 0 and i < g.pts.size())


func test_easing_endpoints() -> void:
	for f: Callable in [Easing.linear, Easing.ease_in_quad, Easing.ease_out_quad, Easing.ease_in_out, Easing.ease_out_back]:
		assert_almost_eq(float(f.call(0.0)), 0.0, 0.0001)
		assert_almost_eq(float(f.call(1.0)), 1.0, 0.0001)
	assert_almost_eq(Easing.pulse(0.5), 1.0, 0.0001)
	assert_almost_eq(Easing.pulse(0.0), 0.0, 0.0001)
