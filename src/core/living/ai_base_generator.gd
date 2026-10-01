class_name AiBaseGenerator
extends RefCounted

## Builds an AI defender base from (seed, tier), deterministically and with valid placements only (#160).
## Ints only; one Rng that is never reseeded.

const WALL_ID: String = "mucous_wall"
const MITOCHONDRIA_ID: String = "mitochondria"
const DENDRITIC_ID: String = "dendritic_cell"
const TIE_SCALE: int = 1000000
const WALL_MARGIN: int = 2


## Returns {"layout": Array[Dictionary], "spent": int, "tier": String}.
## `spent` is the ATP cost of the towers and walls; Mitochondria and Dendritic Cells are free.
static func generate(cfg: GameConfig, tier_id: String, seed: int) -> Dictionary:
	var tier: Dictionary = _tier(cfg, tier_id)
	if tier.is_empty():
		var none: Array[Dictionary] = []
		return {"layout": none, "spent": 0, "tier": tier_id}
	var rng := Rng.new(seed)
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	# Placement is checked and made with a wallet that affords anything, so the budget logic below is the only limit.
	var wallet: Wallet = LivingBaseProfile.unlimited_wallet()
	var candidates: Array[Vector2i] = _candidates(grid, rng)

	if cfg.is_structure_enabled(MITOCHONDRIA_ID):
		for _i: int in range(int(tier["mitochondria"])):
			_place_spaced(cfg, grid, wallet, candidates, MITOCHONDRIA_ID)
	if cfg.is_structure_enabled(DENDRITIC_ID):
		for _i: int in range(int(tier["dendritic"])):
			_place_spaced(cfg, grid, wallet, candidates, DENDRITIC_ID)

	var budget: int = int(tier["budget_atp"])
	var tower_budget: int = budget * (100 - int(tier["wall_pct"])) / 100
	var spent: int = _place_towers(cfg, grid, wallet, candidates, rng, tower_budget)
	spent += _place_walls(cfg, grid, wallet, budget - spent)

	return {"layout": grid.to_layout(), "spent": spent, "tier": tier_id}


static func _tier(cfg: GameConfig, tier_id: String) -> Dictionary:
	for t: Dictionary in cfg.ai_tiers:
		if str(t["id"]) == tier_id:
			return t
	return {}


## Every buildable cell, nearest the Nucleus first. Distance ties are broken by a seeded draw, then by (y, x).
static func _candidates(grid: GridModel, rng: Rng) -> Array[Vector2i]:
	var core: GridModel.PlacedStructure = grid.find_core()
	var nc: Vector2i = Vector2i(grid.width / 2, grid.height / 2)
	if core != null:
		nc = core.origin + core.footprint / 2
	var keyed: Array[Dictionary] = []
	for y: int in range(grid.height):
		for x: int in range(grid.width):
			var c := Vector2i(x, y)
			if not grid.is_buildable_cell(c):
				continue
			var dist: int = maxi(absi(c.x - nc.x), absi(c.y - nc.y))
			keyed.append({"cell": c, "key": dist * TIE_SCALE + rng.next_int(TIE_SCALE)})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["key"] != b["key"]:
			return int(a["key"]) < int(b["key"])
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		if ca.y != cb.y:
			return ca.y < cb.y
		return ca.x < cb.x
	)
	var cells: Array[Vector2i] = []
	for k: Dictionary in keyed:
		cells.append(k["cell"])
	return cells


## Places `type_id` on the first candidate that is legal and leaves a one-cell walkway around it
## (the border is empty or part of the deploy zone). Returns false when nothing fits.
static func _place_spaced(cfg: GameConfig, grid: GridModel, wallet: Wallet, candidates: Array[Vector2i], type_id: String) -> bool:
	var sdef: StructureDef = cfg.structures.get(type_id)
	if sdef == null:
		return false
	for origin: Vector2i in candidates:
		if grid.check_place(type_id, origin, wallet) != GridModel.PlaceError.OK:
			continue
		if not _border_is_clear(grid, origin, sdef.footprint):
			continue
		return grid.place(type_id, origin, wallet) > 0
	return false


static func _border_is_clear(grid: GridModel, origin: Vector2i, footprint: Vector2i) -> bool:
	for y: int in range(origin.y - 1, origin.y + footprint.y + 1):
		for x: int in range(origin.x - 1, origin.x + footprint.x + 1):
			var inside: bool = x >= origin.x and x < origin.x + footprint.x and y >= origin.y and y < origin.y + footprint.y
			if inside:
				continue
			var c := Vector2i(x, y)
			if not grid.in_bounds(c) or grid.is_deploy_zone(c):
				continue
			if grid.structure_id_at(c) != 0:
				return false
	return true


## Spends the tower budget on weighted-random towers. Returns the ATP spent.
static func _place_towers(cfg: GameConfig, grid: GridModel, wallet: Wallet, candidates: Array[Vector2i], rng: Rng, tower_budget: int) -> int:
	var types: Array[String] = []
	for k: Variant in cfg.ai_tower_weights.keys():
		if cfg.structures.has(str(k)):
			types.append(str(k))
	types.sort()
	if types.is_empty():
		return 0
	var total_weight: int = 0
	var cheapest: String = types[0]
	for t: String in types:
		total_weight += int(cfg.ai_tower_weights[t])
		if _cost(cfg, t) < _cost(cfg, cheapest):
			cheapest = t
	var remaining: int = tower_budget
	var spent: int = 0
	while _cost(cfg, cheapest) > 0 and remaining >= _cost(cfg, cheapest):
		var pick: String = _draw(cfg, types, total_weight, rng)
		if _cost(cfg, pick) > remaining:
			pick = cheapest
		if not _place_spaced(cfg, grid, wallet, candidates, pick):
			break
		remaining -= _cost(cfg, pick)
		spent += _cost(cfg, pick)
	return spent


static func _draw(cfg: GameConfig, types: Array[String], total_weight: int, rng: Rng) -> String:
	var roll: int = rng.next_int(total_weight)
	for t: String in types:
		roll -= int(cfg.ai_tower_weights[t])
		if roll < 0:
			return t
	return types[types.size() - 1]


## Rings the placed structures with walls: the perimeter of their bounding box grown by two cells,
## walked clockwise from the top-left corner, until the wall budget runs out. Returns the ATP spent.
static func _place_walls(cfg: GameConfig, grid: GridModel, wallet: Wallet, wall_budget: int) -> int:
	var wall_cost: int = _cost(cfg, WALL_ID)
	if wall_cost <= 0 or not cfg.structures.has(WALL_ID):
		return 0
	var lo := Vector2i(grid.width, grid.height)
	var hi := Vector2i(-1, -1)
	for s: GridModel.PlacedStructure in grid.structures():
		var sdef: StructureDef = cfg.structures.get(s.type_id)
		if sdef == null or sdef.has_tag("wall"):
			continue
		lo = Vector2i(mini(lo.x, s.origin.x), mini(lo.y, s.origin.y))
		hi = Vector2i(maxi(hi.x, s.origin.x + s.footprint.x - 1), maxi(hi.y, s.origin.y + s.footprint.y - 1))
	if hi.x < 0:
		return 0
	var ring: int = grid.deploy_ring
	var x0: int = maxi(lo.x - WALL_MARGIN, ring)
	var y0: int = maxi(lo.y - WALL_MARGIN, ring)
	var x1: int = mini(hi.x + WALL_MARGIN, grid.width - 1 - ring)
	var y1: int = mini(hi.y + WALL_MARGIN, grid.height - 1 - ring)
	var spent: int = 0
	for c: Vector2i in _perimeter(x0, y0, x1, y1):
		if wall_budget - spent < wall_cost:
			break
		if grid.check_place(WALL_ID, c, wallet) == GridModel.PlaceError.OK and grid.place(WALL_ID, c, wallet) > 0:
			spent += wall_cost
	return spent


## The rectangle's edge cells, clockwise from the top-left, each once.
static func _perimeter(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if x1 < x0 or y1 < y0:
		return cells
	for x: int in range(x0, x1 + 1):
		cells.append(Vector2i(x, y0))
	for y: int in range(y0 + 1, y1 + 1):
		cells.append(Vector2i(x1, y))
	if y1 > y0:
		for x: int in range(x1 - 1, x0 - 1, -1):
			cells.append(Vector2i(x, y1))
	if x1 > x0:
		for y: int in range(y1 - 1, y0, -1):
			cells.append(Vector2i(x0, y))
	return cells


static func _cost(cfg: GameConfig, type_id: String) -> int:
	var sdef: StructureDef = cfg.structures.get(type_id)
	return int(sdef.cost.get("atp", 0)) if sdef != null else 0
