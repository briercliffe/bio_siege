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

# Isometric battle layers, back to front: GridView (ground), BiofilmView, UnitLayer, IntentLinesView, BattleOverlay.
var biofilm_view: BiofilmView = null
var unit_layer: UnitLayer = null
var intent_lines_view: IntentLinesView = null
var overlay: BattleOverlay = null

var _biofilm_changes: int = 0
var _biofilm_max_group: int = 0

var banner_panel: Control = null
var banner_label: Label = null
var _banner_shown: bool = false


func _resolve_nodes() -> void:
	if grid_view == null:
		grid_view = get_node_or_null("GridView") as GridView
	if hud_combat == null:
		hud_combat = get_node_or_null("HudCombat") as HudCombat
	if banner_panel == null:
		banner_panel = get_node_or_null("BannerPanel") as Control
	if banner_panel != null and banner_label == null:
		banner_label = banner_panel.get_node_or_null("BannerLabel") as Label
	if banner_label == null:
		banner_label = get_node_or_null("Label") as Label


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

	_resolve_nodes()

	if hud_combat == null:
		hud_combat = HudCombatScene.instantiate() as HudCombat
		add_child(hud_combat)

	if banner_panel != null:
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
	unit_layer.reduce_flashes = SettingsApply.reduce_flashes(settings_path)

	if runner == null:
		runner = BattleRunner.new()
		runner.name = "BattleRunner"
		runner.process_priority = -1
		add_child(runner)
		runner.ticked.connect(_on_runner_ticked)
		runner.battle_finished.connect(_on_battle_finished)

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
	intent_lines_view.setup(session, runner, snapshots, projection)
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

	if intent_lines_view == null:
		intent_lines_view = IntentLinesView.new()
		intent_lines_view.name = "IntentLinesView"
		_insert_after(intent_lines_view, after)
	else:
		move_child(intent_lines_view, after.get_index() + 1)
	after = intent_lines_view

	if overlay == null:
		overlay = BattleOverlay.new()
		overlay.name = "BattleOverlay"
		_insert_after(overlay, after)
	else:
		move_child(overlay, after.get_index() + 1)


## SettingsApply.GROUP hook: the Settings screen (opened from Pause) saved a change.
func on_settings_changed() -> void:
	if unit_layer != null:
		unit_layer.reduce_flashes = SettingsApply.reduce_flashes(settings_path)


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


var settings_path: String = GameSettings.DEFAULT_PATH


func _record_outbreak(sim: BattleSim) -> void:
	var structures: Array = session.battle_setup.structures if session.battle_setup != null else []
	var score: int = int(session.last_result.get("score", RaidScore.compute(session.config, structures, sim.outcome)))
	session.record_outbreak(sim.outcome, score)
	var run: OutbreakRun = session.outbreak
	session.last_result["outbreak"] = run.to_dict()
	var have_log: bool = SessionLogger != null and SessionLogger.has_method("log_event")
	if have_log:
		SessionLogger.log_event("outbreak_generation_end", {
			"generation": run.generation if run.ended else run.generation - 1,
			"score": score if sim.outcome == "attacker" else 0,
			"total_score": run.total_score,
			"outcome": sim.outcome,
			"strains": session.last_launch.get("strains", {}),
		})
	if run.ended:
		var best: int = maxi(GameSettings.get_int(GameSettings.SECTION_GAME, GameSettings.KEY_BEST_OUTBREAK, 0, settings_path), run.total_score)
		GameSettings.set_int(GameSettings.SECTION_GAME, GameSettings.KEY_BEST_OUTBREAK, best, settings_path)
		session.last_result["outbreak_best"] = best
		if have_log:
			SessionLogger.log_event("outbreak_run_end", {
				"generations_cleared": run.generations_cleared(),
				"total_score": run.total_score,
				"best": best,
			})


func _on_battle_finished(sim: BattleSim) -> void:
	if session != null and sim != null:
		var tick_rate: int = session.config.tick_rate if (session.config != null and session.config.tick_rate > 0) else 20
		var battle_s: float = float(sim.tick) / float(tick_rate)
		var first_contact_s: float = float(sim.first_contact_tick) / float(tick_rate) if sim.first_contact_tick >= 0 else -1.0

		var nucleus: StructureState = sim.structure(sim.nucleus_id)
		var nucleus_hp: int = nucleus.hp if nucleus != null else 0
		var nucleus_max_hp: int = nucleus.max_hp if nucleus != null else 0

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

		if session.config != null and session.config.flag("outbreak_mode") and session.outbreak != null:
			_record_outbreak(sim)

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
		0.0,
		64.0,
		maxf(r.size.x, 10.0),
		maxf(r.size.y - 64.0, 10.0)
	)
	grid_view.fit_to_rect(inset_rect)
