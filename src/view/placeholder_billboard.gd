class_name PlaceholderBillboard
extends RefCounted

## Stand-in models drawn in screen space until the real painters land (#67 to #70).
## Also reused by the battle view (#64). Walls are drawn by WallRenderer (#69).

const GHOST_OPACITY: float = 0.75

## Draws a placeholder shape whose bottom-centre sits on `foot`.
static func draw_billboard(ci: CanvasItem, shape: String, color: Color, foot: Vector2, width: float, height: float) -> void:
	PlaceholderShapes.draw_shape(ci, shape, Rect2(foot.x - width * 0.5, foot.y - height, width, height), color)
