extends GutTest

var config: GameConfig


func before_each() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	config = res.config


func test_every_config_id_has_a_cached_painter() -> void:
	var ids: Array[String] = []
	for id_var: Variant in config.pathogens:
		ids.append(str(id_var))
	for id_var: Variant in config.structures:
		ids.append(str(id_var))
	assert_gt(ids.size(), 0)
	for id: String in ids:
		var a: ModelPainter = ModelRegistry.painter_for(id)
		assert_not_null(a, id)
		assert_same(ModelRegistry.painter_for(id), a, "same instance for %s" % id)
		if id == "rhinovirus":
			assert_true(a is RhinoPainter, "real painter registered: %s" % id)
		elif id == "bacteriophage":
			assert_true(a is PhagePainter, "real painter registered: %s" % id)
		elif id == "staphylococcus":
			assert_true(a is StaphPainter, "real painter registered: %s" % id)
		elif id == "mucous_wall":
			assert_true(a is WallPainter, "lone-cell wall painter registered: %s" % id)
		elif id == "macrophage":
			assert_true(a is MacrophagePainter, "real painter registered: %s" % id)
		elif id == "b_cell":
			assert_true(a is BCellPainter, "real painter registered: %s" % id)
		elif id == "nucleus":
			assert_true(a is NucleusPainter, "real painter registered: %s" % id)
		elif id == "mitochondria":
			assert_true(a is MitochondriaPainter, "real painter registered: %s" % id)
		elif id == "dendritic_cell":
			assert_true(a is DendriticPainter, "real painter registered: %s" % id)
		else:
			assert_true(a is PlaceholderPainter, "placeholder until a real painter is registered: %s" % id)
	assert_true(ModelRegistry.painter_for("not_a_model") is PlaceholderPainter, "unknown ids fall back to a placeholder")


func test_heights_match_the_spec() -> void:
	ModelRegistry.configure(config)
	var expected: Dictionary = {"rhinovirus": 1.25, "bacteriophage": 3.0, "staphylococcus": 2.35,
		"macrophage": 3.0, "b_cell": 4.3, "nucleus": 4.1, "mucous_wall": 0.8, "mitochondria": 2.0, "dendritic_cell": 2.4}
	for id_var: Variant in expected:
		var id: String = id_var
		assert_almost_eq(ModelRegistry.painter_for(id).height_tiles(), float(expected[id]), 0.0001, id)


func test_configure_leaves_real_painters_alone() -> void:
	# Every config id has a real painter now, so configure() has no placeholder to style. The Nucleus
	# ignores its rounded_square placeholder shape and is always the dome.
	ModelRegistry.configure(config)
	assert_eq((config.structures["nucleus"] as StructureDef).placeholder_shape, "rounded_square")
	assert_true(ModelRegistry.painter_for("nucleus") is NucleusPainter)
	assert_true(ModelRegistry.painter_for("macrophage") is MacrophagePainter)
	assert_true(ModelRegistry.painter_for("b_cell") is BCellPainter)
