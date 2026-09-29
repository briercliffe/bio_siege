extends GutTest

func _load_default_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	return res.config

# 1. After reset_with_nucleus(): Nucleus id 1 at origin (9,9), covering (9,9), (10,9), (9,10) and (10,10), all NUCLEUS.
func test_reset_with_nucleus_defaults() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	assert_eq(grid.width, 20)
	assert_eq(grid.height, 20)
	assert_eq(grid.deploy_ring, 1)

	var origin: Vector2i = grid.default_nucleus_origin()
	assert_eq(origin, Vector2i(9, 9))

	var nucleus: GridModel.PlacedStructure = grid.get_structure(1)
	assert_not_null(nucleus, "Nucleus with id 1 must exist")
	assert_eq(nucleus.id, 1)
	assert_eq(nucleus.type_id, "nucleus")
	assert_eq(nucleus.origin, Vector2i(9, 9))
	assert_eq(nucleus.footprint, Vector2i(2, 2))

	var expected_cells: Array[Vector2i] = [
		Vector2i(9, 9), Vector2i(10, 9),
		Vector2i(9, 10), Vector2i(10, 10)
	]
	assert_eq(nucleus.cells(), expected_cells)

	for cell: Vector2i in expected_cells:
		assert_eq(grid.tile_state(cell), GridModel.TileState.NUCLEUS, "Cell %s should be NUCLEUS" % str(cell))
		assert_eq(grid.structure_id_at(cell), 1, "Cell %s should point to structure id 1" % str(cell))

	# Non-core occupied count should be 0 (Nucleus is core)
	assert_eq(grid.occupied_cell_count(), 0)
	assert_eq(grid.count_by_type(), {"nucleus": 1})
	assert_true(grid.total_cost().is_empty())

# 2. is_deploy_zone: true for (0,0), (0,5), (19,19) and (5,19); false for (1,1) and (18,18).
func test_is_deploy_zone_and_bounds() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)

	# Deploy zone checks
	assert_true(grid.is_deploy_zone(Vector2i(0, 0)))
	assert_true(grid.is_deploy_zone(Vector2i(0, 5)))
	assert_true(grid.is_deploy_zone(Vector2i(19, 19)))
	assert_true(grid.is_deploy_zone(Vector2i(5, 19)))
	assert_true(grid.is_deploy_zone(Vector2i(19, 0)))
	assert_true(grid.is_deploy_zone(Vector2i(0, 19)))

	assert_false(grid.is_deploy_zone(Vector2i(1, 1)))
	assert_false(grid.is_deploy_zone(Vector2i(18, 18)))
	assert_false(grid.is_deploy_zone(Vector2i(9, 9)))

	# Out of bounds must return false for is_deploy_zone
	assert_false(grid.is_deploy_zone(Vector2i(-1, 0)))
	assert_false(grid.is_deploy_zone(Vector2i(20, 5)))
	assert_false(grid.is_deploy_zone(Vector2i(5, 20)))

	# is_buildable_cell: in bounds and not deploy zone
	assert_true(grid.is_buildable_cell(Vector2i(1, 1)))
	assert_true(grid.is_buildable_cell(Vector2i(18, 18)))
	assert_true(grid.is_buildable_cell(Vector2i(9, 9)))
	assert_false(grid.is_buildable_cell(Vector2i(0, 0)))
	assert_false(grid.is_buildable_cell(Vector2i(0, 5)))
	assert_false(grid.is_buildable_cell(Vector2i(19, 19)))
	assert_false(grid.is_buildable_cell(Vector2i(-1, 5)))
	assert_false(grid.is_buildable_cell(Vector2i(20, 20)))

	# in_bounds
	assert_true(grid.in_bounds(Vector2i(0, 0)))
	assert_true(grid.in_bounds(Vector2i(19, 19)))
	assert_false(grid.in_bounds(Vector2i(-1, 0)))
	assert_false(grid.in_bounds(Vector2i(0, -1)))
	assert_false(grid.in_bounds(Vector2i(20, 0)))
	assert_false(grid.in_bounds(Vector2i(0, 20)))

# 3. Placing a mucous_wall at (1,1) returns id 2, costs 10 ATP and sets the tile to WALL.
func test_place_structure_success() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 1000})
	watch_signals(grid)

	var id: int = grid.place("mucous_wall", Vector2i(1, 1), wallet)
	assert_eq(id, 2, "First placed structure after nucleus should have id 2")
	assert_eq(wallet.get_amount("atp"), 990, "Should spend 10 ATP")
	assert_eq(grid.tile_state(Vector2i(1, 1)), GridModel.TileState.WALL)
	assert_eq(grid.structure_id_at(Vector2i(1, 1)), 2)
	assert_eq(grid.occupied_cell_count(), 1)
	assert_eq(grid.count_by_type(), {"nucleus": 1, "mucous_wall": 1})
	assert_eq(grid.total_cost(), {"atp": 10})
	assert_signal_emitted(grid, "structure_placed")

	# Tower placement (e.g. macrophage)
	var tower_id: int = grid.place("macrophage", Vector2i(3, 3), wallet)
	assert_eq(tower_id, 3)
	assert_eq(wallet.get_amount("atp"), 890, "Should spend 100 ATP")
	assert_eq(grid.tile_state(Vector2i(3, 3)), GridModel.TileState.TOWER)
	assert_eq(grid.structure_id_at(Vector2i(3, 3)), 3)
	assert_eq(grid.occupied_cell_count(), 2)
	assert_eq(grid.count_by_type(), {"nucleus": 1, "mucous_wall": 1, "macrophage": 1})
	assert_eq(grid.total_cost(), {"atp": 110})

# 4. Placing failures: (0,5) -> DEPLOY_ZONE, (20,5) -> OUT_OF_BOUNDS, (9,9) -> OCCUPIED, b_cell with 100 ATP -> INSUFFICIENT_FUNDS. Leaves wallet unchanged.
func test_place_failures_and_wallet_unchanged() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 100})

	# Deploy zone
	var err_deploy: GridModel.PlaceError = grid.check_place("mucous_wall", Vector2i(0, 5), wallet)
	assert_eq(err_deploy, GridModel.PlaceError.DEPLOY_ZONE)
	var id_deploy: int = grid.place("mucous_wall", Vector2i(0, 5), wallet)
	assert_eq(id_deploy, 0)
	assert_eq(wallet.get_amount("atp"), 100)

	# Out of bounds
	var err_oob: GridModel.PlaceError = grid.check_place("mucous_wall", Vector2i(20, 5), wallet)
	assert_eq(err_oob, GridModel.PlaceError.OUT_OF_BOUNDS)
	var id_oob: int = grid.place("mucous_wall", Vector2i(20, 5), wallet)
	assert_eq(id_oob, 0)
	assert_eq(wallet.get_amount("atp"), 100)

	# Occupied by Nucleus
	var err_occ: GridModel.PlaceError = grid.check_place("mucous_wall", Vector2i(9, 9), wallet)
	assert_eq(err_occ, GridModel.PlaceError.OCCUPIED)
	var id_occ: int = grid.place("mucous_wall", Vector2i(9, 9), wallet)
	assert_eq(id_occ, 0)
	assert_eq(wallet.get_amount("atp"), 100)

	# Insufficient funds (b_cell costs 150 ATP, wallet has 100)
	var err_funds: GridModel.PlaceError = grid.check_place("b_cell", Vector2i(2, 2), wallet)
	assert_eq(err_funds, GridModel.PlaceError.INSUFFICIENT_FUNDS)
	var id_funds: int = grid.place("b_cell", Vector2i(2, 2), wallet)
	assert_eq(id_funds, 0)
	assert_eq(wallet.get_amount("atp"), 100)

# 5. Trying to place nucleus returns NOT_BUILDABLE.
func test_place_nucleus_not_buildable() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 1000})
	var err: GridModel.PlaceError = grid.check_place("nucleus", Vector2i(2, 2), wallet)
	assert_eq(err, GridModel.PlaceError.NOT_BUILDABLE)

	var id: int = grid.place("nucleus", Vector2i(2, 2), wallet)
	assert_eq(id, 0)
	assert_eq(wallet.get_amount("atp"), 1000)

# 6. Unknown type returns UNKNOWN_TYPE.
func test_place_unknown_type() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 1000})
	var err: GridModel.PlaceError = grid.check_place("laser_turret", Vector2i(2, 2), wallet)
	assert_eq(err, GridModel.PlaceError.UNKNOWN_TYPE)

	var id: int = grid.place("laser_turret", Vector2i(2, 2), wallet)
	assert_eq(id, 0)

# Check place priority / order: UNKNOWN_TYPE -> NOT_BUILDABLE -> OUT_OF_BOUNDS -> DEPLOY_ZONE -> OCCUPIED -> INSUFFICIENT_FUNDS
func test_check_place_priority_order() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var poor_wallet: Wallet = Wallet.new({"atp": 0})

	# Unknown type vs out of bounds: unknown type takes priority
	var err1: GridModel.PlaceError = grid.check_place("unknown_xyz", Vector2i(99, 99), poor_wallet)
	assert_eq(err1, GridModel.PlaceError.UNKNOWN_TYPE)

	# Not buildable vs out of bounds: not buildable takes priority
	var err2: GridModel.PlaceError = grid.check_place("nucleus", Vector2i(99, 99), poor_wallet)
	assert_eq(err2, GridModel.PlaceError.NOT_BUILDABLE)

	# Not buildable vs deploy zone
	var err3: GridModel.PlaceError = grid.check_place("nucleus", Vector2i(0, 0), poor_wallet)
	assert_eq(err3, GridModel.PlaceError.NOT_BUILDABLE)

	# Out of bounds vs deploy zone:
	# A structure footprint partially out of bounds must fail with OUT_OF_BOUNDS
	var err4: GridModel.PlaceError = grid.check_place("mucous_wall", Vector2i(-1, 0), poor_wallet)
	assert_eq(err4, GridModel.PlaceError.OUT_OF_BOUNDS)

	# Deploy zone vs occupied / funds:
	# mucous_wall in deploy zone with 0 funds fails with DEPLOY_ZONE
	var err5: GridModel.PlaceError = grid.check_place("mucous_wall", Vector2i(0, 0), poor_wallet)
	assert_eq(err5, GridModel.PlaceError.DEPLOY_ZONE)

	# Occupied vs insufficient funds:
	# Placing at (9,9) (Nucleus) with 0 funds fails with OCCUPIED
	var err6: GridModel.PlaceError = grid.check_place("mucous_wall", Vector2i(9, 9), poor_wallet)
	assert_eq(err6, GridModel.PlaceError.OCCUPIED)

	# Insufficient funds: valid position, but cannot afford
	var err7: GridModel.PlaceError = grid.check_place("mucous_wall", Vector2i(2, 2), poor_wallet)
	assert_eq(err7, GridModel.PlaceError.INSUFFICIENT_FUNDS)

# 7. sell refunds full cost, tile becomes EMPTY, next placement gets new id (no reuse)
func test_sell_refund_and_id_increment() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 500})
	watch_signals(grid)

	# Place macrophage (costs 100 ATP) -> id 2
	var id: int = grid.place("macrophage", Vector2i(2, 2), wallet)
	assert_eq(id, 2)
	assert_eq(wallet.get_amount("atp"), 400)
	assert_eq(grid.tile_state(Vector2i(2, 2)), GridModel.TileState.TOWER)
	assert_eq(grid.occupied_cell_count(), 1)

	# Sell structure 2
	var ok: bool = grid.sell(2, wallet)
	assert_true(ok, "Sell should succeed for non-core structure")
	assert_eq(wallet.get_amount("atp"), 500, "Should refund 100% (100 ATP)")
	assert_eq(grid.tile_state(Vector2i(2, 2)), GridModel.TileState.EMPTY)
	assert_eq(grid.structure_id_at(Vector2i(2, 2)), 0)
	assert_null(grid.get_structure(2))
	assert_eq(grid.occupied_cell_count(), 0)
	assert_signal_emitted(grid, "structure_removed")

	# Next placement gets id 3 (no id reuse)
	var new_id: int = grid.place("mucous_wall", Vector2i(2, 2), wallet)
	assert_eq(new_id, 3, "ID counter must strictly increase and never reuse 2")
	assert_eq(wallet.get_amount("atp"), 490)
	assert_eq(grid.tile_state(Vector2i(2, 2)), GridModel.TileState.WALL)

# 8. Selling the Nucleus returns false.
func test_cannot_sell_nucleus() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 1000})
	var ok: bool = grid.sell(1, wallet)
	assert_false(ok, "Selling Nucleus must return false")
	assert_eq(wallet.get_amount("atp"), 1000)
	assert_eq(grid.tile_state(Vector2i(9, 9)), GridModel.TileState.NUCLEUS)
	assert_not_null(grid.get_structure(1))

# Selling non-existent structure returns false
func test_cannot_sell_non_existent() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 1000})
	var ok: bool = grid.sell(999, wallet)
	assert_false(ok)
	assert_eq(wallet.get_amount("atp"), 1000)

# 9. ring_cells(): size 76, index 0 = (0,0), index 19 = (19,0), index 20 = (19,1), index 38 = (19,19), index 57 = (0,19), index 75 = (0,1), and no duplicates.
func test_ring_cells_order_and_uniqueness() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)

	var ring: Array[Vector2i] = grid.ring_cells()
	assert_eq(ring.size(), 76, "20x20 perimeter has 76 cells (2*20 + 2*20 - 4)")

	assert_eq(ring[0], Vector2i(0, 0))
	assert_eq(ring[19], Vector2i(19, 0))
	assert_eq(ring[20], Vector2i(19, 1))
	assert_eq(ring[38], Vector2i(19, 19))
	assert_eq(ring[57], Vector2i(0, 19))
	assert_eq(ring[75], Vector2i(0, 1))

	# Uniqueness check
	var seen: Dictionary = {}
	for cell: Vector2i in ring:
		assert_false(seen.has(cell), "Cell %s appeared more than once in ring_cells" % str(cell))
		seen[cell] = true
		assert_true(grid.is_deploy_zone(cell), "Ring cell %s must be in deploy zone" % str(cell))

# 10. buildable_cell_count() == 324.
func test_buildable_cell_count() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)

	assert_eq(grid.buildable_cell_count(), 324, "20x20 with 1-tile deploy ring should have 18*18=324 buildable cells")

	# Verify by counting every cell in the grid
	var actual_count: int = 0
	for y in range(grid.height):
		for x in range(grid.width):
			if grid.is_buildable_cell(Vector2i(x, y)):
				actual_count += 1
	assert_eq(actual_count, 324)

# 11. to_layout() followed by load_layout() on a fresh grid gives the same count_by_type() and cells.
func test_to_layout_and_load_layout_cycle() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid_a: GridModel = GridModel.new(cfg)
	grid_a.reset_with_nucleus()

	var wallet_a: Wallet = Wallet.new({"atp": 1000})
	var id_wall: int = grid_a.place("mucous_wall", Vector2i(1, 1), wallet_a)
	assert_eq(id_wall, 2)
	var id_macro: int = grid_a.place("macrophage", Vector2i(3, 3), wallet_a)
	assert_eq(id_macro, 3)
	var id_bcell: int = grid_a.place("b_cell", Vector2i(5, 5), wallet_a)
	assert_eq(id_bcell, 4)

	var layout: Array[Dictionary] = grid_a.to_layout()
	assert_eq(layout.size(), 4, "Layout should have 4 structures including Nucleus")
	assert_eq(layout[0]["type"], "nucleus")
	assert_eq(layout[0]["origin"], Vector2i(9, 9))
	assert_eq(layout[1]["type"], "mucous_wall")
	assert_eq(layout[1]["origin"], Vector2i(1, 1))
	assert_eq(layout[2]["type"], "macrophage")
	assert_eq(layout[2]["origin"], Vector2i(3, 3))
	assert_eq(layout[3]["type"], "b_cell")
	assert_eq(layout[3]["origin"], Vector2i(5, 5))

	# Load layout into a fresh grid
	var grid_b: GridModel = GridModel.new(cfg)
	var wallet_b: Wallet = Wallet.new({"atp": 1000})
	var err: GridModel.PlaceError = grid_b.load_layout(layout, wallet_b)
	assert_eq(err, GridModel.PlaceError.OK)

	# Verify state parity
	assert_eq(grid_b.count_by_type(), grid_a.count_by_type())
	assert_eq(grid_b.occupied_cell_count(), grid_a.occupied_cell_count())
	assert_eq(grid_b.total_cost(), grid_a.total_cost())
	assert_eq(wallet_b.get_amount("atp"), wallet_a.get_amount("atp"))

	for y in range(grid_a.height):
		for x in range(grid_a.width):
			var c := Vector2i(x, y)
			assert_eq(grid_b.tile_state(c), grid_a.tile_state(c), "Tile state mismatch at %s" % str(c))
			assert_eq(grid_b.structure_id_at(c), grid_a.structure_id_at(c), "Structure ID mismatch at %s" % str(c))

# load_layout error propagation
func test_load_layout_errors() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)

	# Insufficient funds
	var poor_wallet: Wallet = Wallet.new({"atp": 50})
	var invalid_layout: Array = [
		{"type": "b_cell", "origin": Vector2i(2, 2)} # costs 150 ATP
	]
	var err: GridModel.PlaceError = grid.load_layout(invalid_layout, poor_wallet)
	assert_eq(err, GridModel.PlaceError.INSUFFICIENT_FUNDS)

	# Out of bounds
	var rich_wallet: Wallet = Wallet.new({"atp": 1000})
	var oob_layout: Array = [
		{"type": "mucous_wall", "origin": Vector2i(99, 99)}
	]
	var err_oob: GridModel.PlaceError = grid.load_layout(oob_layout, rich_wallet)
	assert_eq(err_oob, GridModel.PlaceError.OUT_OF_BOUNDS)

# 12. Loading a grid config at 12x12 puts the Nucleus at (5,5) and gives 44 ring cells. Proves nothing is hard-coded.
func test_custom_grid_size_12x12() -> void:
	var base_cfg: GameConfig = _load_default_config()

	var cfg_12: GameConfig = GameConfig.new()
	cfg_12.grid_width = 12
	cfg_12.grid_height = 12
	cfg_12.deploy_ring = 1
	cfg_12.structures = base_cfg.structures

	var grid: GridModel = GridModel.new(cfg_12)
	assert_eq(grid.width, 12)
	assert_eq(grid.height, 12)

	# (12 - 2) / 2 = 5
	assert_eq(grid.default_nucleus_origin(), Vector2i(5, 5))

	grid.reset_with_nucleus()
	var nucleus: GridModel.PlacedStructure = grid.get_structure(1)
	assert_not_null(nucleus)
	assert_eq(nucleus.origin, Vector2i(5, 5))
	assert_eq(nucleus.cells(), [
		Vector2i(5, 5), Vector2i(6, 5),
		Vector2i(5, 6), Vector2i(6, 6)
	])

	# 2*12 + 2*12 - 4 = 44
	var ring: Array[Vector2i] = grid.ring_cells()
	assert_eq(ring.size(), 44)
	assert_eq(ring[0], Vector2i(0, 0))
	assert_eq(ring[11], Vector2i(11, 0))
	assert_eq(ring[12], Vector2i(11, 1))
	assert_eq(ring[22], Vector2i(11, 11))
	assert_eq(ring[33], Vector2i(0, 11))
	assert_eq(ring[43], Vector2i(0, 1))

	# Buildable cell count: (12 - 2) * (12 - 2) = 100
	assert_eq(grid.buildable_cell_count(), 100)

# structures() returns list sorted by id ascending
func test_structures_sorted_by_id() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 1000})
	grid.place("mucous_wall", Vector2i(1, 1), wallet) # id 2
	grid.place("mucous_wall", Vector2i(2, 2), wallet) # id 3
	grid.place("mucous_wall", Vector2i(3, 3), wallet) # id 4

	grid.sell(3, wallet) # sell middle structure

	grid.place("macrophage", Vector2i(4, 4), wallet) # id 5

	var structs: Array[GridModel.PlacedStructure] = grid.structures()
	assert_eq(structs.size(), 4)
	assert_eq(structs[0].id, 1)
	assert_eq(structs[1].id, 2)
	assert_eq(structs[2].id, 4)
	assert_eq(structs[3].id, 5)

# reset_with_nucleus emits structure_removed for old structures and structure_placed for nucleus
func test_reset_with_nucleus_signals() -> void:
	var cfg: GameConfig = _load_default_config()
	var grid: GridModel = GridModel.new(cfg)
	grid.reset_with_nucleus()

	var wallet: Wallet = Wallet.new({"atp": 1000})
	grid.place("mucous_wall", Vector2i(1, 1), wallet)

	watch_signals(grid)
	grid.reset_with_nucleus()

	assert_signal_emitted(grid, "structure_removed")
	assert_signal_emitted(grid, "structure_placed")
	assert_eq(grid.structures().size(), 1)
	assert_eq(grid.structures()[0].id, 1)
