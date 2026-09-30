class_name PathogenDef
extends RefCounted

var id: String = ""
var display_name: String = ""
var role: String = ""
var cost: Dictionary = {}
var hp: int = 0
var speed_mt_per_tick: int = 0
var attack_damage: int = 0
var attack_interval_ticks: int = 0
var attack_range_mt: int = 0
var tags: PackedStringArray = PackedStringArray()
var priority_tags: PackedStringArray = PackedStringArray()
var damage_multipliers_pct: Dictionary = {}
var placeholder_shape: String = ""
var placeholder_color: Color = Color.WHITE
var levels: Array = []
var targeting_fallback: String = "nearest"
var has_biofilm: bool = false
var biofilm_link_mt: int = 0
var biofilm_break_mt: int = 0
var biofilm_damage_taken_pct: int = 100
var biofilm_regroup_ticks: int = 0
var has_hijack: bool = false
var hijack_channel_ticks: int = 0
var hijack_disable_ticks: int = 0
var hijack_target_tags: PackedStringArray = PackedStringArray()
var strains: Array[StrainDef] = []

func strain(variant_id: String) -> StrainDef:
	if variant_id == "wild":
		return StrainDef.wild()
	for sd: StrainDef in strains:
		if sd.id == variant_id:
			return sd
	return null

func strain_ids() -> Array[String]:
	var ids: Array[String] = ["wild"]
	for sd: StrainDef in strains:
		ids.append(sd.id)
	return ids

func has_tag(t: String) -> bool:
	return tags.has(t)
