class_name PoolAudit
extends RefCounted

## Breeding integrity (AM-11, plan section 12: "the server breeds, not the client"). A genome pool is checked before
## it is used in a raid: the right number of genomes with the right slot counts, only known alleles, and a
## generation the owner could really have reached. A pool that fails is reset to wild. Pure: no network or Time.

const BAD_POOL: String = "bad_pool"
const WRONG_LENGTH: String = "wrong_length"
const UNKNOWN_ALLELE: String = "unknown_allele"
const BAD_GENERATION: String = "bad_generation"
const UNKNOWN_TYPE: String = "unknown_type"


## Why `pool` (a BreedPool.to_dict() shaped value) is not valid for `type_id`, or "" when it is.
## `max_generation` is the number of raids its owner took part in: a pool breeds at most once per raid.
static func check(cfg: GameConfig, type_id: String, pool: Variant, max_generation: int) -> String:
	if not cfg.is_breeding_type(type_id):
		return UNKNOWN_TYPE
	if not pool is Dictionary:
		return BAD_POOL
	var d: Dictionary = pool as Dictionary
	var gen: Variant = d.get("generation", 0)
	if not _is_whole(gen) or int(gen) < 0 or int(gen) > maxi(0, max_generation):
		return BAD_GENERATION
	var antigen_slots: int = cfg.coevo_antigen_slots
	var receptor_slots: int = cfg.coevo_receptor_slots
	if d.has("antigen_slots"):
		if not _is_whole(d["antigen_slots"]) or int(d["antigen_slots"]) != cfg.coevo_antigen_slots:
			return WRONG_LENGTH
	if d.has("receptor_slots"):
		var rs: Variant = d["receptor_slots"]
		if not _is_whole(rs) or int(rs) < cfg.coevo_receptor_slots or int(rs) > cfg.coevo_receptor_slots + BreedPool.MAX_EXTRA_RECEPTORS:
			return WRONG_LENGTH
		receptor_slots = int(rs)
	var genomes: Variant = d.get("genomes", null)
	if not genomes is Array or (genomes as Array).size() != cfg.coevo_pool_size:
		return WRONG_LENGTH
	for g: Variant in genomes as Array:
		if not g is Dictionary:
			return BAD_POOL
		var gd: Dictionary = g as Dictionary
		var antigens: Variant = gd.get("antigens", null)
		var receptors: Variant = gd.get("receptors", null)
		if not antigens is Array or not receptors is Array:
			return BAD_POOL
		if (antigens as Array).size() != antigen_slots or (receptors as Array).size() != receptor_slots:
			return WRONG_LENGTH
		for a: Variant in antigens as Array:
			if typeof(a) != TYPE_STRING or (str(a) != "" and not cfg.coevo_antigen_name.has(str(a))):
				return UNKNOWN_ALLELE
		for r: Variant in receptors as Array:
			if typeof(r) != TYPE_STRING or (str(r) != "" and not cfg.coevo_receptor_name.has(str(r))):
				return UNKNOWN_ALLELE
	return ""


## Audits a type_id -> pool dictionary. Returns {"pools": the same with every bad pool replaced by a wild one (an
## unknown type is dropped), "resets": [{"type_id", "reason"}]}. A missing pool stays missing (it starts wild).
static func audit(cfg: GameConfig, pools: Dictionary, max_generation: int) -> Dictionary:
	var clean: Dictionary = {}
	var resets: Array[Dictionary] = []
	var ids: Array = pools.keys()
	ids.sort()
	for type_var: Variant in ids:
		var type_id: String = str(type_var)
		var reason: String = check(cfg, type_id, pools[type_var], max_generation)
		if reason.is_empty():
			clean[type_id] = pools[type_var]
			continue
		resets.append({"type_id": type_id, "reason": reason})
		if reason != UNKNOWN_TYPE:
			clean[type_id] = BreedPool.wild_pool(type_id, cfg).to_dict()
	return {"pools": clean, "resets": resets}


## How many raids a profile took part in: raids it launched (against players and AI) plus raids against it.
static func participation(profile: Dictionary) -> int:
	return maxi(0, _int_of(profile, "raid_counter")) + maxi(0, _int_of(profile, "ai_raid_counter")) \
			+ maxi(0, _int_of(profile, "defense_counter"))


static func _int_of(d: Dictionary, key: String) -> int:
	var v: Variant = d.get(key, 0)
	return int(v) if _is_whole(v) else 0


static func _is_whole(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_finite(float(v)) and floorf(float(v)) == float(v)
