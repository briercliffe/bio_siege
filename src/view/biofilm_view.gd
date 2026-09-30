class_name BiofilmView
extends Node2D

const BIOFILM_COLOR: Color = Color("#f1c40f")
const FILL_ALPHA: float = 0.15
const LINE_ALPHA: float = 0.35
const RADIUS_TILES: float = 0.8
const LINE_WIDTH_PX: float = 6.0

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
	queue_redraw()


func _unit_ground(p: PathogenState) -> Vector2:
	if snapshots != null and runner != null and snapshots.has_unit(p.id):
		return snapshots.unit_ground(p.id, runner.alpha)
	return Vector2(p.pos) / 1000.0


## Flat ground decal under the units: group discs as ground ellipses, links as screen lines.
func _draw() -> void:
	if runner == null or runner.sim == null or projection == null:
		return
	var sim: BattleSim = runner.sim
	var fill := Color(BIOFILM_COLOR.r, BIOFILM_COLOR.g, BIOFILM_COLOR.b, FILL_ALPHA)
	var line := Color(BIOFILM_COLOR.r, BIOFILM_COLOR.g, BIOFILM_COLOR.b, LINE_ALPHA)
	var k: float = projection.tile_px / 14.0
	for root: Variant in sim.biofilm.groups.keys():
		var ids: Array = sim.biofilm.groups[root]
		var members: Array[PathogenState] = []
		for id_var: Variant in ids:
			var m: PathogenState = sim.pathogen(int(id_var))
			if m != null and m.alive:
				members.append(m)
		draw_set_transform_matrix(projection.ground_transform())
		for m: PathogenState in members:
			draw_circle(_unit_ground(m), RADIUS_TILES, fill)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		for i: int in range(members.size()):
			var a: PathogenState = members[i]
			for j: int in range(i + 1, members.size()):
				var b: PathogenState = members[j]
				var brk: int = a.def.biofilm_break_mt
				if FixedMath.dist_sq(a.pos, b.pos) < brk * brk:
					draw_line(projection.ground_to_screen(_unit_ground(a)), projection.ground_to_screen(_unit_ground(b)), line, LINE_WIDTH_PX * k)
