class_name DeployController
extends Node

signal deployed(type_id: String, cell: Vector2i)

## A press shorter than this on a band cell is a tap; a longer one is a hold that keeps deploying.
const TAP_HOLD_S: float = 0.25
const NO_TYPE_TOAST: String = "Select a pathogen card first"

var session: Session = null
var grid_view: GridView = null
var hud: HudSpawn = null
var toast: Toast = null
var fsm: GameStateMachine = null

var selected_type: String = ""
var predict_mode: bool = false

var _is_pressing: bool = false
var _current_cell: Vector2i = Vector2i(-99999, -99999)
var _hold_timer: float = 0.0
var _press_elapsed: float = 0.0
## True once the press has lasted TAP_HOLD_S, so it deploys on an interval instead of recalling.
var _hold_active: bool = false
## True while a press on an occupied cell may still turn out to be a tap that recalls a unit.
var _pending_recall: bool = false

func setup(p_session: Session, p_grid_view: GridView, p_hud: HudSpawn, p_toast: Toast = null, p_fsm: GameStateMachine = null) -> void:
	if hud != null:
		if hud.deploy_type_selected.is_connected(_on_hud_deploy_type_selected):
			hud.deploy_type_selected.disconnect(_on_hud_deploy_type_selected)
		if hud.predict_mode_selected.is_connected(_on_hud_predict_mode_selected):
			hud.predict_mode_selected.disconnect(_on_hud_predict_mode_selected)
		if hud.launch_requested.is_connected(_on_hud_launch_requested):
			hud.launch_requested.disconnect(_on_hud_launch_requested)

	if grid_view != null:
		if grid_view.cell_pressed.is_connected(_on_cell_pressed):
			grid_view.cell_pressed.disconnect(_on_cell_pressed)
		if grid_view.cell_dragged.is_connected(_on_cell_dragged):
			grid_view.cell_dragged.disconnect(_on_cell_dragged)
		if grid_view.cell_released.is_connected(_on_cell_released):
			grid_view.cell_released.disconnect(_on_cell_released)
		if grid_view.press_cancelled.is_connected(_on_press_cancelled):
			grid_view.press_cancelled.disconnect(_on_press_cancelled)

	session = p_session
	grid_view = p_grid_view
	hud = p_hud
	toast = p_toast
	if p_fsm != null:
		fsm = p_fsm

	_is_pressing = false
	_hold_timer = 0.0
	_press_elapsed = 0.0
	_hold_active = false
	_pending_recall = false

	if grid_view != null and session != null:
		grid_view.army = session.army
		if session.prediction_structure_id > 0:
			grid_view.predicted_structure_id = session.prediction_structure_id

	if hud != null:
		hud.deploy_type_selected.connect(_on_hud_deploy_type_selected)
		hud.predict_mode_selected.connect(_on_hud_predict_mode_selected)
		hud.launch_requested.connect(_on_hud_launch_requested)
		if not hud.selected_type_id.is_empty():
			selected_type = hud.selected_type_id
		predict_mode = hud.predict_active

	if grid_view != null:
		grid_view.cell_pressed.connect(_on_cell_pressed)
		grid_view.cell_dragged.connect(_on_cell_dragged)
		grid_view.cell_released.connect(_on_cell_released)
		grid_view.press_cancelled.connect(_on_press_cancelled)

## A pinch took over the touch: abandon the press without recalling or deploying.
func _on_press_cancelled() -> void:
	_is_pressing = false
	_pending_recall = false
	_hold_active = false
	_hold_timer = 0.0
	_press_elapsed = 0.0

func select_deploy_type(type_id: String) -> void:
	selected_type = type_id

## The pathogen type a deploy places: the one picked on the tray, or "" when none is selected.
func _get_effective_deploy_type() -> String:
	if not selected_type.is_empty():
		return selected_type
	if hud != null and not hud.selected_type_id.is_empty():
		return hud.selected_type_id
	return ""

func _on_hud_deploy_type_selected(type_id: String) -> void:
	selected_type = type_id

func _on_hud_predict_mode_selected(on: bool) -> void:
	predict_mode = on

func _deploy_unit(type_id: String, cell: Vector2i) -> bool:
	var ok: bool = session.army.deploy(type_id, cell)
	if ok:
		if SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("unit_deployed", {"type": type_id, "cell": cell})
		deployed.emit(type_id, cell)
	return ok

func _try_deploy(cell: Vector2i) -> bool:
	if session == null or session.grid == null or session.army == null:
		return false

	var type_to_deploy: String = _get_effective_deploy_type()
	if type_to_deploy.is_empty():
		if toast != null:
			toast.show_message(NO_TYPE_TOAST)
		return false

	if session.army.reserve_count(type_to_deploy) > 0:
		return _deploy_unit(type_to_deploy, cell)

	# Reserve == 0, auto-buy if wallet can afford
	if session.wallet != null and session.army.buy(type_to_deploy, session.wallet):
		if SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("unit_bought", {"type": type_to_deploy})
		return _deploy_unit(type_to_deploy, cell)

	# Cannot afford
	if toast != null:
		toast.show_message("Not enough ATP")
	return false

func _on_cell_pressed(cell: Vector2i) -> void:
	if session == null or session.grid == null:
		return

	if predict_mode:
		_is_pressing = false
		if session != null and session.grid != null:
			var sid: int = session.grid.structure_id_at(cell)
			if sid > 0:
				var s: GridModel.PlacedStructure = session.grid.get_structure(sid)
				if s != null:
					session.prediction_structure_id = sid
					if grid_view != null:
						grid_view.predicted_structure_id = sid
					if SessionLogger != null and SessionLogger.has_method("log_event"):
						SessionLogger.log_event("prediction", {
							"structure_id": sid,
							"structure_type": s.type_id
						})
					predict_mode = false
					if hud != null:
						hud.set_predict_mode(false)
		return

	# In deploy mode
	if not session.grid.is_deploy_zone(cell):
		_is_pressing = false
		if toast != null:
			toast.show_message("Deploy on the green ring")
		return

	_is_pressing = true
	_current_cell = cell
	_hold_timer = 0.0
	_press_elapsed = 0.0
	_hold_active = false

	# A press on a cell that already holds units waits to see whether it is a tap (recall) or a hold (deploy).
	_pending_recall = session.army != null and not session.army.deployed_at(cell).is_empty()
	if _pending_recall:
		return

	var ok: bool = _try_deploy(cell)
	if not ok:
		_is_pressing = false

func _on_cell_dragged(cell: Vector2i) -> void:
	if not _is_pressing:
		return
	if cell != _current_cell:
		_pending_recall = false
	_current_cell = cell

func _on_cell_released(_cell: Vector2i) -> void:
	if _is_pressing and _pending_recall and not _hold_active and _press_elapsed < TAP_HOLD_S:
		_recall_at(_current_cell)
	_is_pressing = false
	_pending_recall = false
	_hold_active = false
	_hold_timer = 0.0
	_press_elapsed = 0.0

func _recall_at(cell: Vector2i) -> void:
	if session == null or session.army == null:
		return
	var recalled_type: String = session.army.recall_last_at(cell)
	if not recalled_type.is_empty() and SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("unit_recalled", {"type": recalled_type, "cell": cell})

func _process(delta: float) -> void:
	if not _is_pressing:
		return
	if session == null or session.grid == null or session.config == null:
		return
	_press_elapsed += delta
	var hold_delta: float = delta
	if not _hold_active:
		if _press_elapsed < TAP_HOLD_S:
			return
		# The press became a hold: no recall any more, deploy once, then repeat on the interval.
		_hold_active = true
		_pending_recall = false
		hold_delta = _press_elapsed - TAP_HOLD_S
		_hold_timer = 0.0
		if session.grid.is_deploy_zone(_current_cell) and not _try_deploy(_current_cell):
			_is_pressing = false
			return
	if not session.grid.is_deploy_zone(_current_cell):
		return

	var interval: float = session.config.deploy_hold_interval_s
	if interval <= 0.0:
		interval = 0.1

	_hold_timer += hold_delta
	while _is_pressing and _hold_timer >= interval:
		_hold_timer -= interval
		var ok: bool = _try_deploy(_current_cell)
		if not ok:
			_is_pressing = false
			break

func _on_hud_launch_requested() -> void:
	if session == null or session.grid == null or session.army == null or session.config == null:
		return

	# 1. session.battle_count += 1
	session.battle_count += 1

	# 2. session.seed = session.config.default_seed + session.battle_count
	session.seed = session.config.default_seed + session.battle_count

	# 3. Auto-place leftovers:
	#    var rng := Rng.new(session.seed)
	#    var ring := session.grid.ring_cells()
	#    For each type in session.config.pathogen_ids() (alphabetical order):
	#      while session.army.reserve_count(type) > 0:
	#        session.army.deploy(type, ring[rng.next_int(ring.size())])
	var rng := Rng.new(session.seed)
	var ring: Array[Vector2i] = session.grid.ring_cells()
	if not ring.is_empty():
		var p_ids: Array[String] = session.config.pathogen_ids()
		p_ids.sort()
		for type_id: String in p_ids:
			while session.army.reserve_count(type_id) > 0:
				var target_cell: Vector2i = ring[rng.next_int(ring.size())]
				session.army.deploy(type_id, target_cell)

	# 4. Build setup:
	#    session.battle_setup = BattleSetup.create(session.grid.to_layout(), session.army.deployments.duplicate(true), session.seed)
	var memory_seed: Dictionary = {}
	if session.config.memory_enabled():
		var strain_keys: Array[String] = []
		for dep: Dictionary in session.army.deployments:
			var key: String = "%s/%s" % [str(dep.get("type", "")), str(dep.get("strain", "wild"))]
			if not strain_keys.has(key):
				strain_keys.append(key)
		memory_seed = session.memory.seed_map(strain_keys, session.config)
	var populations: Dictionary = {}
	if session.config.coevolution_enabled():
		for type_id: String in session.config.coevo_types:
			populations[type_id] = session.population(type_id).to_dict()
	session.battle_setup = BattleSetup.create(
		session.grid.to_layout(),
		session.army.deployments.duplicate(true),
		session.seed,
		memory_seed,
		populations
	)
	var army_counts: Dictionary = {}
	for p_id: String in session.config.pathogen_ids():
		var cnt: int = session.army.deployed_count(p_id)
		if cnt > 0:
			army_counts[p_id] = cnt

	session.last_launch = {
		"base_atp": session.grid.total_cost().get("atp", 0),
		"army_atp": session.army.total_cost().get("atp", 0),
		"unspent_atp": session.wallet.get_amount("atp") if session.wallet != null else 0,
		"army_counts": army_counts
	}

	var army_atp_by_type: Dictionary = {}
	for t_id: Variant in army_counts.keys():
		var unit_atp: int = int(session.army.unit_cost(str(t_id)).get("atp", 0))
		army_atp_by_type[str(t_id)] = unit_atp * int(army_counts[t_id])

	var launch_event: Dictionary = {
		"seed": session.seed,
		"army_counts": army_counts,
		"base_atp": session.last_launch.base_atp,
		"army_atp": session.last_launch.army_atp,
		"unspent_atp": session.last_launch.unspent_atp,
		"flags": session.config.feature_flags.duplicate(),
		"army_atp_by_type": army_atp_by_type,
	}
	if session.config != null and session.config.flag("strains"):
		var strains_used: Dictionary = {}
		for t_id: Variant in army_counts.keys():
			strains_used[str(t_id)] = session.army.strain_of(str(t_id))
		session.last_launch["strains"] = strains_used
		launch_event["strains"] = strains_used

	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("launch", launch_event)

	# 5. fsm.request_transition(GameStateMachine.Phase.INFECTION)
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.INFECTION)
