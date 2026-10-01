class_name UnitCopy
extends RefCounted

## Player-facing descriptions of the structures. This is copy, not stats, so it lives here and not in data/*.json.

const DESCRIPTIONS: Dictionary = {
	"mucous_wall": "Blocks paths. Pathogens walk around short walls and break through long ones.",
	"macrophage": "Splashes every pathogen near its target. Great against swarms, weak against tanks.",
	"b_cell": "Shots home in and never miss. Fragile up close, so keep walls in front of it.",
	"nucleus": "Your headquarters. If it falls, the attack wins.",
}


## The description for a type id, or "" when there is none.
static func description(type_id: String) -> String:
	return str(DESCRIPTIONS.get(type_id, ""))
