class_name HowToPlayDiagram
extends Control

## Simple explanatory diagrams for the How to play overlay, drawn with
## PlaceholderShapes. Shapes, colours and costs come from the loaded config.

const PAGE_COUNT: int = 4
const BG_COLOR: Color = Color("#f4f8fc")
const GRID_LINE_COLOR: Color = Color("#c3ccd6")
const RING_COLOR: Color = Color("#2ecc71")
const INK_COLOR: Color = Color("#12304f")
const ATP_COLOR: Color = Color("#f1c40f")
const HP_BAD_COLOR: Color = Color("#e74c3c")
const TILE: float = 40.0
const LABEL_SIZE: int = 15

const FALLBACK_LOOKS: Dictionary = {
	"nucleus": ["rounded_square", Color("#8e44ad")],
	"mucous_wall": ["square", Color("#c8b98a")],
	"macrophage": ["circle", Color("#2e86de")],
	"b_cell": ["diamond", Color("#16a085")],
	"rhinovirus": ["triangle", Color("#e67e22")],
	"bacteriophage": ["lander", Color("#c0392b")],
	"staphylococcus": ["cluster", Color("#d4ac0d")],
}

var page: int = 0:
	set(value):
		page = clampi(value, 0, PAGE_COUNT - 1)
		queue_redraw()

var config: GameConfig = null:
	set(value):
		config = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(640.0, 200.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	match page:
		0:
			_draw_synthesis()
		1:
			_draw_switching()
		2:
			_draw_incubation()
		3:
			_draw_infection()


# ---- Lookups ---------------------------------------------------------------

func _shape_of(id: String) -> String:
	if config != null:
		if config.structures.has(id):
			return (config.structures[id] as StructureDef).placeholder_shape
		if config.pathogens.has(id):
			return (config.pathogens[id] as PathogenDef).placeholder_shape
	return str((FALLBACK_LOOKS[id] as Array)[0])


func _color_of(id: String) -> Color:
	if config != null:
		if config.structures.has(id):
			return (config.structures[id] as StructureDef).placeholder_color
		if config.pathogens.has(id):
			return (config.pathogens[id] as PathogenDef).placeholder_color
	return (FALLBACK_LOOKS[id] as Array)[1]


func _name_of(id: String) -> String:
	if config != null:
		if config.structures.has(id):
			return (config.structures[id] as StructureDef).display_name
		if config.pathogens.has(id):
			return (config.pathogens[id] as PathogenDef).display_name
	return id.capitalize()


func _cost_of(id: String) -> int:
	if config != null:
		if config.structures.has(id):
			return int((config.structures[id] as StructureDef).cost.get("atp", 0))
		if config.pathogens.has(id):
			return int((config.pathogens[id] as PathogenDef).cost.get("atp", 0))
	return 0


func _role_of(id: String) -> String:
	if config != null and config.pathogens.has(id):
		return (config.pathogens[id] as PathogenDef).role
	return ""


# ---- Drawing helpers -------------------------------------------------------

func _unit(id: String, center: Vector2, tile_scale: float = 1.0) -> void:
	var side: float = TILE * tile_scale
	PlaceholderShapes.draw_shape(self, _shape_of(id), Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), _color_of(id))


func _text(text: String, center_x: float, baseline_y: float, width: float = 200.0, color: Color = INK_COLOR) -> void:
	draw_string(get_theme_default_font(), Vector2(center_x - width * 0.5, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER, width, LABEL_SIZE, color)


func _caption(id: String, center: Vector2, with_cost: bool) -> void:
	_text(_name_of(id), center.x, center.y, 150.0)
	if with_cost and _cost_of(id) > 0:
		_text("%d ATP" % _cost_of(id), center.x, center.y + 18.0, 150.0, INK_COLOR.lightened(0.3))


func _arrow(from: Vector2, to: Vector2, color: Color, width: float = 3.0) -> void:
	var dir: Vector2 = (to - from).normalized()
	var side: Vector2 = dir.orthogonal()
	draw_line(from, to - dir * 6.0, color, width, true)
	draw_colored_polygon(PackedVector2Array([to, to - dir * 14.0 + side * 8.0, to - dir * 14.0 - side * 8.0]), color)


func _bolt(center: Vector2, scale_factor: float = 1.0) -> void:
	var w: float = 20.0 * scale_factor
	var h: float = 26.0 * scale_factor
	var o: Vector2 = center - Vector2(w, h) * 0.5
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(w * 0.58, h * 0.05), o + Vector2(w * 0.18, h * 0.52), o + Vector2(w * 0.48, h * 0.52),
		o + Vector2(w * 0.32, h * 0.95), o + Vector2(w * 0.82, h * 0.42), o + Vector2(w * 0.52, h * 0.42),
		o + Vector2(w * 0.68, h * 0.05),
	]), ATP_COLOR)


func _mini_grid(origin: Vector2, cols: int, rows: int) -> void:
	draw_rect(Rect2(origin, Vector2(cols, rows) * TILE), Color.WHITE, true)
	for x in range(cols + 1):
		draw_line(origin + Vector2(float(x) * TILE, 0.0), origin + Vector2(float(x) * TILE, float(rows) * TILE), GRID_LINE_COLOR, 1.0)
	for y in range(rows + 1):
		draw_line(origin + Vector2(0.0, float(y) * TILE), origin + Vector2(float(cols) * TILE, float(y) * TILE), GRID_LINE_COLOR, 1.0)


func _cell_center(origin: Vector2, cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


# ---- Pages -----------------------------------------------------------------

func _draw_synthesis() -> void:
	var y: float = size.y * 0.42
	var xs: Array[float] = [size.x * 0.18, size.x * 0.5, size.x * 0.82]

	# Walls block paths.
	for i in range(3):
		_unit("mucous_wall", Vector2(xs[0] + float(i - 1) * (TILE * 0.7), y), 0.7)
	_caption("mucous_wall", Vector2(xs[0], y + 50.0), true)

	# Macrophage splashes nearby pathogens.
	draw_circle(Vector2(xs[1], y), 56.0, Color(_color_of("macrophage"), 0.18))
	draw_arc(Vector2(xs[1], y), 56.0, 0.0, TAU, 40, _color_of("macrophage"), 2.0, true)
	_unit("macrophage", Vector2(xs[1], y))
	_unit("rhinovirus", Vector2(xs[1] - 40.0, y + 22.0), 0.45)
	_unit("rhinovirus", Vector2(xs[1] + 36.0, y - 24.0), 0.45)
	_caption("macrophage", Vector2(xs[1], y + 82.0), true)

	# B-Cell snipes from range.
	var target: Vector2 = Vector2(xs[2] + 56.0, y)
	_unit("b_cell", Vector2(xs[2] - 56.0, y))
	_unit("bacteriophage", target, 0.6)
	_arrow(Vector2(xs[2] - 32.0, y), target - Vector2(20.0, 0.0), _color_of("b_cell"), 2.0)
	_caption("b_cell", Vector2(xs[2] - 56.0, y + 50.0), true)


func _draw_switching() -> void:
	var y: float = size.y * 0.45
	var base_c: Vector2 = Vector2(size.x * 0.2, y)
	_unit("nucleus", base_c, 1.4)
	for offset: Vector2 in [Vector2(-1.3, 0.0), Vector2(1.3, 0.0), Vector2(0.0, -1.3), Vector2(0.0, 1.3)]:
		_unit("mucous_wall", base_c + offset * TILE * 0.9, 0.6)
	_unit("macrophage", base_c + Vector2(-1.3, -1.3) * TILE * 0.9, 0.6)
	_unit("b_cell", base_c + Vector2(1.3, 1.3) * TILE * 0.9, 0.6)
	_text("Your base", base_c.x, y + 82.0)

	_arrow(Vector2(size.x * 0.36, y), Vector2(size.x * 0.52, y), INK_COLOR)
	_text("Finalize", size.x * 0.44, y - 14.0, 100.0)

	var army_c: Vector2 = Vector2(size.x * 0.74, y)
	_unit("rhinovirus", army_c + Vector2(-50.0, -30.0), 0.8)
	_unit("bacteriophage", army_c + Vector2(20.0, -34.0), 0.8)
	_unit("staphylococcus", army_c + Vector2(-10.0, 28.0), 0.9)
	_unit("rhinovirus", army_c + Vector2(56.0, 26.0), 0.8)
	_text("Your army", army_c.x, y + 82.0)

	_bolt(Vector2(size.x * 0.44, y + 34.0), 1.2)
	_text("Unspent ATP", size.x * 0.44, y + 70.0, 130.0)


func _draw_incubation() -> void:
	var cols: int = 7
	var rows: int = 4
	var origin: Vector2 = Vector2(28.0, (size.y - float(rows) * TILE) * 0.5 - 6.0)
	_mini_grid(origin, cols, rows)

	# Deploy ring: the outer band of tiles.
	draw_rect(Rect2(origin, Vector2(cols, rows) * TILE).grow(-1.5), RING_COLOR, false, 3.0)
	draw_rect(Rect2(origin + Vector2(TILE, TILE), Vector2(cols - 2, rows - 2) * TILE), RING_COLOR, false, 3.0)

	# Base in the middle.
	_unit("nucleus", origin + Vector2(3.5, 2.0) * TILE, 1.3)
	_unit("macrophage", _cell_center(origin, Vector2i(2, 1)), 0.7)
	_unit("b_cell", _cell_center(origin, Vector2i(4, 2)), 0.7)

	# Pathogens on the ring, with a tap marker on the next spot.
	_unit("rhinovirus", _cell_center(origin, Vector2i(0, 1)), 0.7)
	_unit("rhinovirus", _cell_center(origin, Vector2i(0, 2)), 0.7)
	_unit("bacteriophage", _cell_center(origin, Vector2i(3, 0)), 0.7)
	var tap: Vector2 = _cell_center(origin, Vector2i(6, 1))
	draw_arc(tap, 12.0, 0.0, TAU, 24, INK_COLOR, 2.0, true)
	draw_arc(tap, 18.0, 0.0, TAU, 24, Color(INK_COLOR, 0.4), 2.0, true)
	_text("Tap the green ring", origin.x + float(cols) * TILE * 0.5, origin.y + float(rows) * TILE + 20.0, 260.0)

	# Legend from the pathogen roster.
	var lx: float = origin.x + float(cols) * TILE + 40.0
	var ids: Array[String] = ["rhinovirus", "bacteriophage", "staphylococcus"]
	for i in range(ids.size()):
		var ly: float = 46.0 + float(i) * 52.0
		_unit(ids[i], Vector2(lx + 16.0, ly), 0.8)
		draw_string(get_theme_default_font(), Vector2(lx + 44.0, ly - 2.0), _name_of(ids[i]), HORIZONTAL_ALIGNMENT_LEFT, 200.0, LABEL_SIZE, INK_COLOR)
		var role: String = _role_of(ids[i])
		if _cost_of(ids[i]) > 0:
			role = "%s · %d ATP" % [role, _cost_of(ids[i])] if not role.is_empty() else "%d ATP" % _cost_of(ids[i])
		draw_string(get_theme_default_font(), Vector2(lx + 44.0, ly + 16.0), role, HORIZONTAL_ALIGNMENT_LEFT, 220.0, LABEL_SIZE - 2, INK_COLOR.lightened(0.3))


func _draw_infection() -> void:
	var y: float = size.y * 0.5
	var nucleus_c: Vector2 = Vector2(size.x * 0.82, y)
	var wall_c: Vector2 = Vector2(size.x * 0.6, y - 34.0)
	var tower_c: Vector2 = Vector2(size.x * 0.6, y + 40.0)

	_unit("mucous_wall", wall_c, 0.8)
	_unit("macrophage", tower_c, 0.8)
	_unit("nucleus", nucleus_c, 1.5)

	# Nucleus health bar.
	var bar: Rect2 = Rect2(nucleus_c + Vector2(-40.0, -66.0), Vector2(80.0, 10.0))
	draw_rect(bar, Color(0.12, 0.12, 0.12, 0.8), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * 0.6, bar.size.y)), HP_BAD_COLOR, true)
	_text("Nucleus", nucleus_c.x, nucleus_c.y + 66.0, 120.0)

	# Pathogens and their faint intent lines.
	var starts: Array[Vector2] = [Vector2(size.x * 0.1, y - 50.0), Vector2(size.x * 0.1, y + 4.0), Vector2(size.x * 0.1, y + 58.0)]
	var goals: Array[Vector2] = [wall_c, nucleus_c, tower_c]
	var ids: Array[String] = ["rhinovirus", "staphylococcus", "bacteriophage"]
	for i in range(starts.size()):
		var color: Color = _color_of(ids[i])
		draw_line(starts[i], goals[i], Color(color, 0.35), 3.0, true)
		_unit(ids[i], starts[i], 0.8)
	_text("Faint lines show where they are heading", size.x * 0.34, size.y - 10.0, 340.0)
