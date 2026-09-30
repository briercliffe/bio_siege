class_name ModelPainter
extends RefCounted

## Base class for a model painter. Painters draw facing right with the ground centre at `anchor`,
## and never modify anything but the canvas item they draw on.

## Virtual. `anchor` is the ground centre on screen, `t_px` the tile size in px.
func paint(_ci: CanvasItem, _anchor: Vector2, _pose: ModelPose, _t_px: float) -> void:
	pass


## Optional decals drawn before all sprites.
func paint_ground(_ci: CanvasItem, _anchor: Vector2, _pose: ModelPose, _t_px: float) -> void:
	pass


## Model height in tiles, used for health-bar placement and bounding boxes.
func height_tiles() -> float:
	return 1.0
