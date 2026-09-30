extends GutTest

const POINTS: Array[Vector2] = [
	Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(40, 40), Vector2(20, 20),
	Vector2(-3.5, 2.25), Vector2(7.125, -9.75), Vector2(-12, -12), Vector2(0.5, 0.5), Vector2(39.99, 0.01),
	Vector2(13.37, 26.42), Vector2(-0.001, 0.001), Vector2(100, -100), Vector2(2.5, 37.5), Vector2(18, 18.5),
	Vector2(33.3, 12.1), Vector2(5, 5), Vector2(-40, 40), Vector2(0.25, 39.75), Vector2(21.5, 8.25),
]

func _proj() -> IsoProjection:
	return IsoProjection.new(14.0, Vector2(320.0, 100.0))

func test_origin_maps_to_origin() -> void:
	var p: IsoProjection = _proj()
	assert_eq(p.ground_to_screen(Vector2.ZERO), p.origin)

func test_round_trip() -> void:
	var p: IsoProjection = _proj()
	for g: Vector2 in POINTS:
		var back: Vector2 = p.screen_to_ground(p.ground_to_screen(g))
		assert_almost_eq(back.x, g.x, 1e-4)
		assert_almost_eq(back.y, g.y, 1e-4)

func test_cell_center_round_trip_for_every_cell() -> void:
	var p: IsoProjection = _proj()
	var bad: int = 0
	for y: int in range(40):
		for x: int in range(40):
			var c := Vector2i(x, y)
			if p.screen_to_cell(p.cell_center(c)) != c:
				bad += 1
	assert_eq(bad, 0)

func test_tile_axes_at_default_size() -> void:
	var p := IsoProjection.new(14.0, Vector2.ZERO)
	var d: Vector2 = p.ground_to_screen(Vector2(1, 0)) - p.ground_to_screen(Vector2(0, 0))
	assert_almost_eq(d.x, 7.84, 0.01)
	assert_almost_eq(d.y, 3.92, 0.01)
	var size: Vector2 = p.island_size(40, 40)
	assert_almost_eq(size.x, 627.2, 0.01)
	assert_almost_eq(size.y, 313.6, 0.01)

func test_depth_key_increases_along_rows_and_columns() -> void:
	var bad: int = 0
	for i: int in range(39):
		for j: int in range(40):
			if IsoProjection.depth_key(Vector2(i + 1, j)) <= IsoProjection.depth_key(Vector2(i, j)):
				bad += 1
			if IsoProjection.depth_key(Vector2(j, i + 1)) <= IsoProjection.depth_key(Vector2(j, i)):
				bad += 1
	assert_eq(bad, 0)

func test_helpers_agree_with_ground_to_screen() -> void:
	var p: IsoProjection = _proj()
	assert_eq(p.cell_center(Vector2i(3, 4)), p.ground_to_screen(Vector2(3.5, 4.5)))
	assert_eq(p.footprint_center(Vector2i(18, 18), Vector2i(4, 4)), p.ground_to_screen(Vector2(20, 20)))
	assert_eq(p.mt_to_screen(Vector2i(2500, 4000)), p.ground_to_screen(Vector2(2.5, 4.0)))
	var via_transform: Vector2 = p.ground_transform() * Vector2(3.0, 5.0)
	var direct: Vector2 = p.ground_to_screen(Vector2(3.0, 5.0))
	assert_almost_eq(via_transform.x, direct.x, 1e-3)
	assert_almost_eq(via_transform.y, direct.y, 1e-3)
