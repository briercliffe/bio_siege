extends GutTest

## The Living Base raid loop (#161), headless: pick an AI base, buy an army, launch, finish, loot, learn.

const DIR: String = "user://test_lb_raid"

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


## Buys `count` rhinoviruses and launches, like the Incubation HUD's Launch button.
func _launch(session: Session, count: int = 30) -> void:
	for i: int in range(count):
		assert_true(session.army.buy("rhinovirus", session.wallet))
	var dc := DeployController.new()
	add_child_autoqfree(dc)
	var gv := GridView.new()
	add_child_autoqfree(gv)
	gv.setup(session.attack_grid(), session.config, session.army)
	dc.setup(session, gv, null, null, null)
	dc._on_hud_launch_requested()


func _finished_sim(session: Session, outcome: String) -> BattleSim:
	var sim := BattleSim.new(session.config, session.battle_setup)
	sim.finished = true
	sim.outcome = outcome
	sim.end_reason = "nucleus_destroyed" if outcome == "attacker" else "timeout"
	sim._survival_granted = true
	return sim


func _finish(session: Session, sim: BattleSim) -> void:
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._on_battle_finished(sim)


func _saved_profile() -> LivingBaseProfile:
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(_store.path))
	return LivingBaseProfile.from_dict(json, _cfg)["profile"]


func _destroy(sim: BattleSim, type_id: String) -> void:
	for s: StructureState in sim.structures:
		if s.type_id == type_id:
			s.alive = false


func test_launch_spends_the_army_and_saves_at_once() -> void:
	var session: Session = _enter()
	var opp_id: String = str(session.profile.opponents[0]["id"])
	assert_true(session.living_flow.begin_raid(opp_id))
	var before: int = session.wallet.get_amount("atp")
	_launch(session)
	assert_eq(session.wallet.get_amount("atp"), before - 300)
	assert_eq(session.profile.raid_counter, 1)
	var saved: LivingBaseProfile = _saved_profile()
	assert_eq(saved.raid_counter, 1)
	assert_eq(int(saved.wallet["atp"]), before - 300, "the army cost survives a restart")
	assert_eq(session.battle_setup.structures.size(), (session.profile.opponents[0]["layout"] as Array).size())


func test_attacker_win_loots_and_replaces_the_base() -> void:
	var session: Session = _enter()
	var opp_id: String = str(session.profile.opponents[0]["id"])
	session.living_flow.begin_raid(opp_id)
	_launch(session)
	var after_buy: int = session.wallet.get_amount("atp")
	var sim: BattleSim = _finished_sim(session, "attacker")
	_destroy(sim, "mitochondria")
	_finish(session, sim)
	var res: Dictionary = session.last_result["living_base"]
	assert_eq(res["outcome"], "attacker")
	assert_eq(res["atp_looted"], 75, "50% of the 150 stored ATP")
	assert_gt(int(res["amino_attacker"]), 0)
	assert_eq(session.wallet.get_amount("atp"), after_buy + 75)
	assert_eq(session.wallet.get_amount("amino_acids"), int(res["amino_attacker"]))
	assert_ne(str(session.profile.opponents[0]["id"]), opp_id, "a beaten base is replaced")
	assert_eq(int(session.profile.opponents[0]["raids"]), 0)
	var saved: LivingBaseProfile = _saved_profile()
	assert_eq(int(saved.wallet["atp"]), after_buy + 75)
	assert_eq(str(saved.opponents[0]["id"]), str(session.profile.opponents[0]["id"]))


func test_defender_win_teaches_the_base() -> void:
	_cfg.feature_flags["immune_memory"] = true
	_cfg.feature_flags["bcell_analysis"] = true
	var session: Session = _enter()
	var opp_id: String = str(session.profile.opponents[0]["id"])
	session.living_flow.begin_raid(opp_id)
	_launch(session)
	var sim: BattleSim = _finished_sim(session, "defender")
	sim.structures[0].analyzed["rhinovirus/wild"] = true
	_finish(session, sim)
	var opp: Dictionary = session.profile.opponents[0]
	assert_eq(str(opp["id"]), opp_id, "not replaced")
	assert_eq(int(opp["raids"]), 1)
	assert_eq(int((opp["memory"] as Dictionary)["entries"]["rhinovirus/wild"]["level"]), 1)
	assert_eq(session.last_result["memory_changes"].size(), 1)
	assert_eq(int(session.last_result["living_base"]["atp_looted"]), 0)
	var saved: LivingBaseProfile = _saved_profile()
	assert_eq(int(saved.opponents[0]["raids"]), 1)
	# Raiding again shows the base what it remembers.
	assert_true(session.living_flow.raid_again())
	assert_eq(session.attack_memory.level_of("rhinovirus/wild"), 1)


func test_the_bases_macrophage_pool_breeds_every_raid() -> void:
	_cfg.feature_flags["coevolution"] = true
	var session: Session = _enter()
	var opp_id: String = str(session.profile.opponents[0]["id"])
	for round_n: int in range(1, 3):
		assert_true(session.living_flow.begin_raid(opp_id))
		_launch(session, 2)
		var sim: BattleSim = _finished_sim(session, "defender")
		sim._pools["macrophage"].fitness[0] = 10
		_finish(session, sim)
		var pool_dict: Dictionary = session.profile.opponents[0]["populations"]["macrophage"]
		assert_eq(int(pool_dict["generation"]), round_n)
		assert_false(session.populations.has("macrophage"), "the player's own pools are separate")
		assert_eq(int((session.populations["rhinovirus"] as BreedPool).generation) >= 0, true)
		session.army.discard_all()


func test_abandoning_keeps_the_army_cost_and_changes_nothing_else() -> void:
	var session: Session = _enter()
	var opp_id: String = str(session.profile.opponents[0]["id"])
	session.living_flow.begin_raid(opp_id)
	_launch(session)
	var after_launch: int = session.wallet.get_amount("atp")
	var opp_before: Dictionary = (session.profile.opponents[0] as Dictionary).duplicate(true)
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._abandon("quit", GameStateMachine.Phase.TITLE)
	assert_eq(session.wallet.get_amount("atp"), after_launch, "no refund")
	assert_eq(session.army.total_count(), 0)
	assert_eq(session.profile.opponents[0], opp_before)
	assert_eq(int(_saved_profile().wallet["atp"]), after_launch)


func test_lab_abandon_still_refunds() -> void:
	var session := Session.new(_cfg)
	for i: int in range(5):
		session.army.buy("rhinovirus", session.wallet)
	var inf := InfectionPhase.new()
	add_child_autoqfree(inf)
	inf.session = session
	inf._abandon("quit", GameStateMachine.Phase.TITLE)
	assert_eq(session.wallet.get_amount("atp"), int(_cfg.start_wallet["atp"]))


func test_back_from_incubation_before_launch_still_refunds() -> void:
	var session: Session = _enter()
	session.living_flow.begin_raid(str(session.profile.opponents[0]["id"]))
	var before: int = session.wallet.get_amount("atp")
	for i: int in range(5):
		session.army.buy("rhinovirus", session.wallet)
	var hud := HudSpawn.new()
	add_child_autofree(hud)
	hud.setup(session)
	hud._on_back_pressed()
	assert_eq(session.wallet.get_amount("atp"), before)
