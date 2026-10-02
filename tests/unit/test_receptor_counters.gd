extends GutTest

## The sim counts receptor hits and checks for the anti-cheat telemetry. They are not part of state_hash().


func _cfg(coevolution: bool) -> GameConfig:
	return GameConfig.load_from_dir("res://data", {"coevolution": coevolution}).config


## A defended base whose macrophages carry a binder, against pathogens that show the antigen it binds.
func _setup(cfg: GameConfig) -> BattleSetup:
	var grid := GridModel.new(cfg)
	grid.load_layout([{"type": "nucleus", "origin": [18, 18]}, {"type": "macrophage", "origin": [14, 10]},
			{"type": "macrophage", "origin": [24, 10]}], LivingBaseProfile.unlimited_wallet())
	var populations: Dictionary = {}
	if cfg.coevolution_enabled():
		var tower: BreedPool = BreedPool.wild_pool("macrophage", cfg)
		for g: Genome in tower.genomes:
			g.receptors[0] = "binder_a"
		var germ: BreedPool = BreedPool.wild_pool("rhinovirus", cfg)
		for i: int in range(germ.genomes.size()):
			germ.genomes[i].antigens[0] = "capsule_a" if i % 2 == 0 else "spike_a"
		populations["macrophage"] = tower.to_dict()
		populations["rhinovirus"] = germ.to_dict()
	var ring: Array[Vector2i] = grid.ring_cells()
	var units: Array = []
	for i: int in range(10):
		units.append({"type": "rhinovirus", "cell": ring[i * 6], "strain": "wild"})
	return BattleSetup.create(grid.to_layout(), units, 321, {}, populations)


func test_counters_increase_with_coevolution_on() -> void:
	var cfg: GameConfig = _cfg(true)
	var sim := BattleSim.new(cfg, _setup(cfg))
	sim.run_to_end()
	assert_gt(sim.receptor_checks, 0)
	assert_gt(sim.receptor_hits, 0, "binder_a binds capsule_a")
	assert_lte(sim.receptor_hits, sim.receptor_checks)


func test_counters_stay_zero_with_coevolution_off() -> void:
	var cfg: GameConfig = _cfg(false)
	var sim := BattleSim.new(cfg, _setup(cfg))
	sim.run_to_end()
	assert_eq(sim.receptor_checks, 0)
	assert_eq(sim.receptor_hits, 0)


func test_the_counters_are_not_part_of_the_hash() -> void:
	var cfg: GameConfig = _cfg(true)
	var plain := BattleSim.new(cfg, _setup(cfg))
	plain.run_to_end()
	var bumped := BattleSim.new(cfg, _setup(cfg))
	bumped.receptor_hits = 12345
	bumped.receptor_checks = 99999
	bumped.run_to_end()
	assert_eq(bumped.state_hash(), plain.state_hash())


func test_match_counts_agree_with_match_pct() -> void:
	var cfg: GameConfig = _cfg(true)
	var pool: BreedPool = BreedPool.wild_pool("macrophage", cfg)
	var attacker: Genome = Genome.wild(cfg.coevo_antigen_slots, cfg.coevo_receptor_slots)
	attacker.receptors[0] = "binder_a"
	attacker.receptors[1] = "binder_b"
	var defender: Genome = Genome.wild(cfg.coevo_antigen_slots, cfg.coevo_receptor_slots)
	defender.antigens[0] = "capsule_a"
	var counts: Vector2i = pool.match_counts(attacker, defender, cfg)
	assert_eq(counts, Vector2i(1, 1))
	assert_eq(pool.match_pct(attacker, defender, cfg), maxi(1, 100 + cfg.coevo_hit_bonus_pct - cfg.coevo_miss_penalty_pct))
	assert_eq(pool.match_counts(null, defender, cfg), Vector2i.ZERO)
	assert_eq(pool.match_pct(Genome.wild(2, 2), defender, cfg), 100)
