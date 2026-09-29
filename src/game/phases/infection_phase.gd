class_name InfectionPhase
extends Control

const PathogenViewScene: PackedScene = preload("res://src/view/pathogen_view.tscn")
const ProjectileViewScene: PackedScene = preload("res://src/view/projectile_view.tscn")
const DeathVfxScene: PackedScene = preload("res://src/view/death_vfx.tscn")
const StructureViewScene: PackedScene = preload("res://src/view/structure_view.tscn")
const GridViewScene: PackedScene = preload("res://src/view/grid_view.tscn")
const HudCombatScene: PackedScene = preload("res://src/ui/hud_combat.tscn")

var session: Session = null
var fsm: GameStateMachine = null

var grid_view: GridView = null
var runner: BattleRunner = null
var hud_combat: HudCombat = null
var intent_lines_view: IntentLinesView = null

var entity_container: Node2D = null
var structures_container: Node2D = null
var pathogens_container: Node2D = null
var projectiles_container: Node2D = null
var vfx_container: Node2D = null

var pathogen_pool: NodePool = null
var projectile_pool: NodePool = null
var vfx_pool: NodePool = null

var _structure_views: Dictionary = {}
var _active_pathogens: Dictionary = {}
var _active_projectiles: Dictionary = {}

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
	grid_view.deploy_mode = false
	grid_view.draw_structures = false

	_init_entity_containers()
	_init_pools()

	if runner == null:
		runner = BattleRunner.new()
		runner.name = "BattleRunner"
		runner.process_priority = -1
		add_child(runner)
		runner.ticked.connect(_on_runner_ticked)
		runner.battle_finished.connect(_on_battle_finished)

	var cfg: GameConfig = session.config if session != null else null
	var b_setup: BattleSetup = session.battle_setup if session != null else null
	if cfg != null and b_setup != null:
		runner.start(cfg, b_setup)
		_init_structure_views()
		_dispatch_events()

	if intent_lines_view != null:
		intent_lines_view.setup(session, runner, _active_pathogens, _structure_views)
	if hud_combat != null:
		hud_combat.setup(session, runner)

	_update_grid_layout()


func _init_entity_containers() -> void:
	if entity_container == null:
		entity_container = Node2D.new()
		entity_container.name = "EntityContainer"
		grid_view.add_child(entity_container)
	else:
		for child in entity_container.get_children():
			child.queue_free()

	structures_container = Node2D.new()
	structures_container.name = "StructuresContainer"
	entity_container.add_child(structures_container)

	intent_lines_view = IntentLinesView.new()
	intent_lines_view.name = "IntentLinesView"
	entity_container.add_child(intent_lines_view)
	intent_lines_view.setup(session, runner, _active_pathogens, _structure_views)

	pathogens_container = Node2D.new()
	pathogens_container.name = "PathogensContainer"
	entity_container.add_child(pathogens_container)

	projectiles_container = Node2D.new()
	projectiles_container.name = "ProjectilesContainer"
	entity_container.add_child(projectiles_container)

	vfx_container = Node2D.new()
	vfx_container.name = "VfxContainer"
	entity_container.add_child(vfx_container)

	_structure_views.clear()
	_active_pathogens.clear()
	_active_projectiles.clear()


func _init_pools() -> void:
	pathogen_pool = NodePool.new(PathogenViewScene, 100, pathogens_container)
	projectile_pool = NodePool.new(ProjectileViewScene, 64, projectiles_container)
	vfx_pool = NodePool.new(DeathVfxScene, 64, vfx_container)


func _init_structure_views() -> void:
	if runner == null or runner.sim == null:
		return
	var tile_px: int = session.config.tile_px if session != null and session.config != null else 32
	for s_state: StructureState in runner.sim.structures:
		var s_def: StructureDef = session.config.structures.get(s_state.type_id) if (session != null and session.config != null and session.config.structures.has(s_state.type_id)) else null
		var sv: StructureView = StructureViewScene.instantiate() as StructureView
		structures_container.add_child(sv)
		sv.setup(s_state, s_def, tile_px, vfx_pool)
		_structure_views[s_state.id] = sv


func _on_runner_ticked() -> void:
	for pv: PathogenView in _active_pathogens.values():
		if is_instance_valid(pv):
			pv.on_ticked()
	for jv: ProjectileView in _active_projectiles.values():
		if is_instance_valid(jv):
			jv.on_ticked()

	if runner != null and runner.sim != null:
		var breached_ids: Dictionary = {}
		for p: PathogenState in runner.sim.pathogens:
			if p != null and p.alive and p.blocker_id != 0:
				breached_ids[p.blocker_id] = true
		for sv: StructureView in _structure_views.values():
			if is_instance_valid(sv):
				sv.set_breached(breached_ids.has(sv.structure_id))

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
		else:
			banner_text = "IMMUNE RESPONSE WINS"

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
	var tile_px: int = session.config.tile_px if session != null and session.config != null else 32

	match event_type:
		SimEvents.UNIT_SPAWNED:
			var uid: int = int(ev.get("unit_id", 0))
			if not _active_pathogens.has(uid):
				var p_state: PathogenState = runner.sim.pathogen(uid)
				if p_state != null and pathogen_pool != null:
					var p_def: PathogenDef = session.config.pathogens.get(p_state.type_id) if (session != null and session.config != null and session.config.pathogens.has(p_state.type_id)) else null
					var pv: PathogenView = pathogen_pool.acquire() as PathogenView
					if pv != null:
						pv.setup(p_state, p_def, tile_px, runner, vfx_pool)
						_active_pathogens[uid] = pv

		SimEvents.STRUCTURE_DAMAGED:
			var sid: int = int(ev.get("structure_id", 0))
			var amount: int = int(ev.get("amount", 0))
			var hp: int = int(ev.get("hp", 0))
			if _structure_views.has(sid):
				var sv: StructureView = _structure_views[sid]
				if is_instance_valid(sv):
					sv.on_damaged(amount, hp)

		SimEvents.STRUCTURE_DESTROYED:
			var sid: int = int(ev.get("structure_id", 0))
			if _structure_views.has(sid):
				var sv: StructureView = _structure_views[sid]
				if is_instance_valid(sv):
					sv.on_destroyed()

		SimEvents.PATHOGEN_DAMAGED:
			var uid: int = int(ev.get("unit_id", 0))
			var amount: int = int(ev.get("amount", 0))
			var hp: int = int(ev.get("hp", 0))
			if _active_pathogens.has(uid):
				var pv: PathogenView = _active_pathogens[uid]
				if is_instance_valid(pv):
					pv.on_damaged(amount, hp)

		SimEvents.PATHOGEN_KILLED:
			var uid: int = int(ev.get("unit_id", 0))
			if _active_pathogens.has(uid):
				var pv: PathogenView = _active_pathogens[uid]
				_active_pathogens.erase(uid)
				if is_instance_valid(pv):
					pv.on_killed()

		SimEvents.SPLASH:
			if vfx_pool != null:
				var sid: int = int(ev.get("structure_id", 0))
				var s_state: StructureState = runner.sim.structure(sid)
				var s_def: StructureDef = session.config.structures.get(s_state.type_id) if (s_state != null and session != null and session.config != null and session.config.structures.has(s_state.type_id)) else null
				var color: Color = s_def.placeholder_color if s_def != null else Color(0.3, 0.7, 1.0, 0.9)
				var pos_mt: Vector2i = ev.get("pos", Vector2i.ZERO)
				var radius_mt: int = int(ev.get("radius", 0))
				var px_pos: Vector2 = Vector2(float(pos_mt.x) * float(tile_px) / 1000.0, float(pos_mt.y) * float(tile_px) / 1000.0)
				var radius_px: float = float(radius_mt) * float(tile_px) / 1000.0
				var vfx: DeathVfx = vfx_pool.acquire() as DeathVfx
				if vfx != null:
					vfx.play_splash_ring(px_pos, radius_px, color)

		SimEvents.PROJECTILE_SPAWNED:
			var p_id: int = int(ev.get("projectile_id", 0))
			var sid: int = int(ev.get("structure_id", 0))
			var s_state: StructureState = runner.sim.structure(sid)
			var s_def: StructureDef = session.config.structures.get(s_state.type_id) if (s_state != null and session != null and session.config != null and session.config.structures.has(s_state.type_id)) else null
			var color: Color = s_def.placeholder_color if s_def != null else Color.WHITE
			var proj_state: ProjectileState = null
			for j: ProjectileState in runner.sim.projectiles:
				if j.id == p_id:
					proj_state = j
					break
			if proj_state != null and projectile_pool != null:
				var jv: ProjectileView = projectile_pool.acquire() as ProjectileView
				if jv != null:
					jv.setup(proj_state, color, tile_px, runner)
					_active_projectiles[p_id] = jv

		SimEvents.PROJECTILE_HIT, SimEvents.PROJECTILE_FIZZLED:
			var p_id: int = int(ev.get("projectile_id", 0))
			if _active_projectiles.has(p_id):
				var jv: ProjectileView = _active_projectiles[p_id]
				_active_projectiles.erase(p_id)
				if is_instance_valid(jv):
					jv.release_projectile()

		SimEvents.BATTLE_ENDED:
			if not _banner_shown:
				_show_end_banner()


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

	if fsm != null:
		fsm.request_transition(GameStateMachine.Phase.RESULTS)


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
