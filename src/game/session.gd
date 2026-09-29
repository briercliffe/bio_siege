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
var prediction_structure_id: int = 0      # filled by #25
var intent_lines_enabled: bool = true

func _init(p_config: GameConfig = null) -> void:
	config = p_config
	if config != null:
		seed = config.default_seed
		intent_lines_enabled = bool(config.feature_flags.get("intent_lines_default", true))
		wallet = Wallet.new(config.start_wallet)
		grid = GridModel.new(config)
		grid.reset_with_nucleus()
		army = Army.new(config)
