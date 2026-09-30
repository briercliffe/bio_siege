extends GutTest

var cfg: GameConfig = null

func before_all() -> void:
	cfg = GameConfig.load_from_dir("res://data").config


func test_wild_summary() -> void:
	assert_eq(StrainDef.wild().summary(), "No mutations")
	assert_true(StrainDef.wild().is_wild())
	assert_eq(StrainDef.wild().id, "wild")


func test_default_strain_summaries() -> void:
	var rhino: PathogenDef = cfg.pathogens["rhinovirus"]
	assert_eq(rhino.strain("capsid_hardening").summary(), "+15% HP · -10% speed")
	assert_eq(rhino.strain("rapid_replication").summary(), "-15% HP · -20% cost")
	assert_eq(rhino.strain("antigenic_masking").summary(), "-10% damage · -50% B-Cell learning")


func test_staph_first_strain_is_cell_wall() -> void:
	var staph: PathogenDef = cfg.pathogens["staphylococcus"]
	assert_eq(staph.strain_ids()[1], "thick_cell_wall")
	assert_eq(staph.strain("thick_cell_wall").display_name, "Thickened Cell Wall")
