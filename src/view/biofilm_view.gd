class_name BiofilmView
extends Node2D

const BIOFILM_COLOR: Color = Color("#f1c40f")
const FILL_ALPHA: float = 0.15
const LINE_ALPHA: float = 0.35
const RADIUS_TILES: float = 0.8
const LINE_WIDTH_PX: float = 6.0

var session: Session = null
var runner: BattleRunner = null
var active_pathogens: Dictionary = {}


func setup(p_session: Session, p_runner: BattleRunner, p_active_pathogens: Dictionary) -> void:
	session = p_session
	runner = p_runner
	active_pathogens = p_active_pathogens


func _process(_delta: float) -> void:
	queue_redraw()


func _unit_pos(p: PathogenState, tile_px: int) -> Vector2:
	if active_pathogens.has(p.id) and is_instance_valid(active_pathogens[p.id]):
		return active_pathogens[p.id].position
	return Vector2(p.pos) * float(tile_px) / 1000.0


func _draw() -> void:
	if runner == null or runner.sim == null:
		return
	var sim: BattleSim = runner.sim
	var tile_px: int = session.config.tile_px if (session != null and session.config != null) else 32
	var fill := Color(BIOFILM_COLOR.r, BIOFILM_COLOR.g, BIOFILM_COLOR.b, FILL_ALPHA)
	var line := Color(BIOFILM_COLOR.r, BIOFILM_COLOR.g, BIOFILM_COLOR.b, LINE_ALPHA)
	for root: Variant in sim.biofilm.groups.keys():
		var ids: Array = sim.biofilm.groups[root]
		var members: Array[PathogenState] = []
		for id_var: Variant in ids:
			var m: PathogenState = sim.pathogen(int(id_var))
			if m != null and m.alive:
				members.append(m)
		for m: PathogenState in members:
			draw_circle(_unit_pos(m, tile_px), RADIUS_TILES * float(tile_px), fill)
		for i: int in range(members.size()):
			var a: PathogenState = members[i]
			for j: int in range(i + 1, members.size()):
				var b: PathogenState = members[j]
				var brk: int = a.def.biofilm_break_mt
				if FixedMath.dist_sq(a.pos, b.pos) < brk * brk:
					draw_line(_unit_pos(a, tile_px), _unit_pos(b, tile_px), line, LINE_WIDTH_PX)
