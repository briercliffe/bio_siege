class_name Replay
extends RefCounted

## Replay handles headless replay and verification of battle snapshots.
## Pure RefCounted with zero Node/OS/scene dependencies.


static func verify(battle_text: String, config: GameConfig) -> Dictionary:
	var parsed: Dictionary = SnapshotIO.parse_battle(battle_text, config)
	if not parsed.get("ok", false):
		return {
			"ok": false,
			"match": false,
			"error": parsed.get("error", "Failed to parse battle"),
			"expected_hash": "",
			"actual_hash": "",
			"config_matches": false,
		}

	var expected_hash: String = str(parsed.result.get("final_state_hash", ""))
	var expected_outcome: String = str(parsed.result.get("outcome", ""))
	var expected_ticks: int = int(parsed.result.get("ticks", -1))
	var config_matches: bool = (config != null and parsed.config_hash == config.content_hash)

	var setup: BattleSetup = parsed.setup as BattleSetup
	var sim := BattleSim.new(config, setup)
	while not sim.finished:
		sim.step()

	var actual_hash: String = sim.state_hash()
	var hash_match: bool = (actual_hash == expected_hash)
	var outcome_match: bool = (sim.outcome == expected_outcome)
	var ticks_match: bool = (sim.tick == expected_ticks)
	var is_match: bool = hash_match and outcome_match and ticks_match

	var err_msg: String = ""
	if not is_match:
		if not hash_match:
			err_msg = "Hash mismatch: expected %s, got %s" % [expected_hash, actual_hash]
		elif not outcome_match:
			err_msg = "Outcome mismatch: expected %s, got %s" % [expected_outcome, sim.outcome]
		elif not ticks_match:
			err_msg = "Ticks mismatch: expected %d, got %d" % [expected_ticks, sim.tick]

	return {
		"ok": true,
		"match": is_match,
		"error": err_msg,
		"expected_hash": expected_hash,
		"actual_hash": actual_hash,
		"config_matches": config_matches,
	}
