extends GutTest

const GameDataScript: GDScript = preload("res://src/game/game_data.gd")
const TEMP_DIR: String = "user://test_config_reload"

var _base: GameConfig = null


func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	_base = res.config


func after_each() -> void:
	_remove_temp_dir()


# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------

func _read_json(file_name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file_name))
	return parsed as Dictionary


## Builds a valid config from the shipped data after `mutator` edited the three parsed roots.
func _variant(mutator: Callable) -> GameConfig:
	var rules: Dictionary = _read_json("game_rules.json")
	var structures: Dictionary = _read_json("structures.json")
	var pathogens: Dictionary = _read_json("pathogens.json")
	mutator.call(rules, structures, pathogens)
	var res: ConfigLoadResult = GameConfig.load_from_strings(JSON.stringify(rules), JSON.stringify(structures), JSON.stringify(pathogens))
	assert_true(res.is_ok(), "variant config must be valid: %s" % ["\n".join(res.errors)])
	return res.config


func _with_cost(structure_id: String, atp: int) -> GameConfig:
	return _variant(func(_r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		s[structure_id]["cost"]["atp"] = atp
	)


func _write_temp_data(structures_text: String = "") -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	for file_name: String in ["game_rules.json", "structures.json", "pathogens.json"]:
		var text: String = FileAccess.get_file_as_string("res://data/" + file_name)
		if file_name == "structures.json" and not structures_text.is_empty():
			text = structures_text
		var f: FileAccess = FileAccess.open(TEMP_DIR + "/" + file_name, FileAccess.WRITE)
		f.store_string(text)
		f.close()


func _remove_temp_dir() -> void:
	var dir: DirAccess = DirAccess.open(TEMP_DIR)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(TEMP_DIR)


func _new_game_data() -> Node:
	var gd: Node = GameDataScript.new()
	add_child_autoqfree(gd)
	return gd


# -----------------------------------------------------------------------------
# ConfigDiff: changed-leaf counting
# -----------------------------------------------------------------------------

func test_diff_identical_trees_is_zero() -> void:
	var a: Dictionary = {"x": 1, "y": {"z": [1, 2, {"k": "v"}]}}
	assert_eq(ConfigDiff.count_changed_leaves(a, a.duplicate(true)), 0)


func test_diff_counts_each_changed_scalar() -> void:
	var old_tree: Dictionary = {"a": 1, "b": {"c": 2, "d": 3}, "e": "s"}
	var new_tree: Dictionary = {"a": 9, "b": {"c": 2, "d": 4}, "e": "t"}
	assert_eq(ConfigDiff.count_changed_leaves(old_tree, new_tree), 3)


func test_diff_counts_added_and_removed_leaves() -> void:
	var old_tree: Dictionary = {"a": 1, "gone": {"p": 1, "q": 2}}
	var new_tree: Dictionary = {"a": 1, "fresh": [1, 2, 3]}
	# removed: p, q; added: three array items
	assert_eq(ConfigDiff.count_changed_leaves(old_tree, new_tree), 5)


func test_diff_added_empty_container_counts_one() -> void:
	assert_eq(ConfigDiff.count_changed_leaves({"a": 1}, {"a": 1, "tags": []}), 1)


func test_diff_arrays_compare_by_index_and_length() -> void:
	assert_eq(ConfigDiff.count_changed_leaves([1, 2, 3], [1, 5, 3]), 1)
	assert_eq(ConfigDiff.count_changed_leaves([1, 2], [1, 2, 3, 4]), 2)
	assert_eq(ConfigDiff.count_changed_leaves([1, 2, 3], [1]), 2)


func test_diff_ignores_comment_keys() -> void:
	var old_tree: Dictionary = {"_comment": "a", "v": 1, "n": {"_note": "x", "w": 2}}
	var new_tree: Dictionary = {"_comment": "b", "v": 1, "n": {"_note": "y", "w": 2}, "_extra": 5}
	assert_eq(ConfigDiff.count_changed_leaves(old_tree, new_tree), 0)


func test_diff_int_and_float_with_same_value_are_equal() -> void:
	assert_eq(ConfigDiff.count_changed_leaves({"a": 150}, {"a": 150.0}), 0)
	assert_eq(ConfigDiff.count_changed_leaves({"a": 150}, {"a": 120.5}), 1)


func test_diff_type_change_counts_once() -> void:
	assert_eq(ConfigDiff.count_changed_leaves({"a": {"b": 1, "c": 2}}, {"a": 7}), 1)
	assert_eq(ConfigDiff.count_changed_leaves({"a": "1"}, {"a": 1}), 1)


func test_diff_between_real_configs() -> void:
	assert_eq(ConfigDiff.count_changed_leaves(_base.source_data, _base.source_data), 0)
	assert_eq(ConfigDiff.count_changed_leaves(_base.source_data, _with_cost("b_cell", 120).source_data), 1)
	var two_changes: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, p: Dictionary) -> void:
		s["macrophage"]["hp"] = 501
		p["rhinovirus"]["speed_tiles_s"] = 3.0
	)
	assert_eq(ConfigDiff.count_changed_leaves(_base.source_data, two_changes.source_data), 2)


func test_loaded_config_keeps_source_data() -> void:
	assert_true(_base.source_data.has("game_rules"))
	assert_true(_base.source_data.has("structures"))
	assert_true(_base.source_data.has("pathogens"))
	assert_eq(float(_base.source_data["structures"]["b_cell"]["cost"]["atp"]), 150.0)


# -----------------------------------------------------------------------------
# core additions: Wallet.set_amount, GridModel.set_config / remove_unknown_structures,
# Army.set_config / remove_unknown_types
# -----------------------------------------------------------------------------

func test_wallet_set_amount_allows_negative_and_emits_changed() -> void:
	var wallet := Wallet.new({"atp": 100})
	watch_signals(wallet)
	wallet.set_amount("atp", -40)
	assert_eq(wallet.get_amount("atp"), -40)
	assert_signal_emitted_with_parameters(wallet, "changed", ["atp", -40])
	wallet.set_amount("atp", -40)
	assert_signal_emit_count(wallet, "changed", 1)
	assert_false(wallet.can_afford({"atp": 1}))


func test_grid_set_config_updates_dimensions() -> void:
	var grid := GridModel.new(_base)
	var bigger: GameConfig = _variant(func(r: Dictionary, _s: Dictionary, _p: Dictionary) -> void:
		r["grid"]["width"] = 16
		r["grid"]["height"] = 18
		r["grid"]["deploy_ring"] = 3
	)
	grid.set_config(bigger)
	assert_eq(grid.width, 16)
	assert_eq(grid.height, 18)
	assert_eq(grid.deploy_ring, 3)


func test_grid_remove_unknown_structures() -> void:
	var session := Session.new(_base)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.grid.place("mucous_wall", Vector2i(7, 3), session.wallet)
	var no_macrophage: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		s.erase("macrophage")
	)
	session.grid.set_config(no_macrophage)
	watch_signals(session.grid)
	assert_eq(session.grid.remove_unknown_structures(), 1)
	assert_signal_emit_count(session.grid, "structure_removed", 1)
	assert_eq(session.grid.structure_id_at(Vector2i(3, 3)), 0)
	assert_gt(session.grid.structure_id_at(Vector2i(7, 3)), 0)
	assert_eq(session.grid.remove_unknown_structures(), 0)


func test_army_remove_unknown_types() -> void:
	var session := Session.new(_base)
	session.army.buy("rhinovirus", session.wallet)
	session.army.buy("bacteriophage", session.wallet)
	session.army.buy("bacteriophage", session.wallet)
	session.army.deploy("bacteriophage", Vector2i(0, 3))
	var no_phage: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p.erase("bacteriophage")
	)
	session.army.set_config(no_phage)
	watch_signals(session.army)
	assert_eq(session.army.remove_unknown_types(), 2)
	assert_signal_emit_count(session.army, "changed", 1)
	assert_eq(session.army.total_count(), 1)
	assert_eq(session.army.reserve_count("rhinovirus"), 1)
	assert_eq(session.army.deployments.size(), 0)


# -----------------------------------------------------------------------------
# Session.apply_new_config
# -----------------------------------------------------------------------------

func test_cost_decrease_recomputes_atp_at_new_prices() -> void:
	var session := Session.new(_base)
	session.grid.place("b_cell", Vector2i(3, 3), session.wallet)
	session.grid.place("b_cell", Vector2i(7, 3), session.wallet)
	for i in range(5):
		session.army.buy("rhinovirus", session.wallet)
	assert_eq(session.wallet.get_amount("atp"), 1000 - 300 - 50)

	var summary: Dictionary = session.apply_new_config(_with_cost("b_cell", 120))

	assert_eq(session.wallet.get_amount("atp"), 1000 - 240 - 50)
	assert_eq(summary["atp"], 710)
	assert_eq(summary["changed_values"], 1)
	assert_false(summary["base_reset"])
	assert_false(summary["over_budget"])
	assert_eq(summary["message"], "Config reloaded (1 value changed)")
	assert_eq(session.grid.count_by_type().get("b_cell"), 2)
	assert_eq(session.army.total_count(), 5)


func test_new_prices_apply_to_later_purchases_and_refunds() -> void:
	var session := Session.new(_base)
	session.apply_new_config(_with_cost("b_cell", 120))
	var before: int = session.wallet.get_amount("atp")
	var sid: int = session.grid.place("b_cell", Vector2i(3, 3), session.wallet)
	assert_gt(sid, 0)
	assert_eq(session.wallet.get_amount("atp"), before - 120)
	session.grid.sell(sid, session.wallet)
	assert_eq(session.wallet.get_amount("atp"), before)


func test_cost_increase_can_push_atp_negative_without_selling() -> void:
	var session := Session.new(_base)
	for x in [3, 7, 11]:
		session.grid.place("macrophage", Vector2i(x, 3), session.wallet)
	for i in range(10):
		session.army.buy("rhinovirus", session.wallet)
	assert_eq(session.wallet.get_amount("atp"), 1000 - 300 - 100)

	var summary: Dictionary = session.apply_new_config(_with_cost("macrophage", 400))

	# base 3 * 400 + army 100 = 1300 > 1000
	assert_eq(session.wallet.get_amount("atp"), -300)
	assert_eq(summary["atp"], -300)
	assert_true(summary["over_budget"])
	assert_true((summary["notices"] as Array).has("Your base and army now cost more than your budget"))
	assert_true(String(summary["message"]).contains("Your base and army now cost more than your budget"))
	assert_eq(session.grid.count_by_type().get("macrophage"), 3, "nothing is auto-sold")
	assert_eq(session.army.total_count(), 10, "nothing is auto-sold")


func test_negative_atp_recovers_when_selling() -> void:
	var session := Session.new(_base)
	var sid: int = session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.apply_new_config(_with_cost("macrophage", 1500))
	assert_eq(session.wallet.get_amount("atp"), -500)
	# selling refunds the new price
	session.grid.sell(sid, session.wallet)
	assert_eq(session.wallet.get_amount("atp"), 1000)


func test_apply_reports_changed_value_count() -> void:
	var session := Session.new(_base)
	var three: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, p: Dictionary) -> void:
		s["macrophage"]["hp"] = 501
		s["b_cell"]["hp"] = 401
		p["rhinovirus"]["hp"] = 31
	)
	var summary: Dictionary = session.apply_new_config(three)
	assert_eq(summary["changed_values"], 3)
	assert_eq(summary["message"], "Config reloaded (3 values changed)")
	assert_eq(session.config, three)


func test_apply_updates_grid_and_army_config_references() -> void:
	var session := Session.new(_base)
	var cheaper: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p["rhinovirus"]["cost"]["atp"] = 5
	)
	session.apply_new_config(cheaper)
	var before: int = session.wallet.get_amount("atp")
	assert_true(session.army.buy("rhinovirus", session.wallet))
	assert_eq(session.wallet.get_amount("atp"), before - 5)
	assert_eq(session.army.total_cost().get("atp"), 5)


func test_grid_width_change_resets_base() -> void:
	var session := Session.new(_base)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.army.buy("rhinovirus", session.wallet)
	session.army.buy("rhinovirus", session.wallet)
	session.army.deploy("rhinovirus", Vector2i(0, 3))
	session.prediction_structure_id = 2
	var wide: GameConfig = _variant(func(r: Dictionary, _s: Dictionary, _p: Dictionary) -> void:
		r["grid"]["width"] = 16
	)

	var summary: Dictionary = session.apply_new_config(wide)

	assert_true(summary["base_reset"])
	assert_eq(summary["message"], "Config reloaded (1 value changed) · Grid size changed: base reset")
	assert_eq(session.grid.width, 16)
	assert_eq(session.wallet.get_amount("atp"), 1000)
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.army.deployments.size(), 0)
	assert_eq(session.grid.structures().size(), 1, "only the nucleus remains")
	assert_eq(session.grid.structure_id_at(session.grid.default_nucleus_origin()), 1)
	assert_eq(session.prediction_structure_id, 0)
	assert_eq(session.config, wide)


func test_deploy_ring_change_resets_base() -> void:
	var session := Session.new(_base)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	var ring: GameConfig = _variant(func(r: Dictionary, _s: Dictionary, _p: Dictionary) -> void:
		r["grid"]["deploy_ring"] = 3
	)
	var summary: Dictionary = session.apply_new_config(ring)
	assert_true(summary["base_reset"])
	assert_eq(session.grid.deploy_ring, 3)
	assert_eq(session.wallet.get_amount("atp"), 1000)
	assert_eq(session.grid.structures().size(), 1)


func test_unchanged_grid_does_not_reset_base() -> void:
	var session := Session.new(_base)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	var summary: Dictionary = session.apply_new_config(_with_cost("b_cell", 120))
	assert_false(summary["base_reset"])
	assert_eq(session.grid.structures().size(), 2)


func test_start_wallet_change_recomputes_atp() -> void:
	var session := Session.new(_base)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	var richer: GameConfig = _variant(func(r: Dictionary, _s: Dictionary, _p: Dictionary) -> void:
		r["start_wallet"]["atp"] = 1500
	)
	session.apply_new_config(richer)
	assert_eq(session.wallet.get_amount("atp"), 1400)


func test_unknown_structure_type_is_removed_and_reported() -> void:
	var session := Session.new(_base)
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.grid.place("macrophage", Vector2i(7, 3), session.wallet)
	session.grid.place("mucous_wall", Vector2i(11, 3), session.wallet)
	var no_macrophage: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		s.erase("macrophage")
	)

	var summary: Dictionary = session.apply_new_config(no_macrophage)

	assert_eq(summary["removed_structures"], 2)
	assert_true((summary["notices"] as Array).has("Removed 2 structures of unknown type"))
	assert_false(session.grid.count_by_type().has("macrophage"))
	assert_eq(session.grid.count_by_type().get("mucous_wall"), 1)
	assert_eq(session.grid.structure_id_at(Vector2i(3, 3)), 0)
	# removed structures are no longer paid for
	assert_eq(session.wallet.get_amount("atp"), 1000 - 5)
	assert_false(summary["base_reset"])


func test_unknown_pathogen_type_is_dropped_from_army() -> void:
	var session := Session.new(_base)
	session.army.buy("rhinovirus", session.wallet)
	session.army.buy("staphylococcus", session.wallet)
	var no_staph: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p.erase("staphylococcus")
	)
	var summary: Dictionary = session.apply_new_config(no_staph)
	assert_eq(summary["removed_units"], 1)
	assert_eq(session.army.total_count(), 1)
	assert_eq(session.wallet.get_amount("atp"), 990)
	assert_true((summary["notices"] as Array).has("Removed 1 units of unknown type"))


func test_apply_emits_wallet_changed_for_live_huds() -> void:
	var session := Session.new(_base)
	session.grid.place("b_cell", Vector2i(3, 3), session.wallet)
	watch_signals(session.wallet)
	session.apply_new_config(_with_cost("b_cell", 120))
	assert_signal_emitted_with_parameters(session.wallet, "changed", ["atp", 880])


func test_apply_clears_pending_config() -> void:
	var session := Session.new(_base)
	session.pending_config = _with_cost("b_cell", 120)
	session.apply_new_config(session.pending_config)
	assert_null(session.pending_config)


func test_apply_null_config_is_a_noop() -> void:
	var session := Session.new(_base)
	var summary: Dictionary = session.apply_new_config(null)
	assert_eq(session.config, _base)
	assert_eq(summary["changed_values"], 0)


# -----------------------------------------------------------------------------
# GameStateMachine: queue during INFECTION
# -----------------------------------------------------------------------------

func _make_fsm(phase: GameStateMachine.Phase) -> GameStateMachine:
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.session = Session.new(_base)
	fsm.phase = phase
	return fsm


func test_reload_during_infection_is_queued_not_applied() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.INFECTION)
	var faster: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p["rhinovirus"]["speed_tiles_s"] = 4.0
	)
	var old_speed: int = _base.pathogens["rhinovirus"].speed_mt_per_tick
	watch_signals(fsm)

	fsm.on_config_reloaded(faster)

	assert_eq(fsm.session.config, _base, "battle keeps the old config")
	assert_eq(fsm.session.config.pathogens["rhinovirus"].speed_mt_per_tick, old_speed)
	assert_eq(fsm.session.pending_config, faster)
	assert_signal_not_emitted(fsm, "config_applied")


func test_queued_config_applies_when_infection_ends_in_results() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.INFECTION)
	var faster: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p["rhinovirus"]["speed_tiles_s"] = 4.0
	)
	fsm.on_config_reloaded(faster)
	watch_signals(fsm)

	assert_true(fsm.request_transition(GameStateMachine.Phase.RESULTS))

	assert_eq(fsm.session.config, faster)
	assert_null(fsm.session.pending_config)
	assert_signal_emit_count(fsm, "config_applied", 1)
	var summary: Dictionary = get_signal_parameters(fsm, "config_applied", 0)[0]
	assert_eq(summary["changed_values"], 1)
	assert_gt(fsm.session.config.pathogens["rhinovirus"].speed_mt_per_tick, _base.pathogens["rhinovirus"].speed_mt_per_tick)


func test_latest_queued_config_wins() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.INFECTION)
	var first: GameConfig = _with_cost("b_cell", 130)
	var second: GameConfig = _with_cost("b_cell", 120)
	fsm.on_config_reloaded(first)
	fsm.on_config_reloaded(second)
	fsm.request_transition(GameStateMachine.Phase.RESULTS)
	assert_eq(fsm.session.config, second)


func test_queued_config_applies_when_infection_is_left_by_force() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.INFECTION)
	var cheaper: GameConfig = _with_cost("b_cell", 120)
	fsm.on_config_reloaded(cheaper)
	fsm.force_transition(GameStateMachine.Phase.SYNTHESIS)
	assert_eq(fsm.session.config, cheaper)
	assert_null(fsm.session.pending_config)


func test_reload_outside_infection_applies_immediately() -> void:
	for phase: GameStateMachine.Phase in [GameStateMachine.Phase.SYNTHESIS, GameStateMachine.Phase.INCUBATION, GameStateMachine.Phase.RESULTS]:
		var fsm: GameStateMachine = _make_fsm(phase)
		var cheaper: GameConfig = _with_cost("b_cell", 120)
		watch_signals(fsm)
		fsm.on_config_reloaded(cheaper)
		assert_eq(fsm.session.config, cheaper, GameStateMachine.get_phase_name(phase))
		assert_null(fsm.session.pending_config)
		assert_signal_emit_count(fsm, "config_applied", 1)


func test_reload_is_ignored_without_session() -> void:
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	watch_signals(fsm)
	fsm.on_config_reloaded(_with_cost("b_cell", 120))
	assert_signal_not_emitted(fsm, "config_applied")


func test_running_battle_sim_keeps_its_own_config() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.INFECTION)
	var sim := BattleSim.new(_base, Scenarios.open_field(42))
	var faster: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p["rhinovirus"]["speed_tiles_s"] = 4.0
	)
	fsm.on_config_reloaded(faster)
	fsm.request_transition(GameStateMachine.Phase.RESULTS)
	assert_eq(fsm.session.config, faster)
	assert_eq(sim.config, _base)


# -----------------------------------------------------------------------------
# Main scene wiring
# -----------------------------------------------------------------------------

func test_main_shows_banners_for_reload_results() -> void:
	var main_node: Node = (load("res://src/main.tscn") as PackedScene).instantiate()
	add_child_autoqfree(main_node)
	var banner: DevBanner = main_node.get_node("DevBanner") as DevBanner
	var fsm: GameStateMachine = main_node.get_node("GameStateMachine") as GameStateMachine
	assert_false(banner.visible)

	GameData.config_reload_failed.emit(PackedStringArray(["structures.json: macrophage.hp: must be > 0 (got -1)"]))
	assert_true(banner.visible)
	assert_eq(banner.kind, DevBanner.Kind.ERROR)
	assert_true(banner.current_text.contains("macrophage.hp"))

	GameData.config_reloaded.emit(_with_cost("b_cell", 120))
	assert_eq(banner.kind, DevBanner.Kind.INFO)
	assert_eq(banner.current_text, "Config reloaded (1 value changed)")
	assert_eq(fsm.session.config.structures["b_cell"].cost["atp"], 120)


# -----------------------------------------------------------------------------
# HUD refresh
# -----------------------------------------------------------------------------

func _make_build_hud(session: Session) -> HudBuild:
	var grid_view := GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, session.config)
	var controller := BuildController.new()
	add_child_autofree(controller)
	controller.setup(session, grid_view)
	var hud: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
	add_child_autofree(hud)
	hud.setup(session, controller)
	return hud


func test_build_tray_card_shows_new_cost() -> void:
	var session := Session.new(_base)
	var hud: HudBuild = _make_build_hud(session)
	assert_eq(hud.get_card("b_cell").cost_label.text, "150 ATP")

	session.apply_new_config(_with_cost("b_cell", 120))
	hud.refresh_config()

	assert_eq(hud.get_card("b_cell").cost_label.text, "120 ATP")
	assert_eq(hud.get_card("b_cell").cost_atp, 120)


func test_build_tray_refreshes_names_and_roles_in_place() -> void:
	var session := Session.new(_base)
	var hud: HudBuild = _make_build_hud(session)
	var card_before: HudCard = hud.get_card("macrophage")
	var renamed: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		s["macrophage"]["display_name"] = "Big Eater"
		s["macrophage"]["role"] = "Eats things"
	)
	session.apply_new_config(renamed)
	hud.refresh_config()
	assert_eq(hud.get_card("macrophage"), card_before, "same card node, updated in place")
	assert_eq(card_before.name_label.text, "Big Eater")
	assert_eq(card_before.role_label.text, "Eats things")


func test_build_tray_rebuilds_when_structure_removed() -> void:
	var session := Session.new(_base)
	var hud: HudBuild = _make_build_hud(session)
	hud.controller.select_tool("macrophage")
	var no_macrophage: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		s.erase("macrophage")
	)
	session.apply_new_config(no_macrophage)
	hud.refresh_config()
	assert_null(hud.get_card("macrophage"))
	assert_not_null(hud.get_card("b_cell"))
	assert_not_null(hud.get_card("sell"))
	assert_eq(hud.controller.tool, "", "selected tool of a removed structure is cleared")


func test_build_tray_rebuilds_when_structure_added() -> void:
	var session := Session.new(_base)
	var hud: HudBuild = _make_build_hud(session)
	var count_before: int = hud.get_cards().size()
	var extra: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		var clone: Dictionary = (s["macrophage"] as Dictionary).duplicate(true)
		clone["display_name"] = "Macrophage Two"
		s["macrophage_two"] = clone
	)
	session.apply_new_config(extra)
	hud.refresh_config()
	assert_eq(hud.get_cards().size(), count_before + 1)
	assert_not_null(hud.get_card("macrophage_two"))


func test_build_tray_keeps_selection_when_rebuilt_for_reorder() -> void:
	var session := Session.new(_base)
	var hud: HudBuild = _make_build_hud(session)
	hud.controller.select_tool("b_cell")
	# b_cell becomes cheaper than macrophage: the tray order changes
	session.apply_new_config(_with_cost("b_cell", 50))
	hud.refresh_config()
	assert_eq(hud.controller.tool, "b_cell")
	assert_true(hud.get_card("b_cell").is_selected)
	assert_eq(hud.get_cards()[0].tool_id, "mucous_wall")
	assert_eq(hud.get_cards()[1].tool_id, "b_cell")


func test_build_hud_shows_negative_atp_in_red() -> void:
	var session := Session.new(_base)
	var hud: HudBuild = _make_build_hud(session)
	var normal: Color = hud.atp_label.get_theme_color("font_color")
	session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	session.apply_new_config(_with_cost("macrophage", 1500))
	hud.refresh_config()
	assert_eq(hud.atp_label.text, "ATP -500")
	assert_eq(hud.atp_label.get_theme_color("font_color"), HudBuild.ATP_OVER_BUDGET_COLOR)

	session.grid.sell(session.grid.structure_id_at(Vector2i(3, 3)), session.wallet)
	assert_eq(hud.atp_label.text, "ATP 1000")
	assert_eq(hud.atp_label.get_theme_color("font_color"), normal)


func _make_spawn_hud(session: Session) -> HudSpawn:
	var hud: HudSpawn = (load("res://src/ui/hud_spawn.tscn") as PackedScene).instantiate() as HudSpawn
	add_child_autofree(hud)
	hud.setup(session)
	return hud


func test_spawn_tray_card_shows_new_cost_and_keeps_counts() -> void:
	var session := Session.new(_base)
	var hud: HudSpawn = _make_spawn_hud(session)
	session.army.buy("rhinovirus", session.wallet)
	session.army.buy("rhinovirus", session.wallet)
	var cheaper: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p["rhinovirus"]["cost"]["atp"] = 5
	)
	session.apply_new_config(cheaper)
	hud.refresh_config()
	var card: HudSpawnCard = hud.get_card("rhinovirus")
	assert_eq(card.cost_label.text, "5 ATP")
	assert_eq(card.count_badge.text, "2 · 0 deployed")
	assert_eq(hud.atp_label.text, "ATP 990")


func test_spawn_tray_rebuilds_when_pathogen_removed() -> void:
	var session := Session.new(_base)
	var hud: HudSpawn = _make_spawn_hud(session)
	hud._on_card_pressed(hud.get_card("staphylococcus"))
	assert_eq(hud.selected_type_id, "staphylococcus")
	var no_staph: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p.erase("staphylococcus")
	)
	session.apply_new_config(no_staph)
	hud.refresh_config()
	assert_null(hud.get_card("staphylococcus"))
	assert_not_null(hud.get_recall_card())
	assert_eq(hud.selected_type_id, "")


func test_spawn_hud_shows_negative_atp_in_red() -> void:
	var session := Session.new(_base)
	var hud: HudSpawn = _make_spawn_hud(session)
	var normal: Color = hud.atp_label.get_theme_color("font_color")
	for i in range(5):
		session.army.buy("staphylococcus", session.wallet)
	var pricey: GameConfig = _variant(func(_r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		p["staphylococcus"]["cost"]["atp"] = 300
	)
	session.apply_new_config(pricey)
	hud.refresh_config()
	assert_eq(hud.atp_label.text, "ATP -500")
	assert_eq(hud.atp_label.get_theme_color("font_color"), HudSpawn.ATP_OVER_BUDGET_COLOR)
	session.army.refund_all(session.wallet)
	assert_eq(hud.atp_label.get_theme_color("font_color"), normal)


func test_synthesis_phase_refreshes_grid_and_tray_on_config_change() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.NONE)
	fsm.force_transition(GameStateMachine.Phase.SYNTHESIS)
	var synth: SynthesisPhase = fsm.current_phase_scene as SynthesisPhase
	assert_not_null(synth)
	var wide: GameConfig = _variant(func(r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		r["grid"]["width"] = 16
		s["b_cell"]["cost"]["atp"] = 120
	)
	fsm.on_config_reloaded(wide)
	assert_eq(synth.grid_view.config, wide)
	assert_eq(synth.grid_view.grid.width, 16)
	assert_eq(synth.hud_build.get_card("b_cell").cost_label.text, "120 ATP")


func test_incubation_phase_refreshes_grid_and_tray_on_config_change() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.SYNTHESIS)
	fsm.force_transition(GameStateMachine.Phase.INCUBATION)
	var incubation: IncubationPhase = fsm.current_phase_scene as IncubationPhase
	assert_not_null(incubation)
	var changed: GameConfig = _variant(func(r: Dictionary, _s: Dictionary, p: Dictionary) -> void:
		r["grid"]["width"] = 16
		p["rhinovirus"]["cost"]["atp"] = 5
	)
	fsm.on_config_reloaded(changed)
	assert_eq(incubation.grid_view.config, changed)
	assert_eq(incubation.grid_view.grid.width, 16)
	assert_eq(incubation.hud_spawn.get_card("rhinovirus").cost_label.text, "5 ATP")


func test_results_phase_refreshes_new_base_label_on_config_change() -> void:
	var fsm: GameStateMachine = _make_fsm(GameStateMachine.Phase.INFECTION)
	fsm.force_transition(GameStateMachine.Phase.RESULTS)
	var results: ResultsPhase = fsm.current_phase_scene as ResultsPhase
	assert_not_null(results)
	assert_eq(results.btn_new_base.text, "Start over with 1000 ATP")
	var richer: GameConfig = _variant(func(r: Dictionary, _s: Dictionary, _p: Dictionary) -> void:
		r["start_wallet"]["atp"] = 1500
	)
	fsm.on_config_reloaded(richer)
	assert_eq(results.btn_new_base.text, "Start over with 1500 ATP")


func test_error_banner_is_cleared_by_reload_queued_during_infection() -> void:
	var main_node: Node = (load("res://src/main.tscn") as PackedScene).instantiate()
	add_child_autoqfree(main_node)
	var banner: DevBanner = main_node.get_node("DevBanner") as DevBanner
	var fsm: GameStateMachine = main_node.get_node("GameStateMachine") as GameStateMachine
	fsm.phase = GameStateMachine.Phase.INFECTION

	GameData.config_reload_failed.emit(PackedStringArray(["bad value"]))
	assert_eq(banner.kind, DevBanner.Kind.ERROR)

	var cheaper: GameConfig = _with_cost("b_cell", 120)
	GameData.config_reloaded.emit(cheaper)

	assert_ne(banner.kind, DevBanner.Kind.ERROR)
	assert_false(banner.visible)
	assert_eq(fsm.session.pending_config, cheaper, "the reload itself is still queued")


func test_prediction_cleared_when_predicted_structure_is_removed() -> void:
	var session := Session.new(_base)
	var doomed: int = session.grid.place("macrophage", Vector2i(3, 3), session.wallet)
	var kept: int = session.grid.place("b_cell", Vector2i(7, 3), session.wallet)
	var no_macrophage: GameConfig = _variant(func(_r: Dictionary, s: Dictionary, _p: Dictionary) -> void:
		s.erase("macrophage")
	)
	session.prediction_structure_id = doomed
	session.apply_new_config(no_macrophage)
	assert_eq(session.prediction_structure_id, 0)

	session.prediction_structure_id = kept
	session.apply_new_config(_with_cost("b_cell", 120))
	assert_eq(session.prediction_structure_id, kept, "still on the grid, so kept")


func test_prediction_survives_to_results_when_grid_resets_on_leaving_infection() -> void:
	var fsm := GameStateMachine.new()
	add_child_autoqfree(fsm)
	fsm.start()
	fsm.request_transition(GameStateMachine.Phase.INCUBATION)
	var nucleus_id: int = fsm.session.grid.structure_id_at(fsm.session.grid.default_nucleus_origin())
	fsm.session.army.buy("rhinovirus", fsm.session.wallet)
	fsm.session.prediction_structure_id = nucleus_id
	fsm.session.battle_setup = Scenarios.open_field(42)
	fsm.request_transition(GameStateMachine.Phase.INFECTION)
	var infection: InfectionPhase = fsm.current_phase_scene as InfectionPhase
	var wide: GameConfig = _variant(func(r: Dictionary, _s: Dictionary, _p: Dictionary) -> void:
		r["grid"]["width"] = 16
	)
	fsm.on_config_reloaded(wide)

	infection.runner.sim.run_to_end()
	infection._on_battle_finished(infection.runner.sim)

	assert_eq(fsm.phase, GameStateMachine.Phase.RESULTS)
	assert_eq(fsm.session.config, wide)
	assert_eq(fsm.session.prediction_structure_id, 0, "the reset base has new structure ids")
	var results: ResultsPhase = fsm.current_phase_scene as ResultsPhase
	assert_true(results.val_prediction.visible, "the battle's prediction is still shown")
	assert_eq(fsm.session.last_result["prediction_structure_id"], nucleus_id)


# -----------------------------------------------------------------------------
# GameData watcher
# -----------------------------------------------------------------------------

func test_hot_reload_support_matrix() -> void:
	assert_true(GameDataScript.is_hot_reload_supported(true, false))
	assert_false(GameDataScript.is_hot_reload_supported(false, false), "release build")
	assert_false(GameDataScript.is_hot_reload_supported(true, true), "exported debug template")
	assert_false(GameDataScript.is_hot_reload_supported(false, true))


func test_no_watcher_timer_when_disabled() -> void:
	var gd: Node = autofree(GameDataScript.new())
	gd.setup_watcher(false)
	assert_false(gd.hot_reload_enabled)
	assert_eq(gd.get_children().size(), 0)


func test_watcher_timer_runs_every_second_when_enabled() -> void:
	var gd: Node = _new_game_data()
	for child: Node in gd.get_children():
		child.free()
	gd.setup_watcher(true)
	assert_true(gd.hot_reload_enabled)
	var timers: Array[Node] = gd.get_children().filter(func(n: Node) -> bool: return n is Timer)
	assert_eq(timers.size(), 1)
	var timer: Timer = timers[0] as Timer
	assert_eq(timer.wait_time, 1.0)
	assert_false(timer.one_shot)
	assert_false(timer.is_stopped())


func test_autoload_watcher_matches_build_type() -> void:
	var expect_timer: bool = GameDataScript.is_hot_reload_supported()
	assert_eq(GameData.hot_reload_enabled, expect_timer)
	var timers: Array[Node] = GameData.get_children().filter(func(n: Node) -> bool: return n is Timer)
	assert_eq(timers.size(), 1 if expect_timer else 0)


func test_check_for_changes_detects_timestamp_change() -> void:
	_write_temp_data()
	var gd: Node = _new_game_data()
	gd.load_data(TEMP_DIR)
	watch_signals(gd)
	assert_false(gd.check_for_changes(), "nothing changed yet")
	assert_signal_not_emitted(gd, "config_reloaded")

	gd._mtimes = {"game_rules.json": 1, "structures.json": 1, "pathogens.json": 1}
	assert_true(gd.check_for_changes())
	assert_signal_emit_count(gd, "config_reloaded", 1)
	assert_false(gd.check_for_changes(), "new timestamps were remembered")


func test_reload_success_swaps_config_and_emits() -> void:
	_write_temp_data()
	var gd: Node = _new_game_data()
	gd.load_data(TEMP_DIR)
	var old_config: GameConfig = gd.config
	watch_signals(gd)

	var edited: Dictionary = _read_json("structures.json")
	edited["b_cell"]["cost"]["atp"] = 120
	_write_temp_data(JSON.stringify(edited))
	assert_true(gd.reload_config())

	assert_ne(gd.config, old_config)
	assert_eq(gd.config.structures["b_cell"].cost["atp"], 120)
	assert_signal_emitted_with_parameters(gd, "config_reloaded", [gd.config])
	assert_signal_not_emitted(gd, "config_reload_failed")


func test_reload_failure_keeps_old_config_and_reports_errors() -> void:
	_write_temp_data()
	var gd: Node = _new_game_data()
	gd.load_data(TEMP_DIR)
	var old_config: GameConfig = gd.config
	watch_signals(gd)

	var broken: Dictionary = _read_json("structures.json")
	broken["macrophage"]["hp"] = -1
	_write_temp_data(JSON.stringify(broken))
	assert_false(gd.reload_config())

	assert_eq(gd.config, old_config)
	assert_signal_not_emitted(gd, "config_reloaded")
	assert_signal_emit_count(gd, "config_reload_failed", 1)
	var errors: PackedStringArray = get_signal_parameters(gd, "config_reload_failed", 0)[0]
	assert_gt(errors.size(), 0)
	assert_true("\n".join(errors).contains("hp"))

	# fixing the file recovers
	_write_temp_data()
	assert_true(gd.reload_config())
	assert_signal_emit_count(gd, "config_reloaded", 1)


func test_reload_recovers_from_invalid_startup_config() -> void:
	var broken: Dictionary = _read_json("structures.json")
	broken["macrophage"]["hp"] = -1
	_write_temp_data(JSON.stringify(broken))
	var gd: Node = _new_game_data()
	gd.load_data(TEMP_DIR)
	assert_push_error("GameData failed to load config")
	assert_null(gd.config)
	assert_false(gd.load_errors.is_empty())

	_write_temp_data()
	assert_true(gd.reload_config())
	assert_not_null(gd.config)
	assert_true(gd.load_errors.is_empty())
