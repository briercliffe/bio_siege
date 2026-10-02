extends GutTest

## Living Base flow (#158): entering the mode, saving after edits, collecting, Test in Lab.

const DIR: String = "user://test_lb_flow"

var _cfg: GameConfig = null
var _store: LivingBaseStore = null


func before_each() -> void:
	_cfg = GameConfig.load_from_dir("res://data").config
	_cfg.feature_flags["living_base"] = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_store = LivingBaseStore.new()
	_store.path = DIR + "/living_base.json"


func after_each() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _enter() -> Session:
	var session := Session.new(_cfg)
	LivingBaseFlow.new(_store).enter(session)
	return session


func test_enter_loads_a_fresh_profile_into_the_session() -> void:
	var session: Session = _enter()
	assert_eq(session.mode, Session.Mode.LIVING_BASE)
	assert_not_null(session.profile)
	assert_not_null(session.living_flow)
	assert_eq(session.grid.structures().size(), 1)
	assert_not_null(session.grid.find_core())
	assert_eq(session.wallet.get_amount("atp"), _cfg.lb_start_wallet["atp"])
	assert_eq(session.wallet.get_amount("amino_acids"), 0)
	assert_true(_store.exists())


func test_a_placed_structure_survives_re_entering() -> void:
	var session: Session = _enter()
	var id: int = session.grid.place("macrophage", Vector2i(10, 10), session.wallet)
	assert_true(id > 0)
	session.living_flow.sync_profile_from_session()
	var spent: int = int(_cfg.structures["macrophage"].cost["atp"])

	var again: Session = _enter()
	assert_eq(again.grid.structures().size(), 2)
	assert_true(again.grid.structure_id_at(Vector2i(10, 10)) > 0)
	assert_eq(again.wallet.get_amount("atp"), int(_cfg.lb_start_wallet["atp"]) - spent)


func test_collect_moves_stored_atp_to_the_wallet_and_saves() -> void:
	var session: Session = _enter()
	session.profile.stored_atp = 40
	var before: int = session.wallet.get_amount("atp")
	assert_eq(session.living_flow.collect(), 40)
	assert_eq(session.wallet.get_amount("atp"), before + 40)
	assert_eq(session.profile.stored_atp, 0)
	assert_eq(session.living_flow.collect(), 0)

	var again: Session = _enter()
	assert_eq(again.wallet.get_amount("atp"), before + 40)
	assert_eq(again.profile.stored_atp, 0)


func test_tick_banks_generated_atp() -> void:
	var session: Session = _enter()
	session.grid.place("mitochondria", Vector2i(10, 10), session.wallet)
	session.living_flow.sync_profile_from_session()
	session.profile.last_clock_unix = LivingBaseStore.now_unix() - 7200
	assert_eq(session.living_flow.tick(), 120)
	assert_eq(session.profile.stored_atp, 120)


func test_offline_time_is_banked_on_enter() -> void:
	var session: Session = _enter()
	session.grid.place("mitochondria", Vector2i(10, 10), session.wallet)
	session.living_flow.sync_profile_from_session()
	session.profile.last_clock_unix = LivingBaseStore.now_unix() - 3600
	_store.save_profile(session.profile)
	var again: Session = _enter()
	assert_between(again.profile.stored_atp, 60, 61)


func test_test_in_lab_copies_the_base_and_leaves_the_profile_alone() -> void:
	var session: Session = _enter()
	session.grid.place("macrophage", Vector2i(10, 10), session.wallet)
	session.living_flow.sync_profile_from_session()
	var layout: Array[Dictionary] = session.grid.to_layout()
	var cost: int = int(session.grid.total_cost().get("atp", 0))

	session.living_flow.start_test_in_lab()
	# start_test_in_lab saves once more (the clock may have ticked); nothing after it may touch the file.
	var saved_text: String = FileAccess.get_file_as_string(_store.path)
	assert_eq(session.mode, Session.Mode.LAB)
	assert_null(session.profile)
	assert_eq(session.grid.to_layout(), layout)
	assert_eq(session.wallet.get_amount("atp"), maxi(0, int(_cfg.start_wallet["atp"]) - cost))
	assert_eq(session.wallet.get_amount("amino_acids"), 0)

	session.grid.sell(session.grid.structure_id_at(Vector2i(10, 10)), session.wallet)
	assert_eq(FileAccess.get_file_as_string(_store.path), saved_text, "the profile file is unchanged")


func test_reset_to_lab_starts_a_clean_lab_after_living_base() -> void:
	var session: Session = _enter()
	session.grid.place("macrophage", Vector2i(10, 10), session.wallet)
	LivingBaseFlow.reset_to_lab(session)
	assert_eq(session.mode, Session.Mode.LAB)
	assert_eq(session.grid.structures().size(), 1)
	assert_eq(session.wallet.get_amount("atp"), int(_cfg.start_wallet["atp"]))


func test_reset_to_lab_leaves_a_lab_session_alone() -> void:
	var session := Session.new(_cfg)
	session.grid.place("macrophage", Vector2i(10, 10), session.wallet)
	LivingBaseFlow.reset_to_lab(session)
	assert_eq(session.grid.structures().size(), 2)


func test_notices_from_a_reset_save_are_kept() -> void:
	var f: FileAccess = FileAccess.open(_store.path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	var session := Session.new(_cfg)
	var flow := LivingBaseFlow.new(_store)
	flow.enter(session)
	assert_eq(flow.notices, [LivingBaseStore.BAD_NOTICE])


func test_lab_base_survives_a_trip_to_living_base() -> void:
	var session := Session.new(_cfg)
	session.grid.place("macrophage", Vector2i(10, 10), session.wallet)
	var atp: int = session.wallet.get_amount("atp")
	LivingBaseFlow.new(_store).enter(session)
	assert_eq(session.grid.structures().size(), 1, "Living Base starts from its own profile")
	LivingBaseFlow.reset_to_lab(session)
	assert_eq(session.mode, Session.Mode.LAB)
	assert_eq(session.grid.structures().size(), 2)
	assert_eq(session.wallet.get_amount("atp"), atp)
	assert_true(session.lab_stash.is_empty())
	LivingBaseFlow.reset_to_lab(session)
	assert_eq(session.grid.structures().size(), 2, "a second pick of Lab leaves it alone")
