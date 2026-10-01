extends GutTest

var cfg: GameConfig = null

func before_each() -> void:
	cfg = GameConfig.load_from_dir("res://data").config

func _g(antigens: Array, receptors: Array) -> Genome:
	return Genome.from_slots(antigens, receptors, cfg)

func _pool() -> BreedPool:
	return BreedPool.wild_pool("rhinovirus", cfg)

func _two_parent_pool(mutation_pct: int) -> BreedPool:
	cfg.coevo_mutation_pct = mutation_pct
	var p: BreedPool = _pool()
	p.genomes[0] = _g(["capsule_a", "capsule_b"], ["binder_a", "binder_b"])
	p.genomes[1] = _g(["spike_a", "spike_b"], ["clamp_a", "clamp_b"])
	p.fitness[0] = 1
	p.fitness[1] = 1
	return p

# --- match_pct ---

func test_match_table() -> void:
	var p: BreedPool = _pool()
	assert_eq(p.match_pct(_g([], []), _g(["capsule_a"], []), cfg), 100)
	assert_eq(p.match_pct(_g([], ["binder_a", ""]), _g(["capsule_a", ""], []), cfg), 125)
	assert_eq(p.match_pct(_g([], ["binder_a", "binder_b"]), _g(["capsule_a", "capsule_b"], []), cfg), 150)
	assert_eq(p.match_pct(_g([], ["binder_a", "binder_b"]), _g(["", ""], []), cfg), 50)
	assert_eq(p.match_pct(_g([], ["binder_a", "clamp_a"]), _g(["capsule_a", ""], []), cfg), 100)

func test_match_null_attacker_is_100() -> void:
	assert_eq(_pool().match_pct(null, _g(["capsule_a"], []), cfg), 100)

func test_match_never_below_one() -> void:
	cfg.coevo_hit_bonus_pct = 0
	cfg.coevo_miss_penalty_pct = 100
	assert_eq(_pool().match_pct(_g([], ["binder_a", "binder_b"]), _g([], []), cfg), 1)

func test_two_receptors_same_antigen_both_match() -> void:
	cfg.coevo_receptor_binds["clamp_a"] = "capsule_a"
	assert_eq(_pool().match_pct(_g([], ["binder_a", "clamp_a"]), _g(["capsule_a", ""], []), cfg), 150)

# --- fitness ---

func test_apply_survival_once_per_index() -> void:
	var p: BreedPool = _pool()
	var alive: Array[int] = [2, 2, -1, 99]
	p.apply_survival(alive, cfg)
	assert_eq(p.fitness[2], cfg.coevo_survival_bonus)
	var total: int = 0
	for f: int in p.fitness:
		total += f
	assert_eq(total, cfg.coevo_survival_bonus)

# --- breed ---

func test_breed_only_fit_parent() -> void:
	cfg.coevo_mutation_pct = 0
	var p: BreedPool = _pool()
	p.genomes[2] = _g(["capsule_a", "spike_a"], ["binder_a", "clamp_a"])
	p.fitness[2] = 10
	var res: Dictionary = p.breed(Rng.new(7), cfg)
	assert_true(res["bred"])
	assert_eq(res["top_parent"], 2)
	assert_eq(res["top_count"], cfg.coevo_pool_size)
	assert_eq(res["mutated"], 0)
	assert_eq(p.generation, 1)
	for g: Genome in p.genomes:
		assert_eq(g.to_dict(), {"antigens": ["capsule_a", "spike_a"], "receptors": ["binder_a", "clamp_a"]})
	for f: int in p.fitness:
		assert_eq(f, 0)

func test_breed_all_zero_fitness_noop() -> void:
	var p: BreedPool = _pool()
	p.genomes[0] = _g(["capsule_a"], [])
	var before: Dictionary = p.to_dict()
	var res: Dictionary = p.breed(Rng.new(1), cfg)
	assert_false(res["bred"])
	assert_eq(res["top_parent"], -1)
	assert_eq(res["top_count"], 0)
	assert_eq(p.generation, 0)
	assert_eq(p.to_dict(), before)

func test_crossover_copies_parent_a_or_b() -> void:
	# Seed 3: child 0 copies every slot from genome 0. Seed 4: every slot from genome 1.
	var p: BreedPool = _two_parent_pool(0)
	p.breed(Rng.new(3), cfg)
	assert_eq(p.genomes[0].to_dict(), {"antigens": ["capsule_a", "capsule_b"], "receptors": ["binder_a", "binder_b"]})
	p = _two_parent_pool(0)
	p.breed(Rng.new(4), cfg)
	assert_eq(p.genomes[0].to_dict(), {"antigens": ["spike_a", "spike_b"], "receptors": ["clamp_a", "clamp_b"]})

func test_mutation_fills_slot() -> void:
	# Seed 22 with wild parents: child 0 gains binder_a in receptor slot 0.
	cfg.coevo_mutation_pct = 100
	var p: BreedPool = _pool()
	p.fitness[0] = 1
	var res: Dictionary = p.breed(Rng.new(22), cfg)
	assert_eq(res["mutated"], cfg.coevo_pool_size)
	assert_eq(p.genomes[0].to_dict(), {"antigens": ["", ""], "receptors": ["binder_a", ""]})

func test_mutation_clears_slot() -> void:
	# Seed 2 with two full identical parents: child 0 has receptor slot 0 cleared (catalog roll 0).
	cfg.coevo_mutation_pct = 100
	var p: BreedPool = _pool()
	var full: Genome = _g(["capsule_a", "capsule_b"], ["binder_a", "binder_b"])
	p.genomes[0] = full
	p.genomes[1] = full.duplicate_genome()
	p.fitness[0] = 1
	p.fitness[1] = 1
	p.breed(Rng.new(2), cfg)
	assert_eq(p.genomes[0].to_dict(), {"antigens": ["capsule_a", "capsule_b"], "receptors": ["", "binder_b"]})

func test_breed_is_deterministic() -> void:
	var a: BreedPool = _two_parent_pool(50)
	var b: BreedPool = _two_parent_pool(50)
	a.breed(Rng.new(99), cfg)
	b.breed(Rng.new(99), cfg)
	assert_eq(a.to_dict(), b.to_dict())

# --- serialisation ---

func test_round_trip() -> void:
	var p: BreedPool = _two_parent_pool(0)
	p.generation = 4
	var q: BreedPool = BreedPool.from_dict(p.to_dict(), "rhinovirus", cfg)
	assert_eq(q.to_dict(), p.to_dict())
	assert_eq(q.fitness, [0, 0, 0, 0, 0, 0, 0, 0] as Array[int])

func test_from_dict_sanitises() -> void:
	var d: Dictionary = {
		"generation": 2.0,
		"genomes": [{"antigens": ["bogus", "capsule_a", "spike_a"], "receptors": [7, "binder_a"]}],
	}
	var q: BreedPool = BreedPool.from_dict(d, "rhinovirus", cfg)
	assert_eq(q.generation, 2)
	assert_eq(q.genomes.size(), cfg.coevo_pool_size)
	assert_eq(q.genomes[0].to_dict(), {"antigens": ["", "capsule_a"], "receptors": ["", "binder_a"]})
	assert_true(q.genomes[1].is_wild())
	var long_list: Array = []
	for i: int in range(cfg.coevo_pool_size + 5):
		long_list.append({"antigens": ["capsule_a"], "receptors": []})
	var r: BreedPool = BreedPool.from_dict({"genomes": long_list}, "rhinovirus", cfg)
	assert_eq(r.genomes.size(), cfg.coevo_pool_size)
	assert_eq(r.generation, 0)

func test_wild_pool_is_wild() -> void:
	var p: BreedPool = _pool()
	assert_true(p.is_wild())
	assert_eq(p.genomes.size(), 8)
	p.genomes[3] = _g(["coat_a"], [])
	assert_false(p.is_wild())
