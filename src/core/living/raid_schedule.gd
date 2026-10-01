class_name RaidSchedule
extends RefCounted

## When AI raids on the player's base are due (#162). Pure: the caller passes both timestamps.


## How many AI raids are due since `last_ai_raid_unix`, capped at ai_raid_max_pending.
static func due_count(cfg: GameConfig, last_ai_raid_unix: int, now_unix: int) -> int:
	var elapsed: int = now_unix - last_ai_raid_unix
	if elapsed <= 0 or cfg.ai_raid_interval_s <= 0:
		return 0
	return mini(cfg.ai_raid_max_pending, elapsed / cfg.ai_raid_interval_s)


## The new last_ai_raid_unix after resolving `count` raids: last + count * interval, but when the cap was
## hit with more raids owed than the cap, jump to `now` so a long absence does not queue raids forever.
static func advance(cfg: GameConfig, last_ai_raid_unix: int, now_unix: int, count: int) -> int:
	var interval: int = cfg.ai_raid_interval_s
	if interval <= 0:
		return last_ai_raid_unix
	var elapsed: int = now_unix - last_ai_raid_unix
	if count == cfg.ai_raid_max_pending and elapsed / interval > cfg.ai_raid_max_pending:
		return now_unix
	return last_ai_raid_unix + count * interval
