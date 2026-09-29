extends GutTest


func test_allows_up_to_max_within_window_then_blocks() -> void:
	var limiter := SfxRateLimiter.new(6, 100)
	for i in range(6):
		assert_true(limiter.allow(1000 + i * 10), "event %d should pass" % i)
	assert_false(limiter.allow(1059), "7th event inside the window is dropped")
	assert_false(limiter.allow(1099), "still inside the window of the first event")


func test_window_slides() -> void:
	var limiter := SfxRateLimiter.new(6, 100)
	for i in range(6):
		limiter.allow(1000)
	assert_false(limiter.allow(1050))
	assert_true(limiter.allow(1100), "the first batch is 100 ms old, so the window has room again")


func test_dropped_events_do_not_extend_the_block() -> void:
	var limiter := SfxRateLimiter.new(2, 100)
	assert_true(limiter.allow(0))
	assert_true(limiter.allow(10))
	for t in range(20, 100, 10):
		assert_false(limiter.allow(t))
	assert_true(limiter.allow(100), "only allowed events count toward the window")


func test_defaults_match_the_spec() -> void:
	var limiter := SfxRateLimiter.new()
	assert_eq(limiter.max_events, 6)
	assert_eq(limiter.window_ms, 100)


func test_reset_clears_history() -> void:
	var limiter := SfxRateLimiter.new(1, 100)
	assert_true(limiter.allow(0))
	assert_false(limiter.allow(1))
	limiter.reset()
	assert_true(limiter.allow(2))
