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
		if _config.is_structure_enabled(s.type_id):
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
	if not sdef.buildable or not _config.is_structure_enabled(type_id):
		return PlaceError.NOT_BUILDABLE

	var footprint_err: PlaceError = _check_footprint(sdef.footprint, origin, 0)
	if footprint_err != PlaceError.OK:
		return footprint_err

	if wallet != null:
		if not wallet.can_afford(sdef.cost):
			return PlaceError.INSUFFICIENT_FUNDS
	else:
		for cur: Variant in sdef.cost.keys():
			if int(sdef.cost[cur]) > 0:
				return PlaceError.INSUFFICIENT_FUNDS

	return PlaceError.OK

## Bounds, deploy ring and overlap checks shared by check_place and check_move.
## Cells owned by ignore_id count as free (0 ignores nothing).
func _check_footprint(footprint: Vector2i, origin: Vector2i, ignore_id: int) -> PlaceError:
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			if not in_bounds(Vector2i(x, y)):
				return PlaceError.OUT_OF_BOUNDS

	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			if is_deploy_zone(Vector2i(x, y)):
				return PlaceError.DEPLOY_ZONE

	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			var cell: Vector2i = Vector2i(x, y)
			if _cell_to_id.has(cell) and int(_cell_to_id[cell]) != ignore_id:
				return PlaceError.OCCUPIED

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

## Same validation as check_place except there is no cost check and the
## structure's own current cells count as free. An unknown id reports UNKNOWN_TYPE.
func check_move(structure_id: int, new_origin: Vector2i) -> PlaceError:
	var s: PlacedStructure = _structures.get(structure_id, null)
	if s == null:
		return PlaceError.UNKNOWN_TYPE
	return _check_footprint(s.footprint, new_origin, structure_id)

## Moves a structure keeping its id. On success emits structure_removed(old)
## then structure_placed(new); moving to the current origin is a silent no-op.
func move_structure(structure_id: int, new_origin: Vector2i) -> PlaceError:
	var err: PlaceError = check_move(structure_id, new_origin)
	if err != PlaceError.OK:
		return err
	var old: PlacedStructure = _structures[structure_id]
	if old.origin == new_origin:
		return PlaceError.OK
	var moved := PlacedStructure.new()
	moved.id = old.id
	moved.type_id = old.type_id
	moved.origin = new_origin
	moved.footprint = old.footprint
	for c: Vector2i in old.cells():
		_cell_to_id.erase(c)
	_structures[moved.id] = moved
	for c: Vector2i in moved.cells():
		_cell_to_id[c] = moved.id
	structure_removed.emit(old)
	structure_placed.emit(moved)
	return PlaceError.OK

## The placed core structure (Nucleus), or null when there is none.
func find_core() -> PlacedStructure:
	for s: PlacedStructure in structures():
		if _is_core_type(s.type_id):
			return s
	return null

func _is_core_type(type_id: String) -> bool:
	var sdef: StructureDef = _config.structures.get(type_id) if _config != null else null
	return (sdef != null and sdef.has_tag("core")) or type_id == "nucleus"

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
	if width <= 0 or height <= 0 or deploy_ring <= 0:
		return cells
	var depth_count: int = mini(deploy_ring, (mini(width, height) + 1) / 2)
	for d in range(depth_count):
		var x0: int = d
		var y0: int = d
		var x1: int = width - 1 - d
		var y1: int = height - 1 - d
		if x0 == x1 and y0 == y1:
			cells.append(Vector2i(x0, y0))
			continue
		# 1. top row: x0..x1 at y0
		for x in range(x0, x1 + 1):
			cells.append(Vector2i(x, y0))
		# 2. right col: y0+1..y1 at x1
		for y in range(y0 + 1, y1 + 1):
			cells.append(Vector2i(x1, y))
		# 3. bottom row: x1-1 down to x0 at y1
		if y1 > y0:
			for x in range(x1 - 1, x0 - 1, -1):
				cells.append(Vector2i(x, y1))
		# 4. left col: y1-1 down to y0+1 at x0
		if x1 > x0:
			for y in range(y1 - 1, y0, -1):
				cells.append(Vector2i(x0, y))
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

## Rebuilds the grid from a layout. A core entry moves the Nucleus to that
## origin (applied first so other structures validate against its final cells).
func load_layout(layout: Array, wallet: Wallet = null) -> PlaceError:
	reset_with_nucleus()
	var entries: Array[Dictionary] = []
	for item: Variant in layout:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var origin_val: Variant = entry.get("origin", Vector2i.ZERO)
		var origin: Vector2i = Vector2i.ZERO
		if origin_val is Vector2i:
			origin = origin_val
		elif origin_val is Array and (origin_val as Array).size() >= 2:
			origin = Vector2i(int((origin_val as Array)[0]), int((origin_val as Array)[1]))
		entries.append({"type": str(entry.get("type", "")), "origin": origin})

	var core_moved: bool = false
	for entry: Dictionary in entries:
		if not _is_core_type(str(entry["type"])) or core_moved:
			continue
		core_moved = true
		var core: PlacedStructure = find_core()
		if core != null:
			var move_err: PlaceError = move_structure(core.id, entry["origin"])
			if move_err != PlaceError.OK:
				return move_err

	for entry: Dictionary in entries:
		var type_id: String = str(entry["type"])
		if _is_core_type(type_id):
			continue
		var origin: Vector2i = entry["origin"]
		if _config != null and not _config.is_structure_enabled(type_id):
			return PlaceError.UNKNOWN_TYPE
		var err: PlaceError = check_place(type_id, origin, wallet)
		if err != PlaceError.OK:
			return err
		var new_id: int = place(type_id, origin, wallet)
		if new_id == 0:
			return PlaceError.INSUFFICIENT_FUNDS
	return PlaceError.OK
