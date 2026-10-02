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
var background: AmbientBackground = null
## Online PvP raid: "Raid expires in 9:41" until the server's expiry, then back to base with the army spent.
const EXPIRY_TEXT: String = "Raid expires in %d:%02d"
const EXPIRED_TEXT: String = "Raid expired. Your army was spent."
const EXPIRY_TOP: float = 74.0
const EXPIRY_SIZE: Vector2 = Vector2(240.0, 36.0)
var expiry_pill: PanelContainer = null
var expiry_label: Label = null
## Tests set this to fake the clock; -1 reads the system clock.
var now_unix_override: int = -1
var _expiry_timer: Timer = null
var _expired: bool = false

## Island area between the HUD cards at 1280x720 (mockups 09 and 10): x 320..960, y 96..616.
const ISLAND_INSET_X: float = 320.0
const ISLAND_TOP: float = 96.0
const ISLAND_BOTTOM_INSET: float = 104.0

func _resolve_nodes() -> void:
	if background == null:
		background = AmbientBackground.new()
		background.name = "Background"
		background.night = true
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(background)
		move_child(background, 0)
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
		grid_view.setup(session.attack_grid(), session.config, session.army)
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
		if not hud_spawn.settings_requested.is_connected(_on_settings_requested):
			hud_spawn.settings_requested.connect(_on_settings_requested)
		if not hud_spawn.quit_requested.is_connected(_on_quit_requested):
			hud_spawn.quit_requested.connect(_on_quit_requested)

	if deploy_controller != null and session != null and grid_view != null and hud_spawn != null:
		deploy_controller.setup(session, grid_view, hud_spawn, toast, fsm)
		if not deploy_controller.deployed.is_connected(_on_deployed):
			deploy_controller.deployed.connect(_on_deployed)

	_update_grid_layout()

	_setup_expiry()

	if fsm != null and fsm.previous_phase == GameStateMachine.Phase.SYNTHESIS:
		if side_switch_overlay != null:
			var remaining_atp: int = session.wallet.get_amount("atp") if (session != null and session.wallet != null) else 0
			side_switch_overlay.play(remaining_atp)
	else:
		if side_switch_overlay != null:
			side_switch_overlay.visible = false

## The countdown pill and its one-second timer exist only for an online PvP raid.
func _setup_expiry() -> void:
	_expired = false
	var online_raid: bool = session != null and session.living_flow != null and session.living_flow.has_pvp_raid()
	if expiry_pill != null:
		expiry_pill.visible = online_raid
	if _expiry_timer != null:
		_expiry_timer.stop()
	if not online_raid:
		return
	if expiry_pill == null:
		expiry_pill = PanelContainer.new()
		expiry_pill.name = "ExpiryPill"
		expiry_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		expiry_pill.anchor_left = 0.5
		expiry_pill.anchor_right = 0.5
		expiry_pill.offset_left = -EXPIRY_SIZE.x * 0.5
		expiry_pill.offset_right = EXPIRY_SIZE.x * 0.5
		expiry_pill.offset_top = EXPIRY_TOP
		expiry_pill.offset_bottom = EXPIRY_TOP + EXPIRY_SIZE.y
		var pal: Dictionary = UiPalette.for_theme(true)
		expiry_pill.add_theme_stylebox_override("panel", KitDraw.make_box(pal["panel"] as Color, EXPIRY_SIZE.y * 0.5, 2, pal["panel_border"] as Color))
		expiry_label = Label.new()
		expiry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		expiry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiFonts.style_label(expiry_label, 15, 700, pal["ink"] as Color)
		expiry_pill.add_child(expiry_label)
		add_child(expiry_pill)
	if _expiry_timer == null:
		_expiry_timer = Timer.new()
		_expiry_timer.wait_time = 1.0
		_expiry_timer.one_shot = false
		_expiry_timer.autostart = true  # the phase may not be in the tree yet when setup() runs
		_expiry_timer.timeout.connect(update_expiry)
		add_child(_expiry_timer)
	elif _expiry_timer.is_inside_tree():
		_expiry_timer.start()
	update_expiry()


func _now_unix() -> int:
	return now_unix_override if now_unix_override >= 0 else int(Time.get_unix_time_from_system())


## Refreshes the countdown; at zero the raid is over: the army is reported (and spent) and the player goes home.
func update_expiry() -> void:
	if _expired or session == null or session.living_flow == null or not session.living_flow.has_pvp_raid():
		return
	var remaining: int = session.pvp_expires_unix - _now_unix()
	if remaining > 0:
		expiry_label.text = EXPIRY_TEXT % [remaining / 60, remaining % 60]
		return
	_expired = true
	expiry_label.text = EXPIRED_TEXT
	if _expiry_timer != null:
		_expiry_timer.stop()
	if toast != null:
		toast.show_message(EXPIRED_TEXT)
	var flow: LivingBaseFlow = session.living_flow
	flow.cancel_pvp_raid()
	if session.army != null:
		session.army.discard_all()
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)


## Called by GameStateMachine after a config hot reload was applied (#27).
func on_config_changed(_summary: Dictionary) -> void:
	if session == null:
		return
	if grid_view != null:
		grid_view.setup(session.attack_grid(), session.config, session.army)
	_update_grid_layout()
	if hud_spawn != null:
		hud_spawn.refresh_config()

func _on_help_requested() -> void:
	if fsm != null:
		fsm.how_to_play_requested.emit()

func _on_settings_requested() -> void:
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("settings")

func _on_quit_requested() -> void:
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.TITLE)

func _on_library_requested(kind: String) -> void:
	if fsm != null:
		fsm.library_requested.emit(kind)

func _on_deployed(_type_id: String, _cell: Vector2i) -> void:
	Sfx.play("deploy")

func _on_back_requested() -> void:
	if session != null and session.living_flow != null:
		session.clear_attack_target()
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
		ISLAND_INSET_X,
		ISLAND_TOP,
		maxf(r.size.x - ISLAND_INSET_X * 2.0, 10.0),
		maxf(r.size.y - ISLAND_TOP - ISLAND_BOTTOM_INSET, 10.0)
	)
	grid_view.fit_to_rect(inset_rect)
