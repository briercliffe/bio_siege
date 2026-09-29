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
var damage_multipliers_pct: Dictionary = {}
var placeholder_shape: String = ""
var placeholder_color: Color = Color.WHITE
var levels: Array = []

func has_tag(t: String) -> bool:
	return tags.has(t)
