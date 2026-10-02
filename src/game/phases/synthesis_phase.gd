class_name SynthesisPhase
extends Control

var session: Session = null
var fsm: GameStateMachine = null
## Save library folder for the HUD's save menu entry; GameStateMachine sets it before setup().
var saves_root: String = SaveLibrary.DEFAULT_ROOT

var grid_view: GridView = null
var build_controller: BuildController = null
var toast: Toast = null
var hud_build: HudBuild = null
var background: AmbientBackground = null
## Living Base: the "Resolving raids..." card and then the "While you were away" summary.
var away_overlay: DimOverlay = null
var away_card: FloatingCard = null
var away_label: Label = null
var away_buttons: HBoxContainer = null
var btn_away_ok: PillButton = null
var btn_away_log: PillButton = null

## Island area between the HUD cards at 1280x720 (mockups 05 to 07): x 320..960, y 96..616.
const ISLAND_INSET_X: float = 320.0
const ISLAND_TOP: float = 96.0
const ISLAND_BOTTOM_INSET: float = 104.0

func _resolve_nodes() -> void:
	if background == null:
		background = AmbientBackground.new()
		background.name = "Background"
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(background)
		move_child(background, 0)
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
		grid_view.set_night(false)

	if build_controller != null and session != null and grid_view != null:
		build_controller.setup(session, grid_view)
		if not build_controller.place_failed.is_connected(_on_place_failed):
			build_controller.place_failed.connect(_on_place_failed)
		if not build_controller.placed.is_connected(_on_placed):
			build_controller.placed.connect(_on_placed)
		if not build_controller.sold.is_connected(_on_sold):
			build_controller.sold.connect(_on_sold)
		if not build_controller.undone.is_connected(_on_undone):
			build_controller.undone.connect(_on_undone)
		if not build_controller.nucleus_moved.is_connected(_on_nucleus_moved):
			build_controller.nucleus_moved.connect(_on_nucleus_moved)

	if hud_build != null:
		hud_build.saves_root = saves_root

	_show_living_base_notices()
	_connect_online_flow()
	_begin_away_raids()

	if hud_build != null and session != null and build_controller != null:
		hud_build.setup(session, build_controller)
		if not hud_build.finalize_requested.is_connected(_on_finalize_requested):
			hud_build.finalize_requested.connect(_on_finalize_requested)
		if not hud_build.help_requested.is_connected(_on_help_requested):
			hud_build.help_requested.connect(_on_help_requested)
		if not hud_build.library_requested.is_connected(_on_library_requested):
			hud_build.library_requested.connect(_on_library_requested)
		if not hud_build.settings_requested.is_connected(_on_settings_requested):
			hud_build.settings_requested.connect(_on_settings_requested)
		if not hud_build.quit_requested.is_connected(_on_quit_requested):
			hud_build.quit_requested.connect(_on_quit_requested)
		if not hud_build.test_in_lab_requested.is_connected(_on_test_in_lab_requested):
			hud_build.test_in_lab_requested.connect(_on_test_in_lab_requested)
		if not hud_build.raid_requested.is_connected(_on_raid_requested):
			hud_build.raid_requested.connect(_on_raid_requested)
		if not hud_build.incoming_infection_requested.is_connected(_on_incoming_infection_requested):
			hud_build.incoming_infection_requested.connect(_on_incoming_infection_requested)
		if not hud_build.upgrades_requested.is_connected(_on_upgrades_requested):
			hud_build.upgrades_requested.connect(_on_upgrades_requested)
		if not hud_build.mutation_lab_requested.is_connected(_on_mutation_lab_requested):
			hud_build.mutation_lab_requested.connect(_on_mutation_lab_requested)
		if not hud_build.leaderboard_requested.is_connected(_on_leaderboard_requested):
			hud_build.leaderboard_requested.connect(_on_leaderboard_requested)
		if not hud_build.defense_log_requested.is_connected(_on_defense_log_requested):
			hud_build.defense_log_requested.connect(_on_defense_log_requested)

	_update_grid_layout()

func _exit_tree() -> void:
	_sync_living_base()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_sync_living_base()


## Writes the player's base, wallet, memory and pools to the Living Base profile (Living Base mode only).
func _sync_living_base() -> void:
	if session != null and session.living_flow != null:
		session.living_flow.sync_profile_from_session()
		if session.living_flow.is_online():
			# Fire and forget: the flow outlives this phase and reports a rejection through its message signal.
			session.living_flow.commit_if_dirty()


## Online: server messages (a rejected save) become toasts, and the first online visit may offer the offline base.
func _connect_online_flow() -> void:
	if session == null or session.living_flow == null or not session.living_flow.is_online():
		return
	var flow: LivingBaseFlow = session.living_flow
	if not flow.message.is_connected(_on_flow_message):
		flow.message.connect(_on_flow_message)
	if flow.import_offer_pending and hud_build != null:
		hud_build.offer_import_online()


func _on_flow_message(text: String) -> void:
	if toast != null:
		toast.show_message(text)


## Shows what loading the profile reported (a reset or trimmed save), once.
func _show_living_base_notices() -> void:
	if session == null or session.living_flow == null or toast == null:
		return
	for notice: String in session.living_flow.notices:
		toast.show_message(notice)
	session.living_flow.notices = []


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
		ISLAND_INSET_X,
		ISLAND_TOP,
		maxf(r.size.x - ISLAND_INSET_X * 2.0, 10.0),
		maxf(r.size.y - ISLAND_TOP - ISLAND_BOTTOM_INSET, 10.0)
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

func _on_settings_requested() -> void:
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("settings")

## Living Base: the Defense log button opens the log of AI raids over Synthesis.
func _on_defense_log_requested() -> void:
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("defense_log")


## Living Base: the Upgrades button opens the Amino Acid upgrades screen over Synthesis.
func _on_mutation_lab_requested() -> void:
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("mutation_lab")


func _on_leaderboard_requested() -> void:
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("leaderboard")


func _on_upgrades_requested() -> void:
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("upgrades")


## Living Base: "Incoming infection" plays an AI raid on the base now, straight into Infection.
func _on_incoming_infection_requested() -> void:
	if session == null or session.living_flow == null or not session.living_flow.begin_live_defense():
		return
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.INFECTION)


## AI raids that came due while the player was away resolve one per frame behind a card, so the app does not
## freeze (one raid takes about 100 ms).
func _begin_away_raids() -> void:
	if session == null or session.living_flow == null:
		return
	if not session.living_flow.has_pending_raids() and session.unseen_away_summary.is_empty():
		return
	away_overlay = DimOverlay.new()
	away_overlay.name = "AwayOverlay"
	add_child(away_overlay)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	away_overlay.add_child(center)
	away_card = FloatingCard.new()
	away_card.name = "AwayCard"
	center.add_child(away_card)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	away_card.add_child(box)
	away_label = Label.new()
	away_label.name = "AwayLabel"
	away_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	away_label.custom_minimum_size = Vector2(360.0, 0.0)
	UiFonts.style_label(away_label, 18, 700, UiPalette.color(false, "ink"))
	box.add_child(away_label)
	away_buttons = HBoxContainer.new()
	away_buttons.name = "AwayButtons"
	away_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	away_buttons.add_theme_constant_override("separation", 12)
	away_buttons.visible = false
	box.add_child(away_buttons)
	btn_away_ok = PillButton.new("OK", PillButton.Variant.PRIMARY)
	btn_away_ok.name = "BtnAwayOk"
	btn_away_ok.pressed.connect(_close_away_card)
	away_buttons.add_child(btn_away_ok)
	btn_away_log = PillButton.new("View log", PillButton.Variant.SECONDARY)
	btn_away_log.name = "BtnAwayLog"
	btn_away_log.visible = false
	btn_away_log.pressed.connect(_on_away_log_pressed)
	away_buttons.add_child(btn_away_log)
	_update_away_label()
	set_process(true)


func _process(_delta: float) -> void:
	if away_card == null or session == null or session.living_flow == null:
		set_process(false)
		return
	if session.living_flow.has_pending_raids():
		session.living_flow.resolve_next_raid()
		_update_away_label()
		return
	_show_away_summary()
	set_process(false)


func _update_away_label() -> void:
	var flow: LivingBaseFlow = session.living_flow
	var done: int = int(flow.away_summary.get("raids", 0))
	away_label.text = "Resolving raids... %d of %d" % [done, done + flow.pending_raids]


func _show_away_summary() -> void:
	away_label.text = session.living_flow.away_summary_text()
	away_buttons.visible = true
	# "View log" appears once the Defense log screen exists (LB-17).
	btn_away_log.visible = fsm != null and fsm.screen_stack != null and fsm.screen_stack.scene_paths.has("defense_log")


func _on_away_log_pressed() -> void:
	_close_away_card()
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("defense_log")


func _close_away_card() -> void:
	if session != null and session.living_flow != null and not session.living_flow.has_pending_raids():
		session.unseen_away_summary = {}
	if away_overlay != null:
		away_overlay.queue_free()
		away_overlay = null
		away_card = null


## Living Base: the Raid button opens the opponent picker over Synthesis.
func _on_raid_requested() -> void:
	_sync_living_base()
	if fsm != null and fsm.screen_stack != null:
		fsm.screen_stack.push("opponents")


func _on_test_in_lab_requested() -> void:
	if session == null or session.living_flow == null:
		return
	session.living_flow.start_test_in_lab()
	if fsm != null:
		fsm.force_transition(GameStateMachine.Phase.SYNTHESIS)


func _on_quit_requested() -> void:
	_sync_living_base()
	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.TITLE)

func _on_library_requested(kind: String) -> void:
	if fsm != null:
		fsm.library_requested.emit(kind)

func _on_placed(_type_id: String, _cell: Vector2i) -> void:
	Sfx.play("place")
	_sync_living_base()

func _on_nucleus_moved(_from: Vector2i, _to: Vector2i) -> void:
	Sfx.play("place")
	_sync_living_base()

func _on_undone(_count: int, refund: Dictionary, cell: Vector2i) -> void:
	_on_sold("", refund, cell)

func _on_sold(_type_id: String, refund: Dictionary, cell: Vector2i) -> void:
	Sfx.play("sell")
	_sync_living_base()
	if toast == null:
		return
	var atp: int = int(refund.get("atp", 0))
	if atp > 0 and grid_view != null:
		var center_pos: Vector2 = grid_view.to_global(grid_view.cell_to_local_center(cell))
		toast.show_floating_text("+%d ATP" % atp, center_pos)
