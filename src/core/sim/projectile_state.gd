class_name ProjectileState
extends RefCounted

var id: int = 0
var source_id: int = 0
var target_id: int = 0
var pos: Vector2i = Vector2i.ZERO
var speed: int = 0
var damage: int = 0
var alive: bool = true

static func create(p_id: int, p_source_id: int, p_target_id: int, p_pos: Vector2i, p_speed: int, p_damage: int) -> ProjectileState:
	var proj := ProjectileState.new()
	proj.id = p_id
	proj.source_id = p_source_id
	proj.target_id = p_target_id
	proj.pos = p_pos
	proj.speed = p_speed
	proj.damage = p_damage
	proj.alive = true
	return proj
