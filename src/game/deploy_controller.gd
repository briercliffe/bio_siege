class_name DeployController
extends Node

var session: Session = null
var grid_view: GridView = null
var hud: HudSpawn = null
var toast: Toast = null
var fsm: GameStateMachine = null

var selected_type: String = ""
var recall_mode: bool = false

var _is_pressing: bool = false
var _current_cell: Vector2i = Vector2i(-99999, -99999)
var _hold_timer: float = 0.0

func setup(p_session: Session, p_grid_view: GridView, p_hud: HudSpawn, p_toast: Toast = null, p_fsm: GameStateMachine = null) -> void:
	if hud != null:
		if hud.deploy_type_selected.is_connected(_on_hud_deploy_type_selected):
			hud.deploy_type_selected.disconnect(_on_hud_deploy_type_selected)
		if hud.recall_tool_selected.is_connected(_on_hud_recall_tool_selected):
			hud.recall_tool_selected.disconnect(_on_hud_recall_tool_selected)
		if hud.launch_requested.is_connected(_on_hud_launch_requested):
			hud.launch_requested.disconnect(_on_hud_launch_requested)

	if grid_view != null:
		if grid_view.cell_pressed.is_connected(_on_cell_pressed):
			grid_view.cell_pressed.disconnect(_on_cell_pressed)
		if grid_view.cell_dragged.is_connected(_on_cell_dragged):
			grid_view.cell_dragged.disconnect(_on_cell_dragged)
		if grid_view.cell_released.is_connected(_on_cell_released):
			grid_view.cell_released.disconnect(_on_cell_released)

	session = p_session
	grid_view = p_grid_view
	hud = p_hud
	toast = p_toast
	if p_fsm != null:
		fsm = p_fsm

	_is_pressing = false
	_hold_timer = 0.0

	if grid_view != null and session != null:
		grid_view.army = session.army

	if hud != null:
		hud.deploy_type_selected.connect(_on_hud_deploy_type_selected)
		hud.recall_tool_selected.connect(_on_hud_recall_tool_selected)
		hud.launch_requested.connect(_on_hud_launch_requested)
		if not hud.selected_type_id.is_empty():
			selected_type = hud.selected_type_id
		recall_mode = hud.recall_active

	if grid_view != null:
		grid_view.cell_pressed.connect(_on_cell_pressed)
		grid_view.cell_dragged.connect(_on_cell_dragged)
		grid_view.cell_released.connect(_on_cell_released)

func select_deploy_type(type_id: String) -> void:
	selected_type = type_id
	recall_mode = false

func select_recall_tool(on: bool) -> void:
	recall_mode = on

func _get_effective_deploy_type() -> String:
	if not selected_type.is_empty():
		return selected_type
	if hud != null and not hud.selected_type_id.is_empty():
		return hud.selected_type_id
	if session != null and session.army != null:
		for type_id: Variant in session.army.reserve.keys():
			var tid: String = str(type_id)
			if session.army.reserve_count(tid) > 0:
				return tid
	if session != null and session.config != null:
		var p_ids: Array[String] = session.config.pathogen_ids()
		if not p_ids.is_empty():
			return p_ids[0]
	return ""

func _on_hud_deploy_type_selected(type_id: String) -> void:
	selected_type = type_id
	recall_mode = false

func _on_hud_recall_tool_selected(on: bool) -> void:
	recall_mode = on

func _try_deploy(cell: Vector2i) -> bool:
	if session == null or session.grid == null or session.army == null:
		return false

	var type_to_deploy: String = _get_effective_deploy_type()
	if type_to_deploy.is_empty():
		return false

	if session.army.reserve_count(type_to_deploy) > 0:
		return session.army.deploy(type_to_deploy, cell)

	# Reserve == 0, auto-buy if wallet can afford
	if session.wallet != null and session.army.buy(type_to_deploy, session.wallet):
		return session.army.deploy(type_to_deploy, cell)

	# Cannot afford
	if toast != null:
		toast.show_message("Not enough ATP")
	return false

func _on_cell_pressed(cell: Vector2i) -> void:
	if session == null or session.grid == null:
		return

	if recall_mode:
		_is_pressing = false
		if session.grid.is_deploy_zone(cell):
			if session.army != null:
				session.army.recall_last_at(cell)
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

	var ok: bool = _try_deploy(cell)
	if not ok:
		_is_pressing = false

func _on_cell_dragged(cell: Vector2i) -> void:
	if not _is_pressing:
		return
	_current_cell = cell

func _on_cell_released(_cell: Vector2i) -> void:
	_is_pressing = false
	_hold_timer = 0.0

func _process(delta: float) -> void:
	if not _is_pressing:
		return
	if recall_mode:
		return
	if session == null or session.grid == null or session.config == null:
		return
	if not session.grid.is_deploy_zone(_current_cell):
		return

	var interval: float = session.config.deploy_hold_interval_s
	if interval <= 0.0:
		interval = 0.1

	_hold_timer += delta
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
	session.battle_setup = BattleSetup.create(
		session.grid.to_layout(),
		session.army.deployments.duplicate(true),
		session.seed
	)

	# 5. fsm.request_transition(GameStateMachine.Phase.INFECTION)
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.INFECTION)
