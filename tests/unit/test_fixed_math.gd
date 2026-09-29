extends GutTest

func test_constants() -> void:
	assert_eq(FixedMath.MT_PER_TILE, 1000)

func test_cell_center() -> void:
	assert_eq(FixedMath.cell_center(Vector2i(0, 0)), Vector2i(500, 500))
	assert_eq(FixedMath.cell_center(Vector2i(1, 1)), Vector2i(1500, 1500))
	assert_eq(FixedMath.cell_center(Vector2i(5, 9)), Vector2i(5500, 9500))
	assert_eq(FixedMath.cell_center(Vector2i(10, 20)), Vector2i(10500, 20500))

func test_rect_center() -> void:
	# 1x1 at origin matches cell_center
	assert_eq(FixedMath.rect_center(Vector2i(0, 0), Vector2i(1, 1)), Vector2i(500, 500))
	assert_eq(FixedMath.rect_center(Vector2i(3, 4), Vector2i(1, 1)), Vector2i(3500, 4500))

	# 2x2 at (0, 0) -> (1000, 1000)
	assert_eq(FixedMath.rect_center(Vector2i(0, 0), Vector2i(2, 2)), Vector2i(1000, 1000))
	# 2x2 at (9, 9) -> (10000, 10000)
	assert_eq(FixedMath.rect_center(Vector2i(9, 9), Vector2i(2, 2)), Vector2i(10000, 10000))

	# 3x3 at (0, 0) -> (1500, 1500)
	assert_eq(FixedMath.rect_center(Vector2i(0, 0), Vector2i(3, 3)), Vector2i(1500, 1500))
	# 2x3 at (2, 4) -> (2000 + 1000, 4000 + 1500) = (3000, 5500)
	assert_eq(FixedMath.rect_center(Vector2i(2, 4), Vector2i(2, 3)), Vector2i(3000, 5500))

func test_pos_to_cell() -> void:
	assert_eq(FixedMath.pos_to_cell(Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(FixedMath.pos_to_cell(Vector2i(500, 500)), Vector2i(0, 0))
	assert_eq(FixedMath.pos_to_cell(Vector2i(999, 999)), Vector2i(0, 0))
	assert_eq(FixedMath.pos_to_cell(Vector2i(1000, 1000)), Vector2i(1, 1))
	assert_eq(FixedMath.pos_to_cell(Vector2i(1500, 2500)), Vector2i(1, 2))
	assert_eq(FixedMath.pos_to_cell(Vector2i(9500, 9500)), Vector2i(9, 9))

func test_dist_sq() -> void:
	assert_eq(FixedMath.dist_sq(Vector2i(100, 200), Vector2i(100, 200)), 0)
	assert_eq(FixedMath.dist_sq(Vector2i(0, 0), Vector2i(3, 4)), 25)
	assert_eq(FixedMath.dist_sq(Vector2i(3, 4), Vector2i(0, 0)), 25)
	assert_eq(FixedMath.dist_sq(Vector2i(1000, 2000), Vector2i(4000, 6000)), 25000000)
	assert_eq(FixedMath.dist_sq(Vector2i(500, 500), Vector2i(200, 100)), 250000)

func test_within() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(3, 4) # dist_sq = 25
	assert_true(FixedMath.within(a, b, 5))
	assert_true(FixedMath.within(a, b, 6))
	assert_false(FixedMath.within(a, b, 4))
	assert_false(FixedMath.within(a, b, 0))
	assert_true(FixedMath.within(a, a, 0))

func test_isqrt() -> void:
	assert_eq(FixedMath.isqrt(-100), 0)
	assert_eq(FixedMath.isqrt(-1), 0)
	assert_eq(FixedMath.isqrt(0), 0)
	assert_eq(FixedMath.isqrt(1), 1)
	assert_eq(FixedMath.isqrt(2), 1)
	assert_eq(FixedMath.isqrt(3), 1)
	assert_eq(FixedMath.isqrt(4), 2)
	assert_eq(FixedMath.isqrt(5), 2)
	assert_eq(FixedMath.isqrt(8), 2)
	assert_eq(FixedMath.isqrt(9), 3)
	assert_eq(FixedMath.isqrt(15), 3)
	assert_eq(FixedMath.isqrt(16), 4)
	assert_eq(FixedMath.isqrt(25), 5)
	assert_eq(FixedMath.isqrt(100), 10)
	assert_eq(FixedMath.isqrt(10000), 100)
	assert_eq(FixedMath.isqrt(1000000), 1000)
	assert_eq(FixedMath.isqrt(25000000), 5000)
	assert_eq(FixedMath.isqrt(25000001), 5000)
	assert_eq(FixedMath.isqrt(24999999), 4999)
	assert_eq(FixedMath.isqrt(1000000000000), 1000000)

	# Exhaustive verification for range 0 to 500
	for n in range(500):
		var r: int = FixedMath.isqrt(n)
		assert_true(r * r <= n, "isqrt(%d)^2 <= %d" % [n, n])
		assert_true((r + 1) * (r + 1) > n, "(isqrt(%d)+1)^2 > %d" % [n, n])

func test_move_towards() -> void:
	var origin := Vector2i(0, 0)

	# Already at destination
	assert_eq(FixedMath.move_towards(origin, origin, 100), origin)

	# Step >= distance reaches target exactly
	var dest := Vector2i(300, 400) # dist = 500
	assert_eq(FixedMath.move_towards(origin, dest, 500), dest)
	assert_eq(FixedMath.move_towards(origin, dest, 600), dest)

	# Step < distance along cardinal directions
	assert_eq(FixedMath.move_towards(Vector2i(1000, 0), Vector2i(3000, 0), 500), Vector2i(1500, 0))
	assert_eq(FixedMath.move_towards(Vector2i(0, 2000), Vector2i(0, 1000), 300), Vector2i(0, 1700))

	# Diagonal movement
	# from (0, 0) to (3000, 4000), dist = 5000. Step = 1000 -> moves (600, 800)
	assert_eq(FixedMath.move_towards(Vector2i.ZERO, Vector2i(3000, 4000), 1000), Vector2i(600, 800))

	# Moving towards negative coordinates
	# from (5000, 5000) to (2000, 1000), d = (-3000, -4000), dist = 5000. Step = 2500 -> (3500, 3000)
	assert_eq(FixedMath.move_towards(Vector2i(5000, 5000), Vector2i(2000, 1000), 2500), Vector2i(3500, 3000))

func test_apply_pct() -> void:
	assert_eq(FixedMath.apply_pct(100, 100), 100)
	assert_eq(FixedMath.apply_pct(100, 50), 50)
	assert_eq(FixedMath.apply_pct(200, 150), 300)
	assert_eq(FixedMath.apply_pct(75, 50), 37) # 3750 / 100 = 37
	assert_eq(FixedMath.apply_pct(100, 0), 0)
	assert_eq(FixedMath.apply_pct(0, 50), 0)
	assert_eq(FixedMath.apply_pct(-100, 50), -50)
