class_name Trophies
extends RefCounted

## PvP trophy maths (AM-07, docs/SERVER_PLAN.md). Pure: the worker computes the deltas, the server only writes them.


## The size of a raid's trophy swing: clamp(base + (defender - attacker) / divisor, min, max). Integer division
## truncates toward zero, so a small trophy gap changes nothing.
static func delta(cfg: GameConfig, attacker_trophies: int, defender_trophies: int) -> int:
	var raw: int = cfg.pvp_trophy_base + (defender_trophies - attacker_trophies) / maxi(1, cfg.pvp_trophy_diff_divisor)
	return clampi(raw, cfg.pvp_trophy_min, maxi(cfg.pvp_trophy_min, cfg.pvp_trophy_max))


## An attacker win moves `delta` from the defender to the attacker. A defender win moves `delta / 2` the other way.
## Nobody drops below 0, so the returned deltas are the changes that really happen.
## Returns {"attacker_delta", "defender_delta", "attacker_after", "defender_after"}.
static func settle(cfg: GameConfig, attacker_trophies: int, defender_trophies: int, attacker_won: bool) -> Dictionary:
	var d: int = delta(cfg, attacker_trophies, defender_trophies)
	var attacker_raw: int = d if attacker_won else -(d / 2)
	var defender_raw: int = -d if attacker_won else d / 2
	var attacker_after: int = maxi(0, attacker_trophies + attacker_raw)
	var defender_after: int = maxi(0, defender_trophies + defender_raw)
	return {
		"attacker_delta": attacker_after - attacker_trophies,
		"defender_delta": defender_after - defender_trophies,
		"attacker_after": attacker_after,
		"defender_after": defender_after,
	}
