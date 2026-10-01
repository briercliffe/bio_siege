class_name LivingBaseFlow
extends RefCounted

## Glue between the Session and the persistent Living Base profile (#158): entering the mode,
## writing the player's base, wallet, memory and pools back after every change, collecting
## Mitochondria ATP, and the "Test in Lab" copy. Game layer, so it may read the real-time clock.

var store: LivingBaseStore = null
var session: Session = null
## Messages from loading the profile (reset or trimmed saves). The Synthesis phase shows them once.
var notices: Array[String] = []
## AI raids that came due while the player was away and are not resolved yet.
var pending_raids: int = 0
## What the resolved away-raids did: {"raids", "held", "atp_lost", "amino_gained"}. Empty when none were due.
var away_summary: Dictionary = {}

var _raids_total: int = 0
var _raids_done: int = 0
var _raids_origin_unix: int = 0
var _raids_now_unix: int = 0


func _init(p_store: LivingBaseStore = null) -> void:
	store = p_store if p_store != null else LivingBaseStore.new()


## Loads (or creates) the profile, banks the offline ATP, and loads it into the session. AI raids that came
## due while the player was away are resolved at once, or left pending with `defer_raids` so the UI can
## resolve them one per frame (resolve_next_raid).
func enter(p_session: Session, defer_raids: bool = false) -> void:
	session = p_session
	if session == null or session.config == null:
		return
	var cfg: GameConfig = session.config
	var res: Dictionary = store.load_profile(cfg)
	notices = []
	for n: Variant in res.get("notices", []):
		notices.append(str(n))
	var profile: LivingBaseProfile = res["profile"]
	var now: int = LivingBaseStore.now_unix()
	profile.advance_clock(cfg, now)
	profile.ensure_opponents(cfg)
	session.mode = Session.Mode.LIVING_BASE
	session.profile = profile
	session.living_flow = self
	session.live_defense = false
	session.clear_attack_target()
	_apply_profile_to_session()
	_plan_away_raids(now)
	if not defer_raids:
		resolve_all_pending()
	store.save_profile(profile)


## True while away-raids are waiting to be resolved.
func has_pending_raids() -> bool:
	return pending_raids > 0


## Resolves the next due AI raid headless (one run_to_end, about 100 ms) and logs it. Raids resolve one after
## another, so each sees what the earlier ones taught the base. Returns false when nothing was pending.
func resolve_next_raid() -> bool:
	if not is_active() or pending_raids <= 0:
		return false
	var cfg: GameConfig = session.config
	var profile: LivingBaseProfile = session.profile
	profile.wallet = session.wallet.to_dict()
	var entry: Dictionary = DefenseRunner.resolve_offline(cfg, profile, profile.ai_raid_counter)
	profile.push_defense_log(entry, cfg)
	_load_defender_state_into_session()
	pending_raids -= 1
	_raids_done += 1
	away_summary["raids"] = _raids_done
	away_summary["held"] = int(away_summary.get("held", 0)) + (1 if str(entry["outcome"]) == "defender" else 0)
	away_summary["atp_lost"] = int(away_summary.get("atp_lost", 0)) + int(entry["atp_lost"])
	away_summary["amino_gained"] = int(away_summary.get("amino_gained", 0)) + int(entry["amino_gained"])
	# Saved after every raid, so an interrupted resolve never repeats a raid.
	if pending_raids == 0:
		profile.last_ai_raid_unix = RaidSchedule.advance(cfg, _raids_origin_unix, _raids_now_unix, _raids_total)
	else:
		profile.last_ai_raid_unix = _raids_origin_unix + _raids_done * cfg.ai_raid_interval_s
	store.save_profile(profile)
	return true


func resolve_all_pending() -> void:
	while resolve_next_raid():
		pass


## "While you were away: 2 raids · 1 held · -80 ATP · +12 Amino Acids". Empty when no raid came due.
func away_summary_text() -> String:
	var raids: int = int(away_summary.get("raids", 0))
	if raids <= 0:
		return ""
	var parts: Array[String] = ["%d raid%s" % [raids, "" if raids == 1 else "s"], "%d held" % int(away_summary.get("held", 0))]
	if int(away_summary.get("atp_lost", 0)) > 0:
		parts.append("-%d ATP" % int(away_summary["atp_lost"]))
	if int(away_summary.get("amino_gained", 0)) > 0:
		parts.append("+%d Amino Acids" % int(away_summary["amino_gained"]))
	return "While you were away: " + " · ".join(parts)


## Plays an AI raid on the player's base live ("Incoming infection"). Sets the battle up and aims the session
## at the player's own base. It does not use up a scheduled raid. Returns false when not in Living Base.
func begin_live_defense() -> bool:
	if not is_active():
		return false
	sync_profile_from_session()
	var cfg: GameConfig = session.config
	var profile: LivingBaseProfile = session.profile
	session.battle_setup = DefenseRunner.build_setup(cfg, profile, profile.ai_raid_counter)
	var layout: Array[Dictionary] = []
	for entry: Dictionary in profile.layout:
		layout.append(entry.duplicate(true))
	session.attack_layout = layout
	session.attack_memory = session.memory
	session.attack_populations = {}
	for type_id: Variant in session.populations.keys():
		if cfg.structures.has(str(type_id)):
			session.attack_populations[type_id] = session.populations[type_id]
	session.attack_opponent_id = ""
	session.army = Army.new(cfg)
	session.prediction_structure_id = 0
	session.last_result = {}
	session.last_launch = {}
	session.live_defense = true
	return true


## Applies a finished live AI raid like an offline one and logs it with `live: true`. Returns the log entry
## (with its replay) so the caller can keep it; the battle log is also in the defense log.
func finish_live_defense(sim: BattleSim) -> Dictionary:
	if not is_active() or not session.live_defense or session.battle_setup == null:
		return {}
	var cfg: GameConfig = session.config
	var profile: LivingBaseProfile = session.profile
	profile.wallet = session.wallet.to_dict()
	var entry: Dictionary = DefenseRunner.apply_result(cfg, profile, session.battle_setup, sim, profile.ai_raid_counter)
	entry["live"] = true
	profile.push_defense_log(entry, cfg)
	_load_defender_state_into_session()
	sync_profile_from_session()
	return entry


## Leaves a live defense: the target and the live flag are cleared and the profile saved.
func end_live_defense() -> void:
	if session == null:
		return
	session.live_defense = false
	session.clear_attack_target()
	session.battle_setup = null
	sync_profile_from_session()


func _plan_away_raids(now: int) -> void:
	var cfg: GameConfig = session.config
	var profile: LivingBaseProfile = session.profile
	_raids_origin_unix = profile.last_ai_raid_unix
	_raids_now_unix = now
	_raids_total = RaidSchedule.due_count(cfg, profile.last_ai_raid_unix, now)
	_raids_done = 0
	pending_raids = _raids_total
	away_summary = {}


## After a defense result changed the profile, brings the live session copies up to date.
func _load_defender_state_into_session() -> void:
	var cfg: GameConfig = session.config
	var profile: LivingBaseProfile = session.profile
	session.memory = ImmuneMemory.from_dict(profile.memory, cfg, BaseUpgrades.memory_slots(cfg, profile.upgrades))
	for type_id: Variant in profile.populations.keys():
		var tid: String = str(type_id)
		if cfg.is_breeding_type(tid) and cfg.structures.has(tid) and profile.populations[type_id] is Dictionary:
			session.populations[tid] = BreedPool.from_dict(profile.populations[type_id], tid, cfg)
	session.wallet.set_amount("amino_acids", int(profile.wallet.get("amino_acids", 0)))


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


## Buys the next level of an Amino Acid upgrade from the live wallet, then saves. Returns whether it was bought.
func buy_upgrade(upgrade_id: String) -> bool:
	if not is_active():
		return false
	if not BaseUpgrades.buy(session.config, session.profile.upgrades, upgrade_id, session.wallet):
		return false
	if upgrade_id == "receptor_slot":
		BaseUpgrades.widen_receptor_pools(session.config, session.populations)
	sync_profile_from_session()
	return true


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
	session.live_defense = false
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
	p_session.live_defense = false
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
	session.memory = ImmuneMemory.from_dict(profile.memory, cfg, BaseUpgrades.memory_slots(cfg, profile.upgrades))
	session.reset_populations()
	for type_id: Variant in profile.populations.keys():
		var tid: String = str(type_id)
		if cfg.is_breeding_type(tid) and profile.populations[type_id] is Dictionary:
			session.populations[tid] = BreedPool.from_dict(profile.populations[type_id], tid, cfg)
	session.prediction_structure_id = 0
	session.last_result = {}
	session.last_launch = {}
