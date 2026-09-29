class_name StructureState
extends RefCounted

var id: int = 0
var type_id: String = ""
var def: StructureDef = null
var origin: Vector2i = Vector2i.ZERO
var footprint: Vector2i = Vector2i.ONE
var center: Vector2i = Vector2i.ZERO          # FixedMath.rect_center
var hp: int = 0
var max_hp: int = 0
var alive: bool = true
var attack_cooldown: int = 0  # ticks until the next shot; 0 = ready
var target_id: int = 0        # pathogen id the tower is shooting, 0 = none

static func create(p_id: int, p_type_id: String, p_def: StructureDef, p_origin: Vector2i) -> StructureState:
	var state := StructureState.new()
	state.id = p_id
	state.type_id = p_type_id
	state.def = p_def
	state.origin = p_origin
	state.footprint = p_def.footprint if p_def != null else Vector2i.ONE
	state.center = FixedMath.rect_center(state.origin, state.footprint)
	state.hp = p_def.hp if p_def != null else 0
	state.max_hp = state.hp
	state.alive = true
	state.attack_cooldown = 0
	state.target_id = 0
	return state

func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			result.append(Vector2i(x, y))
	return result
