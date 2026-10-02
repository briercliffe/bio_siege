extends GutTest
## The server bundles data/*.json with its own content hash. Both sides must agree with this fixture.
## Refresh with: godot --headless --path . -s tools/print_content_hash.gd


func test_fixture_matches_game_config_hash() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_not_null(res.config)
	var f: FileAccess = FileAccess.open("res://server/test/fixtures/content_hash.txt", FileAccess.READ)
	assert_not_null(f, "fixture missing")
	if f == null:
		return
	assert_eq(f.get_as_text().strip_edges(), res.config.content_hash,
		"data/*.json changed: refresh server/test/fixtures/content_hash.txt (tools/print_content_hash.gd)")
