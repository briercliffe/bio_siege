class_name PlaceholderPainter
extends ModelPainter

## Draws the old geometric placeholder through PlaceholderShapes. The hit flash and death fade come
## from the pose. Real painters (#67 to #70) replace this one per type id in ModelRegistry.

const HIT_WHITE: float = 0.6

var shape: String = "square"
var color: Color = Color.WHITE
## Sprite size in tiles (width, height).
var size_t: Vector2 = Vector2(1.0, 1.0)


func paint(ci: CanvasItem, anchor: Vector2, pose: ModelPose, t_px: float) -> void:
	var col: Color = color.lerp(Color.WHITE, HIT_WHITE * pose.hit_t)
	col.a *= 1.0 - pose.death_t
	PlaceholderBillboard.draw_billboard(ci, shape, col, anchor, size_t.x * t_px, size_t.y * t_px)


func height_tiles() -> float:
	return size_t.y
