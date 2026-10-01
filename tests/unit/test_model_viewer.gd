extends GutTest

const VIEWER_SCENE: String = "res://tools/model_viewer.tscn"


func _make_viewer() -> Control:
	var viewer: Control = (load(VIEWER_SCENE) as PackedScene).instantiate()
	add_child_autofree(viewer)
	return viewer


func test_lists_every_model_plus_post_and_walls() -> void:
	var viewer: Control = _make_viewer()
	var ids: Array[String] = viewer.model_ids
	assert_eq(ids.size(), 11)
	assert_true(ids.has("post"))
	assert_true(ids.has("walls"))
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


func test_towers_use_the_battle_tower_timings_and_aim() -> void:
	var viewer: Control = _make_viewer()
	var charge: ModelPose = viewer.pose_for("b_cell", ModelPose.Anim.WINDUP, 0.15)
	assert_eq(charge.anim, ModelPose.Anim.WINDUP)
	assert_almost_eq(charge.attack_t, 0.5, 0.0001, "3 of the 6 charge ticks")
	assert_gt(charge.aim.x, 0.0, "aims toward the facing side")
	assert_eq(viewer.pose_for("b_cell", ModelPose.Anim.STRIKE, 0.0).attack_t, 1.0)
	var recoil: ModelPose = viewer.pose_for("b_cell", ModelPose.Anim.RECOVER, 0.15)
	assert_eq(recoil.anim, ModelPose.Anim.RECOVER)
	assert_almost_eq(recoil.attack_t, 0.5, 0.0001)
	var macro: ModelPose = viewer.pose_for("macrophage", ModelPose.Anim.WINDUP, 0.0)
	assert_eq(macro.anim, ModelPose.Anim.WINDUP)
	assert_almost_eq(macro.attack_t, 0.0, 0.0001)
	var saw_strike: bool = false
	for i: int in range(40):
		var p: ModelPose = viewer.pose_for("b_cell", viewer.STATE_ATTACK_LOOP, float(i) / 20.0)
		saw_strike = saw_strike or p.anim == ModelPose.Anim.STRIKE
	assert_true(saw_strike, "the attack loop fires")
	assert_eq(viewer.pose_for("b_cell", ModelPose.Anim.IDLE, 0.0).aim, Vector2.ZERO, "idle has no target")
	assert_eq(viewer.pose_for("nucleus", ModelPose.Anim.WINDUP, 0.2).aim, Vector2.ZERO, "the Nucleus never attacks")


func test_health_toggle_reaches_the_pose() -> void:
	var viewer: Control = _make_viewer()
	viewer._on_hp_pressed(2)
	assert_almost_eq(viewer.pose_for("nucleus", ModelPose.Anim.IDLE, 0.0).hp_frac, 0.1, 0.0001)
	assert_true(viewer.hp_buttons[2].button_pressed)


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


func test_walls_entry_starts_on_the_sheet_layout() -> void:
	var viewer: Control = _make_viewer()
	var cells: Array[Vector2i] = viewer.wall_cells
	assert_eq(cells.size(), 11 + 4 + 4)
	for c: Vector2i in [Vector2i(12, 16), Vector2i(22, 16), Vector2i(17, 20), Vector2i(12, 20)]:
		assert_true(cells.has(c), str(c))
	assert_eq(viewer.wall_hurt.keys(), [Vector2i(20, 16), Vector2i(21, 16)])
	assert_eq(viewer.wall_gone.keys(), [Vector2i(15, 16)])
	assert_true(viewer.TILE_SIZES.has(40), "T = 40 is selectable for the stripes check")
	viewer.select_model("walls")
	await wait_process_frames(2)
	assert_eq(viewer._walls.renderer.cell_count(), cells.size() - 1, "the gap is not built")
	assert_false(viewer._walls.renderer.has_cell(Vector2i(15, 16)))
	assert_true(viewer._walls.renderer.has_post(Vector2i(17, 16)), "T-junction")
	assert_true(viewer._walls.renderer.has_post(Vector2i(14, 16)), "end beside the gap")


func test_wall_tap_modes_toggle_hurt_destroyed_and_attacked() -> void:
	var viewer: Control = _make_viewer()
	viewer.select_model("walls")
	assert_false(viewer.tap_wall_cell(Vector2i(18, 16)), "no mode, no change")
	viewer.set_wall_tap_mode("hurt")
	assert_true(viewer.tap_wall_cell(Vector2i(18, 16)))
	assert_true(viewer.wall_hurt.has(Vector2i(18, 16)))
	viewer.set_wall_tap_mode("destroy")
	assert_true(viewer.tap_wall_cell(Vector2i(18, 16)))
	assert_true(viewer.wall_gone.has(Vector2i(18, 16)))
	assert_true(viewer.tap_wall_cell(Vector2i(15, 16)))
	assert_false(viewer.wall_gone.has(Vector2i(15, 16)), "tapping a gap restores it")
	viewer.set_wall_tap_mode("attack")
	assert_true(viewer.tap_wall_cell(Vector2i(13, 16)))
	assert_true(viewer.wall_attacked.has(Vector2i(13, 16)))
	assert_false(viewer.tap_wall_cell(Vector2i(0, 0)), "cells outside the layout are ignored")
	await wait_process_frames(2)
	assert_false(viewer._walls.renderer.has_cell(Vector2i(18, 16)))
	assert_true(viewer._walls.renderer.has_cell(Vector2i(15, 16)))
	viewer.reset_walls()
	assert_eq(viewer.wall_gone.keys(), [Vector2i(15, 16)])
	assert_true(viewer.wall_attacked.is_empty())


func test_touch_on_the_stage_taps_the_cell_under_it() -> void:
	var viewer: Control = _make_viewer()
	await wait_process_frames(2)
	viewer.select_model("walls")
	viewer.set_wall_tap_mode("hurt")
	var proj: IsoProjection = viewer._walls_projection(float(viewer.tile_px))
	var ev := InputEventScreenTouch.new()
	ev.pressed = false
	ev.position = proj.cell_center(Vector2i(18, 16)) + viewer.stage.position
	viewer._on_holder_input(ev)
	assert_true(viewer.wall_hurt.has(Vector2i(18, 16)))


func test_stage_and_sheet_walls_keep_their_own_caches() -> void:
	var viewer: Control = _make_viewer()
	var stage_proj: IsoProjection = viewer._walls_projection(float(viewer.tile_px))
	var sheet_proj: IsoProjection = viewer._walls_projection(viewer.WALLS_CELL_TILE_PX)
	for i: int in range(3):
		viewer._ensure_walls(viewer._walls, stage_proj)
		viewer._ensure_walls(viewer._sheet_walls, sheet_proj)
	assert_eq(viewer._walls.rebuilds, 1, "alternating with the sheet does not rebuild the stage")
	assert_eq(viewer._sheet_walls.rebuilds, 1)
	assert_eq(viewer._sheet_walls.renderer.tile_px(), viewer.WALLS_CELL_TILE_PX)
	viewer.set_wall_tap_mode("hurt")
	viewer.tap_wall_cell(Vector2i(18, 16))
	viewer._ensure_walls(viewer._walls, stage_proj)
	assert_eq(viewer._walls.rebuilds, 2, "a layout change rebuilds")


func test_walls_draw_in_every_state() -> void:
	var viewer: Control = _make_viewer()
	viewer.select_model("walls")
	viewer.wall_attacked[Vector2i(13, 16)] = true
	for s: int in range(viewer.STATE_NAMES.size()):
		viewer.select_state(s)
		viewer.time_s = 0.2
		await wait_process_frames(1)
	assert_gt(viewer.stage.draw_count, 0)
	var hit: ModelPose = viewer.pose_for("walls", ModelPose.Anim.HIT, 0.1)
	assert_gt(hit.shake, 0.0)
	assert_eq(viewer.pose_for("walls", ModelPose.Anim.HIT, 0.15).shake, 0.0, "3-tick wall shake")
