class_name PathService
extends RefCounted

var grid_version: int = 0
var computations_total: int = 0      # real A* runs (cache misses) since creation
var computations_this_tick: int = 0

var _width: int
var _height: int
var _empty_weight: float
var _budget_per_tick: int
var _astar: AStarGrid2D
var _cache: Dictionary = {}          # String "%d,%d>%d,%d" -> Array[Vector2i]

func _init(width: int, height: int, empty_weight: float, budget_per_tick: int) -> void:
	_width = width
	_height = height
	_empty_weight = empty_weight
	_budget_per_tick = budget_per_tick

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.jumping_enabled = false
	_astar.update()
	for y in range(height):
		for x in range(width):
			_astar.set_point_weight_scale(Vector2i(x, y), empty_weight)

func set_cell_weight(cell: Vector2i, weight: float) -> void:
	if not _astar.is_in_bounds(cell.x, cell.y):
		push_warning("PathService: cell out of bounds: %s" % [cell])
		return
	_astar.set_point_weight_scale(cell, weight)

func get_cell_weight(cell: Vector2i) -> float:
	if not _astar.is_in_bounds(cell.x, cell.y):
		return 0.0
	return _astar.get_point_weight_scale(cell)

func clear_cell(cell: Vector2i) -> void:
	if not _astar.is_in_bounds(cell.x, cell.y):
		push_warning("PathService: cell out of bounds: %s" % [cell])
		return
	_astar.set_point_weight_scale(cell, _empty_weight)
	grid_version += 1
	_cache.clear()

func begin_tick() -> void:
	computations_this_tick = 0

func can_compute() -> bool:
	return computations_this_tick < _budget_per_tick

func peek_cached(from: Vector2i, to: Vector2i) -> bool:
	return _cache.has("%d,%d>%d,%d" % [from.x, from.y, to.x, to.y])

func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not _astar.is_in_bounds(from.x, from.y) or not _astar.is_in_bounds(to.x, to.y):
		push_warning("PathService: point out of bounds: %s -> %s" % [from, to])
		var empty_path: Array[Vector2i] = []
		return empty_path
	var key: String = "%d,%d>%d,%d" % [from.x, from.y, to.x, to.y]
	if _cache.has(key):
		return (_cache[key] as Array[Vector2i]).duplicate()
	var path: Array[Vector2i] = _astar.get_id_path(from, to)
	_cache[key] = path.duplicate()
	computations_total += 1
	computations_this_tick += 1
	return path.duplicate()

func get_cache_size() -> int:
	return _cache.size()
