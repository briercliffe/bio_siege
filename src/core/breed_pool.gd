class_name BreedPool
extends RefCounted

## A small population of genomes for one breeding type (#141). Integer maths and Rng only.
var type_id: String = ""
var generation: int = 0
var genomes: Array[Genome] = []
var fitness: Array[int] = [] # parallel to genomes; lasts one battle
## Slots per genome. They equal the config's unless the pool was widened by an upgrade (#169).
var antigen_slots: int = 0
var receptor_slots: int = 0
## The config's slot counts when the pool was made, so to_dict can leave out counts that match them.
var _base_antigen_slots: int = 0
var _base_receptor_slots: int = 0
## The most extra receptor slots a pool may carry when loaded.
const MAX_EXTRA_RECEPTORS: int = 4

static func wild_pool(p_type_id: String, cfg: GameConfig) -> BreedPool:
	var pool := BreedPool.new()
	pool.type_id = p_type_id
	pool.antigen_slots = cfg.coevo_antigen_slots
	pool.receptor_slots = cfg.coevo_receptor_slots
	pool._base_antigen_slots = pool.antigen_slots
	pool._base_receptor_slots = pool.receptor_slots
	for i: int in range(cfg.coevo_pool_size):
		pool.genomes.append(Genome.wild(cfg.coevo_antigen_slots, cfg.coevo_receptor_slots))
		pool.fitness.append(0)
	return pool

## Gives every genome `extra` more empty receptor slots (a Living Base upgrade). Never shrinks.
func widen_receptors(extra: int) -> void:
	if extra <= 0:
		return
	var target: int = receptor_slots + extra
	for g: Genome in genomes:
		while g.receptors.size() < target:
			g.receptors.append("")
	receptor_slots = target

## Damage percent (100 = x1) for attacker receptors against defender antigens.
func match_pct(attacker: Genome, defender: Genome, cfg: GameConfig) -> int:
	if attacker == null or attacker.receptor_count() == 0:
		return 100
	var matched: int = 0
	var unmatched: int = 0
	for r: String in attacker.receptors:
		if r == "":
			continue
		var binds: String = str(cfg.coevo_receptor_binds.get(r, ""))
		if binds != "" and defender != null and defender.antigens.has(binds):
			matched += 1
		else:
			unmatched += 1
	return maxi(1, 100 + matched * cfg.coevo_hit_bonus_pct - unmatched * cfg.coevo_miss_penalty_pct)

func add_fitness(index: int, amount: int) -> void:
	if index < 0 or index >= fitness.size():
		return
	fitness[index] += amount

## Adds the survival bonus once to each distinct in-range index.
func apply_survival(alive_indexes: Array[int], cfg: GameConfig) -> void:
	var seen: Dictionary = {}
	for idx: int in alive_indexes:
		if idx < 0 or idx >= fitness.size() or seen.has(idx):
			continue
		seen[idx] = true
		fitness[idx] += cfg.coevo_survival_bonus

func is_wild() -> bool:
	for g: Genome in genomes:
		if not g.is_wild():
			return false
	return true

func _pick_parent(total: int, rng: Rng) -> int:
	var roll: int = rng.next_int(total)
	var running: int = 0
	for i: int in range(fitness.size()):
		running += maxi(0, fitness[i])
		if running > roll:
			return i
	return fitness.size() - 1

## Replaces the pool with fitness-weighted offspring. Does not reseed rng.
## `receptor_bias` (receptor ids) narrows where a mutated receptor slot draws from, instead of the whole catalog:
## 0 clears the slot, otherwise the value is receptor_bias[n - 1]. Antigen slots and an empty bias behave exactly
## as before and consume the same random numbers.
func breed(rng: Rng, cfg: GameConfig, receptor_bias: Array[String] = []) -> Dictionary:
	var total: int = 0
	for f: int in fitness:
		total += maxi(0, f)
	var size: int = genomes.size()
	if total <= 0:
		return {"bred": false, "generation": generation, "top_parent": -1, "top_count": 0, "pool_size": size, "mutated": 0}
	generation += 1
	var a_slots: int = antigen_slots
	var r_slots: int = receptor_slots
	var antigen_ids: Array[String] = []
	for k: Variant in cfg.coevo_antigen_name.keys():
		antigen_ids.append(str(k))
	var receptor_ids: Array[String] = []
	for k: Variant in cfg.coevo_receptor_name.keys():
		receptor_ids.append(str(k))
	var children: Array[Genome] = []
	var credit: Array[int] = []
	credit.resize(size)
	credit.fill(0)
	var mutated: int = 0
	for c: int in range(size):
		var pa: int = _pick_parent(total, rng)
		var pb: int = _pick_parent(total, rng)
		var ga: Genome = genomes[pa]
		var gb: Genome = genomes[pb]
		var child: Genome = Genome.wild(a_slots, r_slots)
		for i: int in range(a_slots):
			child.antigens[i] = ga.antigens[i] if rng.next_int(2) == 0 else gb.antigens[i]
		for i: int in range(r_slots):
			child.receptors[i] = ga.receptors[i] if rng.next_int(2) == 0 else gb.receptors[i]
		if rng.next_int(100) < cfg.coevo_mutation_pct:
			mutated += 1
			var slot: int = rng.next_int(a_slots + r_slots)
			if slot < a_slots:
				var n: int = rng.next_int(antigen_ids.size() + 1)
				child.antigens[slot] = "" if n == 0 else antigen_ids[n - 1]
			else:
				var pick_from: Array[String] = receptor_bias if not receptor_bias.is_empty() else receptor_ids
				var n2: int = rng.next_int(pick_from.size() + 1)
				child.receptors[slot - a_slots] = "" if n2 == 0 else pick_from[n2 - 1]
		children.append(child)
		credit[pa] += 1
		if pb != pa:
			credit[pb] += 1
	genomes = children
	for i: int in range(fitness.size()):
		fitness[i] = 0
	var top_parent: int = 0
	var top_count: int = 0
	for i: int in range(size):
		if credit[i] > top_count:
			top_count = credit[i]
			top_parent = i
	return {"bred": true, "generation": generation, "top_parent": top_parent, "top_count": top_count, "pool_size": size, "mutated": mutated}

## Slot counts are written only when they differ from the config's, so default files stay as they were.
func to_dict() -> Dictionary:
	var arr: Array = []
	for g: Genome in genomes:
		arr.append(g.to_dict())
	var d: Dictionary = {"generation": generation, "genomes": arr}
	if antigen_slots != _base_antigen_slots:
		d["antigen_slots"] = antigen_slots
	if receptor_slots != _base_receptor_slots:
		d["receptor_slots"] = receptor_slots
	return d

## Rebuilds the pool's genomes with other slot counts (used when loading a widened pool).
func _resize_slots(p_antigen_slots: int, p_receptor_slots: int) -> void:
	antigen_slots = p_antigen_slots
	receptor_slots = p_receptor_slots
	for i: int in range(genomes.size()):
		genomes[i] = Genome.wild(antigen_slots, receptor_slots)

static func from_dict(d: Dictionary, p_type_id: String, cfg: GameConfig) -> BreedPool:
	var pool: BreedPool = BreedPool.wild_pool(p_type_id, cfg)
	var rs_v: Variant = d.get("receptor_slots", cfg.coevo_receptor_slots)
	var rs: int = cfg.coevo_receptor_slots
	if (typeof(rs_v) == TYPE_INT or typeof(rs_v) == TYPE_FLOAT) and is_equal_approx(float(rs_v), roundf(float(rs_v))):
		rs = clampi(int(rs_v), cfg.coevo_receptor_slots, cfg.coevo_receptor_slots + MAX_EXTRA_RECEPTORS)
	var as_v: Variant = d.get("antigen_slots", cfg.coevo_antigen_slots)
	var an_slots: int = cfg.coevo_antigen_slots
	if (typeof(as_v) == TYPE_INT or typeof(as_v) == TYPE_FLOAT) and is_equal_approx(float(as_v), roundf(float(as_v))):
		an_slots = clampi(int(as_v), cfg.coevo_antigen_slots, cfg.coevo_antigen_slots)
	if rs != pool.receptor_slots or an_slots != pool.antigen_slots:
		pool._resize_slots(an_slots, rs)
	var gen_v: Variant = d.get("generation", 0)
	if (typeof(gen_v) == TYPE_INT or typeof(gen_v) == TYPE_FLOAT) and int(gen_v) >= 0:
		pool.generation = int(gen_v)
	var list_v: Variant = d.get("genomes", [])
	if typeof(list_v) != TYPE_ARRAY:
		return pool
	var list: Array = list_v
	for i: int in range(mini(list.size(), pool.genomes.size())):
		if typeof(list[i]) != TYPE_DICTIONARY:
			continue
		var gd: Dictionary = list[i]
		var an: Variant = gd.get("antigens", [])
		var rc: Variant = gd.get("receptors", [])
		pool.genomes[i] = Genome.from_slots(an if typeof(an) == TYPE_ARRAY else [], rc if typeof(rc) == TYPE_ARRAY else [], cfg, pool.antigen_slots, pool.receptor_slots)
	return pool
