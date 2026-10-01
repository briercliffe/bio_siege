class_name IncubationPhase
extends Control

var session: Session = null
var fsm: GameStateMachine = null
## Save library folder for the HUD's save menu entry; GameStateMachine sets it before setup().
var saves_root: String = SaveLibrary.DEFAULT_ROOT

var grid_view: GridView = null
var deploy_controller: DeployController = null
var hud_spawn: HudSpawn = null
var toast: Toast = null
var side_switch_overlay: SideSwitchOverlay = null

func _resolve_nodes() -> void:
	if grid_view == null:
		grid_view = get_node_or_null("GridView") as GridView
	if deploy_controller == null:
		deploy_controller = get_node_or_null("DeployController") as DeployController
	if deploy_controller == null:
		deploy_controller = DeployController.new()
		deploy_controller.name = "DeployController"
		add_child(deploy_controller)
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
		grid_view.setup(session.grid, session.config, session.army)
		grid_view.set_night(true)
		grid_view.deploy_mode = true

	if hud_spawn != null:
		hud_spawn.saves_root = saves_root

	if hud_spawn != null and session != null:
		hud_spawn.setup(session)
		if not hud_spawn.back_requested.is_connected(_on_back_requested):
			hud_spawn.back_requested.connect(_on_back_requested)
		if not hud_spawn.help_requested.is_connected(_on_help_requested):
			hud_spawn.help_requested.connect(_on_help_requested)
		if not hud_spawn.library_requested.is_connected(_on_library_requested):
			hud_spawn.library_requested.connect(_on_library_requested)

	if deploy_controller != null and session != null and grid_view != null and hud_spawn != null:
		deploy_controller.setup(session, grid_view, hud_spawn, toast, fsm)
		if not deploy_controller.deployed.is_connected(_on_deployed):
			deploy_controller.deployed.connect(_on_deployed)

	_update_grid_layout()

	if fsm != null and fsm.previous_phase == GameStateMachine.Phase.SYNTHESIS:
		if side_switch_overlay != null:
			var remaining_atp: int = session.wallet.get_amount("atp") if (session != null and session.wallet != null) else 0
			side_switch_overlay.play(remaining_atp)
	else:
		if side_switch_overlay != null:
			side_switch_overlay.visible = false

## Called by GameStateMachine after a config hot reload was applied (#27).
func on_config_changed(_summary: Dictionary) -> void:
	if session == null:
		return
	if grid_view != null:
		grid_view.setup(session.grid, session.config, session.army)
	_update_grid_layout()
	if hud_spawn != null:
		hud_spawn.refresh_config()

func _on_help_requested() -> void:
	if fsm != null:
		fsm.how_to_play_requested.emit()

func _on_library_requested(kind: String) -> void:
	if fsm != null:
		fsm.library_requested.emit(kind)

func _on_deployed(_type_id: String, _cell: Vector2i) -> void:
	Sfx.play("deploy")

func _on_back_requested() -> void:
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)

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
