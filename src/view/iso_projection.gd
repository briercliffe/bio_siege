class_name IsoProjection
extends RefCounted

## View-only 2:1 dimetric projection (docs/MVP_UI_SPEC.md section 3).
## The simulation stays a flat integer grid; this maps ground points to screen pixels and back.

const DEFAULT_SCALE: float = 0.56          # spec section 3: s = 0.56 (2:1 dimetric)

var tile_px: float = 14.0                  # T
var scale: float = DEFAULT_SCALE           # s
var origin: Vector2 = Vector2.ZERO         # screen position of ground point (0, 0)

func _init(p_tile_px: float = 14.0, p_origin: Vector2 = Vector2.ZERO, p_scale: float = DEFAULT_SCALE) -> void:
	tile_px = p_tile_px
	origin = p_origin
	scale = p_scale

## Ground point in tile units (floats) -> local screen px.
func ground_to_screen(g: Vector2) -> Vector2:
	return origin + Vector2((g.x - g.y) * tile_px * scale, (g.x + g.y) * tile_px * scale * 0.5)

## Exact inverse of ground_to_screen.
func screen_to_ground(p: Vector2) -> Vector2:
	var q: Vector2 = p - origin
	var a: float = q.x / (tile_px * scale)          # gx - gy
	var b: float = 2.0 * q.y / (tile_px * scale)    # gx + gy
	return Vector2((a + b) * 0.5, (b - a) * 0.5)

func screen_to_cell(p: Vector2) -> Vector2i:
	var g: Vector2 = screen_to_ground(p)
	return Vector2i(int(floorf(g.x)), int(floorf(g.y)))

func cell_center(cell: Vector2i) -> Vector2:
	return ground_to_screen(Vector2(cell) + Vector2(0.5, 0.5))

func footprint_center(o: Vector2i, fp: Vector2i) -> Vector2:
	return ground_to_screen(Vector2(o) + Vector2(fp) * 0.5)

## Sim milli-tiles -> screen.
func mt_to_screen(pos_mt: Vector2i) -> Vector2:
	return ground_to_screen(Vector2(pos_mt) / 1000.0)

## Spec section 3 depth rule: sort ascending by gx + gy of the anchor.
static func depth_key(g: Vector2) -> float:
	return g.x + g.y

## Maps tile units to screen px, so ground shapes can be drawn directly in tile units.
func ground_transform() -> Transform2D:
	return Transform2D(Vector2(tile_px * scale, tile_px * scale * 0.5), Vector2(-tile_px * scale, tile_px * scale * 0.5), origin)

## Diamond bounding box of a grid_w x grid_h island.
func island_size(grid_w: int, grid_h: int) -> Vector2:
	var span: float = float(grid_w + grid_h) * tile_px * scale
	return Vector2(span, span * 0.5)
