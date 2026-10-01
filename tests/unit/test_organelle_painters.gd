extends GutTest

## MitochondriaPainter and DendriticPainter (#171): heights, every pose at three tile sizes and the death phases
## draw cleanly, the pulse and present animations come from AnimDriver, and Reduce flashes stills them.

const TILE_SIZES: Array[float] = [8.0, 14.0, 56.0]

var _cfg: GameConfig = null


class DrawHost extends Node2D:
	var draw_cb: Callable = Callable()
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		if draw_cb.is_valid():
			draw_cb.call(self)


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config


func _painters() -> Array[ModelPainter]:
	return [MitochondriaPainter.new(), DendriticPainter.new()]


func _pose(anim: ModelPose.Anim, t: float = 0.5) -> ModelPose:
	var p := ModelPose.new()
	p.anim = anim
	p.seed = 7
	p.time = 1.37
	p.pulse_phase = 0.3
	p.hp_frac = 0.6
	match anim:
		ModelPose.Anim.STRIKE:
			p.attack_t = t
		ModelPose.Anim.HIT:
			p.hit_t = t
			p.shake = t
		ModelPose.Anim.DEAD:
			p.death_t = t
	return p


func _draw_cleanly(cb: Callable) -> void:
	var host := DrawHost.new()
	add_child_autofree(host)
	host.draw_cb = cb
	host.queue_redraw()
	await wait_process_frames(2)
	assert_gt(host.draw_count, 0, "the host drew")
	assert_eq(get_logger().get_errors().size(), 0, "no engine errors")


func test_heights() -> void:
	assert_eq(MitochondriaPainter.new().height_tiles(), 2.0)
	assert_eq(DendriticPainter.new().height_tiles(), 2.4)
	for p: ModelPainter in _painters():
		assert_true(p.has_custom_death())
		assert_gt(p.idle_period_s(), 0.0)


func test_registry_returns_the_new_painters() -> void:
	assert_true(ModelRegistry.painter_for("mitochondria") is MitochondriaPainter)
	assert_true(ModelRegistry.painter_for("dendritic_cell") is DendriticPainter)
	assert_false(ModelRegistry.painter_for("mitochondria") is PlaceholderPainter)


func test_every_pose_at_three_sizes_and_three_times_draws_cleanly() -> void:
	var painters: Array[ModelPainter] = _painters()
	await _draw_cleanly(func(ci: CanvasItem) -> void:
		for painter: ModelPainter in painters:
			for anim: int in ModelPose.Anim.values():
				for time_t: float in [0.0, 0.5, 1.0]:
					for t: float in TILE_SIZES:
						var pose: ModelPose = _pose(anim as ModelPose.Anim, time_t)
						painter.paint_ground(ci, Vector2(120.0, 200.0), pose, t)
						painter.paint(ci, Vector2(120.0, 200.0), pose, t)
	)


func test_every_death_phase_draws_cleanly() -> void:
	var painters: Array[ModelPainter] = _painters()
	await _draw_cleanly(func(ci: CanvasItem) -> void:
		for painter: ModelPainter in painters:
			for d: float in [0.0, 0.2, 0.44, 0.45, 0.46, 0.7, 0.99, 1.0]:
				for t: float in [14.0, 56.0]:
					painter.paint(ci, Vector2(120.0, 200.0), _pose(ModelPose.Anim.DEAD, d), t)
	)


func test_a_full_and_an_empty_buffer_draw_cleanly() -> void:
	var mito := MitochondriaPainter.new()
	await _draw_cleanly(func(ci: CanvasItem) -> void:
		for f: float in [-1.0, 0.0, 0.5, 1.0, 3.0]:
			mito.stored_fraction = f
			mito.paint(ci, Vector2(120.0, 200.0), _pose(ModelPose.Anim.IDLE), 40.0)
	)
	mito.reset()
	assert_eq(mito.stored_fraction, 0.0, "a battle starts at 0")


func test_the_registry_reset_empties_the_mitochondria_buffer() -> void:
	var mito: MitochondriaPainter = ModelRegistry.painter_for("mitochondria") as MitochondriaPainter
	mito.stored_fraction = 0.8
	ModelRegistry.reset_painters()
	assert_eq(mito.stored_fraction, 0.0)


# --- AnimDriver ---

func _state(type_id: String, id: int = 1) -> StructureState:
	return StructureState.create(id, type_id, _cfg.structures[type_id], Vector2i(10, 10))


func test_death_ticks_are_registered() -> void:
	assert_eq(AnimDriver.death_ticks_for("mitochondria"), 18)
	assert_eq(AnimDriver.death_ticks_for("dendritic_cell"), 14)


func test_the_mitochondria_pulse_clock_runs_and_reduce_flashes_holds_it_still() -> void:
	var live := AnimDriver.new(false)
	var calm := AnimDriver.new(true)
	var s: StructureState = _state("mitochondria")
	var a1: float = live.pose_for_structure(s, 0, Vector2.ZERO, 0.0, false).pulse_phase
	var a2: float = live.pose_for_structure(s, 0, Vector2.ZERO, 0.1, false).pulse_phase
	assert_ne(a1, a2, "the pulse advances")
	var b1: float = calm.pose_for_structure(s, 0, Vector2.ZERO, 0.0, false).pulse_phase
	var b2: float = calm.pose_for_structure(s, 0, Vector2.ZERO, 0.1, false).pulse_phase
	assert_eq(b1, b2, "Reduce flashes stills the pulse")


func test_a_shared_analysis_makes_the_presenter_pulse_for_a_few_ticks() -> void:
	var driver := AnimDriver.new(false)
	var d: StructureState = _state("dendritic_cell", 5)
	assert_eq(driver.pose_for_structure(d, 10, Vector2.ZERO, 0.0, false).anim, ModelPose.Anim.IDLE)
	driver.on_event({"type": SimEvents.ANALYSIS_SHARED, "tick": 10, "presenter_id": 5, "from_id": 1, "to_id": 2, "strain_key": "rhinovirus/wild"})
	var first: ModelPose = driver.pose_for_structure(d, 11, Vector2.ZERO, 0.0, false)
	assert_eq(first.anim, ModelPose.Anim.STRIKE)
	assert_eq(first.attack_t, 0.0)
	var later: ModelPose = driver.pose_for_structure(d, 15, Vector2.ZERO, 0.0, false)
	assert_eq(later.anim, ModelPose.Anim.STRIKE)
	assert_gt(later.attack_t, 0.0)
	assert_eq(driver.pose_for_structure(d, 11 + AnimDriver.PRESENT_TICKS, Vector2.ZERO, 0.0, false).anim, ModelPose.Anim.IDLE)
	var other: StructureState = _state("dendritic_cell", 6)
	assert_eq(driver.pose_for_structure(other, 12, Vector2.ZERO, 0.0, false).anim, ModelPose.Anim.IDLE, "only the presenter pulses")


func test_reduce_flashes_removes_the_present_pulse() -> void:
	var driver := AnimDriver.new(true)
	var d: StructureState = _state("dendritic_cell", 5)
	driver.on_event({"type": SimEvents.ANALYSIS_SHARED, "tick": 10, "presenter_id": 5, "from_id": 1, "to_id": 2, "strain_key": "x/y"})
	assert_eq(driver.pose_for_structure(d, 12, Vector2.ZERO, 0.0, false).anim, ModelPose.Anim.IDLE)


func test_the_sway_is_deterministic_per_cell() -> void:
	# ViewRng gives each id its own fixed phase.
	assert_eq(ViewRng.hash01(7, 10), ViewRng.hash01(7, 10))
	assert_ne(ViewRng.hash01(7, 10), ViewRng.hash01(8, 10))


func test_the_trap_ring_scales_with_the_unit_and_wobbles_only_without_reduce_flashes() -> void:
	var rhino: float = UnitLayer.trap_ring_radius("rhinovirus", 20.0, 0.0, false)
	var staph: float = UnitLayer.trap_ring_radius("staphylococcus", 20.0, 0.0, false)
	assert_gt(staph, rhino, "a bigger unit gets a bigger ring")
	var calm_a: float = UnitLayer.trap_ring_radius("rhinovirus", 20.0, 0.05, true)
	var calm_b: float = UnitLayer.trap_ring_radius("rhinovirus", 20.0, 0.11, true)
	assert_eq(calm_a, calm_b, "Reduce flashes stops the wobble")
	var wob_a: float = UnitLayer.trap_ring_radius("rhinovirus", 20.0, 0.05, false)
	var wob_b: float = UnitLayer.trap_ring_radius("rhinovirus", 20.0, 0.11, false)
	assert_ne(wob_a, wob_b)
	assert_lte(absf(wob_a / calm_a - 1.0), UnitLayer.TRAP_WOBBLE + 0.0001)
