class_name HudSpawnCard
extends StepperCard

## One pathogen in the Incubation tray: a night StepperCard (icon, name, cost, - count +) plus the
## bookkeeping the HUD and its tests read. The count is reserve + deployed. `+` buys and is disabled
## when the wallet cannot pay; `-` unbuys from the reserve. Tapping the card body emits `selected`.

signal buy_requested(type_id: String)
signal unbuy_requested(type_id: String)

var type_id: String = ""
var cost_atp: int = 0
var reserve_count: int = 0
var deployed_count: int = 0
var cost_label: Label:
	get:
		return _cost
var name_label: Label:
	get:
		return _name
var is_card_selected: bool:
	get:
		return is_chosen


func _init() -> void:
	super()
	night = true
	plus_pressed.connect(func() -> void: buy_requested.emit(type_id))
	minus_pressed.connect(func() -> void: unbuy_requested.emit(type_id))


func setup_pathogen(p_def: PathogenDef, cfg: GameConfig = null) -> void:
	type_id = p_def.id
	cost_atp = int(p_def.cost.get("atp", 0))
	config = cfg
	setup(p_def.id, p_def.display_name, "%d ATP" % cost_atp, count)


func set_selected(value: bool) -> void:
	set_chosen(value)


func set_unit_cost(atp: int) -> void:
	cost_atp = atp
	_cost.text = "%d ATP" % atp


func update_counts(reserve_cnt: int, deployed_cnt: int) -> void:
	reserve_count = reserve_cnt
	deployed_count = deployed_cnt
	count = reserve_cnt + deployed_cnt
	minus_button.disabled = reserve_cnt <= 0


func update_affordability(wallet_atp: int) -> void:
	plus_enabled = wallet_atp >= cost_atp
