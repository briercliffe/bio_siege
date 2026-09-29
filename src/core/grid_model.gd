class_name GridModel
extends RefCounted

enum TileState { EMPTY, WALL, TOWER, NUCLEUS }
enum PlaceError { OK, OUT_OF_BOUNDS, DEPLOY_ZONE, OCCUPIED, INSUFFICIENT_FUNDS, NOT_BUILDABLE, UNKNOWN_TYPE }

class PlacedStructure extends RefCounted:
	var id: int = 0
	var type_id: String = ""
	var origin: Vector2i = Vector2i.ZERO
	var footprint: Vector2i = Vector2i.ONE

	func cells() -> Array[Vector2i]:
		var res: Array[Vector2i] = []
		for y in range(origin.y, origin.y + footprint.y):
			for x in range(origin.x, origin.x + footprint.x):
				res.append(Vector2i(x, y))
		return res

signal structure_placed(s: PlacedStructure)
signal structure_removed(s: PlacedStructure)

var _config: GameConfig = null
var width: int = 0
var height: int = 0
var deploy_ring: int = 0

var _next_id: int = 1
var _structures: Dictionary = {} # int id -> PlacedStructure
var _cell_to_id: Dictionary = {} # Vector2i cell -> int id

func _init(config: GameConfig = null) -> void:
	_config = config
	if config != null:
		width = config.grid_width
		height = config.grid_height
		deploy_ring = config.deploy_ring

func set_config(config: GameConfig) -> void:
	_config = config
	if config != null:
		width = config.grid_width
		height = config.grid_height
		deploy_ring = config.deploy_ring

func remove_unknown_structures() -> int:
	var removed: int = 0
	if _config == null:
		return removed
	for s: PlacedStructure in structures():
		if _config.structures.has(s.type_id):
			continue
		_structures.erase(s.id)
		for c: Vector2i in s.cells():
			_cell_to_id.erase(c)
		structure_removed.emit(s)
		removed += 1
	return removed

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height

func is_deploy_zone(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	if deploy_ring <= 0:
		return false
	return cell.x < deploy_ring or cell.x >= width - deploy_ring or cell.y < deploy_ring or cell.y >= height - deploy_ring

func is_buildable_cell(cell: Vector2i) -> bool:
	return in_bounds(cell) and not is_deploy_zone(cell)

func tile_state(cell: Vector2i) -> TileState:
	if not _cell_to_id.has(cell):
		return TileState.EMPTY
	var sid: int = int(_cell_to_id[cell])
	var s: PlacedStructure = _structures.get(sid)
	if s == null:
		return TileState.EMPTY
	var sdef: StructureDef = _config.structures.get(s.type_id) if _config != null else null
	if sdef != null:
		if sdef.has_tag("core"):
			return TileState.NUCLEUS
		if sdef.has_tag("wall"):
			return TileState.WALL
		return TileState.TOWER
	if s.type_id == "nucleus":
		return TileState.NUCLEUS
	return TileState.TOWER

func structure_id_at(cell: Vector2i) -> int:
	return int(_cell_to_id.get(cell, 0))

func get_structure(id: int) -> PlacedStructure:
	return _structures.get(id, null)

func structures() -> Array[PlacedStructure]:
	var list: Array[PlacedStructure] = []
	for s: PlacedStructure in _structures.values():
		list.append(s)
	list.sort_custom(func(a: PlacedStructure, b: PlacedStructure) -> bool:
		return a.id < b.id
	)
	return list

func check_place(type_id: String, origin: Vector2i, wallet: Wallet = null) -> PlaceError:
	if _config == null or not _config.structures.has(type_id):
		return PlaceError.UNKNOWN_TYPE

	var sdef: StructureDef = _config.structures[type_id]
	if not sdef.buildable:
		return PlaceError.NOT_BUILDABLE

	for y in range(origin.y, origin.y + sdef.footprint.y):
		for x in range(origin.x, origin.x + sdef.footprint.x):
			if not in_bounds(Vector2i(x, y)):
				return PlaceError.OUT_OF_BOUNDS

	for y in range(origin.y, origin.y + sdef.footprint.y):
		for x in range(origin.x, origin.x + sdef.footprint.x):
			if is_deploy_zone(Vector2i(x, y)):
				return PlaceError.DEPLOY_ZONE

	for y in range(origin.y, origin.y + sdef.footprint.y):
		for x in range(origin.x, origin.x + sdef.footprint.x):
			if _cell_to_id.has(Vector2i(x, y)):
				return PlaceError.OCCUPIED

	if wallet != null:
		if not wallet.can_afford(sdef.cost):
			return PlaceError.INSUFFICIENT_FUNDS
	else:
		for cur: Variant in sdef.cost.keys():
			if int(sdef.cost[cur]) > 0:
				return PlaceError.INSUFFICIENT_FUNDS

	return PlaceError.OK

func place(type_id: String, origin: Vector2i, wallet: Wallet = null) -> int:
	var err: PlaceError = check_place(type_id, origin, wallet)
	if err != PlaceError.OK:
		return 0
	var sdef: StructureDef = _config.structures[type_id]
	if wallet != null and not sdef.cost.is_empty():
		var spent: bool = wallet.spend(sdef.cost)
		if not spent:
			return 0
	var s := PlacedStructure.new()
	s.id = _next_id
	_next_id += 1
	s.type_id = type_id
	s.origin = origin
	s.footprint = sdef.footprint
	_structures[s.id] = s
	for c: Vector2i in s.cells():
		_cell_to_id[c] = s.id
	structure_placed.emit(s)
	return s.id

func sell(structure_id: int, wallet: Wallet = null) -> bool:
	if not _structures.has(structure_id):
		return false
	var s: PlacedStructure = _structures[structure_id]
	var sdef: StructureDef = _config.structures.get(s.type_id) if _config != null else null
	var is_core: bool = (sdef != null and sdef.has_tag("core")) or (s.type_id == "nucleus")
	if is_core:
		return false
	if wallet != null and sdef != null and not sdef.cost.is_empty():
		wallet.refund(sdef.cost)
	_structures.erase(structure_id)
	for c: Vector2i in s.cells():
		_cell_to_id.erase(c)
	structure_removed.emit(s)
	return true

func default_nucleus_origin() -> Vector2i:
	var core_id: String = _config.core_structure_id() if _config != null else "nucleus"
	if core_id.is_empty():
		core_id = "nucleus"
	var core_def: StructureDef = _config.structures.get(core_id) if _config != null else null
	var fw: int = core_def.footprint.x if core_def != null else 2
	var fh: int = core_def.footprint.y if core_def != null else 2
	return Vector2i((width - fw) / 2, (height - fh) / 2)

func reset_with_nucleus() -> void:
	var old_structures: Array[PlacedStructure] = structures()
	_structures.clear()
	_cell_to_id.clear()
	for s: PlacedStructure in old_structures:
		structure_removed.emit(s)

	_next_id = 1
	var core_id: String = _config.core_structure_id() if _config != null else "nucleus"
	if core_id.is_empty():
		core_id = "nucleus"
	var core_def: StructureDef = _config.structures.get(core_id) if _config != null else null
	var fp: Vector2i = core_def.footprint if core_def != null else Vector2i(2, 2)

	var nucleus := PlacedStructure.new()
	nucleus.id = _next_id
	_next_id += 1
	nucleus.type_id = core_id
	nucleus.origin = default_nucleus_origin()
	nucleus.footprint = fp

	_structures[nucleus.id] = nucleus
	for c: Vector2i in nucleus.cells():
		_cell_to_id[c] = nucleus.id

	structure_placed.emit(nucleus)

func ring_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if width <= 0 or height <= 0:
		return cells
	if width == 1 and height == 1:
		cells.append(Vector2i(0, 0))
		return cells
	# 1. top row: x = 0..width-1 at y = 0
	for x in range(0, width):
		cells.append(Vector2i(x, 0))
	# 2. right col: y = 1..height-1 at x = width-1
	for y in range(1, height):
		cells.append(Vector2i(width - 1, y))
	# 3. bottom row: x = width-2 down to 0 at y = height-1
	for x in range(width - 2, -1, -1):
		cells.append(Vector2i(x, height - 1))
	# 4. left col: y = height-2 down to 1 at x = 0
	for y in range(height - 2, 0, -1):
		cells.append(Vector2i(0, y))
	return cells

func buildable_cell_count() -> int:
	var bw: int = maxi(0, width - 2 * deploy_ring)
	var bh: int = maxi(0, height - 2 * deploy_ring)
	return bw * bh

func occupied_cell_count() -> int:
	var count: int = 0
	for s: PlacedStructure in _structures.values():
		var sdef: StructureDef = _config.structures.get(s.type_id) if _config != null else null
		var is_core: bool = (sdef != null and sdef.has_tag("core")) or (s.type_id == "nucleus")
		if is_core:
			continue
		count += s.footprint.x * s.footprint.y
	return count

func count_by_type() -> Dictionary:
	var counts: Dictionary = {}
	for s: PlacedStructure in _structures.values():
		counts[s.type_id] = int(counts.get(s.type_id, 0)) + 1
	return counts

func total_cost() -> Dictionary:
	var total: Dictionary = {}
	for s: PlacedStructure in _structures.values():
		var sdef: StructureDef = _config.structures.get(s.type_id) if _config != null else null
		var is_core: bool = (sdef != null and sdef.has_tag("core")) or (s.type_id == "nucleus")
		if is_core or sdef == null or sdef.cost.is_empty():
			continue
		for cur: Variant in sdef.cost.keys():
			var cur_name: String = str(cur)
			var amount: int = int(sdef.cost[cur])
			total[cur_name] = int(total.get(cur_name, 0)) + amount
	return total

func to_layout() -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	for s: PlacedStructure in structures():
		layout.append({
			"type": s.type_id,
			"origin": s.origin
		})
	return layout

func load_layout(layout: Array, wallet: Wallet = null) -> PlaceError:
	reset_with_nucleus()
	for item: Variant in layout:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var type_id: String = str(entry.get("type", ""))
		var origin_val: Variant = entry.get("origin", Vector2i.ZERO)
		var origin: Vector2i = Vector2i.ZERO
		if origin_val is Vector2i:
			origin = origin_val
		elif origin_val is Array and (origin_val as Array).size() >= 2:
			origin = Vector2i(int((origin_val as Array)[0]), int((origin_val as Array)[1]))

		var sdef: StructureDef = _config.structures.get(type_id) if _config != null else null
		var is_core: bool = (sdef != null and sdef.has_tag("core")) or (type_id == "nucleus")
		if is_core:
			continue

		var err: PlaceError = check_place(type_id, origin, wallet)
		if err != PlaceError.OK:
			return err
		var new_id: int = place(type_id, origin, wallet)
		if new_id == 0:
			return PlaceError.INSUFFICIENT_FUNDS
	return PlaceError.OK
