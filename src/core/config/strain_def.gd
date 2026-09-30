class_name StrainDef
extends RefCounted

var id: String = "wild"
var display_name: String = "Wild type"
var hp_pct: int = 100
var speed_pct: int = 100
var damage_pct: int = 100
var cost_pct: int = 100
var analysis_rate_pct: int = 100

static func wild() -> StrainDef:
	return StrainDef.new()

func is_wild() -> bool:
	return id == "wild"

func summary() -> String:
	if is_wild():
		return "No mutations"
	var parts: PackedStringArray = PackedStringArray()
	var entries: Array = [
		[hp_pct, "HP"],
		[speed_pct, "speed"],
		[damage_pct, "damage"],
		[cost_pct, "cost"],
		[analysis_rate_pct, "B-Cell learning"],
	]
	for e: Array in entries:
		var pct: int = int(e[0])
		if pct != 100:
			parts.append("%+d%% %s" % [pct - 100, str(e[1])])
	if parts.is_empty():
		return "No mutations"
	return " · ".join(parts)
