class_name WallPainter
extends ModelPainter

## A lone Mucous Wall cell (an end, so it carries a post) drawn through WallRenderer, for the model viewer
## and small static icons. The battle and the island never use this: they draw connected runs with
## WallRenderer directly. The cell is baked around the local origin and rebuilt only when the tile size
## changes; painting moves it to the anchor.

const CELL: Vector2i = Vector2i.ZERO

## Draws only the post (the viewer's "post" entry).
var post_only: bool = false

var _renderer: WallRenderer = WallRenderer.new()
var _walls: Dictionary = {CELL: true}
var _built_t: float = -1.0


func _init(p_post_only: bool = false) -> void:
	post_only = p_post_only


func height_tiles() -> float:
	return WallRenderer.HEIGHT_T


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t_px: float) -> void:
	if t_px != _built_t:
		_built_t = t_px
		var proj := IsoProjection.new(t_px, Vector2.ZERO)
		proj.origin = -proj.cell_center(CELL)
		_renderer.rebuild(_walls, proj)
	_renderer.offset = anchor
	if pose.anim == ModelPose.Anim.DEAD:
		_renderer.paint_goo(ci, CELL, pose.death_t)
		_renderer.paint_break(ci, CELL, pose.death_t)
		return
	if post_only:
		_renderer.paint_post(ci, CELL, pose)
		return
	_renderer.paint_shadows(ci)
	_renderer.paint_cell(ci, CELL, pose.hp_frac, pose)
