class_name Genome
extends RefCounted

## One individual's antigens (what it shows) and receptors (what it binds). "" is an empty slot.
var antigens: Array[String] = []
var receptors: Array[String] = []

static func wild(antigen_slots: int, receptor_slots: int) -> Genome:
	var g := Genome.new()
	for i: int in range(antigen_slots):
		g.antigens.append("")
	for i: int in range(receptor_slots):
		g.receptors.append("")
	return g

func is_wild() -> bool:
	for a: String in antigens:
		if a != "":
			return false
	for r: String in receptors:
		if r != "":
			return false
	return true

func receptor_count() -> int:
	var n: int = 0
	for r: String in receptors:
		if r != "":
			n += 1
	return n

func duplicate_genome() -> Genome:
	var g := Genome.new()
	g.antigens = antigens.duplicate()
	g.receptors = receptors.duplicate()
	return g

func to_dict() -> Dictionary:
	return {"antigens": antigens.duplicate(), "receptors": receptors.duplicate()}

## Builds a genome of the configured slot counts, or of explicit ones (a widened pool, #169; -1 = config).
## Unknown ids, non-strings and extra entries are dropped.
static func from_slots(antigens_in: Array, receptors_in: Array, cfg: GameConfig, antigen_slots: int = -1, receptor_slots: int = -1) -> Genome:
	var g: Genome = Genome.wild(antigen_slots if antigen_slots >= 0 else cfg.coevo_antigen_slots,
			receptor_slots if receptor_slots >= 0 else cfg.coevo_receptor_slots)
	for i: int in range(mini(antigens_in.size(), g.antigens.size())):
		var v: Variant = antigens_in[i]
		if typeof(v) == TYPE_STRING and cfg.coevo_antigen_name.has(v):
			g.antigens[i] = v
	for i: int in range(mini(receptors_in.size(), g.receptors.size())):
		var v: Variant = receptors_in[i]
		if typeof(v) == TYPE_STRING and cfg.coevo_receptor_name.has(v):
			g.receptors[i] = v
	return g
