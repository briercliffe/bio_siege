extends GutTest

var config: GameConfig = null


func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load cleanly")
	config = res.config


func test_atlas_layout_is_disjoint_and_fits() -> void:
	var cell := Vector2i(63, 51)
	var layout: Dictionary = SpriteBaker.atlas_layout(3, SpriteBaker.FRAMES_PER_TYPE, cell)
	var rects: Array[Rect2i] = layout["rects"]
	var size: Vector2i = layout["size"]
	assert_eq(rects.size(), 3 * SpriteBaker.FRAMES_PER_TYPE)
	assert_lte(size.x, SpriteBaker.MAX_ATLAS_PX)
	for i: int in range(rects.size()):
		assert_true(Rect2i(Vector2i.ZERO, size).encloses(rects[i]), "rect %d lies inside the atlas" % i)
		assert_eq(rects[i].size, cell)
		for j: int in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "rects %d and %d overlap" % [i, j])


func test_atlas_layout_wraps_wide_cells() -> void:
	var layout: Dictionary = SpriteBaker.atlas_layout(2, 33, Vector2i(500, 100), 2000)
	assert_eq((layout["size"] as Vector2i).x, 2000)
	assert_eq((layout["rects"] as Array).size(), 66)


func test_frame_counts_match_the_clip_table() -> void:
	var total: int = 0
	for clip: int in range(SpriteBaker.FRAME_COUNTS.size()):
		assert_eq(SpriteBaker.CLIP_START[clip], total)
		total += SpriteBaker.FRAME_COUNTS[clip]
	assert_eq(total, SpriteBaker.FRAMES_PER_TYPE)
	assert_eq(SpriteBaker.FRAME_COUNTS, [8, 8, 6, 3, 8] as Array[int])


func test_frame_index_for_eight_frames() -> void:
	assert_eq(SpriteBaker.frame_index(0.0, 8), 0)
	assert_eq(SpriteBaker.frame_index(0.5, 8), 4)
	assert_eq(SpriteBaker.frame_index(0.999, 8), 7)
	assert_eq(SpriteBaker.frame_index(1.0, 8), 7, "t = 1 stays inside the clip")


func test_select_picks_the_clip_for_each_pose() -> void:
	var pose := ModelPose.new()
	assert_eq(SpriteBaker.select(pose, 1.2), Vector2i(SpriteBaker.Clip.IDLE, 0))
	pose.time = 0.6
	assert_eq(SpriteBaker.select(pose, 1.2).y, 4)
	pose.time = 1.2 + 0.65
	assert_eq(SpriteBaker.select(pose, 1.2).y, 4, "the idle loop wraps")
	pose.anim = ModelPose.Anim.MOVE
	pose.gait_phase = 0.5
	assert_eq(SpriteBaker.select(pose, 1.2), Vector2i(SpriteBaker.Clip.MOVE, 4))
	pose.hit_t = 1.0
	assert_eq(SpriteBaker.select(pose, 1.2), Vector2i(SpriteBaker.Clip.HIT, 0), "a hit shows over a move")
	pose.hit_t = 0.2
	assert_eq(SpriteBaker.select(pose, 1.2).y, 2)
	pose.anim = ModelPose.Anim.STRIKE
	pose.attack_t = AnimDriver.STRIKE_T
	assert_eq(SpriteBaker.select(pose, 1.2), Vector2i(SpriteBaker.Clip.ATTACK, 3), "an attack shows over a hit")
	pose.anim = ModelPose.Anim.DEAD
	pose.death_t = 0.999
	assert_eq(SpriteBaker.select(pose, 1.2), Vector2i(SpriteBaker.Clip.DEATH, 7))


func test_the_strike_frame_is_painted_at_the_strike() -> void:
	var strike_frame: int = SpriteBaker.frame_index(AnimDriver.STRIKE_T, SpriteBaker.FRAME_COUNTS[SpriteBaker.Clip.ATTACK])
	var pose: ModelPose = SpriteBaker.pose_for(SpriteBaker.Clip.ATTACK, strike_frame, 1.0)
	assert_eq(pose.anim, ModelPose.Anim.STRIKE)
	assert_eq(pose.attack_t, AnimDriver.STRIKE_T)
	assert_eq(SpriteBaker.pose_for(SpriteBaker.Clip.ATTACK, 0, 1.0).anim, ModelPose.Anim.WINDUP)
	assert_eq(SpriteBaker.pose_for(SpriteBaker.Clip.ATTACK, 5, 1.0).anim, ModelPose.Anim.RECOVER)


func test_every_baked_pose_selects_its_own_frame() -> void:
	for clip: int in range(SpriteBaker.FRAME_COUNTS.size()):
		for frame: int in range(SpriteBaker.FRAME_COUNTS[clip]):
			var sel: Vector2i = SpriteBaker.select(SpriteBaker.pose_for(clip, frame, 1.2), 1.2)
			assert_eq(sel, Vector2i(clip, frame), "clip %d frame %d" % [clip, frame])


func test_pathogen_painters_report_their_idle_period() -> void:
	for id: String in ["rhinovirus", "bacteriophage", "staphylococcus"]:
		assert_gt(ModelRegistry.painter_for(id).idle_period_s(), 1.0, id)


func test_cell_is_big_enough_for_the_largest_pathogen() -> void:
	var ids: Array[String] = ["rhinovirus", "bacteriophage", "staphylococcus"]
	var cell: Vector2 = SpriteBaker.cell_size_px(ids, 14.3)
	assert_gte(cell.x, 2.8 * 14.3)
	assert_gte(cell.y, 3.0 * 14.3)
