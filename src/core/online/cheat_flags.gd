class_name CheatFlags
extends RefCounted

## Per-player anti-cheat telemetry (AM-11). The worker folds each raid into the player's `stats` object and applies
## the receptor-hit-rate rule; the server only stores the result. No automatic ban: a human reads `admin_flagged_list`.
## Pure: no network or Time.

## A player is only judged after this many raids, and only while no pool of theirs got past this generation: a
## base that is honestly bred to a high hit rate has been through many generations.
const MIN_RAIDS: int = 5
const MAX_GENERATION: int = 5


## The stats object after one more raid. `generations` is type_id -> the generation of the pool after the raid.
## Returns {"raids", "receptor_hits", "receptor_checks", "max_generation": {type: int}, "flagged": bool}.
## `flagged` is sticky.
static func updated(cfg: GameConfig, stats: Variant, hits: int, checks: int, generations: Dictionary) -> Dictionary:
	var old: Dictionary = stats as Dictionary if stats is Dictionary else {}
	var out: Dictionary = {
		"raids": _int_of(old, "raids") + 1,
		"receptor_hits": _int_of(old, "receptor_hits") + maxi(0, hits),
		"receptor_checks": _int_of(old, "receptor_checks") + maxi(0, checks),
		"max_generation": {},
		"flagged": bool(old.get("flagged", false)),
	}
	var gens: Dictionary = out["max_generation"] as Dictionary
	var old_gens: Dictionary = old.get("max_generation", {}) as Dictionary if old.get("max_generation", {}) is Dictionary else {}
	for type_var: Variant in old_gens.keys():
		gens[str(type_var)] = _int_of(old_gens, str(type_var))
	for type_var: Variant in generations.keys():
		gens[str(type_var)] = maxi(int(gens.get(str(type_var), 0)), int(generations[type_var]))
	if is_suspicious(cfg, out):
		out["flagged"] = true
	return out


## True when the hit rate is at least pvp.suspicious_hit_rate_pct over at least MIN_RAIDS raids while no pool
## passed generation MAX_GENERATION. Integer maths only.
static func is_suspicious(cfg: GameConfig, stats: Dictionary) -> bool:
	var rate_pct: int = cfg.pvp_suspicious_hit_rate_pct
	if rate_pct <= 0:
		return false
	if _int_of(stats, "raids") < MIN_RAIDS:
		return false
	var checks: int = _int_of(stats, "receptor_checks")
	if checks <= 0:
		return false
	if _int_of(stats, "receptor_hits") * 100 < rate_pct * checks:
		return false
	var highest: int = 0
	var gens: Variant = stats.get("max_generation", {})
	if gens is Dictionary:
		for type_var: Variant in (gens as Dictionary).keys():
			highest = maxi(highest, _int_of(gens as Dictionary, str(type_var)))
	return highest < MAX_GENERATION


static func _int_of(d: Dictionary, key: String) -> int:
	var v: Variant = d.get(key, 0)
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT and is_finite(float(v)):
		return int(v)
	return 0
