class_name Session
extends RefCounted

var config: GameConfig = null
var wallet: Wallet = null
var grid: GridModel = null
var army_reserve: Dictionary = {}     # pathogen id -> int count; #11 replaces this with an Army object
var deployments: Array[Dictionary] = []   # [{"type": String, "cell": Vector2i}]; #11 replaces this too
var seed: int = 0
@warning_ignore("untyped_declaration")
var battle_setup = null      # BattleSetup, set by #12 at launch
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
