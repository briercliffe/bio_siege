class_name HudCard
extends TrayCard

## One tool in the Synthesis tray: a structure to build, the Sell tool, or the Move Nucleus tool.
## A kit TrayCard plus the tool bookkeeping the HUD and its tests read.

const SELL_SUBTITLE: String = "100% refund"
const SELL_EMPTY_SUBTITLE: String = "Nothing to sell"
const MOVE_COST_TEXT: String = "Free"

var tool_id: String = ""
var is_sell: bool = false
var is_move_nucleus: bool = false
var cost_atp: int = 0
var is_selected: bool:
	get:
		return selected


func setup_structure(sdef: StructureDef, cfg: GameConfig = null) -> void:
	tool_id = sdef.id
	is_sell = false
	is_move_nucleus = false
	cost_atp = int(sdef.cost.get("atp", 0))
	config = cfg
	variant = TrayCard.Variant.ITEM
	icon_id = sdef.id
	title = sdef.display_name
	cost_text = "%d ATP" % cost_atp


func setup_sell() -> void:
	tool_id = "sell"
	is_sell = true
	is_move_nucleus = false
	cost_atp = 0
	variant = TrayCard.Variant.SELL
	title = "Sell"
	subtitle = SELL_SUBTITLE


func setup_move_nucleus(core_def: StructureDef, cfg: GameConfig = null) -> void:
	tool_id = BuildController.TOOL_MOVE_NUCLEUS
	is_sell = false
	is_move_nucleus = true
	cost_atp = 0
	config = cfg
	variant = TrayCard.Variant.ITEM
	icon_id = core_def.id if core_def != null else "nucleus"
	title = "Move Nucleus"
	cost_text = MOVE_COST_TEXT


## True for cards that build a structure (as opposed to the Sell and Move Nucleus tools).
func is_structure_card() -> bool:
	return not is_sell and not is_move_nucleus


## Muted and not tappable while the wallet cannot pay for the structure.
func update_affordability(wallet_atp: int) -> void:
	set_affordable(not (is_structure_card() and cost_atp > wallet_atp))


## "100% refund" while there is something to sell, "Nothing to sell" on a fresh base.
func update_sellable(has_pieces: bool) -> void:
	if is_sell:
		subtitle = SELL_SUBTITLE if has_pieces else SELL_EMPTY_SUBTITLE
