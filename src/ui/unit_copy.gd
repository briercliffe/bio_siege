class_name UnitCopy
extends RefCounted

## Player-facing descriptions of the structures and pathogens. This is copy, not stats, so it lives here and
## not in data/*.json. Numbers inside the copy come from the config, never from this file.

const MULTIPLIER_TOKEN: String = "{mult}"
const DEFENSE_TAG: String = "defense"
## Fallback when a multiplier cannot be read from the config.
const MULTIPLIER_FALLBACK: String = "much harder"
const MULTIPLIER_WORDS: Dictionary = {2: "twice", 3: "three times", 4: "four times", 5: "five times"}

const DESCRIPTIONS: Dictionary = {
	"mucous_wall": "Blocks paths. Pathogens walk around short walls and break through long ones.",
	"macrophage": "Splashes every pathogen near its target. Great against swarms, weak against tanks.",
	"b_cell": "Shots home in and never miss. Fragile up close, so keep walls in front of it.",
	"nucleus": "Your headquarters. If it falls, the attack wins.",
	"rhinovirus": "Heads for the nearest structure. Quick and cheap, but Macrophage splash shreds them.",
	"bacteriophage": "Hunts defenses first and hits them {mult}. Fragile, so send it behind a tank.",
	"staphylococcus": "Soaks up damage while the swarm gets through. Slow, so give it a head start.",
}


## The description for a type id, or "" when there is none. Pass the config for copy that quotes a stat.
static func description(type_id: String, config: GameConfig = null) -> String:
	var text: String = str(DESCRIPTIONS.get(type_id, ""))
	if text.contains(MULTIPLIER_TOKEN):
		text = text.replace(MULTIPLIER_TOKEN, _defense_multiplier_text(type_id, config))
	return text


## "three times as hard", built from the pathogen's damage_multipliers.defense.
static func _defense_multiplier_text(type_id: String, config: GameConfig) -> String:
	var pdef: PathogenDef = config.pathogens.get(type_id) as PathogenDef if config != null else null
	var pct: int = int(pdef.damage_multipliers_pct.get(DEFENSE_TAG, 100)) if pdef != null else 100
	if pct <= 100:
		return MULTIPLIER_FALLBACK + " than usual"
	var words: String = ""
	if pct % 100 == 0:
		words = str(MULTIPLIER_WORDS.get(pct / 100, ""))
	if words.is_empty():
		words = "%s times" % _trim(float(pct) / 100.0)
	return "%s as hard" % words


static func _trim(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, floorf(v)) else "%.1f" % v
