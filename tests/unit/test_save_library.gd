extends GutTest

const ROOT: String = "user://test_save_library"
const LEGACY_BASES: String = "user://test_save_library_legacy_bases"
const NOW: int = 1790726400
const DAY: int = 86400


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	for dir_path: String in [ROOT, LEGACY_BASES]:
		_remove_tree(dir_path)


static func _remove_tree(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for sub: String in DirAccess.get_directories_at(dir_path):
		_remove_tree("%s/%s" % [dir_path, sub])
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute("%s/%s" % [dir_path, file_name])
	DirAccess.remove_absolute(dir_path)


func _config() -> GameConfig:
	return GameConfig.load_from_dir("res://data").config


func _library() -> SaveLibrary:
	var lib := SaveLibrary.new(ROOT)
	lib.now_unix = NOW
	return lib


func _session(cfg: GameConfig) -> Session:
	return Session.new(cfg, "user://test_save_library_missing.cfg")


func _layout_of(grid: GridModel) -> Array:
	var out: Array = []
	for entry: Dictionary in grid.to_layout():
		out.append([entry["type"], entry["origin"]])
	out.sort()
	return out


func test_default_root_and_temp_root_never_migrate_by_default() -> void:
	assert_eq(SaveLibrary.DEFAULT_ROOT, "user://saves")
	assert_eq(SaveLibrary.MAX_SLOTS, 12)
	assert_true(SaveLibrary.new().legacy_dirs.has("base"), "the game's library moves user://bases in")
	assert_true(_library().legacy_dirs.is_empty(), "a temp library leaves the player's files alone")


func test_base_round_trips_through_save_list_and_load() -> void:
	var cfg := _config()
	var session := _session(cfg)
	var demo: GridModel = TitleScreen.build_demo_grid(cfg)
	session.wallet.reset(cfg.start_wallet)
	session.grid.load_layout(demo.to_layout(), session.wallet)
	var lib := _library()
	var res: Dictionary = lib.save_base("Ring fort", session.grid, cfg)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(str(res["path"]), "%s/bases/ring_fort_%d.json" % [ROOT, NOW])

	var slots: Array[Dictionary] = lib.list("base")
	assert_eq(slots.size(), 1)
	assert_eq(slots[0]["name"], "Ring fort")
	assert_eq(slots[0]["saved_unix"], NOW)
	assert_eq(slots[0]["summary"], SaveLibrary.summary_for_base(session.grid, cfg))
	assert_eq(lib.list("army").size(), 0, "bases and armies are listed apart")

	var loaded: Dictionary = lib.load_slot(slots[0]["path"], cfg)
	assert_true(loaded["ok"], str(loaded["error"]))
	assert_eq(loaded["kind"], "base")
	var other := _session(cfg)
	assert_eq(SaveLibrary.apply_base(other, loaded["parsed"]), "")
	assert_eq(_layout_of(other.grid), _layout_of(session.grid), "the layout matches")
	assert_eq(other.wallet.get_amount("atp"), session.wallet.get_amount("atp"))


func test_army_round_trips_through_save_list_and_load() -> void:
	var cfg := _config()
	var session := _session(cfg)
	var cells: Array[Vector2i] = [Vector2i(0, 5), Vector2i(0, 6), Vector2i(1, 7)]
	var types: Array[String] = ["rhinovirus", "rhinovirus", "bacteriophage"]
	for i: int in range(cells.size()):
		assert_true(session.army.buy(types[i], session.wallet))
		assert_true(session.army.deploy(types[i], cells[i]))
	var lib := _library()
	assert_true(lib.save_army("Swarm", session.army, cfg)["ok"])
	var slots: Array[Dictionary] = lib.list("army")
	assert_eq(slots.size(), 1)
	var summary: Dictionary = slots[0]["summary"]
	assert_eq(int(summary["units"]), 3)
	assert_eq(int(summary["atp"]), int(session.army.total_cost().get("atp", 0)))
	assert_eq(int((summary["types"] as Dictionary)["rhinovirus"]), 2)

	var loaded: Dictionary = lib.load_slot(slots[0]["path"], cfg)
	assert_true(loaded["ok"], str(loaded["error"]))
	assert_eq(loaded["kind"], "army")
	var other := _session(cfg)
	var result: Dictionary = SaveLibrary.apply_army(other, loaded["parsed"])
	assert_eq(result, {"deployed": 3, "total": 3})
	for i: int in range(cells.size()):
		assert_eq(other.army.deployments[i]["type"], types[i])
		assert_eq(other.army.deployments[i]["cell"], cells[i])


func test_list_is_newest_first() -> void:
	var cfg := _config()
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	var lib := _library()
	lib.now_unix = NOW - DAY
	lib.save_base("Old", grid, cfg)
	lib.now_unix = NOW
	lib.save_base("New", grid, cfg)
	lib.now_unix = NOW - 3 * DAY
	lib.save_base("Older", grid, cfg)
	var names: Array[String] = []
	for slot: Dictionary in lib.list("base"):
		names.append(str(slot["name"]))
	assert_eq(names, ["New", "Old", "Older"] as Array[String])


func test_delete_slot_removes_the_file() -> void:
	var cfg := _config()
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	var lib := _library()
	var path: String = lib.save_base("Doomed", grid, cfg)["path"]
	assert_true(FileAccess.file_exists(path))
	assert_true(lib.delete_slot(path))
	assert_false(FileAccess.file_exists(path))
	assert_eq(lib.list("base").size(), 0)
	assert_false(lib.delete_slot(path), "a second delete finds nothing")
	assert_false(lib.delete_slot("user://settings.cfg"), "never deletes outside the library")


func test_thirteenth_save_fails_when_the_library_is_full() -> void:
	var cfg := _config()
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	var lib := _library()
	for i: int in range(SaveLibrary.MAX_SLOTS):
		assert_true(lib.save_base("Base", grid, cfg)["ok"], "save %d" % (i + 1))
	assert_eq(lib.list("base").size(), 12, "same-second saves with one name get distinct files")
	var res: Dictionary = lib.save_base("One too many", grid, cfg)
	assert_false(res["ok"])
	assert_eq(res["error"], "Library is full (12). Delete a slot first.")
	assert_eq(lib.list("base").size(), 12)
	assert_true(lib.save_army("Still room", Army.new(cfg), cfg)["ok"], "armies have their own 12 slots")


func test_export_json_is_the_inner_snapshot_and_imports_back() -> void:
	var cfg := _config()
	var grid: GridModel = TitleScreen.build_demo_grid(cfg)
	var lib := _library()
	var path: String = lib.save_base("Ring fort", grid, cfg)["path"]
	var json: String = lib.export_json(path)
	assert_eq(json, SnapshotIO.to_json(SnapshotIO.base_to_dict(grid)), "Share hands out SnapshotIO's JSON")
	assert_true(SnapshotIO.parse_base(json, cfg)["ok"], "balance_sim --base accepts it")

	var res: Dictionary = lib.import_json(json, "", cfg)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(res["kind"], "base")
	assert_eq(res["name"], "Imported base 2")
	assert_eq(lib.list("base").size(), 2)
	assert_eq(lib.export_json(res["path"]), json, "the imported copy is identical")


func test_import_json_detects_armies() -> void:
	var cfg := _config()
	var json: String = SnapshotIO.to_json(SnapshotIO.army_to_dict([{"type": "rhinovirus", "cell": Vector2i(0, 5)}]))
	var lib := _library()
	var res: Dictionary = lib.import_json(json, "Friend's swarm", cfg)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(res["kind"], "army")
	assert_eq(lib.list("army")[0]["name"], "Friend's swarm")


func test_import_json_rejects_bad_input_with_snapshot_io_messages() -> void:
	var cfg := _config()
	var lib := _library()
	var bad_text: String = "not json at all"
	var res: Dictionary = lib.import_json(bad_text, "", cfg)
	assert_false(res["ok"])
	assert_eq(res["error"], SnapshotIO.parse_base(bad_text, cfg)["error"])
	assert_string_starts_with(str(res["error"]), "Invalid JSON")

	var wrong_size: String = JSON.stringify({"format": "bio_siege.base", "version": 1,
			"grid": {"width": cfg.grid_width + 1, "height": cfg.grid_height}, "structures": []})
	res = lib.import_json(wrong_size, "", cfg)
	assert_false(res["ok"])
	assert_eq(res["error"], SnapshotIO.parse_base(wrong_size, cfg)["error"])
	assert_string_starts_with(str(res["error"]), "Grid size mismatch")
	assert_eq(lib.list("base").size(), 0, "nothing is saved on failure")


func test_relative_time() -> void:
	assert_eq(SaveLibrary.relative_time(NOW, NOW), "Saved today")
	assert_eq(SaveLibrary.relative_time(NOW - DAY, NOW), "Saved yesterday")
	assert_eq(SaveLibrary.relative_time(NOW - 3 * DAY, NOW), "Saved 3 days ago")
	assert_eq(SaveLibrary.relative_time(NOW + 60, NOW), "Saved today", "a clock that went backwards")
	# NOW is midnight UTC: one minute before it was yesterday, unless the player's zone shifts the day.
	assert_eq(SaveLibrary.relative_time(NOW - 60, NOW + 60), "Saved yesterday")
	assert_eq(SaveLibrary.relative_time(NOW - 60, NOW + 60, 3600), "Saved today")


func test_summary_for_base_counts_walls_and_towers() -> void:
	var cfg := _config()
	var grid: GridModel = TitleScreen.build_demo_grid(cfg)
	var walls: int = 0
	var towers: int = 0
	for s: GridModel.PlacedStructure in grid.structures():
		var sdef: StructureDef = cfg.structures[s.type_id]
		if sdef.has_tag("wall"):
			walls += 1
		elif sdef.has_attack:
			towers += 1
	var summary: Dictionary = SaveLibrary.summary_for_base(grid, cfg)
	assert_eq(summary["walls"], walls)
	assert_eq(summary["towers"], TitleScreen.DEMO_TOWERS.size())
	assert_eq(summary["towers"], towers)
	assert_gt(int(summary["walls"]), 0)
	assert_eq(summary["atp"], int(grid.total_cost().get("atp", 0)))
	assert_eq(SaveLibrary.summary_text("base", {"atp": 760, "walls": 52, "towers": 4}), "760 ATP · 52 walls, 4 towers")
	assert_eq(SaveLibrary.summary_text("base", {"atp": 780, "walls": 136, "towers": 1}), "780 ATP · 136 walls, 1 tower")
	assert_eq(SaveLibrary.summary_text("army", {"atp": 230, "units": 8}), "230 ATP · 8 units")


func test_slugify() -> void:
	assert_eq(SaveLibrary.slugify("Ring fort"), "ring_fort")
	assert_eq(SaveLibrary.slugify("  Sniper -- cluster #2! "), "sniper_cluster_2")
	assert_eq(SaveLibrary.slugify("???"), "")


func test_legacy_bases_move_in_once() -> void:
	var cfg := _config()
	DirAccess.make_dir_recursive_absolute(LEGACY_BASES)
	var json: String = SnapshotIO.to_json(SnapshotIO.base_to_dict(TitleScreen.build_demo_grid(cfg)))
	for stamp: int in [NOW - DAY, NOW]:
		var f := FileAccess.open("%s/base_%d.json" % [LEGACY_BASES, stamp], FileAccess.WRITE)
		f.store_string(json)
		f.close()
	var junk := FileAccess.open("%s/base_1.json" % LEGACY_BASES, FileAccess.WRITE)
	junk.store_string("{broken")
	junk.close()

	var lib := _library()
	lib.legacy_dirs = {"base": LEGACY_BASES}
	assert_eq(lib.migrate_legacy(cfg), 2)
	var slots: Array[Dictionary] = lib.list("base")
	assert_eq(slots.size(), 2)
	assert_eq(slots[0]["name"], "Imported base 2")
	assert_eq(slots[0]["saved_unix"], NOW)
	assert_eq(slots[1]["name"], "Imported base 1")
	assert_eq(lib.export_json(slots[0]["path"]), json)
	assert_eq(DirAccess.get_files_at(LEGACY_BASES), PackedStringArray(["base_1.json"]), "invalid files stay put")

	var again := FileAccess.open("%s/base_%d.json" % [LEGACY_BASES, NOW + DAY], FileAccess.WRITE)
	again.store_string(json)
	again.close()
	assert_eq(lib.migrate_legacy(cfg), 0, "runs only the first time")
	assert_eq(lib.list("base").size(), 2)
