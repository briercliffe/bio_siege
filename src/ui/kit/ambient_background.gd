class_name AmbientBackground
extends Control

## Full-bleed background behind every screen. Port of mockup canvas Ambient.dc.html:
## a radial gradient, seeded translucent cells, and a vignette. Redraws on resize or theme change only.

const GRADIENT_STEPS: int = 24
const VIGNETTE_RINGS: int = 10
const VIGNETTE_SEGMENTS: int = 64
const VIGNETTE_START: float = 0.55
const DAY_VIGNETTE_START: float = 0.60
const LCG_MOD: float = 2147483648.0
const LCG_MUL: float = 1103515245.0
const LCG_ADD: float = 12345.0
const LCG_SEED: float = 5.0

var night: bool = false:
	set = set_night

# Kept as a member so the mesh outlives the draw call that references it.
var _vignette_mesh: ArrayMesh = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


func set_night(value: bool) -> void:
	night = value
	queue_redraw()


## Deterministic cell layout for a given size and theme (same LCG as the canvas source).
static func cells(w: float, h: float, is_night: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seed_value: float = LCG_SEED
	var count: int = maxi(6, int(roundf(w / 90.0)))
	var pal: Dictionary = UiPalette.for_theme(is_night)
	for i: int in range(count):
		seed_value = fmod(seed_value * LCG_MUL + LCG_ADD, LCG_MOD)
		var size_v: float = 40.0 + (seed_value / LCG_MOD) * 150.0
		seed_value = fmod(seed_value * LCG_MUL + LCG_ADD, LCG_MOD)
		var x: float = (seed_value / LCG_MOD) * w
		seed_value = fmod(seed_value * LCG_MUL + LCG_ADD, LCG_MOD)
		var y: float = (seed_value / LCG_MOD) * h
		out.append({
			"x": x,
			"y": y,
			"size": size_v,
			"fill": pal["cell_fill"],
			"ring": pal["cell_ring"],
		})
	return out


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var pal: Dictionary = UiPalette.for_theme(night)
	_draw_gradient(w, h, pal)
	for cell: Dictionary in cells(w, h, night):
		var c := Vector2(cell["x"] as float, cell["y"] as float)
		var s: float = cell["size"] as float
		var ring: Color = cell["ring"] as Color
		draw_circle(c, s * 0.5, cell["fill"] as Color)
		draw_arc(c, s * 0.5 - 1.5, 0.0, TAU, 48, ring, 3.0, true)
		draw_circle(c, s * 0.15, ring)
	_draw_vignette(w, h, pal["vignette"] as Color)


func _draw_gradient(w: float, h: float, pal: Dictionary) -> void:
	var c0: Color = pal["bg_center"] as Color
	var c1: Color = pal["bg_mid"] as Color
	var c2: Color = pal["bg_edge"] as Color
	draw_rect(Rect2(Vector2.ZERO, size), c2)
	# CSS `ellipse at 50% 45%` sized to the farthest corner.
	var centre := Vector2(w * 0.5, h * 0.45)
	var rx: float = w * 0.5 * sqrt(2.0)
	var ry: float = h * 0.55 * sqrt(2.0)
	for k: int in range(GRADIENT_STEPS, 0, -1):
		var t: float = (float(k) - 0.5) / float(GRADIENT_STEPS)
		var col: Color = c0.lerp(c1, t / 0.55) if t < 0.55 else c1.lerp(c2, (t - 0.55) / 0.45)
		draw_colored_polygon(_ellipse(centre, rx * float(k) / float(GRADIENT_STEPS), ry * float(k) / float(GRADIENT_STEPS)), col)


func _draw_vignette(w: float, h: float, edge: Color) -> void:
	# CSS `ellipse at 50% 50%`, transparent until `start`, then ramping to `edge` at the farthest corner.
	var start: float = VIGNETTE_START if night else DAY_VIGNETTE_START
	var centre := Vector2(w * 0.5, h * 0.5)
	var rx: float = w * 0.5 * sqrt(2.0)
	var ry: float = h * 0.5 * sqrt(2.0)
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	for ring: int in range(VIGNETTE_RINGS + 1):
		var t: float = start + (1.0 - start) * float(ring) / float(VIGNETTE_RINGS)
		var a: float = edge.a * float(ring) / float(VIGNETTE_RINGS)
		for seg: int in range(VIGNETTE_SEGMENTS):
			var ang: float = TAU * float(seg) / float(VIGNETTE_SEGMENTS)
			verts.append(centre + Vector2(cos(ang) * rx * t, sin(ang) * ry * t))
			cols.append(Color(edge.r, edge.g, edge.b, a))
	for ring: int in range(VIGNETTE_RINGS):
		for seg: int in range(VIGNETTE_SEGMENTS):
			var nxt: int = (seg + 1) % VIGNETTE_SEGMENTS
			var a0: int = ring * VIGNETTE_SEGMENTS + seg
			var a1: int = ring * VIGNETTE_SEGMENTS + nxt
			var b0: int = (ring + 1) * VIGNETTE_SEGMENTS + seg
			var b1: int = (ring + 1) * VIGNETTE_SEGMENTS + nxt
			indices.append_array(PackedInt32Array([a0, a1, b0, a1, b1, b0]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	_vignette_mesh = ArrayMesh.new()
	_vignette_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	draw_mesh(_vignette_mesh, null)


static func _ellipse(centre: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n: int = 64
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
