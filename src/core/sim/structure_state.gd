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
var analysis_exposure: Dictionary = {}   # strain_key -> int, hundredths of a tick
var analyzed: Dictionary = {}            # strain_key -> true
var analysis_focus_key: String = ""      # strain key of the current target, for the view
var turncoat_until_tick: int = -1         # phage_turncoat: tick the window ends, -1 = not a turncoat
var turncoat_budget: int = 0              # friendly damage left in this window
var turncoat_pct: int = 0                 # share of attack_damage dealt per friendly shot
var turncoat_target_id: int = 0           # structure being shot, 0 = none
var genome_index: int = -1                # coevolution: index into the type pool, -1 = none

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

func analysis_progress_pct(strain_key: String) -> int:
	if analyzed.has(strain_key):
		return 100
	if def == null or def.analysis_threshold_ticks <= 0:
		return 0
	return mini(100, int(analysis_exposure.get(strain_key, 0)) / def.analysis_threshold_ticks)

func is_analyzed(strain_key: String) -> bool:
	return analyzed.has(strain_key)
