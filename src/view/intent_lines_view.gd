class_name IntentLinesView
extends Node2D

## Intent lines between unit centres, in screen space (docs/MVP_UI_SPEC.md section 3). Toggled by
## session.intent_lines_enabled. Read-only.

const LIFT_T: float = 0.6

var session: Session = null
var runner: BattleRunner = null
var snapshots: BattleSnapshotBuffer = null
var projection: IsoProjection = null


func setup(p_session: Session, p_runner: BattleRunner, p_snapshots: BattleSnapshotBuffer, p_projection: IsoProjection) -> void:
	session = p_session
	runner = p_runner
	snapshots = p_snapshots
	projection = p_projection


func _process(_delta: float) -> void:
	visible = session.intent_lines_enabled if session != null else true
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible or runner == null or runner.sim == null or projection == null:
		return
	var sim: BattleSim = runner.sim
	var lift := Vector2(0.0, -LIFT_T * projection.tile_px)
	var k: float = projection.tile_px / 14.0
	var alpha: float = runner.alpha

	for p: PathogenState in sim.pathogens:
		if p == null or not p.alive:
			continue
		if p.target_id == 0 and p.blocker_id == 0:
			continue
		var base_color: Color = p.def.placeholder_color if p.def != null else Color.WHITE
		var ground: Vector2 = Vector2(p.pos) / 1000.0
		if snapshots != null and snapshots.has_unit(p.id):
			ground = snapshots.unit_ground(p.id, alpha)
		var unit_pos: Vector2 = projection.ground_to_screen(ground) + lift

		if p.target_id != 0:
			var target: StructureState = sim.structure(p.target_id)
			if target != null and target.alive:
				var target_pos: Vector2 = projection.mt_to_screen(target.center) + lift
				if unit_pos.distance_squared_to(target_pos) > 0.001:
					draw_line(unit_pos, target_pos, Color(base_color, 0.35), 1.5 * k)

		if p.blocker_id != 0:
			var blocker: StructureState = sim.structure(p.blocker_id)
			if blocker != null and blocker.alive:
				var blocker_pos: Vector2 = projection.mt_to_screen(blocker.center) + lift
				if unit_pos.distance_squared_to(blocker_pos) > 0.001:
					draw_dashed_line(unit_pos, blocker_pos, Color(base_color, 0.6), 1.5 * k, 6.0 * k)
