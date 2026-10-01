class_name StructureDef
extends RefCounted

var id: String = ""
var display_name: String = ""
var role: String = ""
var cost: Dictionary = {}
var hp: int = 0
var footprint: Vector2i = Vector2i.ONE
var buildable: bool = false
var is_targetable: bool = true
var visible_to_attacker: bool = true
var path_weight: float = 1.0
var tags: PackedStringArray = PackedStringArray()
var has_attack: bool = false
var attack_damage: int = 0
var attack_interval_ticks: int = 0
var attack_range_mt: int = 0
var splash_radius_mt: int = 0
var projectile_speed_mt_per_tick: int = 0
var has_analysis: bool = false
var analysis_threshold_ticks: int = 0
var analysis_multiplier_pct: int = 100
var damage_multipliers_pct: Dictionary = {}
var placeholder_shape: String = ""
var placeholder_color: Color = Color.WHITE
var levels: Array = []
## Feature flag that must be on before this structure can be built; "" means always.
var requires_flag: String = ""
## Resource generator (Mitochondria): ATP per real-time hour and the stored-ATP cap.
## Slow aura (Mucous Wall, behind the mucous_slow flag): pathogens on a neighbouring cell move at this percent.
var has_slow_aura: bool = false
var slow_aura_speed_pct: int = 100
var slow_aura_chebyshev: bool = false
## Trap (Mucous Wall, behind the mucous_trap flag): units with a target tag are rooted on contact.
var has_trap: bool = false
var trap_root_ticks: int = 0
var trap_target_tags: PackedStringArray = PackedStringArray()
var has_generator: bool = false
var generator_atp_per_hour: int = 0
var generator_storage: int = 0

func has_tag(t: String) -> bool:
	return tags.has(t)
