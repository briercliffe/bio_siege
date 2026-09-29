extends GutTest

func test_key_helpers() -> void:
	assert_eq(StatusEffects.key_structure(1), "s:1")
	assert_eq(StatusEffects.key_structure(42), "s:42")
	assert_eq(StatusEffects.key_pathogen(5), "p:5")
	assert_eq(StatusEffects.key_pathogen(100), "p:100")

func test_default_values() -> void:
	var fx := StatusEffects.new()
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 100)
	assert_eq(fx.pct("p:1", StatusEffects.Kind.ATTACK_INTERVAL_PCT), 100)
	assert_eq(fx.pct("p:1", StatusEffects.Kind.DAMAGE_DEALT_PCT), 100)
	assert_eq(fx.pct("p:1", StatusEffects.Kind.DAMAGE_TAKEN_PCT), 100)
	assert_false(fx.has_flag("p:1", StatusEffects.Kind.DISABLED))
	assert_false(fx.has_flag("p:1", StatusEffects.Kind.ROOTED))

func test_single_effect_pct() -> void:
	var fx := StatusEffects.new()
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 80, 5, "ice_tower_1")

	# Effect applied to target
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 80)

	# Does not affect other kinds
	assert_eq(fx.pct("p:1", StatusEffects.Kind.ATTACK_INTERVAL_PCT), 100)

	# Does not affect other entities
	assert_eq(fx.pct("p:2", StatusEffects.Kind.SPEED_PCT), 100)

func test_same_source_replaces_value_and_refreshes_duration() -> void:
	var fx := StatusEffects.new()
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 80, 2, "source_a")
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 80)
	assert_eq(fx.get_duration("p:1", StatusEffects.Kind.SPEED_PCT, "source_a"), 2)

	# Replace with new value and duration
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 60, 5, "source_a")
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 60)
	assert_eq(fx.get_duration("p:1", StatusEffects.Kind.SPEED_PCT, "source_a"), 5)

	# Tick 2 times (would have expired under old duration 2, but has 3 remaining now)
	fx.tick()
	fx.tick()
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 60)
	assert_eq(fx.get_duration("p:1", StatusEffects.Kind.SPEED_PCT, "source_a"), 3)

	# Tick 3 more times -> reaches 0 and expires
	fx.tick()
	fx.tick()
	fx.tick()
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 100)
	assert_eq(fx.get_duration("p:1", StatusEffects.Kind.SPEED_PCT, "source_a"), 0)

func test_multiple_sources_compounding_in_source_key_order() -> void:
	var fx := StatusEffects.new()
	# Add source_b first, then source_a
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 50, 5, "source_b")
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 80, 5, "source_a")

	# Calculation in ascending order: "source_a" (80) then "source_b" (50)
	# 100 * 80 / 100 = 80
	# 80 * 50 / 100 = 40
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 40)

	# 3 sources: "c" (120), "a" (80), "b" (50)
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 120, 5, "source_c")
	# "source_a": 100 * 80 / 100 = 80
	# "source_b": 80 * 50 / 100 = 40
	# "source_c": 40 * 120 / 100 = 48
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 48)

func test_tick_decrements_and_removes_expired() -> void:
	var fx := StatusEffects.new()
	fx.add("p:1", StatusEffects.Kind.DAMAGE_TAKEN_PCT, 150, 1, "debuff_short")
	fx.add("p:1", StatusEffects.Kind.DAMAGE_TAKEN_PCT, 120, 3, "debuff_long")

	# Both active
	# Sorted: debuff_long (120), debuff_short (150)
	# 100 * 120 / 100 = 120
	# 120 * 150 / 100 = 180
	assert_eq(fx.pct("p:1", StatusEffects.Kind.DAMAGE_TAKEN_PCT), 180)

	# Tick 1: debuff_short expires (was 1, now reaches 0)
	fx.tick()
	assert_eq(fx.pct("p:1", StatusEffects.Kind.DAMAGE_TAKEN_PCT), 120)

	# Tick 2: debuff_long duration becomes 1
	fx.tick()
	assert_eq(fx.pct("p:1", StatusEffects.Kind.DAMAGE_TAKEN_PCT), 120)

	# Tick 3: debuff_long expires
	fx.tick()
	assert_eq(fx.pct("p:1", StatusEffects.Kind.DAMAGE_TAKEN_PCT), 100)

func test_permanent_duration() -> void:
	var fx := StatusEffects.new()
	fx.add("s:1", StatusEffects.Kind.DAMAGE_DEALT_PCT, 130, -1, "passive_buff")

	assert_eq(fx.pct("s:1", StatusEffects.Kind.DAMAGE_DEALT_PCT), 130)

	for _i in range(50):
		fx.tick()

	# Duration -1 is never decremented or removed
	assert_eq(fx.pct("s:1", StatusEffects.Kind.DAMAGE_DEALT_PCT), 130)
	assert_eq(fx.get_duration("s:1", StatusEffects.Kind.DAMAGE_DEALT_PCT, "passive_buff"), -1)

func test_disabled_and_rooted_flags() -> void:
	var fx := StatusEffects.new()

	# DISABLED flag
	assert_false(fx.has_flag("p:1", StatusEffects.Kind.DISABLED))
	fx.add("p:1", StatusEffects.Kind.DISABLED, 0, 2, "stun_a")
	assert_true(fx.has_flag("p:1", StatusEffects.Kind.DISABLED))

	# Adding second stun source
	fx.add("p:1", StatusEffects.Kind.DISABLED, 0, 4, "stun_b")
	assert_true(fx.has_flag("p:1", StatusEffects.Kind.DISABLED))

	fx.tick()
	fx.tick() # stun_a expired, stun_b still active (dur 2)
	assert_true(fx.has_flag("p:1", StatusEffects.Kind.DISABLED))

	fx.tick()
	fx.tick() # stun_b expired
	assert_false(fx.has_flag("p:1", StatusEffects.Kind.DISABLED))

	# ROOTED flag
	assert_false(fx.has_flag("p:1", StatusEffects.Kind.ROOTED))
	fx.add("p:1", StatusEffects.Kind.ROOTED, 999, 1, "web") # value ignored
	assert_true(fx.has_flag("p:1", StatusEffects.Kind.ROOTED))
	fx.tick()
	assert_false(fx.has_flag("p:1", StatusEffects.Kind.ROOTED))

func test_clear_entity() -> void:
	var fx := StatusEffects.new()
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 50, 10, "slow")
	fx.add("p:2", StatusEffects.Kind.SPEED_PCT, 70, 10, "slow")

	fx.clear_entity("p:1")
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 100)
	assert_eq(fx.pct("p:2", StatusEffects.Kind.SPEED_PCT), 70)

func test_clear_all() -> void:
	var fx := StatusEffects.new()
	fx.add("p:1", StatusEffects.Kind.SPEED_PCT, 50, 10, "slow")
	fx.add("s:1", StatusEffects.Kind.DAMAGE_DEALT_PCT, 120, 10, "buff")

	fx.clear()
	assert_eq(fx.pct("p:1", StatusEffects.Kind.SPEED_PCT), 100)
	assert_eq(fx.pct("s:1", StatusEffects.Kind.DAMAGE_DEALT_PCT), 100)
