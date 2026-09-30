class_name PathogenState
extends RefCounted

enum State { SEEKING, MOVING, ATTACKING, DEAD }

var id: int = 0
var type_id: String = ""
var def: PathogenDef = null
var pos: Vector2i = Vector2i.ZERO             # milli-tiles
var cell: Vector2i = Vector2i.ZERO            # last cell center reached
var hp: int = 0
var max_hp: int = 0
var alive: bool = true
var state: State = State.SEEKING
var target_id: int = 0        # structure it wants to destroy
var blocker_id: int = 0       # structure blocking its path, 0 = none
var path: Array[Vector2i] = []
var path_index: int = 0       # index of the NEXT waypoint in path
var path_version: int = -1    # grid_version the path was computed for
var attack_cooldown: int = 0
var strain_id: String = "wild"     # ID-03 fills this from the setup
var analysis_rate_pct: int = 100   # how fast B-Cells analyze this strain (100 = x1)
var channel_target_id: int = 0     # structure being hijacked, 0 = none
var channel_ticks_left: int = 0

static func create(p_id: int, p_type_id: String, p_def: PathogenDef, p_cell: Vector2i) -> PathogenState:
	var s := PathogenState.new()
	s.id = p_id
	s.type_id = p_type_id
	s.def = p_def
	s.cell = p_cell
	s.pos = FixedMath.cell_center(p_cell)
	s.hp = p_def.hp if p_def != null else 0
	s.max_hp = s.hp
	s.alive = true
	s.state = State.SEEKING
	s.target_id = 0
	s.blocker_id = 0
	s.path = []
	s.path_index = 0
	s.path_version = -1
	s.attack_cooldown = 0
	return s

func strain_key() -> String:
	return "%s/%s" % [type_id, strain_id]

func attacking_id() -> int:
	return blocker_id if blocker_id != 0 else target_id
