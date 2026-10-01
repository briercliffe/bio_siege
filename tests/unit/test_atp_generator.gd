extends GutTest

var _cfg: GameConfig = null

func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	_cfg = res.config

func _two_mito_layout() -> Array:
	return [
		{"type": "mitochondria", "origin": Vector2i(2, 2)},
		{"type": "macrophage", "origin": Vector2i(8, 8)},
		{"type": "mitochondria", "origin": Vector2i(12, 2)},
	]

func test_rate_and_capacity() -> void:
	var layout: Array = _two_mito_layout()
	assert_eq(AtpGenerator.rate_per_hour(_cfg, layout), 120)
	assert_eq(AtpGenerator.capacity(_cfg, layout), 600)
	assert_eq(AtpGenerator.rate_per_hour(_cfg, []), 0)

func test_accrue_simple() -> void:
	var r: Dictionary = AtpGenerator.accrue(0, 0, 60, 300, 1800, 86400)
	assert_eq(r["stored"], 30)
	assert_eq(r["carry"], 0)
	assert_eq(r["generated"], 30)

func test_accrue_carries_fractional_atp() -> void:
	var r: Dictionary = AtpGenerator.accrue(0, 0, 7, 300, 1000, 86400)
	assert_eq(r["stored"], 1)
	assert_eq(r["carry"], 3400)
	var r2: Dictionary = AtpGenerator.accrue(int(r["stored"]), int(r["carry"]), 7, 300, 100, 86400)
	assert_eq(r2["stored"], 2)
	assert_eq(r2["carry"], 500)
	assert_eq(r2["generated"], 1)

func test_accrue_cap_clears_carry() -> void:
	var r: Dictionary = AtpGenerator.accrue(290, 100, 60, 300, 3600, 86400)
	assert_eq(r["stored"], 300)
	assert_eq(r["carry"], 0)
	assert_eq(r["generated"], 10)

func test_accrue_negative_and_clamped_elapsed() -> void:
	var neg: Dictionary = AtpGenerator.accrue(5, 10, 60, 300, -500, 86400)
	assert_eq(neg["stored"], 5)
	assert_eq(neg["carry"], 10)
	assert_eq(neg["generated"], 0)
	var clamped: Dictionary = AtpGenerator.accrue(0, 0, 60, 100000, 999999, 7200)
	assert_eq(clamped["stored"], 120)

func test_accrue_no_cap_or_rate_changes_nothing() -> void:
	var a: Dictionary = AtpGenerator.accrue(5, 10, 60, 0, 3600, 86400)
	assert_eq(a, {"stored": 5, "carry": 10, "generated": 0})
	var b: Dictionary = AtpGenerator.accrue(5, 10, 0, 300, 3600, 86400)
	assert_eq(b, {"stored": 5, "carry": 10, "generated": 0})

func test_split_stored_remainder_to_first() -> void:
	var layout: Array = [
		{"type": "mitochondria", "origin": Vector2i(2, 2)},
		{"type": "macrophage", "origin": Vector2i(8, 8)},
	]
	# One 300-storage Mitochondria plus a second with storage 100 would need a custom def; use the shipped one twice.
	var two: Array = _two_mito_layout()
	var split: Array[int] = AtpGenerator.split_stored(_cfg, two, 101)
	assert_eq(split, [51, 0, 50])
	var single: Array[int] = AtpGenerator.split_stored(_cfg, layout, 77)
	assert_eq(single, [77, 0])
	assert_eq(AtpGenerator.split_stored(_cfg, two, 0), [0, 0, 0])

func test_split_stored_unequal_storage() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data").config
	var small: StructureDef = (cfg.structures["mitochondria"] as StructureDef)
	var tiny: StructureDef = StructureDef.new()
	tiny.has_generator = true
	tiny.generator_atp_per_hour = 20
	tiny.generator_storage = 100
	cfg.structures["tiny_mito"] = tiny
	assert_eq(small.generator_storage, 300)
	var layout: Array = [
		{"type": "mitochondria", "origin": Vector2i.ZERO},
		{"type": "tiny_mito", "origin": Vector2i.ZERO},
	]
	assert_eq(AtpGenerator.split_stored(cfg, layout, 101), [76, 25])

func test_accrue_stored_above_cap_never_reports_negative_generated() -> void:
	var r: Dictionary = AtpGenerator.accrue(400, 0, 60, 300, 3600, 86400)
	assert_eq(r["stored"], 300)
	assert_eq(r["generated"], 0)
