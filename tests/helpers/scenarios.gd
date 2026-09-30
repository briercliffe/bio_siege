class_name Scenarios
extends RefCounted

## Static scenario factories returning BattleSetup for battle integration tests.
## Every setup includes the Nucleus at origin (9, 9) as the first structure.


static func ring_cells(width: int = 20, height: int = 20) -> Array[Vector2i]:
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


static func open_field(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
	]
	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(19, 10)},
		{"type": "rhinovirus", "cell": Vector2i(10, 0)},
		{"type": "rhinovirus", "cell": Vector2i(10, 19)},
		{"type": "rhinovirus", "cell": Vector2i(0, 0)},
	]
	return BattleSetup.create(structures, units, seed)


static func walled_nucleus(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
	]
	for y in range(8, 12):
		for x in range(8, 12):
			if (x == 9 or x == 10) and (y == 9 or y == 10):
				continue
			structures.append({"type": "mucous_wall", "origin": Vector2i(x, y)})

	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
	]
	return BattleSetup.create(structures, units, seed)


static func short_wall(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
	]
	for y in range(8, 13):
		structures.append({"type": "mucous_wall", "origin": Vector2i(5, y)})

	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
	]
	return BattleSetup.create(structures, units, seed)


static func long_wall(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
	]
	for y in range(1, 19):
		structures.append({"type": "mucous_wall", "origin": Vector2i(5, y)})

	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
		{"type": "rhinovirus", "cell": Vector2i(0, 10)},
	]
	return BattleSetup.create(structures, units, seed)


static func phage_priority(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
		{"type": "b_cell", "origin": Vector2i(15, 10)},
	]
	var units: Array = [
		{"type": "bacteriophage", "cell": Vector2i(0, 10)},
		{"type": "bacteriophage", "cell": Vector2i(0, 10)},
		{"type": "bacteriophage", "cell": Vector2i(0, 10)},
		{"type": "bacteriophage", "cell": Vector2i(0, 10)},
		{"type": "bacteriophage", "cell": Vector2i(0, 10)},
	]
	return BattleSetup.create(structures, units, seed)


static func mixed(ring: Array[Vector2i] = [], seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
	]
	for y in range(7, 13):
		structures.append({"type": "mucous_wall", "origin": Vector2i(7, y)})
	for y in range(7, 13):
		structures.append({"type": "mucous_wall", "origin": Vector2i(12, y)})

	structures.append({"type": "macrophage", "origin": Vector2i(8, 6)})
	structures.append({"type": "macrophage", "origin": Vector2i(11, 13)})
	structures.append({"type": "b_cell", "origin": Vector2i(6, 10)})
	structures.append({"type": "b_cell", "origin": Vector2i(13, 10)})

	var r: Array[Vector2i] = ring
	if r.is_empty():
		r = ring_cells()

	var units: Array = []
	for i in range(20):
		units.append({"type": "rhinovirus", "cell": r[i * 3]})

	var phage_indices: Array[int] = [1, 16, 31, 46, 61]
	for idx in phage_indices:
		units.append({"type": "bacteriophage", "cell": r[idx]})

	var staph_indices: Array[int] = [5, 43]
	for idx in staph_indices:
		units.append({"type": "staphylococcus", "cell": r[idx]})

	return BattleSetup.create(structures, units, seed)


## Reference scenario for "repeating one strain gets punished": Nucleus, two B-Cells and a
## Macrophage inside the base, 20 Rhinoviruses spread evenly around the ring.
## The B-Cells flank the Nucleus and the Macrophage sits in a far corner, so the B-Cells
## live long enough to finish analysis. All cells are inside the base at 20x20 and 40x40.
static func repeat_swarm(ring: Array[Vector2i] = [], seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
		{"type": "b_cell", "origin": Vector2i(8, 9)},
		{"type": "b_cell", "origin": Vector2i(11, 10)},
		{"type": "macrophage", "origin": Vector2i(3, 3)},
	]
	var r: Array[Vector2i] = ring
	if r.is_empty():
		r = ring_cells()
	var units: Array = []
	var step: int = maxi(1, r.size() / 20)
	for i in range(20):
		units.append({"type": "rhinovirus", "cell": r[(i * step) % r.size()]})
	return BattleSetup.create(structures, units, seed)


static func stress(ring: Array[Vector2i] = [], seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(9, 9)},
		{"type": "b_cell", "origin": Vector2i(5, 5)},
		{"type": "b_cell", "origin": Vector2i(14, 5)},
		{"type": "b_cell", "origin": Vector2i(5, 14)},
		{"type": "b_cell", "origin": Vector2i(14, 14)},
		{"type": "macrophage", "origin": Vector2i(8, 8)},
		{"type": "macrophage", "origin": Vector2i(11, 8)},
	]
	for x in range(6, 14):
		for y in range(6, 14):
			if x == 6 or x == 13 or y == 6 or y == 13:
				var occupied: bool = false
				for s: Dictionary in structures:
					var origin: Vector2i = s["origin"]
					var fp: Vector2i = Vector2i(2, 2) if s["type"] == "nucleus" else Vector2i(1, 1)
					if x >= origin.x and x < origin.x + fp.x and y >= origin.y and y < origin.y + fp.y:
						occupied = true
						break
				if not occupied:
					structures.append({"type": "mucous_wall", "origin": Vector2i(x, y)})

	if ring.is_empty():
		ring = ring_cells()
	var units: Array = []
	for i in range(100):
		units.append({
			"type": "rhinovirus",
			"cell": ring[i % ring.size()]
		})

	return BattleSetup.create(structures, units, seed)
