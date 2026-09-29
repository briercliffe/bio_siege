class_name SynthesisPhase
extends Control

var session: Session = null
var fsm: GameStateMachine = null

var grid_view: GridView = null
var build_controller: BuildController = null
var toast: Toast = null

func _resolve_nodes() -> void:
	if grid_view == null:
		grid_view = get_node_or_null("GridView") as GridView
	if build_controller == null:
		build_controller = get_node_or_null("BuildController") as BuildController
	if toast == null:
		toast = get_node_or_null("Toast") as Toast

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
		if not build_controller.sold.is_connected(_on_sold):
			build_controller.sold.connect(_on_sold)

	_update_grid_layout()

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

	var padding: float = 20.0
	var inset_rect: Rect2 = Rect2(
		r.position.x + padding,
		r.position.y + padding + 40.0,
		maxf(r.size.x - padding * 2.0, 10.0),
		maxf(r.size.y - padding * 2.0 - 40.0, 10.0)
	)
	grid_view.fit_to_rect(inset_rect)

func _on_place_failed(reason: int) -> void:
	if toast == null:
		return
	var msg: String = Toast.message_for_place_error(reason)
	if not msg.is_empty():
		toast.show_message(msg)

func _on_sold(_type_id: String, refund: Dictionary, cell: Vector2i) -> void:
	if toast == null:
		return
	var atp: int = int(refund.get("atp", 0))
	if atp > 0 and grid_view != null:
		var center_pos: Vector2 = grid_view.to_global(grid_view.cell_to_local_center(cell))
		toast.show_floating_text("+%d ATP" % atp, center_pos)
