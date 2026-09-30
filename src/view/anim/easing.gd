class_name Easing
extends RefCounted

## Static easing curves for painters. Every input is clamped to 0..1 and every curve maps 0 to 0 and 1 to 1
## unless noted.

static func linear(t: float) -> float:
	return clampf(t, 0.0, 1.0)


static func ease_in_quad(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c


static func ease_out_quad(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)


static func ease_in_out(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


static func ease_out_back(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * c * c * c + 1.70158 * c * c


## Rises to 1 at t = 0.5 and falls back to 0 (a smooth bump, 0 at both ends).
static func pulse(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return sin(c * PI)


## 0..1 loop position to a -1..1 sine wave.
static func wave(phase: float) -> float:
	return sin(phase * TAU)
