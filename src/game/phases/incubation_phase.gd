class_name IncubationPhase
extends Control

var session: Session = null
var fsm: GameStateMachine = null

var grid_view: GridView = null
var hud_spawn: HudSpawn = null
var toast: Toast = null
var side_switch_overlay: SideSwitchOverlay = null

func _resolve_nodes() -> void:
	if grid_view == null:
		grid_view = get_node_or_null("GridView") as GridView
	if hud_spawn == null:
		hud_spawn = get_node_or_null("HudSpawn") as HudSpawn
	if toast == null:
		toast = get_node_or_null("Toast") as Toast
	if side_switch_overlay == null:
		side_switch_overlay = get_node_or_null("SideSwitchOverlay") as SideSwitchOverlay

func _ready() -> void:
	_resolve_nodes()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if not resized.is_connected(_on_viewport_size_changed):
		resized.connect(_on_viewport_size_changed)
	_update_grid_layout()

func setup(p_session: Session, p_fsm: GameStateMachine) -> void:
	session = p_session
	fsm = p_fsm
	_resolve_nodes()

	if grid_view != null and session != null:
		grid_view.setup(session.grid, session.config)
		grid_view.deploy_mode = true

	if hud_spawn != null and session != null:
		hud_spawn.setup(session)
		if not hud_spawn.back_requested.is_connected(_on_back_requested):
			hud_spawn.back_requested.connect(_on_back_requested)
		if not hud_spawn.launch_requested.is_connected(_on_launch_requested):
			hud_spawn.launch_requested.connect(_on_launch_requested)

	_update_grid_layout()

	if fsm != null and fsm.previous_phase == GameStateMachine.Phase.SYNTHESIS:
		if side_switch_overlay != null:
			var remaining_atp: int = session.wallet.get_amount("atp") if (session != null and session.wallet != null) else 0
			side_switch_overlay.play(remaining_atp)
	else:
		if side_switch_overlay != null:
			side_switch_overlay.visible = false

func _on_back_requested() -> void:
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)

func _on_launch_requested() -> void:
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.INFECTION)

func _on_viewport_size_changed() -> void:
	_update_grid_layout()

func _update_grid_layout() -> void:
	if grid_view == null:
		return
	var r: Rect2 = get_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		if get_viewport() != null:
			r = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		else:
			r = Rect2(0.0, 0.0, 1280.0, 720.0)

	var inset_rect: Rect2 = Rect2(
		0.0,
		64.0,
		maxf(r.size.x, 10.0),
		maxf(r.size.y - 224.0, 10.0)
	)
	grid_view.fit_to_rect(inset_rect)
