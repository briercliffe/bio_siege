class_name SfxRateLimiter
extends RefCounted

## Sliding-window limiter: at most `max_events` allowed within any `window_ms`.
## The caller supplies the clock, so the logic is deterministic and testable.

var window_ms: int = 100
var max_events: int = 6

var _stamps: Array[int] = []


func _init(p_max_events: int = 6, p_window_ms: int = 100) -> void:
	max_events = p_max_events
	window_ms = p_window_ms


func allow(now_ms: int) -> bool:
	while not _stamps.is_empty() and now_ms - _stamps[0] >= window_ms:
		_stamps.pop_front()
	if _stamps.size() >= max_events:
		return false
	_stamps.append(now_ms)
	return true


func reset() -> void:
	_stamps.clear()
