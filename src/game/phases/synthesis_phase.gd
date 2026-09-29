class_name SynthesisPhase
extends Control

var session: Session = null
var fsm: GameStateMachine = null

var grid_view: GridView = null
var build_controller: BuildController = null
var toast: Toast = null
var hud_build: HudBuild = null

func _resolve_nodes() -> void:
	if grid_view == null:
		grid_view = get_node_or_null("GridView") as GridView
	if build_controller == null:
		build_controller = get_node_or_null("BuildController") as BuildController
	if toast == null:
		toast = get_node_or_null("Toast") as Toast
	if hud_build == null:
		hud_build = get_node_or_null("HudBuild") as HudBuild

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

	if build_controller != null and session != null and grid_view != null:
		build_controller.setup(session, grid_view)
		if not build_controller.place_failed.is_connected(_on_place_failed):
			build_controller.place_failed.connect(_on_place_failed)
		if not build_controller.placed.is_connected(_on_placed):
			build_controller.placed.connect(_on_placed)
		if not build_controller.sold.is_connected(_on_sold):
			build_controller.sold.connect(_on_sold)

	if hud_build != null and session != null and build_controller != null:
		hud_build.setup(session, build_controller)
		if not hud_build.finalize_requested.is_connected(_on_finalize_requested):
			hud_build.finalize_requested.connect(_on_finalize_requested)
		if not hud_build.help_requested.is_connected(_on_help_requested):
			hud_build.help_requested.connect(_on_help_requested)

	_update_grid_layout()

## Called by GameStateMachine after a config hot reload was applied (#27).
func on_config_changed(_summary: Dictionary) -> void:
	if session == null:
		return
	if grid_view != null:
		grid_view.setup(session.grid, session.config)
	_update_grid_layout()
	if hud_build != null:
		hud_build.refresh_config()

func _on_finalize_requested() -> void:
	if session != null and SessionLogger != null and SessionLogger.has_method("log_event"):
		var atp_rem: int = session.wallet.get_amount("atp") if session.wallet != null else 0
		var b_cost: int = session.grid.total_cost().get("atp", 0) if session.grid != null else 0
		var counts: Dictionary = {}
		var walls: int = 0
		var occupied: int = 0
		if session.grid != null:
			for s in session.grid.structures():
				counts[s.type_id] = int(counts.get(s.type_id, 0)) + 1
				var sdef: StructureDef = session.config.structures.get(s.type_id) if session.config != null else null
				if sdef != null and sdef.has_tag("wall"):
					walls += 1
				occupied += s.footprint.x * s.footprint.y
		var buildable: int = 0
		if session.grid != null:
			for y in range(session.grid.height):
				for x in range(session.grid.width):
					if session.grid.is_buildable_cell(Vector2i(x, y)):
						buildable += 1
		var occ_pct: float = 0.0
		if buildable > 0:
			occ_pct = roundf(float(occupied) / float(buildable) * 1000.0) / 10.0

		SessionLogger.log_event("finalize_base", {
			"atp_remaining": atp_rem,
			"base_cost": b_cost,
			"counts_by_type": counts,
			"walls_placed": walls,
			"occupancy_pct": occ_pct
		})

	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.INCUBATION)

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
		maxf(r.size.y - 204.0, 10.0)
	)
	grid_view.fit_to_rect(inset_rect)

func _on_place_failed(reason: int) -> void:
	if toast == null:
		return
	var msg: String = Toast.message_for_place_error(reason)
	if not msg.is_empty():
		toast.show_message(msg)

func _on_help_requested() -> void:
	if fsm != null:
		fsm.how_to_play_requested.emit()

func _on_placed(_type_id: String, _cell: Vector2i) -> void:
	Sfx.play("place")

func _on_sold(_type_id: String, refund: Dictionary, cell: Vector2i) -> void:
	Sfx.play("sell")
	if toast == null:
		return
	var atp: int = int(refund.get("atp", 0))
	if atp > 0 and grid_view != null:
		var center_pos: Vector2 = grid_view.to_global(grid_view.cell_to_local_center(cell))
		toast.show_floating_text("+%d ATP" % atp, center_pos)
