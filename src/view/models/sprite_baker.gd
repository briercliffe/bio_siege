class_name SpriteBaker
extends Node

## Bakes each pathogen painter's animation into one atlas texture at battle start (issue #72, plan option C,
## docs/MODEL_PIPELINE_PLAN.md section 6), so UnitLayer draws one textured quad per unit instead of every
## painter command. The atlas is rendered at runtime from the painters in a SubViewport and never saved.
## Fixed poses: idle 8, move 8, attack 6 (windup to recover), hit 3 and death 8 frames. The pose contract is
## unchanged; AnimDriver and the sim are untouched. Per-entity variance in size and light is not baked: both
## are +-4% and cannot be seen at these sizes. Hit flashes, trails and shockwaves are not baked either; the
## hit flash is the HIT clip, and paint_ground() still runs live.
##
## The viewport holds premultiplied colour, drawn here with normal blending, so the 1 px antialiased edges
## come out slightly darker than the live painters'.

enum Clip { IDLE, MOVE, ATTACK, HIT, DEATH }

const FRAME_COUNTS: Array[int] = [8, 8, 6, 3, 8]
## First frame of each clip within one type's block.
const CLIP_START: Array[int] = [0, 8, 16, 22, 25]
const FRAMES_PER_TYPE: int = 33
## Hit flashes shorter than this fall through to the move or idle clip.
const HIT_MIN: float = 0.05
const MAX_ATLAS_PX: int = 4096
## Cell padding around the largest pathogen, in tiles: room for the lunge and the ground shadow.
const CELL_PAD_T: Vector2 = Vector2(1.6, 0.9)
## The ground anchor sits this many tiles above the bottom of the cell.
const ANCHOR_LIFT_T: float = 0.5

var texture: Texture2D = null
var cell_px: Vector2 = Vector2.ZERO
## Atlas pixels per canvas pixel.
var scale_px: float = 1.0
## Bakes started, for tests and the perf notes.
var bake_count: int = 0

var _ready_flag: bool = false
var _generation: int = 0
var _types: Array[String] = []
var _rects: Array[Rect2i] = []
var _key: Vector2 = Vector2(-1.0, -1.0)
var _types_hash: int = 0
var _vp: SubViewport = null
var _canvas: BakeCanvas = null


## Paints every frame of every baked type into the atlas viewport.
class BakeCanvas extends Node2D:
	var baker: SpriteBaker = null

	func _draw() -> void:
		if baker != null:
			baker._paint_atlas(self)


## Rectangles for `type_count * frames_per_type` cells in a grid that fits `max_width` px, row-major, plus
## the atlas size. The rectangles never overlap and always lie inside the size.
static func atlas_layout(type_count: int, frames_per_type: int, cell: Vector2i, max_width: int = MAX_ATLAS_PX) -> Dictionary:
	var total: int = maxi(type_count * frames_per_type, 0)
	var cols: int = clampi(max_width / maxi(cell.x, 1), 1, maxi(total, 1))
	var rows: int = (total + cols - 1) / cols
	var rects: Array[Rect2i] = []
	for i: int in range(total):
		rects.append(Rect2i(Vector2i((i % cols) * cell.x, (i / cols) * cell.y), cell))
	return {"size": Vector2i(cols * cell.x, rows * cell.y), "rects": rects}


## Frame of a clip for t in 0..1: floor(t * count), kept inside the clip.
static func frame_index(t: float, count: int) -> int:
	return clampi(int(floorf(t * float(count))), 0, count - 1)


## (clip, frame) that stands in for a pose. Attack beats hit, which beats move and idle.
static func select(pose: ModelPose, idle_period: float) -> Vector2i:
	match pose.anim:
		ModelPose.Anim.DEAD:
			return Vector2i(Clip.DEATH, frame_index(pose.death_t, FRAME_COUNTS[Clip.DEATH]))
		ModelPose.Anim.WINDUP, ModelPose.Anim.STRIKE, ModelPose.Anim.RECOVER:
			return Vector2i(Clip.ATTACK, frame_index(pose.attack_t, FRAME_COUNTS[Clip.ATTACK]))
	if pose.hit_t > HIT_MIN:
		return Vector2i(Clip.HIT, frame_index(1.0 - pose.hit_t, FRAME_COUNTS[Clip.HIT]))
	if pose.anim == ModelPose.Anim.MOVE:
		return Vector2i(Clip.MOVE, frame_index(pose.gait_phase, FRAME_COUNTS[Clip.MOVE]))
	return Vector2i(Clip.IDLE, frame_index(fposmod(pose.time, idle_period) / idle_period, FRAME_COUNTS[Clip.IDLE]))


## The pose a baked frame is painted with: the middle of the frame's span, except that the attack frame
## holding AnimDriver.STRIKE_T is painted at the strike itself.
static func pose_for(clip: int, frame: int, idle_period: float) -> ModelPose:
	var count: int = FRAME_COUNTS[clip]
	var mid: float = (float(frame) + 0.5) / float(count)
	var pose := ModelPose.new()
	match clip:
		Clip.IDLE:
			pose.time = mid * idle_period
		Clip.MOVE:
			pose.anim = ModelPose.Anim.MOVE
			pose.gait_phase = mid
		Clip.ATTACK:
			var t: float = AnimDriver.STRIKE_T if frame_index(AnimDriver.STRIKE_T, count) == frame else mid
			pose.attack_t = t
			if t == AnimDriver.STRIKE_T:
				pose.anim = ModelPose.Anim.STRIKE
			elif t < AnimDriver.STRIKE_T:
				pose.anim = ModelPose.Anim.WINDUP
			else:
				pose.anim = ModelPose.Anim.RECOVER
		Clip.HIT:
			pose.hit_t = 1.0 - mid
		Clip.DEATH:
			pose.anim = ModelPose.Anim.DEAD
			pose.death_t = mid
	return pose


## Cell size in canvas px: the largest baked pathogen plus padding, at tile size `t_px`.
static func cell_size_px(type_ids: Array[String], t_px: float) -> Vector2:
	var size_t: Vector2 = Vector2.ZERO
	for id: String in type_ids:
		var s: Vector2 = UnitLayer.pathogen_size_t(id)
		size_t = Vector2(maxf(size_t.x, s.x), maxf(size_t.y, s.y))
	return ((size_t + CELL_PAD_T) * t_px).ceil()


func is_ready() -> bool:
	return _ready_flag and texture != null


## True while a bake for these types, tile size and screen scale is finished or under way.
func is_current(type_ids: Array[String], t_px: float, screen_scale: float) -> bool:
	return _key == Vector2(t_px, screen_scale) and _types_hash == type_ids.hash()


## Starts baking `type_ids` at tile size `t_px`. Until the viewport has drawn, is_ready() is false and the
## caller keeps painting live.
func bake(type_ids: Array[String], t_px: float, screen_scale: float) -> void:
	if _vp != null and is_current(type_ids, t_px, screen_scale):
		return
	_key = Vector2(t_px, screen_scale)
	_types_hash = type_ids.hash()
	_ready_flag = false
	_generation += 1
	bake_count += 1
	_types = type_ids.duplicate()
	var cell_canvas: Vector2 = cell_size_px(_types, t_px)
	var layout: Dictionary = {}
	# Lower the resolution until the atlas fits the texture limit.
	scale_px = clampf(screen_scale, 0.25, 4.0)
	while true:
		var cell_i := Vector2i((cell_canvas * scale_px).ceil())
		layout = atlas_layout(_types.size(), FRAMES_PER_TYPE, cell_i)
		if (layout["size"] as Vector2i).y <= MAX_ATLAS_PX or scale_px <= 0.25:
			break
		scale_px *= 0.8
	var cell_i2 := Vector2i((cell_canvas * scale_px).ceil())
	cell_px = Vector2(cell_i2)
	_rects = layout["rects"]
	if _vp == null:
		_vp = SubViewport.new()
		_vp.name = "SpriteAtlas"
		_vp.transparent_bg = true
		_vp.disable_3d = true
		_canvas = BakeCanvas.new()
		_canvas.baker = self
		_vp.add_child(_canvas)
		add_child(_vp)
		texture = _vp.get_texture()
	_vp.size = layout["size"]
	_canvas.scale = Vector2(scale_px, scale_px)
	_canvas.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_finish(_generation)


func _finish(generation: int) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if generation == _generation:
		_ready_flag = true


func _paint_atlas(ci: CanvasItem) -> void:
	var t_px: float = _key.x
	for ti: int in range(_types.size()):
		var painter: ModelPainter = ModelRegistry.painter_for(_types[ti])
		var period: float = painter.idle_period_s()
		for clip: int in range(FRAME_COUNTS.size()):
			for frame: int in range(FRAME_COUNTS[clip]):
				var rect: Rect2i = _rects[ti * FRAMES_PER_TYPE + CLIP_START[clip] + frame]
				var anchor: Vector2 = (Vector2(rect.position) + Vector2(cell_px.x * 0.5, cell_px.y - ANCHOR_LIFT_T * t_px * scale_px)) / scale_px
				painter.paint(ci, anchor, pose_for(clip, frame, period), t_px)


## Draws the baked frame for `pose` with its ground anchor at `anchor`. Returns false (and draws nothing)
## when the type is not in the atlas or the atlas is not ready, so the caller paints live.
func draw(ci: CanvasItem, type_id: String, pose: ModelPose, anchor: Vector2) -> bool:
	if not is_ready():
		return false
	var ti: int = _types.find(type_id)
	if ti < 0:
		return false
	var painter: ModelPainter = ModelRegistry.painter_for(type_id)
	var sel: Vector2i = select(pose, painter.idle_period_s())
	var src: Rect2i = _rects[ti * FRAMES_PER_TYPE + CLIP_START[sel.x] + sel.y]
	var size: Vector2 = cell_px / scale_px
	var pos: Vector2 = anchor - Vector2(size.x * 0.5, size.y - ANCHOR_LIFT_T * _key.x)
	if not pose.facing_right:
		pos.x += size.x
		size.x = -size.x
	ci.draw_texture_rect_region(texture, Rect2(pos, size), Rect2(src))
	return true
