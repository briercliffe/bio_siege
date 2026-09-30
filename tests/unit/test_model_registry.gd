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
		else:
			assert_true(a is PlaceholderPainter, "placeholder until a real painter is registered: %s" % id)


func test_heights_match_the_spec() -> void:
	ModelRegistry.configure(config)
	var expected: Dictionary = {"rhinovirus": 1.25, "bacteriophage": 3.0, "staphylococcus": 2.35,
		"macrophage": 3.0, "b_cell": 4.3, "nucleus": 4.1, "mucous_wall": 0.8}
	for id_var: Variant in expected:
		var id: String = id_var
		assert_almost_eq(ModelRegistry.painter_for(id).height_tiles(), float(expected[id]), 0.0001, id)


func test_placeholder_painter_uses_config_look() -> void:
	ModelRegistry.configure(config)
	# Every pathogen has a real painter now; structures still use placeholders.
	var def: StructureDef = config.structures["macrophage"]
	var painter: PlaceholderPainter = ModelRegistry.painter_for("macrophage") as PlaceholderPainter
	assert_eq(painter.shape, def.placeholder_shape)
	assert_eq(painter.color, def.placeholder_color)
