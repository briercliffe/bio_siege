class_name IntentLinesView
extends Node2D

var session: Session = null
var runner: BattleRunner = null
var active_pathogens: Dictionary = {}
var structure_views: Dictionary = {}


func setup(p_session: Session, p_runner: BattleRunner, p_active_pathogens: Dictionary, p_structure_views: Dictionary) -> void:
	session = p_session
	runner = p_runner
	active_pathogens = p_active_pathogens
	structure_views = p_structure_views


func _process(_delta: float) -> void:
	visible = session.intent_lines_enabled if session != null else true
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible or runner == null or runner.sim == null:
		return

	var tile_px: int = session.config.tile_px if (session != null and session.config != null) else 32

	for p: PathogenState in runner.sim.pathogens:
		if p == null or not p.alive:
			continue

		var base_color: Color = Color.WHITE
		if session != null and session.config != null and session.config.pathogens.has(p.type_id):
			var p_def: PathogenDef = session.config.pathogens[p.type_id]
			if p_def != null:
				base_color = p_def.placeholder_color
		elif active_pathogens.has(p.id) and is_instance_valid(active_pathogens[p.id]):
			var pv = active_pathogens[p.id]
			if pv.pathogen_def != null:
				base_color = pv.pathogen_def.placeholder_color

		var unit_pos: Vector2
		if active_pathogens.has(p.id) and is_instance_valid(active_pathogens[p.id]):
			unit_pos = active_pathogens[p.id].position
		else:
			unit_pos = Vector2(p.pos) * float(tile_px) / 1000.0

		if p.target_id != 0:
			var target: StructureState = runner.sim.structure(p.target_id)
			if target != null and target.alive:
				var target_center: Vector2 = Vector2(target.center) * float(tile_px) / 1000.0
				var color_target := Color(base_color.r, base_color.g, base_color.b, 0.35)
				if unit_pos.distance_squared_to(target_center) > 0.001:
					draw_line(unit_pos, target_center, color_target, 1.5)

		if p.blocker_id != 0:
			var blocker: StructureState = runner.sim.structure(p.blocker_id)
			if blocker != null and blocker.alive:
				var blocker_center: Vector2 = Vector2(blocker.center) * float(tile_px) / 1000.0
				var color_blocker := Color(base_color.r, base_color.g, base_color.b, 0.6)
				if unit_pos.distance_squared_to(blocker_center) > 0.001:
					draw_dashed_line(unit_pos, blocker_center, color_blocker, 1.5, 6.0)
