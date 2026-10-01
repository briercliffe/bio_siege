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


# --- receptor bias (#167) ---

func test_a_receptor_bias_narrows_mutated_receptors() -> void:
	cfg.coevo_mutation_pct = 100
	var bias: Array[String] = ["binder_a"]
	var got_binder: bool = false
	for seed: int in range(1, 9):
		var p: BreedPool = _pool()
		p.fitness[0] = 1
		p.breed(Rng.new(seed), cfg, bias)
		for g: Genome in p.genomes:
			for r: String in g.receptors:
				assert_true(r == "" or r == "binder_a", "receptor %s is binder_a or empty" % r)
			got_binder = got_binder or g.receptors.has("binder_a")
	assert_true(got_binder, "some mutation picks the biased receptor")


func test_an_empty_bias_matches_ce01_exactly() -> void:
	cfg.coevo_mutation_pct = 100
	var a: BreedPool = _two_parent_pool(100)
	var b: BreedPool = _two_parent_pool(100)
	var rng_a := Rng.new(7)
	var rng_b := Rng.new(7)
	a.breed(rng_a, cfg)
	b.breed(rng_b, cfg, [] as Array[String])
	assert_eq(a.to_dict(), b.to_dict())
	assert_eq(rng_a.randi(), rng_b.randi(), "the same random numbers were used")


func test_a_bias_uses_as_many_random_numbers_as_none() -> void:
	cfg.coevo_mutation_pct = 100
	var a: BreedPool = _two_parent_pool(100)
	var b: BreedPool = _two_parent_pool(100)
	var rng_a := Rng.new(7)
	var rng_b := Rng.new(7)
	a.breed(rng_a, cfg)
	b.breed(rng_b, cfg, ["binder_a", "clamp_a"] as Array[String])
	assert_eq(rng_a.randi(), rng_b.randi())
	# Antigen slots are not biased.
	for i: int in range(a.genomes.size()):
		assert_eq(a.genomes[i].antigens, b.genomes[i].antigens)


# --- receptor slots (#169) ---

func test_widen_receptors_adds_an_empty_slot_and_keeps_alleles() -> void:
	var p: BreedPool = _two_parent_pool(0)
	assert_eq(p.receptor_slots, 2)
	p.widen_receptors(1)
	assert_eq(p.receptor_slots, 3)
	assert_eq(p.genomes[0].receptors, ["binder_a", "binder_b", ""] as Array[String])
	assert_eq(p.genomes[1].receptors, ["clamp_a", "clamp_b", ""] as Array[String])
	p.widen_receptors(0)
	p.widen_receptors(-2)
	assert_eq(p.receptor_slots, 3, "it never shrinks")


func test_a_default_breed_is_ce01_exactly() -> void:
	var a: BreedPool = _two_parent_pool(50)
	var b: BreedPool = _two_parent_pool(50)
	b.widen_receptors(0)
	var rng_a := Rng.new(99)
	var rng_b := Rng.new(99)
	a.breed(rng_a, cfg)
	b.breed(rng_b, cfg)
	assert_eq(a.to_dict(), b.to_dict())
	assert_eq(rng_a.randi(), rng_b.randi())


func test_a_widened_pool_breeds_three_receptors_and_may_fill_the_third() -> void:
	cfg.coevo_mutation_pct = 100
	var filled_third: bool = false
	for seed: int in range(1, 30):
		var p: BreedPool = _pool()
		p.widen_receptors(1)
		p.fitness[0] = 1
		p.breed(Rng.new(seed), cfg)
		for g: Genome in p.genomes:
			assert_eq(g.receptors.size(), 3)
			assert_eq(g.antigens.size(), 2)
			filled_third = filled_third or g.receptors[2] != ""
	assert_true(filled_third, "a mutation can land in the third receptor slot")


func test_to_dict_omits_default_slot_counts() -> void:
	var p: BreedPool = _two_parent_pool(0)
	assert_false(p.to_dict().has("receptor_slots"))
	assert_false(p.to_dict().has("antigen_slots"))
	p.widen_receptors(1)
	assert_eq(p.to_dict()["receptor_slots"], 3)


func test_a_widened_pool_round_trips_through_json() -> void:
	var p: BreedPool = _two_parent_pool(0)
	p.widen_receptors(1)
	p.genomes[2] = Genome.from_slots(["wall_a", ""], ["hook_a", "", "latch_b"], cfg, 2, 3)
	p.generation = 4
	var json: Variant = JSON.parse_string(JSON.stringify(p.to_dict()))
	var q: BreedPool = BreedPool.from_dict(json, "rhinovirus", cfg)
	assert_eq(q.receptor_slots, 3)
	assert_eq(q.generation, 4)
	assert_eq(q.genomes[2].receptors, ["hook_a", "", "latch_b"] as Array[String])
	assert_eq(q.to_dict(), p.to_dict())
	# And through a setup's populations and the sim.
	var setup := BattleSetup.create([{"type": "nucleus", "origin": Vector2i(18, 18)}], [], 1, {}, {"rhinovirus": p.to_dict()})
	assert_eq(setup.validate(_load_coevo_cfg()).size(), 0)


func _load_coevo_cfg() -> GameConfig:
	cfg.feature_flags["coevolution"] = true
	return cfg


func test_loading_clamps_receptor_slots() -> void:
	var too_many: BreedPool = BreedPool.from_dict({"receptor_slots": 99, "genomes": []}, "rhinovirus", cfg)
	assert_eq(too_many.receptor_slots, cfg.coevo_receptor_slots + 4)
	var too_few: BreedPool = BreedPool.from_dict({"receptor_slots": 0, "genomes": []}, "rhinovirus", cfg)
	assert_eq(too_few.receptor_slots, cfg.coevo_receptor_slots)
	var junk: BreedPool = BreedPool.from_dict({"receptor_slots": "x", "genomes": []}, "rhinovirus", cfg)
	assert_eq(junk.receptor_slots, cfg.coevo_receptor_slots)


func test_match_counts_only_filled_receptors_whatever_the_slot_count() -> void:
	var p: BreedPool = _pool()
	p.widen_receptors(2)
	var wide: Genome = Genome.from_slots([], ["binder_a", "", "", ""], cfg, 2, 4)
	var narrow: Genome = _g([], ["binder_a", ""] as Array)
	var target: Genome = _g(["capsule_a", ""], [])
	assert_eq(p.match_pct(wide, target, cfg), p.match_pct(narrow, target, cfg))
	assert_eq(p.match_pct(wide, target, cfg), 125)
	var empty_wide: Genome = Genome.wild(2, 4)
	assert_eq(p.match_pct(empty_wide, target, cfg), 100)
