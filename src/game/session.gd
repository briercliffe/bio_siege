class_name Session
extends RefCounted

var config: GameConfig = null
var wallet: Wallet = null
var grid: GridModel = null
var army: Army = null
var seed: int = 0
var battle_count: int = 0
var battle_setup: BattleSetup = null
var last_result: Dictionary = {}          # filled by #20, shown by #22
var last_launch: Dictionary = {}
var prediction_structure_id: int = 0      # filled by #25
var memory: ImmuneMemory = ImmuneMemory.new()  # immune_memory flag: strains learned across raids
var populations: Dictionary = {}          # coevolution flag: type_id -> BreedPool, kept across raids
var best_score: int = 0                   # raid_score flag: best score this session (not persisted)
var intent_lines_enabled: bool = true
var pending_config: GameConfig = null     # hot-reloaded config queued during INFECTION (#27)

func _init(p_config: GameConfig = null, settings_path: String = GameSettings.DEFAULT_PATH) -> void:
	config = p_config
	if config != null:
		seed = config.default_seed
		intent_lines_enabled = SettingsApply.intent_lines_default(config, settings_path)
		wallet = Wallet.new(config.start_wallet)
		grid = GridModel.new(config)
		grid.reset_with_nucleus()
		army = Army.new(config)


## The stored pool for a breeding type, or a wild pool when none is stored.
## Null when the type does not breed or there is no config.
func population(type_id: String) -> BreedPool:
	if config == null or not config.is_breeding_type(type_id):
		return null
	var stored: Variant = populations.get(type_id, null)
	if stored is BreedPool:
		return stored
	return BreedPool.wild_pool(type_id, config)


func reset_populations() -> void:
	populations.clear()


## Applies a hot-reloaded config to the running session (issue #27 apply rules).
## Must not be called mid-battle; GameStateMachine queues the config in
## pending_config during INFECTION and applies it when that phase ends.
func apply_new_config(new_config: GameConfig) -> Dictionary:
	var notices: Array[String] = []
	var summary: Dictionary = {
		"changed_values": 0,
		"base_reset": false,
		"removed_structures": 0,
		"removed_units": 0,
		"over_budget": false,
		"atp": 0,
		"notices": notices,
		"message": "",
	}
	pending_config = null
	if new_config == null:
		return summary

	var old_config: GameConfig = config
	if old_config != null:
		summary["changed_values"] = ConfigDiff.count_changed_leaves(old_config.source_data, new_config.source_data)
	config = new_config
	if new_config.memory_enabled():
		memory.clamp_to(new_config)
	if new_config.coevolution_enabled():
		var rebuilt: Dictionary = {}
		for type_id: Variant in populations.keys():
			var tid: String = str(type_id)
			if new_config.is_breeding_type(tid):
				rebuilt[tid] = BreedPool.from_dict((populations[type_id] as BreedPool).to_dict(), tid, new_config)
		populations = rebuilt
	if grid == null or wallet == null or army == null:
		summary["message"] = _reload_message(int(summary["changed_values"]), notices)
		return summary

	var grid_changed: bool = grid.width != new_config.grid_width or grid.height != new_config.grid_height or grid.deploy_ring != new_config.deploy_ring
	var core_changed: bool = old_config != null and old_config.core_structure_id() != new_config.core_structure_id()
	grid.set_config(new_config)
	army.set_config(new_config)

	if grid_changed or core_changed:
		army.refund_all(null)
		wallet.reset(new_config.start_wallet)
		grid.reset_with_nucleus()
		prediction_structure_id = 0
		summary["base_reset"] = true
		notices.append("Grid size changed: base reset" if grid_changed else "Core structure changed: base reset")
	else:
		var removed_structures: int = grid.remove_unknown_structures()
		var removed_units: int = army.remove_unknown_types()
		summary["removed_structures"] = removed_structures
		summary["removed_units"] = removed_units
		if removed_structures > 0:
			notices.append("Removed %d structures of unknown type" % removed_structures)
		if removed_units > 0:
			notices.append("Removed %d units of unknown type" % removed_units)
		if prediction_structure_id > 0 and grid.get_structure(prediction_structure_id) == null:
			prediction_structure_id = 0
		_recompute_wallet()
		if _is_over_budget():
			summary["over_budget"] = true
			notices.append("Your base and army now cost more than your budget")

	summary["atp"] = wallet.get_amount("atp")
	summary["message"] = _reload_message(int(summary["changed_values"]), notices)
	return summary


## wallet = start budget - cost(layout) - cost(army), all at the current config's prices.
func _recompute_wallet() -> void:
	var base_cost: Dictionary = grid.total_cost()
	var army_cost: Dictionary = army.total_cost()
	var currencies: Dictionary = {}
	for cur: Variant in config.start_wallet.keys():
		currencies[str(cur)] = true
	for cur: Variant in wallet.to_dict().keys():
		currencies[str(cur)] = true
	for cur: Variant in currencies.keys():
		var currency: String = str(cur)
		var remaining: int = int(config.start_wallet.get(currency, 0)) - int(base_cost.get(currency, 0)) - int(army_cost.get(currency, 0))
		wallet.set_amount(currency, remaining)


func _is_over_budget() -> bool:
	for amount: Variant in wallet.to_dict().values():
		if int(amount) < 0:
			return true
	return false


static func _reload_message(changed_values: int, notices: Array[String]) -> String:
	var text: String = "Config reloaded (%d value%s changed)" % [changed_values, "" if changed_values == 1 else "s"]
	for notice: String in notices:
		text += " · " + notice
	return text
