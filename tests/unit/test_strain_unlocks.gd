extends GutTest

var _cfg: GameConfig


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "strains": true}).config


func test_unlock_dna_is_parsed_from_the_data() -> void:
	var rhino: PathogenDef = _cfg.pathogens["rhinovirus"]
	assert_eq(rhino.strain("capsid_hardening").unlock_dna, 0)
	assert_eq(rhino.strain("rapid_replication").unlock_dna, 20)
	assert_eq(rhino.strain("antigenic_masking").unlock_dna, 40)
	assert_eq(StrainDef.wild().unlock_dna, 0)


func test_a_missing_unlock_dna_means_zero_and_bad_values_are_errors() -> void:
	var dir: String = "user://test_unlock_cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in ["game_rules.json", "structures.json", "pathogens.json"]:
		DirAccess.copy_absolute("res://data/" + f, dir + "/" + f)
	var pathogens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/pathogens.json")) as Dictionary
	((pathogens["rhinovirus"] as Dictionary)["strains"][1] as Dictionary).erase("unlock_dna")
	_write(dir + "/pathogens.json", pathogens)
	var ok: ConfigLoadResult = GameConfig.load_from_dir(dir)
	assert_true(ok.is_ok())
	assert_eq((ok.config.pathogens["rhinovirus"] as PathogenDef).strain("rapid_replication").unlock_dna, 0)
	((pathogens["rhinovirus"] as Dictionary)["strains"][1] as Dictionary)["unlock_dna"] = -5
	_write(dir + "/pathogens.json", pathogens)
	var bad: ConfigLoadResult = GameConfig.load_from_dir(dir)
	assert_false(bad.is_ok())
	assert_true(", ".join(bad.errors).contains("unlock_dna: must be >= 0"))
	((pathogens["rhinovirus"] as Dictionary)["strains"][1] as Dictionary)["unlock_dna"] = 1.5
	_write(dir + "/pathogens.json", pathogens)
	assert_true(", ".join(GameConfig.load_from_dir(dir).errors).contains("unlock_dna: must be an integer"))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)


func _write(path: String, data: Dictionary) -> void:
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(data))
	out.close()


func test_modifier_text_is_comma_separated() -> void:
	var rhino: PathogenDef = _cfg.pathogens["rhinovirus"]
	assert_eq(rhino.strain("capsid_hardening").modifier_text(), "+15% HP, -10% speed")
	assert_eq(StrainDef.wild().modifier_text(), "No mutations")


func test_defaults_are_the_free_variants() -> void:
	assert_eq(StrainUnlocks.defaults(_cfg), [
		"bacteriophage/capsid_hardening", "rhinovirus/capsid_hardening", "staphylococcus/thick_cell_wall"] as Array[String])


func test_normalize_adds_defaults_and_drops_unknown_keys() -> void:
	var out: Array[String] = StrainUnlocks.normalize(_cfg, ["rhinovirus/rapid_replication", "rhinovirus/bogus", "nope/x", 5])
	assert_true(out.has("rhinovirus/rapid_replication"))
	assert_true(out.has("rhinovirus/capsid_hardening"))
	assert_false(out.has("rhinovirus/bogus"))
	assert_eq(out.size(), 4)
	var off: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true}).config
	assert_eq(StrainUnlocks.normalize(off, ["rhinovirus/rapid_replication"]), [] as Array[String], "strains flag off: nothing")


func test_is_unlocked() -> void:
	var unlocked: Array = ["rhinovirus/rapid_replication"]
	assert_true(StrainUnlocks.is_unlocked(_cfg, [], "rhinovirus", "wild"))
	assert_true(StrainUnlocks.is_unlocked(_cfg, [], "rhinovirus", "capsid_hardening"))
	assert_false(StrainUnlocks.is_unlocked(_cfg, [], "rhinovirus", "rapid_replication"))
	assert_true(StrainUnlocks.is_unlocked(_cfg, unlocked, "rhinovirus", "rapid_replication"))
	assert_false(StrainUnlocks.is_unlocked(_cfg, unlocked, "rhinovirus", "antigenic_masking"))
	assert_false(StrainUnlocks.is_unlocked(_cfg, unlocked, "rhinovirus", "bogus"))
	assert_false(StrainUnlocks.is_unlocked(_cfg, unlocked, "nope", "wild"))


func test_unlock_spends_dna_and_adds_the_key() -> void:
	var wallet := Wallet.new({"dna": 25})
	var res: Dictionary = StrainUnlocks.unlock(_cfg, [], wallet, "rhinovirus", "rapid_replication")
	assert_true(res["ok"])
	assert_eq(res["cost"], 20)
	assert_eq(wallet.get_amount("dna"), 5)
	assert_true((res["unlocked"] as Array).has("rhinovirus/rapid_replication"))


func test_unlock_errors() -> void:
	var wallet := Wallet.new({"dna": 10})
	assert_eq(StrainUnlocks.unlock(_cfg, [], wallet, "rhinovirus", "rapid_replication")["error"], "insufficient_funds")
	assert_eq(wallet.get_amount("dna"), 10, "nothing is spent on a refusal")
	assert_eq(StrainUnlocks.unlock(_cfg, [], wallet, "rhinovirus", "bogus")["error"], "unknown_strain")
	assert_eq(StrainUnlocks.unlock(_cfg, [], wallet, "rhinovirus", "wild")["error"], "unknown_strain")
	assert_eq(StrainUnlocks.unlock(_cfg, [], wallet, "rhinovirus", "capsid_hardening")["error"], "already_unlocked", "free variants are unlocked")
	var rich := Wallet.new({"dna": 100})
	var first: Dictionary = StrainUnlocks.unlock(_cfg, [], rich, "rhinovirus", "rapid_replication")
	assert_eq(StrainUnlocks.unlock(_cfg, first["unlocked"] as Array, rich, "rhinovirus", "rapid_replication")["error"], "already_unlocked")
	assert_eq(rich.get_amount("dna"), 80)


func test_a_new_profile_includes_the_free_variants_and_old_ones_are_filled_in() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 1, 1800000000)
	assert_eq(p.unlocked_strains, StrainUnlocks.defaults(_cfg))
	var d: Dictionary = p.to_dict()
	d.erase("unlocked_strains")
	var loaded: Dictionary = LivingBaseProfile.from_dict(d, _cfg)
	assert_eq((loaded["profile"] as LivingBaseProfile).unlocked_strains, StrainUnlocks.defaults(_cfg))
	d["unlocked_strains"] = ["rhinovirus/antigenic_masking"]
	var kept: LivingBaseProfile = LivingBaseProfile.from_dict(d, _cfg)["profile"]
	assert_true(kept.unlocked_strains.has("rhinovirus/antigenic_masking"))
	assert_true(kept.unlocked_strains.has("rhinovirus/capsid_hardening"))


func test_flags_off_profiles_are_unchanged() -> void:
	var off: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true}).config
	var p: LivingBaseProfile = LivingBaseProfile.create_new(off, 1, 1800000000)
	assert_true(p.unlocked_strains.is_empty())
	assert_false(p.to_dict().has("unlocked_strains"), "the saved file is exactly today's")
