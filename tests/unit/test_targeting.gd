extends GutTest

var _cfg: GameConfig = null

func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "GameConfig should load successfully from res://data")
	_cfg = res.config

# 1. Nearest wins (Rhinovirus targets B-Cell 2 over Nucleus 1)
func test_nearest_wins_rhinovirus() -> void:
	var nucleus := StructureState.create(1, "nucleus", _cfg.structures["nucleus"], Vector2i(9, 9))
	var b_cell := StructureState.create(2, "b_cell", _cfg.structures["b_cell"], Vector2i(2, 2))
	var rhino := PathogenState.create(10, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))

	# Rhino at (0, 0), pos (500, 500)
	# B-cell at (2, 2), center (2500, 2500), dist_sq = 8,000,000
	# Nucleus at (9, 9), center (10000, 10000), dist_sq = 180,500,000
	var target_id := Targeting.pick_structure_target(rhino, [nucleus, b_cell])
	assert_eq(target_id, 2, "Rhinovirus should pick nearest structure (B-Cell 2) over Nucleus 1")

	# Order independence
	var reverse_id := Targeting.pick_structure_target(rhino, [b_cell, nucleus])
	assert_eq(reverse_id, 2, "Result should be independent of array order")

# 2. Walls ignored (walls closer than Nucleus, targets Nucleus)
func test_walls_ignored() -> void:
	var nucleus := StructureState.create(1, "nucleus", _cfg.structures["nucleus"], Vector2i(9, 9))
	var wall := StructureState.create(2, "mucous_wall", _cfg.structures["mucous_wall"], Vector2i(1, 1))
	var rhino := PathogenState.create(10, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))

	# Wall is at (1, 1) right next to rhino, but wall.def.is_targetable == false
	var target_id := Targeting.pick_structure_target(rhino, [wall, nucleus])
	assert_eq(target_id, 1, "Mucous Wall should be ignored; Nucleus 1 should be targeted")

# 3. Priority tag (Bacteriophage targets B-Cell over nearer Nucleus)
func test_priority_tag_bacteriophage() -> void:
	var nucleus := StructureState.create(1, "nucleus", _cfg.structures["nucleus"], Vector2i(2, 2))
	var b_cell := StructureState.create(2, "b_cell", _cfg.structures["b_cell"], Vector2i(10, 10))
	var phage := PathogenState.create(10, "bacteriophage", _cfg.pathogens["bacteriophage"], Vector2i(1, 1))

	# Nucleus at (2, 2) is closer to (1, 1) than B-cell at (10, 10),
	# but bacteriophage has priority tag 'defense'.
	var target_id := Targeting.pick_structure_target(phage, [nucleus, b_cell])
	assert_eq(target_id, 2, "Bacteriophage should target defense (B-Cell 2) over nearer Nucleus 1")

# 4. Nearest within priority (Bacteriophage with B-Cell and Macrophage targets nearer)
func test_nearest_within_priority() -> void:
	var nucleus := StructureState.create(1, "nucleus", _cfg.structures["nucleus"], Vector2i(9, 9))
	var macro := StructureState.create(3, "macrophage", _cfg.structures["macrophage"], Vector2i(3, 3))
	var b_cell := StructureState.create(2, "b_cell", _cfg.structures["b_cell"], Vector2i(7, 7))
	var phage := PathogenState.create(10, "bacteriophage", _cfg.pathogens["bacteriophage"], Vector2i(0, 0))

	# Both macrophage (id 3) and b_cell (id 2) have tag 'defense'.
	# Macrophage at (3, 3) is closer than B-cell at (7, 7).
	var target_id := Targeting.pick_structure_target(phage, [nucleus, b_cell, macro])
	assert_eq(target_id, 3, "Bacteriophage should pick nearest priority target (Macrophage 3)")

# 5. Fallback (Bacteriophage with dead B-Cell targets Nucleus)
func test_fallback_when_priority_dead() -> void:
	var nucleus := StructureState.create(1, "nucleus", _cfg.structures["nucleus"], Vector2i(9, 9))
	var b_cell := StructureState.create(2, "b_cell", _cfg.structures["b_cell"], Vector2i(2, 2))
	b_cell.alive = false
	var phage := PathogenState.create(10, "bacteriophage", _cfg.pathogens["bacteriophage"], Vector2i(0, 0))

	# B-cell is dead, so priority set is empty; falls back to Nucleus
	var target_id := Targeting.pick_structure_target(phage, [b_cell, nucleus])
	assert_eq(target_id, 1, "Bacteriophage should fallback to Nucleus 1 when defense targets are dead")

# 6. Tie (lowest id wins)
func test_tie_lowest_id_wins() -> void:
	var s_high := StructureState.create(5, "b_cell", _cfg.structures["b_cell"], Vector2i(4, 0))
	var s_low := StructureState.create(3, "b_cell", _cfg.structures["b_cell"], Vector2i(0, 4))
	var rhino := PathogenState.create(10, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))

	# Both are at dist_sq = 16,000,000 from rhino pos (500, 500)
	assert_eq(Targeting.pick_structure_target(rhino, [s_high, s_low]), 3, "Tie breaker should pick lowest id (3)")
	assert_eq(Targeting.pick_structure_target(rhino, [s_low, s_high]), 3, "Tie breaker should be order independent")

# 7. goal_cell_for with Nucleus (0,10) -> (9,10); (10,0) -> (10,9); tie at (10000, 500) -> (9,9)
func test_goal_cell_for_nucleus() -> void:
	var nucleus := StructureState.create(1, "nucleus", _cfg.structures["nucleus"], Vector2i(9, 9))

	# Unit at (0, 10)
	var u1 := PathogenState.create(1, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 10))
	assert_eq(Targeting.goal_cell_for(u1, nucleus), Vector2i(9, 10))

	# Unit at (10, 0)
	var u2 := PathogenState.create(2, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(10, 0))
	assert_eq(Targeting.goal_cell_for(u2, nucleus), Vector2i(10, 9))

	# Unit at pos (10000, 500) equidistant from (9, 9) and (10, 9); tie goes to lowest y then lowest x
	var u3 := PathogenState.create(3, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	u3.pos = Vector2i(10000, 500)
	assert_eq(Targeting.goal_cell_for(u3, nucleus), Vector2i(9, 9))

# 8. Tower range: B-Cell (range 12000) targets in-range, lower id on tie
func test_tower_range_b_cell() -> void:
	var b_cell := StructureState.create(1, "b_cell", _cfg.structures["b_cell"], Vector2i(5, 5))
	# 3x3 tower center is (6500, 6500), attack_range_mt = 12000

	var p_out := PathogenState.create(10, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	p_out.pos = Vector2i(6500, 19500) # dist 13000 > 12000

	var p_in := PathogenState.create(20, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	p_in.pos = Vector2i(6500, 14500) # dist 8000 <= 12000

	assert_eq(Targeting.pick_unit_target(b_cell, [p_out, p_in]), 20, "B-Cell should target in-range unit (20)")

	# Tie: two units in range at same distance (6000)
	var p_tie_a := PathogenState.create(30, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	p_tie_a.pos = Vector2i(12500, 6500)

	var p_tie_b := PathogenState.create(15, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	p_tie_b.pos = Vector2i(6500, 12500)

	assert_eq(Targeting.pick_unit_target(b_cell, [p_tie_a, p_tie_b]), 15, "Tie goes to lowest unit id (15)")
	assert_eq(Targeting.pick_unit_target(b_cell, [p_tie_b, p_tie_a]), 15, "Tie result is order independent")

# 9. tower_keeps_target: out of range or dead returns false
func test_tower_keeps_target() -> void:
	var b_cell := StructureState.create(1, "b_cell", _cfg.structures["b_cell"], Vector2i(5, 5))
	var target := PathogenState.create(10, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	target.pos = Vector2i(6500, 12500) # dist 6000 <= 12000

	# Alive and in range -> true
	assert_true(Targeting.tower_keeps_target(b_cell, target))

	# Moves out of range -> false
	target.pos = Vector2i(6500, 19500) # dist 13000 > 12000
	assert_false(Targeting.tower_keeps_target(b_cell, target), "Out of range should return false")

	# In range but dead -> false
	target.pos = Vector2i(6500, 12500)
	target.alive = false
	assert_false(Targeting.tower_keeps_target(b_cell, target), "Dead target should return false")

	# Target null -> false
	assert_false(Targeting.tower_keeps_target(b_cell, null), "Null target should return false")

	# Tower dead -> false
	target.alive = true
	b_cell.alive = false
	assert_false(Targeting.tower_keeps_target(b_cell, target), "Dead tower should return false")

# 10. Macrophage range (4000) ignores a unit at 5000 mt
func test_macrophage_range_ignores_distant_unit() -> void:
	var macro := StructureState.create(1, "macrophage", _cfg.structures["macrophage"], Vector2i(5, 5))
	# 3x3 center is (6500, 6500), attack_range_mt = 4000

	var p_2500 := PathogenState.create(1, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	p_2500.pos = Vector2i(11500, 6500) # dist 5000 > 4000
	assert_eq(Targeting.pick_unit_target(macro, [p_2500]), 0, "Macrophage should ignore unit at 5000 mt")

	var p_2000 := PathogenState.create(2, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	p_2000.pos = Vector2i(10500, 6500) # dist 4000 <= 4000
	assert_eq(Targeting.pick_unit_target(macro, [p_2000]), 2, "Macrophage should target unit at 4000 mt")

# Edge cases
func test_edge_cases() -> void:
	var b_cell := StructureState.create(1, "b_cell", _cfg.structures["b_cell"], Vector2i(5, 5))
	var rhino := PathogenState.create(1, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))

	# Empty candidate lists
	assert_eq(Targeting.pick_structure_target(rhino, []), 0)
	assert_eq(Targeting.pick_unit_target(b_cell, []), 0)

	# Null safety
	assert_eq(Targeting.pick_structure_target(null, []), 0)
	assert_eq(Targeting.goal_cell_for(null, null), Vector2i.ZERO)
	assert_eq(Targeting.pick_unit_target(null, []), 0)
	assert_false(Targeting.tower_keeps_target(null, null))

	# Structure without attack (e.g. wall)
	var wall := StructureState.create(2, "mucous_wall", _cfg.structures["mucous_wall"], Vector2i(5, 5))
	assert_eq(Targeting.pick_unit_target(wall, [rhino]), 0, "Structure without attack cannot target")

# Phase 2 (#155): Rhinovirus goes for resource structures first.
func test_rhinovirus_prefers_far_mitochondria() -> void:
	var mito := StructureState.create(2, "mitochondria", _cfg.structures["mitochondria"], Vector2i(30, 30))
	var macro := StructureState.create(3, "macrophage", _cfg.structures["macrophage"], Vector2i(3, 3))
	var rhino := PathogenState.create(10, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	assert_eq(Targeting.pick_structure_target(rhino, [macro, mito]), 2)

func test_rhinovirus_without_resource_picks_nearest() -> void:
	var nucleus := StructureState.create(1, "nucleus", _cfg.structures["nucleus"], Vector2i(30, 30))
	var macro := StructureState.create(3, "macrophage", _cfg.structures["macrophage"], Vector2i(3, 3))
	var rhino := PathogenState.create(10, "rhinovirus", _cfg.pathogens["rhinovirus"], Vector2i(0, 0))
	assert_eq(Targeting.pick_structure_target(rhino, [nucleus, macro]), 3)
