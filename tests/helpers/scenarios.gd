class_name Scenarios
extends RefCounted

## Static scenario factories returning BattleSetup for battle integration tests.
## Every setup includes the Nucleus at origin (18, 18) as the first structure.


static func ring_cells(width: int = 40, height: int = 40, depth: int = 1) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if width <= 0 or height <= 0 or depth <= 0:
		return cells
	var depth_count: int = mini(depth, (mini(width, height) + 1) / 2)
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


static func open_field(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
	]
	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "rhinovirus", "cell": Vector2i(39, 20)},
		{"type": "rhinovirus", "cell": Vector2i(20, 0)},
		{"type": "rhinovirus", "cell": Vector2i(20, 39)},
		{"type": "rhinovirus", "cell": Vector2i(0, 0)},
	]
	return BattleSetup.create(structures, units, seed)


## 1-tile wall ring around the 4x4 Nucleus: cells x 17..22 and y 17..22, minus the Nucleus cells.
static func walled_nucleus(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
	]
	for y in range(17, 23):
		for x in range(17, 23):
			if x >= 18 and x <= 21 and y >= 18 and y <= 21:
				continue
			structures.append({"type": "mucous_wall", "origin": Vector2i(x, y)})

	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
	]
	return BattleSetup.create(structures, units, seed)


static func short_wall(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
	]
	for y in range(18, 23):
		structures.append({"type": "mucous_wall", "origin": Vector2i(10, y)})

	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
	]
	return BattleSetup.create(structures, units, seed)


static func long_wall(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
	]
	for y in range(2, 38):
		structures.append({"type": "mucous_wall", "origin": Vector2i(10, y)})

	var units: Array = [
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
		{"type": "rhinovirus", "cell": Vector2i(0, 20)},
	]
	return BattleSetup.create(structures, units, seed)


static func phage_priority(seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "b_cell", "origin": Vector2i(30, 19)},
	]
	var units: Array = [
		{"type": "bacteriophage", "cell": Vector2i(0, 20)},
		{"type": "bacteriophage", "cell": Vector2i(0, 20)},
		{"type": "bacteriophage", "cell": Vector2i(0, 20)},
		{"type": "bacteriophage", "cell": Vector2i(0, 20)},
		{"type": "bacteriophage", "cell": Vector2i(0, 20)},
	]
	return BattleSetup.create(structures, units, seed)


## Unit indices were authored for a 76-cell ring (20x20, one row). They are scaled by the ring
## size so the units stay spread around the whole perimeter on larger deploy bands.
static func _ring_at(r: Array[Vector2i], authored_index: int) -> Vector2i:
	return r[(authored_index * r.size()) / 76]


static func mixed(ring: Array[Vector2i] = [], seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
	]
	for y in range(14, 26):
		structures.append({"type": "mucous_wall", "origin": Vector2i(14, y)})
	for y in range(14, 26):
		structures.append({"type": "mucous_wall", "origin": Vector2i(24, y)})

	structures.append({"type": "macrophage", "origin": Vector2i(16, 10)})
	structures.append({"type": "macrophage", "origin": Vector2i(22, 26)})
	structures.append({"type": "b_cell", "origin": Vector2i(10, 19)})
	structures.append({"type": "b_cell", "origin": Vector2i(27, 19)})

	var r: Array[Vector2i] = ring
	if r.is_empty():
		r = ring_cells()

	var units: Array = []
	for i in range(20):
		units.append({"type": "rhinovirus", "cell": _ring_at(r, i * 3)})

	var phage_indices: Array[int] = [1, 16, 31, 46, 61]
	for idx in phage_indices:
		units.append({"type": "bacteriophage", "cell": _ring_at(r, idx)})

	var staph_indices: Array[int] = [5, 43]
	for idx in staph_indices:
		units.append({"type": "staphylococcus", "cell": _ring_at(r, idx)})

	return BattleSetup.create(structures, units, seed)


## Reference scenario for "repeating one strain gets punished": Nucleus, two B-Cells and a
## Macrophage inside the base, 20 Rhinoviruses spread evenly around the ring.
## The B-Cells flank the Nucleus and the Macrophage sits in a far corner, so the B-Cells
## live long enough to finish analysis. All cells are inside the base on the 40x40 grid.
static func repeat_swarm(ring: Array[Vector2i] = [], seed: int = 1) -> BattleSetup:
	var structures: Array = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "b_cell", "origin": Vector2i(14, 18)},
		{"type": "b_cell", "origin": Vector2i(24, 20)},
		{"type": "macrophage", "origin": Vector2i(4, 4)},
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
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "b_cell", "origin": Vector2i(8, 8)},
		{"type": "b_cell", "origin": Vector2i(28, 8)},
		{"type": "b_cell", "origin": Vector2i(8, 28)},
		{"type": "b_cell", "origin": Vector2i(28, 28)},
		{"type": "macrophage", "origin": Vector2i(14, 14)},
		{"type": "macrophage", "origin": Vector2i(23, 14)},
	]
	for x in range(12, 28):
		for y in range(12, 28):
			if x == 12 or x == 27 or y == 12 or y == 27:
				var occupied: bool = false
				for s: Dictionary in structures:
					var origin: Vector2i = s["origin"]
					var fp: Vector2i = Vector2i(1, 1)
					if s["type"] == "nucleus":
						fp = Vector2i(4, 4)
					elif s["type"] == "b_cell" or s["type"] == "macrophage":
						fp = Vector2i(3, 3)
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
