class_name AtpGenerator
extends RefCounted

## Pure ATP generation maths for Mitochondria (#155). Ints only. Real-time clock
## reads happen in src/game; this class only sees elapsed whole seconds.
## `layout` is the GridModel.to_layout() format: [{"type": String, "origin": ...}].

const SECONDS_PER_HOUR: int = 3600

## Sum of atp_per_hour over every generator in the layout.
static func rate_per_hour(cfg: GameConfig, layout: Array) -> int:
	var total: int = 0
	for def: StructureDef in _generators(cfg, layout):
		if def != null:
			total += def.generator_atp_per_hour
	return total

## Sum of storage over every generator in the layout.
static func capacity(cfg: GameConfig, layout: Array) -> int:
	var total: int = 0
	for def: StructureDef in _generators(cfg, layout):
		if def != null:
			total += def.generator_storage
	return total

## Returns {"stored": int, "carry": int, "generated": int}.
## carry is the leftover ATP*seconds (0..3599) so fractional ATP is never lost.
## GDScript int is 64-bit, so elapsed_s * rate_per_hour cannot overflow for any
## realistic input (24 h x 10 000 ATP/h is under 1e9).
static func accrue(stored: int, carry: int, rate_per_hour_value: int, cap: int, elapsed_s: int, max_elapsed_s: int) -> Dictionary:
	if cap <= 0 or rate_per_hour_value <= 0:
		return {"stored": stored, "carry": carry, "generated": 0}
	var elapsed: int = clampi(elapsed_s, 0, maxi(0, max_elapsed_s))
	var total: int = carry + elapsed * rate_per_hour_value
	var gained: int = total / SECONDS_PER_HOUR
	var new_carry: int = total % SECONDS_PER_HOUR
	var new_stored: int = mini(cap, stored + gained)
	if new_stored >= cap:
		new_carry = 0
	return {"stored": new_stored, "carry": new_carry, "generated": maxi(0, new_stored - stored)}

## Splits `stored` across Mitochondria in layout order by their storage share.
## Returns Array[int] parallel to the layout (0 for non-generators). The remainder goes to the first generator.
static func split_stored(cfg: GameConfig, layout: Array, stored: int) -> Array[int]:
	var result: Array[int] = []
	var total_storage: int = capacity(cfg, layout)
	var first_gen: int = -1
	var assigned: int = 0
	for i: int in range(layout.size()):
		var def: StructureDef = _def_of(cfg, layout[i])
		var share: int = 0
		if def != null and def.has_generator and total_storage > 0 and stored > 0:
			share = stored * def.generator_storage / total_storage
			if first_gen < 0:
				first_gen = i
		elif def != null and def.has_generator and first_gen < 0:
			first_gen = i
		result.append(share)
		assigned += share
	if first_gen >= 0 and stored > assigned:
		result[first_gen] += stored - assigned
	return result

static func _def_of(cfg: GameConfig, entry: Variant) -> StructureDef:
	if cfg == null or typeof(entry) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = entry
	var def: StructureDef = cfg.structures.get(str(d.get("type", "")))
	if def == null or not def.has_generator:
		return null
	return def

static func _generators(cfg: GameConfig, layout: Array) -> Array[StructureDef]:
	var defs: Array[StructureDef] = []
	for entry: Variant in layout:
		defs.append(_def_of(cfg, entry))
	return defs
