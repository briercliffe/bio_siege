extends GutTest

const DIR: String = "user://test_lb"

var _cfg: GameConfig = null
var _store: LivingBaseStore = null

func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	DirAccess.make_dir_recursive_absolute(DIR)
	_store = LivingBaseStore.new()
	_store.path = DIR + "/living_base.json"

func after_each() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)

func test_fresh_load_creates_and_saves_a_file() -> void:
	assert_false(_store.exists())
	var res: Dictionary = _store.load_profile(_cfg)
	assert_true(res["ok"])
	assert_true(res["fresh"])
	assert_true(_store.exists())
	assert_false(FileAccess.file_exists(_store.path + ".tmp"))

func test_save_then_load_round_trips() -> void:
	var p: LivingBaseProfile = LivingBaseProfile.create_new(_cfg, 99, 1234)
	p.wallet["amino_acids"] = 7
	assert_true(_store.save_profile(p))
	assert_true(_store.save_profile(p))
	var res: Dictionary = _store.load_profile(_cfg)
	assert_true(res["ok"])
	assert_false(res["fresh"])
	var q: LivingBaseProfile = res["profile"]
	assert_eq(q.seed, 99)
	assert_eq(q.wallet["amino_acids"], 7)
	assert_eq(q.last_clock_unix, 1234)

func test_corrupt_file_is_kept_as_bad_and_reset() -> void:
	var f: FileAccess = FileAccess.open(_store.path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var res: Dictionary = _store.load_profile(_cfg)
	assert_true(res["ok"])
	assert_true(res["fresh"])
	assert_eq(res["notices"], [LivingBaseStore.BAD_NOTICE])
	assert_true(FileAccess.file_exists(DIR + "/living_base.bad.json"))
	assert_eq(FileAccess.get_file_as_string(DIR + "/living_base.bad.json"), "{ not json")
	assert_true(_store.exists())
