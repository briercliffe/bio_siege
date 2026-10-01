extends GutTest

## Session attack target (#157): raid a base that is not the session's own.

const MAC_ORIGIN: Vector2i = Vector2i(5, 5)


func _cfg() -> GameConfig:
	return GameConfig.load_from_dir("res://data").config


func _other_layout() -> Array[Dictionary]:
	var layout: Array[Dictionary] = [
		{"type": "nucleus", "origin": Vector2i(18, 18)},
		{"type": "macrophage", "origin": MAC_ORIGIN},
	]
	return layout


func test_lab_default_resolves_to_own_base_and_memory() -> void:
	var session := Session.new(_cfg())
	assert_eq(session.mode, Session.Mode.LAB)
	assert_false(session.has_attack_target())
	assert_same(session.attack_grid(), session.grid)
	assert_same(session.defender_memory(), session.memory)


func test_attack_layout_builds_a_separate_grid() -> void:
	var session := Session.new(_cfg())
	var own_before: Array[Dictionary] = session.grid.to_layout()
	session.attack_layout = _other_layout()
	assert_true(session.has_attack_target())
	var g: GridModel = session.attack_grid()
	assert_not_same(g, session.grid)
	assert_eq(g.structures().size(), 2)
	assert_true(g.structure_id_at(MAC_ORIGIN) > 0)
	assert_eq(session.grid.to_layout(), own_before)
	assert_same(session.attack_grid(), g, "the grid is cached")


func test_new_attack_layout_rebuilds_the_grid() -> void:
	var session := Session.new(_cfg())
	session.attack_layout = _other_layout()
	var first: GridModel = session.attack_grid()
	var second_layout: Array[Dictionary] = [{"type": "nucleus", "origin": Vector2i(18, 18)}]
	session.attack_layout = second_layout
	assert_not_same(session.attack_grid(), first)
	assert_eq(session.attack_grid().structures().size(), 1)


func test_defender_memory_prefers_attack_memory() -> void:
	var session := Session.new(_cfg())
	var other := ImmuneMemory.new()
	session.attack_memory = other
	assert_same(session.defender_memory(), other)


func test_clear_attack_target_restores_self_raid() -> void:
	var session := Session.new(_cfg())
	session.attack_layout = _other_layout()
	session.attack_memory = ImmuneMemory.new()
	session.attack_populations = {"macrophage": null}
	session.attack_opponent_id = "ai-1"
	session.attack_grid()
	session.clear_attack_target()
	assert_false(session.has_attack_target())
	assert_same(session.attack_grid(), session.grid)
	assert_same(session.defender_memory(), session.memory)
	assert_true(session.attack_populations.is_empty())
	assert_eq(session.attack_opponent_id, "")


func test_pool_for_splits_by_owner() -> void:
	var cfg: GameConfig = _cfg()
	cfg.feature_flags["coevolution"] = true
	var session := Session.new(cfg)
	var mine: BreedPool = BreedPool.wild_pool("macrophage", cfg)
	mine.generation = 3
	session.populations["macrophage"] = mine
	assert_same(session.pool_for("macrophage"), mine, "self raid: own pools")
	session.attack_layout = _other_layout()
	assert_ne(session.pool_for("macrophage"), mine)
	assert_eq(session.pool_for("macrophage").generation, 0, "defender pool is wild until stored")
	var theirs: BreedPool = BreedPool.wild_pool("macrophage", cfg)
	theirs.generation = 7
	session.store_pool("macrophage", theirs)
	assert_same(session.pool_for("macrophage"), theirs)
	assert_same(session.populations["macrophage"], mine)
	# Pathogen pools always belong to the attacker.
	var rhino: BreedPool = BreedPool.wild_pool("rhinovirus", cfg)
	session.store_pool("rhinovirus", rhino)
	assert_same(session.populations["rhinovirus"], rhino)
	assert_false(session.attack_populations.has("rhinovirus"))


func test_coevolution_split_after_a_raid_on_another_base() -> void:
	var cfg: GameConfig = _cfg()
	cfg.feature_flags["coevolution"] = true
	var session := Session.new(cfg)
	session.attack_layout = _other_layout()
	var pops: Dictionary = {}
	for type_id: String in cfg.coevo_types:
		pops[type_id] = session.pool_for(type_id).to_dict()
	var setup: BattleSetup = BattleSetup.create(
		session.attack_grid().to_layout(),
		[{"type": "rhinovirus", "cell": Vector2i(5, 8)}],
		1, {}, pops)
	var sim := BattleSim.new(cfg, setup)
	var p: PathogenState = sim.pathogen(1)
	p.hp = 100000
	sim.damage_pathogen(p, 10, 1)
	sim._pathogen_attack(p, sim.structure(1))
	session.battle_setup = setup
	InfectionPhase.breed_after_raid(session, sim)
	assert_eq((session.attack_populations["macrophage"] as BreedPool).generation, 1)
	assert_false(session.populations.has("macrophage"), "the defender pool does not land in the attacker's pools")
	assert_eq((session.populations["rhinovirus"] as BreedPool).generation, 1)
	assert_false(session.attack_populations.has("rhinovirus"))
