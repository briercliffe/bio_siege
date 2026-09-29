extends GutTest

func test_init() -> void:
	var ps := PathService.new(20, 20, 1.0, 5)
	assert_eq(ps.grid_version, 0)
	assert_eq(ps.computations_total, 0)
	assert_eq(ps.computations_this_tick, 0)
	assert_true(ps.can_compute())
	assert_eq(ps.get_cache_size(), 0)
	assert_eq(ps.get_cell_weight(Vector2i(0, 0)), 1.0)
	assert_eq(ps.get_cell_weight(Vector2i(19, 19)), 1.0)

func test_find_path_empty_grid() -> void:
	var ps := PathService.new(20, 20, 1.0, 10)
	var from := Vector2i(1, 1)
	var to := Vector2i(1, 6)
	var path := ps.find_path(from, to)

	assert_eq(path.size(), 6)
	assert_eq(path[0], from)
	assert_eq(path[-1], to)
	for i in range(path.size() - 1):
		var step: Vector2i = path[i + 1] - path[i]
		var dist: int = abs(step.x) + abs(step.y)
		assert_eq(dist, 1, "Each step must be Manhattan distance 1")

	# Diagonal / L-shaped navigation
	var diag_path := ps.find_path(Vector2i(2, 3), Vector2i(5, 7))
	assert_eq(diag_path.size(), 8) # |5-2| + |7-3| + 1 = 3 + 4 + 1 = 8
	assert_eq(diag_path[0], Vector2i(2, 3))
	assert_eq(diag_path[-1], Vector2i(5, 7))

func test_short_detour_around_walls() -> void:
	var ps := PathService.new(20, 20, 1.0, 10)
	var wall_cells: Array[Vector2i] = [
		Vector2i(4, 4),
		Vector2i(4, 5),
		Vector2i(4, 6)
	]
	for w in wall_cells:
		ps.set_cell_weight(w, 10.0)

	var from := Vector2i(2, 5)
	var to := Vector2i(6, 5)
	var path := ps.find_path(from, to)

	assert_gt(path.size(), 0)
	assert_eq(path[0], from)
	assert_eq(path[-1], to)

	# The path should detour around the 3-cell wall instead of breaking through
	for cell in path:
		assert_false(wall_cells.has(cell), "Path should detour and not contain wall cell %s" % [cell])

func test_long_wall_breakthrough_through_5_10() -> void:
	var ps := PathService.new(20, 20, 1.0, 10)
	# Wall spans the entire vertical column at x = 5
	for y in range(20):
		ps.set_cell_weight(Vector2i(5, y), 10.0)

	var from := Vector2i(2, 10)
	var to := Vector2i(8, 10)
	var path := ps.find_path(from, to)

	assert_gt(path.size(), 0)
	assert_eq(path[0], from)
	assert_eq(path[-1], to)

	# Breakthrough must occur at (5, 10) because direct horizontal line has minimal cost
	assert_true(path.has(Vector2i(5, 10)), "Path must break through wall at (5, 10)")
	assert_eq(path, [
		Vector2i(2, 10),
		Vector2i(3, 10),
		Vector2i(4, 10),
		Vector2i(5, 10),
		Vector2i(6, 10),
		Vector2i(7, 10),
		Vector2i(8, 10)
	])

func test_clear_cell() -> void:
	var ps := PathService.new(20, 20, 1.0, 10)
	var wall_pos := Vector2i(5, 10)
	ps.set_cell_weight(wall_pos, 10.0)
	assert_eq(ps.get_cell_weight(wall_pos), 10.0)

	var path := ps.find_path(Vector2i(2, 10), Vector2i(8, 10))
	assert_gt(path.size(), 0)
	assert_true(ps.peek_cached(Vector2i(2, 10), Vector2i(8, 10)))
	assert_eq(ps.get_cache_size(), 1)
	assert_eq(ps.grid_version, 0)

	# Clearing the cell restores empty weight, bumps grid_version, and wipes cache
	ps.clear_cell(wall_pos)
	assert_eq(ps.get_cell_weight(wall_pos), 1.0)
	assert_eq(ps.grid_version, 1)
	assert_eq(ps.get_cache_size(), 0)
	assert_false(ps.peek_cached(Vector2i(2, 10), Vector2i(8, 10)))

func test_cache_hits_and_misses() -> void:
	var ps := PathService.new(20, 20, 1.0, 10)
	var from := Vector2i(0, 0)
	var to := Vector2i(3, 3)

	assert_false(ps.peek_cached(from, to))
	assert_eq(ps.computations_total, 0)
	assert_eq(ps.computations_this_tick, 0)

	# First query: cache miss
	var path1 := ps.find_path(from, to)
	assert_true(ps.peek_cached(from, to))
	assert_eq(ps.computations_total, 1)
	assert_eq(ps.computations_this_tick, 1)

	# Second query: cache hit
	var path2 := ps.find_path(from, to)
	assert_eq(ps.computations_total, 1)
	assert_eq(ps.computations_this_tick, 1)
	assert_eq(path1, path2)

	# Query different route: cache miss
	var path3 := ps.find_path(from, Vector2i(4, 4))
	assert_eq(ps.computations_total, 2)
	assert_eq(ps.computations_this_tick, 2)

func test_duplicate_copy_isolation() -> void:
	var ps := PathService.new(20, 20, 1.0, 10)
	var from := Vector2i(0, 0)
	var to := Vector2i(3, 0)

	var path1 := ps.find_path(from, to)
	var expected: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0)
	]
	assert_eq(path1, expected)

	# Mutate returned array
	path1.append(Vector2i(99, 99))
	path1[0] = Vector2i(-5, -5)

	# Verify cached path in PathService was not affected
	var path2 := ps.find_path(from, to)
	assert_eq(path2, expected)
	assert_ne(path2, path1)

func test_budget_per_tick() -> void:
	var ps := PathService.new(20, 20, 1.0, 2)
	assert_true(ps.can_compute())

	# Computation 1 / 2
	ps.find_path(Vector2i(0, 0), Vector2i(1, 1))
	assert_eq(ps.computations_this_tick, 1)
	assert_true(ps.can_compute())

	# Computation 2 / 2: reaches budget limit
	ps.find_path(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(ps.computations_this_tick, 2)
	assert_false(ps.can_compute())

	# Cache hits do not consume budget
	ps.find_path(Vector2i(0, 0), Vector2i(1, 1))
	assert_eq(ps.computations_this_tick, 2)
	assert_false(ps.can_compute())

	# Tick rollover resets computations_this_tick
	ps.begin_tick()
	assert_eq(ps.computations_this_tick, 0)
	assert_true(ps.can_compute())
	# Total computations preserved
	assert_eq(ps.computations_total, 2)

func test_determinism() -> void:
	var runs: Array[Array] = []
	for r in range(5):
		var ps := PathService.new(20, 20, 1.0, 100)
		# Place several walls
		for y in range(3, 15):
			ps.set_cell_weight(Vector2i(8, y), 10.0)
		for x in range(5, 12):
			ps.set_cell_weight(Vector2i(x, 10), 15.0)

		var path := ps.find_path(Vector2i(2, 10), Vector2i(15, 10))
		runs.append(path)

	for r in range(1, runs.size()):
		assert_eq(runs[r], runs[0], "Path calculation must be completely deterministic")

func test_bounds_checking() -> void:
	var ps := PathService.new(20, 20, 1.0, 10)

	var p1 := ps.find_path(Vector2i(-1, 0), Vector2i(5, 5))
	assert_eq(p1.size(), 0)
	assert_eq(ps.computations_total, 0)

	var p2 := ps.find_path(Vector2i(0, 0), Vector2i(20, 10))
	assert_eq(p2.size(), 0)
	assert_eq(ps.computations_total, 0)

	var p3 := ps.find_path(Vector2i(5, -2), Vector2i(5, 25))
	assert_eq(p3.size(), 0)
	assert_eq(ps.computations_total, 0)

	# Out of bounds cell operations do not crash or alter state
	ps.set_cell_weight(Vector2i(-1, -1), 10.0)
	ps.clear_cell(Vector2i(25, 25))
	assert_eq(ps.grid_version, 0)
