extends GutTest

const ROOT: String = "user://test_save_library"
const LEGACY_BASES: String = "user://test_save_library_legacy_bases"
const LEGACY_ARMIES: String = "user://test_save_library_legacy_armies"
const NOW: int = 1790726400
const DAY: int = 86400


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	for dir_path: String in [ROOT, LEGACY_BASES, LEGACY_ARMIES]:
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


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _legacy_base_json(cfg: GameConfig) -> String:
	return SnapshotIO.to_json(SnapshotIO.base_to_dict(TitleScreen.build_demo_grid(cfg)))


func _slot_times(lib: SaveLibrary, kind: String) -> Array[int]:
	var out: Array[int] = []
	for slot: Dictionary in lib.list(kind):
		out.append(int(slot["saved_unix"]))
	return out


func test_migration_is_opt_in_and_never_reads_the_real_folders_from_a_temp_root() -> void:
	assert_eq(SaveLibrary.DEFAULT_ROOT, "user://saves")
	assert_eq(SaveLibrary.MAX_SLOTS, 12)
	assert_true(SaveLibrary.new().legacy_dirs.is_empty(), "a plain library never migrates")
	assert_true(SaveLibrary.new(SaveLibrary.DEFAULT_ROOT).legacy_dirs.is_empty())
	assert_eq(SaveLibrary.default_legacy_dirs(SaveLibrary.DEFAULT_ROOT),
			{"base": "user://bases", "army": "user://armies"}, "Main's library moves the old folders in")
	assert_true(SaveLibrary.default_legacy_dirs(ROOT).is_empty(), "a temp root leaves the player's files alone")
	var cfg := _config()
	assert_true(SaveLibrary.open(ROOT, cfg).legacy_dirs.is_empty())
	assert_true(SaveLibrary.open(ROOT, cfg, true).legacy_dirs.is_empty())
	assert_false(DirAccess.dir_exists_absolute(ROOT), "nothing is written for a temp root")


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
	assert_eq(slots[0]["name"], "Imported base 1", "the newest file moves first")
	assert_eq(slots[0]["saved_unix"], NOW)
	assert_eq(slots[1]["name"], "Imported base 2")
	assert_eq(lib.export_json(slots[0]["path"]), json)
	assert_eq(DirAccess.get_files_at(LEGACY_BASES), PackedStringArray(["base_1.json"]), "invalid files stay put")

	var again := FileAccess.open("%s/base_%d.json" % [LEGACY_BASES, NOW + DAY], FileAccess.WRITE)
	again.store_string(json)
	again.close()
	assert_eq(lib.migrate_legacy(cfg), 0, "everything valid moved in, so later runs skip the scan")
	assert_eq(lib.list("base").size(), 2)


func test_legacy_armies_move_in() -> void:
	var cfg := _config()
	var units: Array = [{"type": "rhinovirus", "cell": Vector2i(0, 5)}, {"type": "bacteriophage", "cell": Vector2i(1, 6)}]
	var json: String = SnapshotIO.to_json(SnapshotIO.army_to_dict(units))
	_write_text("%s/army_%d.json" % [LEGACY_ARMIES, NOW - DAY], json)
	_write_text("%s/army_%d.json" % [LEGACY_ARMIES, NOW], json)
	_write_text("%s/army_7.json" % LEGACY_ARMIES, "{\"format\": \"bio_siege.army\"}")

	var lib := _library()
	lib.legacy_dirs = {"base": LEGACY_BASES, "army": LEGACY_ARMIES}
	assert_eq(lib.migrate_legacy(cfg), 2)
	var slots: Array[Dictionary] = lib.list("army")
	assert_eq(slots.size(), 2)
	assert_eq(slots[0]["name"], "Imported army 1")
	assert_eq(slots[0]["saved_unix"], NOW)
	assert_eq(int((slots[0]["summary"] as Dictionary)["units"]), 2)
	assert_eq(lib.export_json(slots[0]["path"]), json, "the army file is unchanged inside its slot")
	assert_eq(lib.list("base").size(), 0)
	assert_eq(DirAccess.get_files_at(LEGACY_ARMIES), PackedStringArray(["army_7.json"]), "the invalid army stays put")
	assert_true(FileAccess.file_exists("%s/%s" % [ROOT, SaveLibrary.MIGRATED_MARKER]))


func test_migration_takes_the_newest_twelve_and_pulls_more_in_once_slots_free_up() -> void:
	var cfg := _config()
	var json: String = _legacy_base_json(cfg)
	for i: int in range(SaveLibrary.MAX_SLOTS + 2):
		_write_text("%s/base_%d.json" % [LEGACY_BASES, NOW - i * DAY], json)
	var lib := _library()
	lib.legacy_dirs = {"base": LEGACY_BASES}
	assert_eq(lib.migrate_legacy(cfg), 12)
	var expected: Array[int] = []
	for i: int in range(SaveLibrary.MAX_SLOTS):
		expected.append(NOW - i * DAY)
	assert_eq(_slot_times(lib, "base"), expected, "the newest twelve moved in")
	assert_eq(DirAccess.get_files_at(LEGACY_BASES),
			PackedStringArray(["base_%d.json" % (NOW - 13 * DAY), "base_%d.json" % (NOW - 12 * DAY)]),
			"the two oldest stay on disk")
	assert_false(FileAccess.file_exists("%s/%s" % [ROOT, SaveLibrary.MIGRATED_MARKER]), "more are waiting")
	assert_eq(lib.migrate_legacy(cfg), 0, "nothing fits while the library is full")

	assert_true(lib.delete_slot(str(lib.list("base")[0]["path"])))
	assert_eq(lib.migrate_legacy(cfg), 1, "a free slot pulls the next newest in")
	assert_eq(_slot_times(lib, "base")[-1], NOW - 12 * DAY)
	assert_eq(DirAccess.get_files_at(LEGACY_BASES), PackedStringArray(["base_%d.json" % (NOW - 13 * DAY)]))
	assert_false(FileAccess.file_exists("%s/%s" % [ROOT, SaveLibrary.MIGRATED_MARKER]))

	assert_true(lib.delete_slot(str(lib.list("base")[0]["path"])))
	assert_eq(lib.migrate_legacy(cfg), 1)
	assert_eq(DirAccess.get_files_at(LEGACY_BASES).size(), 0)
	assert_true(FileAccess.file_exists("%s/%s" % [ROOT, SaveLibrary.MIGRATED_MARKER]), "done once nothing is left")


func test_a_failed_write_keeps_the_legacy_original() -> void:
	var cfg := _config()
	var json: String = _legacy_base_json(cfg)
	var original: String = "%s/base_%d.json" % [LEGACY_BASES, NOW]
	_write_text(original, json)
	var slot_path: String = "%s/bases/imported_base_1_%d.json" % [ROOT, NOW]
	# A folder where the temp file goes makes the write fail; one where the slot goes makes the rename fail.
	for blocker: String in [slot_path + ".tmp", slot_path]:
		DirAccess.make_dir_recursive_absolute(blocker)
		var lib := _library()
		lib.legacy_dirs = {"base": LEGACY_BASES}
		assert_eq(lib.migrate_legacy(cfg), 0, blocker)
		assert_true(FileAccess.file_exists(original), "the original stays (%s)" % blocker)
		assert_eq(FileAccess.get_file_as_string(original), json)
		assert_eq(lib.list("base").size(), 0, "no slot is left behind")
		assert_false(FileAccess.file_exists(slot_path + ".tmp"), "no temp file is left behind")
		assert_false(FileAccess.file_exists("%s/%s" % [ROOT, SaveLibrary.MIGRATED_MARKER]), "a later run retries")
		DirAccess.remove_absolute(blocker)

	var lib := _library()
	lib.legacy_dirs = {"base": LEGACY_BASES}
	assert_eq(lib.migrate_legacy(cfg), 1, "the retry succeeds once the path is free")
	assert_false(FileAccess.file_exists(original))
	assert_eq(lib.export_json(slot_path), json)


func test_save_reports_a_failed_write() -> void:
	var cfg := _config()
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	var slot_path: String = "%s/bases/ring_fort_%d.json" % [ROOT, NOW]
	DirAccess.make_dir_recursive_absolute(slot_path + ".tmp")
	var res: Dictionary = _library().save_base("Ring fort", grid, cfg)
	assert_false(res["ok"])
	assert_string_starts_with(str(res["error"]), "Could not write")
	assert_eq(_library().list("base").size(), 0)


func test_delete_only_accepts_slot_files() -> void:
	var cfg := _config()
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	var lib := _library()
	lib.legacy_dirs = {"base": LEGACY_BASES}
	lib.migrate_legacy(cfg)
	var marker: String = "%s/%s" % [ROOT, SaveLibrary.MIGRATED_MARKER]
	assert_true(FileAccess.file_exists(marker))
	assert_false(lib.delete_slot(marker), "the migration marker is not a slot")
	assert_true(FileAccess.file_exists(marker))
	var stray: String = "%s/bases/notes.txt" % ROOT
	_write_text(stray, "keep")
	assert_false(lib.delete_slot(stray), "only .json files")
	var nested: String = "%s/bases/deeper/slot.json" % ROOT
	_write_text(nested, "{}")
	assert_false(lib.delete_slot(nested), "only files directly in bases/ or armies/")
	var at_root: String = "%s/slot.json" % ROOT
	_write_text(at_root, "{}")
	assert_false(lib.delete_slot(at_root))
	assert_false(lib.delete_slot("%s/bases/../slot.json" % ROOT))
	assert_true(FileAccess.file_exists(at_root))
	var path: String = lib.save_army("Swarm", Army.new(cfg), cfg)["path"]
	assert_true(lib.delete_slot(path), "army slots delete")


func test_names_are_cut_to_the_max_length() -> void:
	var cfg := _config()
	var grid := GridModel.new(cfg)
	grid.reset_with_nucleus()
	assert_eq(SaveLibrary.MAX_NAME_LENGTH, 40)
	assert_eq(SaveNameDialog.MAX_NAME_LENGTH, SaveLibrary.MAX_NAME_LENGTH, "the name field uses the same limit")
	var lib := _library()
	var long_name: String = "A".repeat(60)
	assert_true(lib.save_base(long_name, grid, cfg)["ok"])
	assert_eq(lib.list("base")[0]["name"], "A".repeat(40))

	var shared: Dictionary = {"slot_version": 1, "name": "B".repeat(39) + "   tail", "kind": "base",
			"saved_unix": NOW, "summary": {}, "data": SnapshotIO.base_to_dict(grid)}
	var res: Dictionary = lib.import_json(JSON.stringify(shared), "", cfg)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(res["name"], "B".repeat(39), "trailing spaces left by the cut are trimmed")
	assert_eq(lib.list("base")[0]["name"], "B".repeat(39))


func _coevo_config(on: bool = true) -> GameConfig:
	var cfg: GameConfig = _config()
	cfg.feature_flags["coevolution"] = on
	return cfg


func test_populations_survive_save_and_apply() -> void:
	var cfg: GameConfig = _coevo_config()
	var session := _session(cfg)
	var pool: BreedPool = BreedPool.wild_pool("rhinovirus", cfg)
	pool.generation = 3
	pool.genomes[0] = Genome.from_slots(["capsule_a", ""], ["binder_a", ""], cfg)
	var lib := _library()
	var res: Dictionary = lib.save_base("Pools", session.grid, cfg, null, {"rhinovirus": pool.to_dict()})
	assert_true(res["ok"], str(res["error"]))
	var loaded: Dictionary = lib.load_slot(lib.list("base")[0]["path"], cfg)
	assert_true(loaded["ok"], str(loaded["error"]))

	var other := _session(cfg)
	assert_eq(SaveLibrary.apply_base(other, loaded["parsed"]), "")
	assert_eq(other.population("rhinovirus").generation, 3)
	assert_eq(other.population("rhinovirus").genomes[0].receptors[0], "binder_a")

	# Pools ride through an import into the library too.
	var imp: Dictionary = lib.import_json(SnapshotIO.to_json(SnapshotIO.base_to_dict(session.grid, null, {"rhinovirus": pool.to_dict()})), "Imported", cfg)
	assert_true(imp["ok"], str(imp["error"]))
	var re_loaded: Dictionary = lib.load_slot(imp["path"], cfg)
	assert_eq(int(re_loaded["parsed"]["populations"]["rhinovirus"]["generation"]), 3)


func test_apply_base_without_populations_resets_pool_when_flag_on() -> void:
	var cfg: GameConfig = _coevo_config()
	var session := _session(cfg)
	var pool: BreedPool = BreedPool.wild_pool("rhinovirus", cfg)
	pool.generation = 5
	session.populations["rhinovirus"] = pool
	var parsed: Dictionary = SnapshotIO.parse_base(SnapshotIO.to_json(SnapshotIO.base_to_dict(session.grid)), cfg)
	assert_eq(SaveLibrary.apply_base(session, parsed), "")
	assert_true(session.populations.is_empty())
	assert_eq(session.population("rhinovirus").generation, 0)


func test_apply_base_ignores_populations_when_flag_off() -> void:
	var cfg: GameConfig = _coevo_config(false)
	var session := _session(cfg)
	var stored: BreedPool = BreedPool.wild_pool("rhinovirus", _coevo_config())
	stored.generation = 5
	session.populations["rhinovirus"] = stored
	var parsed: Dictionary = SnapshotIO.parse_base(SnapshotIO.to_json(SnapshotIO.base_to_dict(session.grid, null, {"rhinovirus": {"generation": 9, "genomes": []}})), cfg)
	assert_eq(SaveLibrary.apply_base(session, parsed), "")
	assert_eq((session.populations["rhinovirus"] as BreedPool).generation, 5)
