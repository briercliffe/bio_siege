class_name FixedMath
extends RefCounted

const MT_PER_TILE: int = 1000

static func cell_center(cell: Vector2i) -> Vector2i:
	return cell * 1000 + Vector2i(500, 500)

static func rect_center(origin: Vector2i, footprint: Vector2i) -> Vector2i:
	return origin * 1000 + footprint * 500

static func pos_to_cell(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x / 1000, pos.y / 1000)

static func dist_sq(a: Vector2i, b: Vector2i) -> int:
	return (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)

static func within(a: Vector2i, b: Vector2i, range_mt: int) -> bool:
	return dist_sq(a, b) <= range_mt * range_mt

static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	if n < 4:
		return 1
	var x0: int = n / 2
	var x1: int = (x0 + n / x0) / 2
	while x1 < x0:
		x0 = x1
		x1 = (x0 + n / x0) / 2
	return x0

static func move_towards(from: Vector2i, to: Vector2i, step: int) -> Vector2i:
	var d: Vector2i = to - from
	var dist: int = isqrt(dist_sq(from, to))
	if dist <= step:
		return to
	return from + Vector2i((d.x * step) / dist, (d.y * step) / dist)

static func apply_pct(value: int, pct: int) -> int:
	return (value * pct) / 100
