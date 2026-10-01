class_name LivingBaseFlow
extends RefCounted

## Glue between the Session and the persistent Living Base profile (#158): entering the mode,
## writing the player's base, wallet, memory and pools back after every change, collecting
## Mitochondria ATP, and the "Test in Lab" copy. Game layer, so it may read the real-time clock.

var store: LivingBaseStore = null
var session: Session = null
## Messages from loading the profile (reset or trimmed saves). The Synthesis phase shows them once.
var notices: Array[String] = []


func _init(p_store: LivingBaseStore = null) -> void:
	store = p_store if p_store != null else LivingBaseStore.new()


## Loads (or creates) the profile, banks the offline ATP, and loads it into the session.
func enter(p_session: Session) -> void:
	session = p_session
	if session == null or session.config == null:
		return
	var cfg: GameConfig = session.config
	var res: Dictionary = store.load_profile(cfg)
	notices = []
	for n: Variant in res.get("notices", []):
		notices.append(str(n))
	var profile: LivingBaseProfile = res["profile"]
	profile.advance_clock(cfg, LivingBaseStore.now_unix())
	profile.ensure_opponents(cfg)
	session.mode = Session.Mode.LIVING_BASE
	session.profile = profile
	session.living_flow = self
	session.clear_attack_target()
	_apply_profile_to_session()
	store.save_profile(profile)


## True while the session is in Living Base mode with a loaded profile.
func is_active() -> bool:
	return session != null and session.mode == Session.Mode.LIVING_BASE and session.profile != null


## Banks the ATP generated since the last call. Saves only when something was generated.
func tick() -> int:
	if not is_active():
		return 0
	var generated: int = session.profile.advance_clock(session.config, LivingBaseStore.now_unix())
	if generated > 0:
		store.save_profile(session.profile)
	return generated


## Copies the session's base, wallet, memory and pools into the profile and saves it.
func sync_profile_from_session() -> void:
	if not is_active():
		return
	var profile: LivingBaseProfile = session.profile
	# Bank time at the old Mitochondria count before the layout changes the rate.
	profile.advance_clock(session.config, LivingBaseStore.now_unix())
	profile.layout = session.grid.to_layout()
	profile.wallet = session.wallet.to_dict()
	profile.memory = session.memory.to_dict()
	var pools: Dictionary = {}
	for type_id: Variant in session.populations.keys():
		var pool: Variant = session.populations[type_id]
		if pool is BreedPool:
			pools[str(type_id)] = (pool as BreedPool).to_dict()
	profile.populations = pools
	store.save_profile(profile)


## Points the session at an AI base: its layout, memory and structure pools become the attack target.
## Returns false when there is no such opponent.
func begin_raid(opponent_id: String) -> bool:
	if not is_active():
		return false
	var index: int = session.profile.opponent_index(opponent_id)
	if index < 0:
		return false
	var cfg: GameConfig = session.config
	var opp: Dictionary = session.profile.opponents[index]
	var layout: Array[Dictionary] = []
	for entry: Variant in opp.get("layout", []):
		layout.append(entry as Dictionary)
	session.attack_layout = layout
	session.attack_memory = ImmuneMemory.from_dict(opp.get("memory", {}), cfg)
	session.attack_populations = {}
	var pops: Dictionary = opp.get("populations", {})
	for type_id: Variant in pops.keys():
		var tid: String = str(type_id)
		if cfg.is_breeding_type(tid) and cfg.structures.has(tid) and pops[type_id] is Dictionary:
			session.attack_populations[tid] = BreedPool.from_dict(pops[type_id], tid, cfg)
	session.attack_opponent_id = opponent_id
	return true


## True while the session is raiding one of the profile's AI bases.
func has_raid_target() -> bool:
	return is_active() and session.attack_opponent_id != "" and session.profile.opponent_index(session.attack_opponent_id) >= 0


## A raid was launched: count it and save at once, so quitting mid-raid cannot undo the army's cost.
func on_launch() -> void:
	if not has_raid_target():
		return
	session.profile.raid_counter += 1
	sync_profile_from_session()


## Applies a finished raid on an AI base: loot, the base's memory and pool learning, replacement of a
## defeated base, and a save. Returns the RaidResolver result.
func finish_raid(sim: BattleSim) -> Dictionary:
	if not has_raid_target():
		return {}
	var cfg: GameConfig = session.config
	var profile: LivingBaseProfile = session.profile
	var index: int = profile.opponent_index(session.attack_opponent_id)
	var opp: Dictionary = profile.opponents[index]
	var pools: Dictionary = {}
	for type_id: String in cfg.coevo_types:
		pools[type_id] = session.pool_for(type_id)
	var res: Dictionary = RaidResolver.resolve(cfg, session.battle_setup, sim, int(opp.get("stored_atp", 0)), session.defender_memory(), pools)
	for type_id: String in cfg.coevo_types:
		session.store_pool(type_id, pools[type_id])

	# Rewards go through the session wallet, the live copy, then the profile is brought up to date.
	profile.wallet = session.wallet.to_dict()
	profile.apply_raid_result(res)
	for currency: Variant in profile.wallet.keys():
		session.wallet.set_amount(str(currency), int(profile.wallet[currency]))

	opp["memory"] = session.defender_memory().to_dict()
	var opp_pools: Dictionary = {}
	for type_id: Variant in session.attack_populations.keys():
		var pool: Variant = session.attack_populations[type_id]
		if pool is BreedPool:
			opp_pools[str(type_id)] = (pool as BreedPool).to_dict()
	opp["populations"] = opp_pools
	opp["raids"] = int(opp.get("raids", 0)) + 1
	opp["stored_atp"] = maxi(0, int(opp.get("stored_atp", 0)) - int(res["atp_looted"]))
	profile.opponents[index] = opp
	if str(res["outcome"]) == "attacker":
		profile.replace_opponent(session.attack_opponent_id, cfg)
	sync_profile_from_session()
	return res


## Leaves the raid: the attack target is cleared and the profile saved. The army is not refunded.
func end_raid() -> void:
	if session == null:
		return
	session.clear_attack_target()
	if session.army != null:
		session.army.discard_all()
	sync_profile_from_session()


## "Raid again": discards the spent army and re-aims at the same opponent if it still exists. Returns whether it did.
func raid_again() -> bool:
	if not is_active():
		return false
	var id: String = session.attack_opponent_id
	if session.army != null:
		session.army.discard_all()
	if id != "" and begin_raid(id):
		return true
	session.clear_attack_target()
	return false


## Moves the stored Mitochondria ATP into the wallet. Returns the amount collected.
func collect() -> int:
	if not is_active():
		return 0
	var profile: LivingBaseProfile = session.profile
	profile.wallet = session.wallet.to_dict()
	var amount: int = profile.collect()
	if amount > 0:
		session.wallet.set_amount("atp", int(profile.wallet.get("atp", 0)))
	sync_profile_from_session()
	return amount


## "Test in Lab": saves the profile, then turns the session into a Lab session that holds the
## same base and memory. The Lab wallet is the start budget minus the base's cost. The profile
## is not touched again, so nothing done in the Lab reaches the Living Base.
func start_test_in_lab() -> void:
	if not is_active():
		return
	sync_profile_from_session()
	var cfg: GameConfig = session.config
	var base_cost: int = int(session.grid.total_cost().get("atp", 0))
	session.mode = Session.Mode.LAB
	session.profile = null
	session.living_flow = null
	session.clear_attack_target()
	session.army = Army.new(cfg)
	session.wallet.reset(cfg.start_wallet)
	session.wallet.set_amount("atp", maxi(0, int(cfg.start_wallet.get("atp", 0)) - base_cost))
	session.prediction_structure_id = 0
	session.last_result = {}
	session.last_launch = {}


## Picking Lab from the Title after a Living Base session starts the Lab from scratch.
## A session that is already in Lab is left as it is.
static func reset_to_lab(p_session: Session) -> void:
	if p_session == null or p_session.config == null or p_session.mode == Session.Mode.LAB:
		return
	var cfg: GameConfig = p_session.config
	p_session.mode = Session.Mode.LAB
	p_session.profile = null
	p_session.living_flow = null
	p_session.clear_attack_target()
	p_session.grid.reset_with_nucleus()
	p_session.army = Army.new(cfg)
	p_session.wallet.reset(cfg.start_wallet)
	p_session.memory = ImmuneMemory.new()
	p_session.reset_populations()
	p_session.prediction_structure_id = 0
	p_session.last_result = {}
	p_session.last_launch = {}


func _apply_profile_to_session() -> void:
	var cfg: GameConfig = session.config
	var profile: LivingBaseProfile = session.profile
	session.grid.load_layout(profile.layout, LivingBaseProfile.unlimited_wallet())
	session.army = Army.new(cfg)
	session.wallet.reset(profile.wallet)
	session.memory = ImmuneMemory.from_dict(profile.memory, cfg)
	session.reset_populations()
	for type_id: Variant in profile.populations.keys():
		var tid: String = str(type_id)
		if cfg.is_breeding_type(tid) and profile.populations[type_id] is Dictionary:
			session.populations[tid] = BreedPool.from_dict(profile.populations[type_id], tid, cfg)
	session.prediction_structure_id = 0
	session.last_result = {}
	session.last_launch = {}
