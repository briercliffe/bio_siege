extends GutTest

func test_determinism() -> void:
	var rng1 := Rng.new(424242)
	var rng2 := Rng.new(424242)

	for _i in range(50):
		assert_eq(rng1.next_int(100), rng2.next_int(100))
		assert_eq(rng1.next_range(-50, 50), rng2.next_range(-50, 50))
		assert_eq(rng1.randi(), rng2.randi())
		assert_eq(rng1.next_bool(), rng2.next_bool())

func test_different_seeds() -> void:
	var rng1 := Rng.new(1)
	var rng2 := Rng.new(2)

	var all_match: bool = true
	for _i in range(20):
		if rng1.next_int(1000000) != rng2.next_int(1000000):
			all_match = false
			break
	assert_false(all_match, "Different seeds should produce different sequences")

func test_seed_getter_and_setter() -> void:
	var rng := Rng.new(123)
	assert_eq(rng.seed, 123)

	rng.seed = 456
	assert_eq(rng.seed, 456)

	# Setting seed resets sequence deterministically
	var rng_ref := Rng.new(456)
	assert_eq(rng.next_int(100), rng_ref.next_int(100))

func test_next_int_bounds() -> void:
	var rng := Rng.new(999)

	# n = 1 must return 0
	for _i in range(10):
		assert_eq(rng.next_int(1), 0)

	# Range [0, n - 1]
	for _i in range(100):
		var v: int = rng.next_int(10)
		assert_true(v >= 0 and v < 10)

	for _i in range(100):
		var v: int = rng.next_int(100)
		assert_true(v >= 0 and v < 100)

func test_next_range_bounds() -> void:
	var rng := Rng.new(777)

	for _i in range(100):
		var v: int = rng.next_range(10, 20)
		assert_true(v >= 10 and v <= 20)

	for _i in range(100):
		var v: int = rng.next_range(-15, -5)
		assert_true(v >= -15 and v <= -5)

	# lo == hi
	assert_eq(rng.next_range(42, 42), 42)

func test_next_bool() -> void:
	var rng := Rng.new(12345)
	var true_count: int = 0
	var false_count: int = 0

	for _i in range(100):
		var b: bool = rng.next_bool()
		if b:
			true_count += 1
		else:
			false_count += 1

	assert_true(true_count > 0)
	assert_true(false_count > 0)
	assert_eq(true_count + false_count, 100)
