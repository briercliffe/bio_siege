extends GutTest

const VIEWER_SCENE: String = "res://tools/model_viewer.tscn"


func _make_viewer() -> Control:
	var viewer: Control = (load(VIEWER_SCENE) as PackedScene).instantiate()
	add_child_autofree(viewer)
	return viewer


func test_lists_every_model_plus_post() -> void:
	var viewer: Control = _make_viewer()
	var ids: Array[String] = viewer.model_ids
	assert_eq(ids.size(), 8)
	assert_true(ids.has("post"))
	assert_true(ids.has("rhinovirus"))
	assert_true(ids.has("b_cell"))
	assert_eq(viewer.model_option.item_count, ids.size())


func test_selecting_each_model_redraws_the_stage() -> void:
	var viewer: Control = _make_viewer()
	await wait_process_frames(2)
	for id: String in viewer.model_ids:
		var before: int = viewer.stage.draw_count
		viewer.select_model(id)
		await wait_process_frames(2)
		assert_eq(viewer.model_id, id)
		assert_gt(viewer.stage.draw_count, before, "stage redrew for " + id)


func test_every_state_and_toggle_builds_a_pose_and_draws() -> void:
	var viewer: Control = _make_viewer()
	viewer.show_anchor = true
	viewer.show_footprint = true
	viewer.show_bounds = true
	viewer.show_gait = true
	viewer.facing_right = false
	for s: int in range(viewer.STATE_NAMES.size()):
		viewer.select_state(s)
		viewer.time_s = 0.3
		await wait_process_frames(1)
		assert_not_null(viewer.pose_for("rhinovirus", s, 0.3))
	assert_gt(viewer.stage.draw_count, 0)


func test_triggers_set_state_and_play() -> void:
	var viewer: Control = _make_viewer()
	viewer.time_s = 1.0
	viewer.trigger("hit")
	assert_eq(viewer.state_index, ModelPose.Anim.HIT)
	assert_true(viewer.playing)
	assert_eq(viewer.time_s, 0.0)
	assert_eq(viewer.pose_for("rhinovirus", ModelPose.Anim.HIT, 0.0).hit_t, 1.0)
	viewer.trigger("death")
	assert_eq(viewer.state_index, ModelPose.Anim.DEAD)
	viewer.trigger("attack")
	assert_eq(viewer.state_index, viewer.STATE_ATTACK_LOOP)


func test_move_gait_uses_speed_and_stride() -> void:
	var viewer: Control = _make_viewer()
	var pd: PathogenDef = viewer.config.pathogens["rhinovirus"]
	var speed_tiles_s: float = float(pd.speed_mt_per_tick) * 20.0 / 1000.0
	var expect: float = fposmod(0.5 * speed_tiles_s / AnimDriver.STRIDE_TILES["rhinovirus"], 1.0)
	var pose: ModelPose = viewer.pose_for("rhinovirus", ModelPose.Anim.MOVE, 0.5)
	assert_almost_eq(pose.gait_phase, expect, 0.0001)


func test_contact_sheet_size_states_are_columns_models_are_rows() -> void:
	var viewer: Control = _make_viewer()
	assert_eq(viewer.contact_sheet_size(7, 6, Vector2i(240, 240)), Vector2i(1440, 1680))


func test_every_button_is_at_least_48_square() -> void:
	var viewer: Control = _make_viewer()
	await wait_process_frames(2)
	var buttons: Array[Node] = viewer.find_children("*", "BaseButton", true, false)
	assert_gt(buttons.size(), 10)
	for n: Node in buttons:
		var b: BaseButton = n as BaseButton
		var min_size: Vector2 = b.get_combined_minimum_size()
		assert_true(min_size.x >= 48.0 and min_size.y >= 48.0, "%s min size %s" % [b.name, str(min_size)])
		assert_true(b.size.x >= 48.0 and b.size.y >= 48.0, "%s size %s" % [b.name, str(b.size)])
