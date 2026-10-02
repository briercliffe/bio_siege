class_name StrainUnlocks
extends RefCounted

## Strain variant unlocks (AM-10, identity section 4.4). Wild is always available, and so is every variant whose
## `unlock_dna` is 0 (the first variant of each pathogen). The rest cost DNA in the Mutation Lab. The profile keeps
## the unlocked variants as "type/variant" keys. Pure: no Node, Time, OS or file access.

const ALREADY_UNLOCKED: String = "already_unlocked"
const UNKNOWN_STRAIN: String = "unknown_strain"
const INSUFFICIENT_FUNDS: String = "insufficient_funds"


static func key(type_id: String, variant_id: String) -> String:
	return "%s/%s" % [type_id, variant_id]


## The variants nobody has to pay for: every non-wild variant with unlock_dna 0, sorted.
static func defaults(cfg: GameConfig) -> Array[String]:
	var out: Array[String] = []
	for type_id: String in cfg.pathogens.keys():
		var pdef: PathogenDef = cfg.pathogens[type_id] as PathogenDef
		for s: StrainDef in pdef.strains:
			if s.unlock_dna <= 0:
				out.append(key(type_id, s.id))
	out.sort()
	return out


## The defaults plus every known key of `raw` (unknown or malformed entries are dropped), sorted.
## Empty while the `strains` flag is off, so a flags-off profile is exactly today's.
static func normalize(cfg: GameConfig, raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not cfg.flag("strains"):
		return out
	out.append_array(defaults(cfg))
	if raw is Array:
		for item: Variant in raw as Array:
			var k: String = str(item)
			if not out.has(k) and _find(cfg, k) != null:
				out.append(k)
	out.sort()
	return out


## True for wild, for a free variant and for a variant in `unlocked`. An unknown strain is not unlocked.
static func is_unlocked(cfg: GameConfig, unlocked: Array, type_id: String, variant_id: String) -> bool:
	if variant_id == "wild":
		return cfg.pathogens.has(type_id)
	var s: StrainDef = _find(cfg, key(type_id, variant_id))
	if s == null:
		return false
	return s.unlock_dna <= 0 or unlocked.has(key(type_id, variant_id))


## Buys a variant with DNA. `wallet` is spent in place on success. Returns
## {"ok", "error", "unlocked": Array[String], "cost": int}.
static func unlock(cfg: GameConfig, unlocked: Array, wallet: Wallet, type_id: String, variant_id: String) -> Dictionary:
	var k: String = key(type_id, variant_id)
	var s: StrainDef = _find(cfg, k)
	var current: Array[String] = normalize(cfg, unlocked)
	if s == null:
		return _fail(UNKNOWN_STRAIN, current)
	if s.unlock_dna <= 0 or current.has(k):
		return _fail(ALREADY_UNLOCKED, current)
	if not wallet.spend({"dna": s.unlock_dna}):
		return _fail(INSUFFICIENT_FUNDS, current)
	current.append(k)
	current.sort()
	return {"ok": true, "error": "", "unlocked": current, "cost": s.unlock_dna}


static func _find(cfg: GameConfig, k: String) -> StrainDef:
	var type_id: String = k.get_slice("/", 0)
	var variant_id: String = k.get_slice("/", 1)
	var pdef: PathogenDef = cfg.pathogens.get(type_id) as PathogenDef
	if pdef == null or variant_id.is_empty() or variant_id == "wild":
		return null
	for s: StrainDef in pdef.strains:
		if s.id == variant_id:
			return s
	return null


static func _fail(error: String, current: Array[String]) -> Dictionary:
	return {"ok": false, "error": error, "unlocked": current, "cost": 0}
