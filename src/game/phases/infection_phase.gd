class_name InfectionPhase
extends Control

const GridViewScene: PackedScene = preload("res://src/view/grid_view.tscn")
const HudCombatScene: PackedScene = preload("res://src/ui/hud_combat.tscn")

var session: Session = null
var fsm: GameStateMachine = null

var grid_view: GridView = null
var runner: BattleRunner = null
var hud_combat: HudCombat = null
var snapshots: BattleSnapshotBuffer = BattleSnapshotBuffer.new()

# Isometric battle layers, back to front: GridView (ground), BiofilmView, UnitLayer, BattleOverlay, EffectLayer.
# UnitLayer also paints the EffectLayer's ground decals under its sprites.
var biofilm_view: BiofilmView = null
var unit_layer: UnitLayer = null
var overlay: BattleOverlay = null
var effect_layer: EffectLayer = null
## Debug rings at impact ticks, behind the "Show impact ticks" toggle (ImpactRings.enabled).
var impact_rings: ImpactRings = null
var effect_model: EffectModel = EffectModel.new()

var _biofilm_changes: int = 0
var _biofilm_max_group: int = 0

## Island area between the HUD cards at 1280x720 (mockup 11): x 320..960, y 96..616.
const ISLAND_INSET_X: float = 320.0
const ISLAND_TOP: float = 96.0
const ISLAND_BOTTOM_INSET: float = 104.0

var background: AmbientBackground = null
var banner_panel: FloatingCard = null
var banner_label: Label = null
var _banner_shown: bool = false

var pause_menu: PauseMenu = null
## The SessionLogger autoload; tests may swap in their own instance.
var logger: Node = null
var _abandoned: bool = false


func _resolve_nodes() -> void:
	if grid_view == null:
		grid_view = get_node_or_null("GridView") as GridView
	if hud_combat == null:
		hud_combat = get_node_or_null("HudCombat") as HudCombat
	if background == null:
		background = AmbientBackground.new()
		background.name = "Background"
		background.night = true
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(background)
		move_child(background, 0)
	if banner_panel == null:
		_build_banner()
	if pause_menu == null:
		pause_menu = PauseMenu.new()
		pause_menu.visible = false
		pause_menu.resume_requested.connect(resume)
		pause_menu.restart_requested.connect(restart_raid)
		pause_menu.settings_requested.connect(open_settings)
		pause_menu.quit_requested.connect(quit_to_menu)
		add_child(pause_menu)


## End-of-battle banner: a night FloatingCard centred over the board. It never takes input.
func _build_banner() -> void:
	var center := CenterContainer.new()
	center.name = "BannerCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	banner_panel = FloatingCard.new()
	banner_panel.name = "BannerPanel"
	banner_panel.night = true
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.visible = false
	center.add_child(banner_panel)
	banner_label = Label.new()
	banner_label.name = "BannerLabel"
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(banner_label, 28, 800, UiPalette.color(true, "ink"))
	banner_panel.add_child(banner_label)


func _ready() -> void:
	add_to_group(SettingsApply.GROUP)
	_resolve_nodes()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if not resized.is_connected(_on_viewport_size_changed):
		resized.connect(_on_viewport_size_changed)
	_update_grid_layout()


func setup(p_session: Session, p_fsm: GameStateMachine) -> void:
	session = p_session
	fsm = p_fsm
	_banner_shown = false
	_abandoned = false

	_resolve_nodes()

	if hud_combat == null:
		hud_combat = HudCombatScene.instantiate() as HudCombat
		add_child(hud_combat)
		move_child(hud_combat, banner_panel.get_parent().get_index())
	if not hud_combat.pause_requested.is_connected(pause):
		hud_combat.pause_requested.connect(pause)
	hud_combat.visible = true
	hud_combat.pause_button.disabled = false
	pause_menu.visible = false

	banner_panel.visible = false

	if grid_view == null:
		grid_view = GridViewScene.instantiate() as GridView
		add_child(grid_view)

	if session != null:
		grid_view.setup(session.grid, session.config, session.army)
	grid_view.set_night(true)
	grid_view.deploy_mode = false
	grid_view.draw_structures = false

	_init_layers()
	var reduce: bool = SettingsApply.reduce_flashes(settings_path)
	unit_layer.reduce_flashes = reduce

	if runner == null:
		runner = BattleRunner.new()
		runner.name = "BattleRunner"
		runner.process_priority = -1
		add_child(runner)
		runner.ticked.connect(_on_runner_ticked)
		runner.battle_finished.connect(_on_battle_finished)
	runner.paused = false
	unit_layer.paused = false

	var cfg: GameConfig = session.config if session != null else null
	var b_setup: BattleSetup = session.battle_setup if session != null else null
	snapshots.reset()
	if cfg != null and b_setup != null:
		runner.start(cfg, b_setup)
		snapshots.capture(runner.sim)

	var sim: BattleSim = runner.sim
	var projection: IsoProjection = grid_view.projection
	unit_layer.setup(sim, cfg, projection, snapshots, runner)
	overlay.setup(sim, cfg, projection, snapshots, runner)
	effect_model.reset()
	effect_layer.session = session
	effect_layer.setup(effect_model, sim, projection, snapshots, runner, reduce)
	unit_layer.effects = effect_layer
	impact_rings.setup(sim, projection, runner)
	if biofilm_view != null:
		biofilm_view.setup(session, runner, snapshots, projection)
	if hud_combat != null:
		hud_combat.setup(session, runner)

	_dispatch_events()
	_update_grid_layout()


## Creates the layer nodes once, directly after GridView so they paint over the ground and under the HUD.
## They share GridView's IsoProjection, so the fit-to-rect layout moves the battle and the island together.
func _init_layers() -> void:
	_biofilm_changes = 0
	_biofilm_max_group = 0

	if biofilm_view != null:
		biofilm_view.queue_free()
		biofilm_view = null
	var after: Node = grid_view
	if session != null and session.config != null and session.config.flag("biofilm"):
		biofilm_view = BiofilmView.new()
		biofilm_view.name = "BiofilmView"
		_insert_after(biofilm_view, after)
		after = biofilm_view

	if unit_layer == null:
		unit_layer = UnitLayer.new()
		unit_layer.name = "UnitLayer"
		_insert_after(unit_layer, after)
	else:
		move_child(unit_layer, after.get_index() + 1)
	after = unit_layer

	if overlay == null:
		overlay = BattleOverlay.new()
		overlay.name = "BattleOverlay"
		_insert_after(overlay, after)
	else:
		move_child(overlay, after.get_index() + 1)
	after = overlay

	if effect_layer == null:
		effect_layer = EffectLayer.new()
		effect_layer.name = "EffectLayer"
		_insert_after(effect_layer, after)
	else:
		move_child(effect_layer, after.get_index() + 1)
	after = effect_layer

	if impact_rings == null:
		impact_rings = ImpactRings.new()
		impact_rings.name = "ImpactRings"
		_insert_after(impact_rings, after)
	else:
		move_child(impact_rings, after.get_index() + 1)


## SettingsApply.GROUP hook: the Settings screen (opened from Pause) saved a change.
func on_settings_changed() -> void:
	var reduce: bool = SettingsApply.reduce_flashes(settings_path)
	if unit_layer != null:
		unit_layer.reduce_flashes = reduce
	if effect_layer != null:
		effect_layer.reduce_flashes = reduce


# --- Pause (screen 12) ---------------------------------------------------------
# The sim only advances when BattleRunner steps it, so pausing is not stepping: the runner stops
# accumulating time and the UnitLayer view clock stops. The tree itself is never paused, so the
# Pause menu and the Settings screen above it keep processing input.

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pause()


func is_paused() -> bool:
	return runner != null and runner.paused


## A battle can be paused while it runs, until its result is known.
func can_pause() -> bool:
	return runner != null and runner.sim != null and runner.is_running and not runner.sim.finished and not _abandoned


func pause() -> void:
	if is_paused() or not can_pause():
		return
	runner.paused = true
	if unit_layer != null:
		unit_layer.paused = true
	hud_combat.visible = false
	pause_menu.visible = true


func resume() -> void:
	if not is_paused() or _abandoned:
		return
	runner.paused = false
	if unit_layer != null:
		unit_layer.paused = false
	hud_combat.visible = true
	pause_menu.visible = false


## Back to Incubation with the same base: the army is refunded so the ATP budget is as before launch.
func restart_raid() -> void:
	_abandon("restart", GameStateMachine.Phase.INCUBATION)


func quit_to_menu() -> void:
	_abandon("quit", GameStateMachine.Phase.TITLE)


## Settings opens over the Pause menu in the night theme; the battle stays paused behind it.
func open_settings() -> void:
	if fsm == null or fsm.screen_stack == null:
		return
	fsm.screen_stack.push("settings")
	var top: Control = fsm.screen_stack.top_screen()
	if top != null and "night" in top:
		top.set("night", true)


## An abandoned battle writes no battle log and no battle_end event, and never reaches Results.
func _abandon(reason: String, to: GameStateMachine.Phase) -> void:
	if _abandoned:
		return
	_abandoned = true
	var tick: int = runner.sim.tick if runner != null and runner.sim != null else 0
	if runner != null:
		runner.paused = true
		runner.is_running = false
	if session != null and session.army != null:
		session.army.refund_all(session.wallet)
	var log_node: Node = logger if logger != null else SessionLogger
	if log_node != null and log_node.has_method("log_event"):
		log_node.call("log_event", "battle_abandoned", {"reason": reason, "tick": tick})
	if fsm != null:
		fsm.request_transition(to)


func _insert_after(node: Node, after: Node) -> void:
	add_child(node)
	move_child(node, after.get_index() + 1)


func _on_runner_ticked() -> void:
	if runner != null and runner.sim != null:
		snapshots.capture(runner.sim)

	if hud_combat != null:
		hud_combat.update_display()


func _process(_delta: float) -> void:
	if runner == null or runner.sim == null:
		return

	_dispatch_events()

	if runner.sim.finished and not _banner_shown:
		_show_end_banner()


func _show_end_banner() -> void:
	_banner_shown = true
	var banner_text: String = ""
	if runner != null and runner.sim != null:
		if runner.sim.end_reason == "nucleus_destroyed":
			banner_text = "INFECTION SUCCESSFUL"
			Sfx.play("win")
		else:
			banner_text = "IMMUNE RESPONSE WINS"
			Sfx.play("lose")

	if banner_label != null:
		banner_label.text = banner_text
	if banner_panel != null:
		banner_panel.visible = true
	if hud_combat != null:
		hud_combat.pause_button.disabled = true


func _dispatch_events() -> void:
	if runner == null or runner.sim == null:
		return
	var events: Array[Dictionary] = runner.sim.drain_events()
	for ev: Dictionary in events:
		_route_event(ev)


func _route_event(ev: Dictionary) -> void:
	var event_type: String = str(ev.get("type", ""))

	match event_type:
		SimEvents.BIOFILM_CHANGED:
			_biofilm_changes += 1
			for g_var: Variant in ev.get("groups", []):
				_biofilm_max_group = maxi(_biofilm_max_group, (g_var as Array).size())

		SimEvents.TOWER_FIRED:
			Sfx.play("tower_fire")

		SimEvents.STRUCTURE_DAMAGED:
			Sfx.play("hit")

		SimEvents.STRUCTURE_DESTROYED:
			Sfx.play("destroy")

		SimEvents.PATHOGEN_DAMAGED:
			Sfx.play("hit")

		SimEvents.BATTLE_ENDED:
			if not _banner_shown:
				_show_end_banner()

	if unit_layer != null:
		unit_layer.on_event(ev)
	if overlay != null:
		overlay.on_event(ev)
	if effect_layer != null:
		effect_layer.on_event(ev)
	if impact_rings != null:
		impact_rings.on_event(ev)


var settings_path: String = GameSettings.DEFAULT_PATH


func _on_battle_finished(sim: BattleSim) -> void:
	if session != null and sim != null:
		var tick_rate: int = session.config.tick_rate if (session.config != null and session.config.tick_rate > 0) else 20
		var battle_s: float = float(sim.tick) / float(tick_rate)
		var first_contact_s: float = float(sim.first_contact_tick) / float(tick_rate) if sim.first_contact_tick >= 0 else -1.0

		var nucleus: StructureState = sim.structure(sim.nucleus_id)
		var nucleus_hp: int = nucleus.hp if nucleus != null else 0
		var nucleus_max_hp: int = nucleus.max_hp if nucleus != null else 0

		# Sim structure ids still standing at the end, for the Results screen's final-state island.
		var alive_structure_ids: Array[int] = []
		for st: StructureState in sim.structures:
			if st.alive:
				alive_structure_ids.append(st.id)

		session.last_result = {
			"outcome": sim.outcome,
			"end_reason": sim.end_reason,
			"ticks": sim.tick,
			"battle_s": battle_s,
			"nucleus_hp": nucleus_hp,
			"nucleus_max_hp": nucleus_max_hp,
			"structures_destroyed": sim.structures_destroyed,
			"structures_total": sim.structures.size(),
			"pathogens_killed": sim.pathogens_killed,
			"pathogens_total": sim.pathogens.size(),
			"first_contact_s": first_contact_s,
			"first_destroyed_structure_id": sim.first_destroyed_structure_id,
			"first_destroyed_structure_type": sim.first_destroyed_structure_type,
			"alive_structure_ids": alive_structure_ids,
			"final_state_hash": sim.state_hash(),
		}

		if session.config != null and session.config.flag("raid_score"):
			var structures: Array = session.battle_setup.structures if session.battle_setup != null else []
			var score: int = RaidScore.compute(session.config, structures, sim.outcome)
			session.best_score = maxi(session.best_score, score)
			session.last_result["score"] = score
			session.last_result["base_value"] = RaidScore.base_value(session.config, structures)
			session.last_result["best_score"] = session.best_score

		if session.config != null and session.config.flag("bcell_analysis"):
			session.last_result["analyzed_strains"] = sim.analyzed_strain_keys()

		if session.config != null and session.config.memory_enabled():
			var mem_changes: Array[Dictionary] = session.memory.update_after_raid(sim.seen_strain_keys(), sim.analyzed_strain_keys(), session.config)
			session.last_result["memory_changes"] = mem_changes
			session.last_result["memory"] = session.memory.to_dict()
			if SessionLogger != null and SessionLogger.has_method("log_event"):
				SessionLogger.log_event("memory_updated", {"raids": session.memory.raids, "changes": mem_changes})

		if session.config != null and session.config.flag("biofilm"):
			session.last_result["biofilm_max_group"] = _biofilm_max_group
			session.last_result["biofilm_changes"] = _biofilm_changes

		if session.config != null and session.config.flag("phage_hijack"):
			session.last_result["hijacks_completed"] = sim.hijacks_completed
			session.last_result["hijacks_interrupted"] = sim.hijacks_interrupted
			session.last_result["pathogens_consumed"] = sim.pathogens_consumed

		var pred_id: int = session.prediction_structure_id if session != null else 0
		# Kept with the result so a config applied on leaving INFECTION cannot erase it.
		session.last_result["prediction_structure_id"] = pred_id
		var pred_correct = null
		if pred_id > 0:
			pred_correct = (sim.first_destroyed_structure_id > 0 and sim.first_destroyed_structure_id == pred_id)

		var battle_end_data: Dictionary = session.last_result.duplicate()
		battle_end_data["prediction_structure_id"] = pred_id if pred_id > 0 else null
		battle_end_data["prediction_correct"] = pred_correct
		if SessionLogger != null and SessionLogger.has_method("log_event"):
			SessionLogger.log_event("battle_end", battle_end_data)

		_write_battle_log(sim)

	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.RESULTS)


func _write_battle_log(sim: BattleSim) -> void:
	if session == null or session.config == null or session.battle_setup == null or sim == null:
		return

	var log_dict: Dictionary = SnapshotIO.battle_to_dict(session.config, session.battle_setup, sim)
	var json_str: String = SnapshotIO.to_json(log_dict)

	if not DirAccess.dir_exists_absolute("user://battles"):
		DirAccess.make_dir_recursive_absolute("user://battles")

	var unix_time: int = int(Time.get_unix_time_from_system())
	var seed_val: int = session.battle_setup.seed
	var file_path: String = "user://battles/battle_%d_%d.json" % [unix_time, seed_val]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file != null:
		file.store_string(json_str)
		file.close()

	_rotate_battle_logs()


func _rotate_battle_logs() -> void:
	var dir := DirAccess.open("user://battles")
	if dir == null:
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while not fn.is_empty():
		if not dir.current_is_dir() and fn.ends_with(".json"):
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()

	if files.size() <= 50:
		return

	files.sort_custom(func(a: String, b: String) -> bool:
		var time_a: int = FileAccess.get_modified_time("user://battles/" + a)
		var time_b: int = FileAccess.get_modified_time("user://battles/" + b)
		if time_a != time_b:
			return time_a < time_b
		return a < b
	)

	while files.size() > 50:
		var oldest: String = files.pop_front()
		dir.remove(oldest)


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
