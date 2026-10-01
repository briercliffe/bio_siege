class_name ModelPainter
extends RefCounted

## Base class for a model painter. Painters draw facing right with the ground centre at `anchor`,
## and never modify anything but the canvas item they draw on.

## Virtual. `anchor` is the ground centre on screen, `t_px` the tile size in px.
func paint(_ci: CanvasItem, _anchor: Vector2, _pose: ModelPose, _t_px: float) -> void:
	pass


## Optional ground decals (trails, shockwaves). UnitLayer calls this for each unit just before that unit's
## paint(), inside the depth-sorted pass, so a decal sorts with its unit: it covers anything painted
## earlier (units behind) and is covered by anything painted later (units in front).
func paint_ground(_ci: CanvasItem, _anchor: Vector2, _pose: ModelPose, _t_px: float) -> void:
	pass


## Virtual. Drops any per-unit state the painter keeps between frames (painters are cached and shared, and
## entity ids restart with each battle). UnitLayer calls it through ModelRegistry.reset_painters() at the
## start of a battle and whenever the projection's tile size or origin changes. No-op by default.
func reset() -> void:
	pass


## Model height in tiles, used for health-bar placement and bounding boxes.
func height_tiles() -> float:
	return 1.0


## Virtual. True when paint() draws its own death from pose.death_t; otherwise EffectLayer adds a generic
## puff where the entity died.
func has_custom_death() -> bool:
	return false
