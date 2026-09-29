class_name Rng
extends RefCounted

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var seed: int:
	get:
		return _rng.seed
	set(val):
		_rng.seed = val

func _init(p_seed: int = 0) -> void:
	_rng.seed = p_seed

func next_int(n: int) -> int:
	assert(n >= 1, "Rng.next_int: n must be >= 1")
	if n <= 1:
		return 0
	return _rng.randi_range(0, n - 1)

func next_range(lo: int, hi: int) -> int:
	return _rng.randi_range(lo, hi)

func randi() -> int:
	return _rng.randi()

func randi_range(lo: int, hi: int) -> int:
	return _rng.randi_range(lo, hi)

func next_bool() -> bool:
	return next_int(2) == 1
