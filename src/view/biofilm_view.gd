class_name BiofilmView
extends Node2D

const BIOFILM_COLOR: Color = Color("#f1c40f")
const FILL_ALPHA: float = 0.15
const LINE_ALPHA: float = 0.35
const RADIUS_TILES: float = 0.8
const LINE_WIDTH_PX: float = 6.0
const FILL: Color = Color(BIOFILM_COLOR, FILL_ALPHA)
const LINE: Color = Color(BIOFILM_COLOR, LINE_ALPHA)

var session: Session = null
var runner: BattleRunner = null
var snapshots: BattleSnapshotBuffer = null
var projection: IsoProjection = null
## Live members of the group being drawn; only the first _member_count entries are current.
var _members: Array[PathogenState] = []
var _member_count: int = 0
var _drawn_key: Vector4 = Vector4(-1.0, 0.0, 0.0, 0.0)


func setup(p_session: Session, p_runner: BattleRunner, p_snapshots: BattleSnapshotBuffer, p_projection: IsoProjection) -> void:
	session = p_session
	runner = p_runner
	snapshots = p_snapshots
	projection = p_projection


func _process(_delta: float) -> void:
	if runner == null or projection == null:
		return
	if runner.is_running and not runner.paused:
		queue_redraw()
	elif _projection_key() != _drawn_key:
		queue_redraw()


func _projection_key() -> Vector4:
	return Vector4(projection.tile_px, projection.origin.x, projection.origin.y, projection.scale)


func _unit_ground(p: PathogenState) -> Vector2:
	if snapshots != null and runner != null and snapshots.has_unit(p.id):
		return snapshots.unit_ground(p.id, runner.alpha)
	return Vector2(p.pos) / 1000.0


## Flat ground decal under the units: group discs as ground ellipses, links as screen lines.
func _draw() -> void:
	if runner == null or runner.sim == null or projection == null:
		return
	var sim: BattleSim = runner.sim
	_drawn_key = _projection_key()
	var k: float = projection.tile_px / 14.0
	for root: Variant in sim.biofilm.groups:
		var ids: Array = sim.biofilm.groups[root]
		if _members.size() < ids.size():
			_members.resize(ids.size())
		_member_count = 0
		for id_var: Variant in ids:
			var m: PathogenState = sim.pathogen(int(id_var))
			if m != null and m.alive:
				_members[_member_count] = m
				_member_count += 1
		draw_set_transform_matrix(projection.ground_transform())
		for i: int in range(_member_count):
			draw_circle(_unit_ground(_members[i]), RADIUS_TILES, FILL)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		for i: int in range(_member_count):
			var a: PathogenState = _members[i]
			for j: int in range(i + 1, _member_count):
				var b: PathogenState = _members[j]
				var brk: int = a.def.biofilm_break_mt
				if FixedMath.dist_sq(a.pos, b.pos) < brk * brk:
					draw_line(projection.ground_to_screen(_unit_ground(a)), projection.ground_to_screen(_unit_ground(b)), LINE, LINE_WIDTH_PX * k)
