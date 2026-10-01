class_name AmbientBackground
extends Control

## Full-bleed background behind every screen. Port of mockup canvas Ambient.dc.html:
## a radial gradient, seeded translucent cells, and a vignette. Redraws on resize or theme change only.
##
## The gradient is GRADIENT_STEPS flat bands, the look of the canvas's stacked ellipses, built as one
## triangle list of non-overlapping rings so each pixel is filled once. Stacking 24 near-full-screen
## ellipses cost about 25 ms a frame on a software renderer behind the battle (docs/PERF_BASELINE.md).
## All geometry is cached per size and theme, so _draw() allocates nothing.

const GRADIENT_STEPS: int = 24
const GRADIENT_SEGMENTS: int = 64
## The outermost band reaches past the screen corners, in place of a full-screen edge-colour rect under it.
const GRADIENT_OUTER_K: float = 2.0
const VIGNETTE_RINGS: int = 10
const VIGNETTE_SEGMENTS: int = 64
const VIGNETTE_START: float = 0.55
const DAY_VIGNETTE_START: float = 0.60
const LCG_MOD: float = 2147483648.0
const LCG_MUL: float = 1103515245.0
const LCG_ADD: float = 12345.0
const LCG_SEED: float = 5.0
const CELL_ARC_POINTS: int = 48
const CELL_RING_WIDTH: float = 3.0

var night: bool = false:
	set = set_night

var _cache_key: Vector3 = Vector3(-1.0, -1.0, -1.0)
var _cells: Array[Dictionary] = []
var _grad_pts: PackedVector2Array = PackedVector2Array()
var _grad_cols: PackedColorArray = PackedColorArray()
var _grad_idx: PackedInt32Array = PackedInt32Array()
var _vig_pts: PackedVector2Array = PackedVector2Array()
var _vig_cols: PackedColorArray = PackedColorArray()
var _vig_idx: PackedInt32Array = PackedInt32Array()


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


## Colour of gradient band k (1 = innermost, GRADIENT_STEPS = outermost): the canvas stops at 0, 55% and 100%.
static func band_color(k: int, pal: Dictionary) -> Color:
	var c0: Color = pal["bg_center"] as Color
	var c1: Color = pal["bg_mid"] as Color
	var c2: Color = pal["bg_edge"] as Color
	var t: float = (float(k) - 0.5) / float(GRADIENT_STEPS)
	return c0.lerp(c1, t / 0.55) if t < 0.55 else c1.lerp(c2, (t - 0.55) / 0.45)


## Triangles in the cached gradient and vignette lists, for tests.
func triangle_counts() -> Vector2i:
	return Vector2i(_grad_idx.size() / 3, _vig_idx.size() / 3)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	_ensure_cache(w, h)
	var ci: RID = get_canvas_item()
	RenderingServer.canvas_item_add_triangle_array(ci, _grad_idx, _grad_pts, _grad_cols)
	for cell: Dictionary in _cells:
		var c := Vector2(cell["x"] as float, cell["y"] as float)
		var s: float = cell["size"] as float
		var ring: Color = cell["ring"] as Color
		draw_circle(c, s * 0.5, cell["fill"] as Color)
		draw_arc(c, s * 0.5 - CELL_RING_WIDTH * 0.5, 0.0, TAU, CELL_ARC_POINTS, ring, CELL_RING_WIDTH, true)
		draw_circle(c, s * 0.15, ring)
	RenderingServer.canvas_item_add_triangle_array(ci, _vig_idx, _vig_pts, _vig_cols)


func _ensure_cache(w: float, h: float) -> void:
	var key := Vector3(w, h, 1.0 if night else 0.0)
	if key == _cache_key:
		return
	_cache_key = key
	var pal: Dictionary = UiPalette.for_theme(night)
	_cells = cells(w, h, night)
	_build_gradient(w, h, pal)
	_build_vignette(w, h, pal["vignette"] as Color)


## CSS `ellipse at 50% 45%` sized to the farthest corner, as flat bands: band k fills the ring between the
## ellipses at (k - 1) / STEPS and k / STEPS of the radius, exactly what drawing the ellipses largest first
## over each other shows.
func _build_gradient(w: float, h: float, pal: Dictionary) -> void:
	var centre := Vector2(w * 0.5, h * 0.45)
	var rx: float = w * 0.5 * sqrt(2.0)
	var ry: float = h * 0.55 * sqrt(2.0)
	var n: int = GRADIENT_SEGMENTS
	var unit: PackedVector2Array = PackedVector2Array()
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		unit.append(Vector2(cos(a) * rx, sin(a) * ry))
	_grad_pts = PackedVector2Array()
	_grad_cols = PackedColorArray()
	_grad_idx = PackedInt32Array()
	# Band 1 is a fan around the centre.
	var col: Color = band_color(1, pal)
	_grad_pts.append(centre)
	_grad_cols.append(col)
	for i: int in range(n):
		_grad_pts.append(centre + unit[i] / float(GRADIENT_STEPS))
		_grad_cols.append(col)
	for i: int in range(n):
		_grad_idx.append_array(PackedInt32Array([0, 1 + i, 1 + (i + 1) % n]))
	# Bands 2..STEPS, then the edge colour from the outermost ellipse to past the corners. Each ring has its
	# own vertices so the colour stays flat across it.
	for k: int in range(2, GRADIENT_STEPS + 2):
		var inner_s: float = float(k - 1) / float(GRADIENT_STEPS)
		var outer_s: float = float(k) / float(GRADIENT_STEPS) if k <= GRADIENT_STEPS else GRADIENT_OUTER_K
		col = band_color(k, pal) if k <= GRADIENT_STEPS else pal["bg_edge"] as Color
		var base: int = _grad_pts.size()
		for i: int in range(n):
			_grad_pts.append(centre + unit[i] * inner_s)
			_grad_pts.append(centre + unit[i] * outer_s)
			_grad_cols.append(col)
			_grad_cols.append(col)
		for i: int in range(n):
			var a0: int = base + i * 2
			var b0: int = base + ((i + 1) % n) * 2
			_grad_idx.append_array(PackedInt32Array([a0, a0 + 1, b0 + 1, a0, b0 + 1, b0]))


## CSS `ellipse at 50% 50%`, transparent until `start`, then ramping to `edge` at the farthest corner.
func _build_vignette(w: float, h: float, edge: Color) -> void:
	var start: float = VIGNETTE_START if night else DAY_VIGNETTE_START
	var centre := Vector2(w * 0.5, h * 0.5)
	var rx: float = w * 0.5 * sqrt(2.0)
	var ry: float = h * 0.5 * sqrt(2.0)
	_vig_pts = PackedVector2Array()
	_vig_cols = PackedColorArray()
	_vig_idx = PackedInt32Array()
	for ring: int in range(VIGNETTE_RINGS + 1):
		var t: float = start + (1.0 - start) * float(ring) / float(VIGNETTE_RINGS)
		var a: float = edge.a * float(ring) / float(VIGNETTE_RINGS)
		for seg: int in range(VIGNETTE_SEGMENTS):
			var ang: float = TAU * float(seg) / float(VIGNETTE_SEGMENTS)
			_vig_pts.append(centre + Vector2(cos(ang) * rx * t, sin(ang) * ry * t))
			_vig_cols.append(Color(edge.r, edge.g, edge.b, a))
	for ring: int in range(VIGNETTE_RINGS):
		for seg: int in range(VIGNETTE_SEGMENTS):
			var nxt: int = (seg + 1) % VIGNETTE_SEGMENTS
			var a0: int = ring * VIGNETTE_SEGMENTS + seg
			var a1: int = ring * VIGNETTE_SEGMENTS + nxt
			var b0: int = (ring + 1) * VIGNETTE_SEGMENTS + seg
			var b1: int = (ring + 1) * VIGNETTE_SEGMENTS + nxt
			_vig_idx.append_array(PackedInt32Array([a0, a1, b0, a1, b1, b0]))
