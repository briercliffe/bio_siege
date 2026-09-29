extends GutTest

func test_structure_state_cells_and_center() -> void:
	var s := StructureState.new()
	s.id = 1
	s.type_id = "test_tower"
	s.origin = Vector2i(2, 3)
	s.footprint = Vector2i(2, 2)
	s.center = FixedMath.rect_center(s.origin, s.footprint)
	s.hp = 100
	s.max_hp = 100
	s.alive = true
	s.attack_cooldown = 0
	s.target_id = 0

	assert_eq(s.center, Vector2i(3000, 4000))

	var cells := s.cells()
	assert_eq(cells.size(), 4)
	assert_has(cells, Vector2i(2, 3))
	assert_has(cells, Vector2i(3, 3))
	assert_has(cells, Vector2i(2, 4))
	assert_has(cells, Vector2i(3, 4))

func test_structure_state_1x1_cells() -> void:
	var s := StructureState.new()
	s.origin = Vector2i(5, 5)
	s.footprint = Vector2i(1, 1)

	var cells := s.cells()
	assert_eq(cells.size(), 1)
	assert_eq(cells[0], Vector2i(5, 5))

func test_pathogen_state_attacking_id() -> void:
	var p := PathogenState.new()
	p.id = 10
	p.type_id = "rhinovirus"
	p.cell = Vector2i(0, 0)
	p.pos = FixedMath.cell_center(p.cell)
	p.hp = 50
	p.max_hp = 50
	p.alive = true
	p.state = PathogenState.State.SEEKING

	# When no blocker and no target
	assert_eq(p.attacking_id(), 0)

	# When target is set and blocker is 0 -> attacks target
	p.target_id = 1
	p.blocker_id = 0
	assert_eq(p.attacking_id(), 1)

	# When blocker is set -> attacks blocker instead of target
	p.blocker_id = 2
	assert_eq(p.attacking_id(), 2)

	# Enum values
	assert_eq(p.state, PathogenState.State.SEEKING)
	p.state = PathogenState.State.MOVING
	assert_eq(p.state, PathogenState.State.MOVING)
	p.state = PathogenState.State.ATTACKING
	assert_eq(p.state, PathogenState.State.ATTACKING)
	p.state = PathogenState.State.DEAD
	assert_eq(p.state, PathogenState.State.DEAD)

func test_projectile_state() -> void:
	var proj := ProjectileState.new()
	proj.id = 1
	proj.source_id = 10
	proj.target_id = 20
	proj.pos = Vector2i(1500, 1500)
	proj.speed = 200
	proj.damage = 15
	proj.alive = true

	assert_eq(proj.id, 1)
	assert_eq(proj.source_id, 10)
	assert_eq(proj.target_id, 20)
	assert_eq(proj.pos, Vector2i(1500, 1500))
	assert_eq(proj.speed, 200)
	assert_eq(proj.damage, 15)
	assert_true(proj.alive)

	var helper_proj := ProjectileState.create(2, 10, 20, Vector2i(500, 500), 300, 25)
	assert_eq(helper_proj.id, 2)
	assert_eq(helper_proj.speed, 300)
	assert_eq(helper_proj.damage, 25)
	assert_true(helper_proj.alive)

func test_create_factory_methods() -> void:
	var s_def := StructureDef.new()
	s_def.hp = 250
	s_def.footprint = Vector2i(2, 2)
	var s := StructureState.create(1, "b_cell", s_def, Vector2i(1, 1))
	assert_eq(s.id, 1)
	assert_eq(s.hp, 250)
	assert_eq(s.max_hp, 250)
	assert_eq(s.center, Vector2i(2000, 2000))
	assert_true(s.alive)

	var p_def := PathogenDef.new()
	p_def.hp = 80
	var p := PathogenState.create(2, "rhinovirus", p_def, Vector2i(3, 3))
	assert_eq(p.id, 2)
	assert_eq(p.hp, 80)
	assert_eq(p.max_hp, 80)
	assert_eq(p.pos, Vector2i(3500, 3500))
	assert_true(p.alive)

