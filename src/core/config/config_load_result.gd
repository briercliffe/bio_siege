class_name ConfigLoadResult
extends RefCounted

var config: GameConfig = null
var errors: PackedStringArray = PackedStringArray()

func is_ok() -> bool:
	return errors.is_empty()

func is_err() -> bool:
	return not errors.is_empty()
