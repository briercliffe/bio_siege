class_name StructureView
extends Node2D

var structure_state: StructureState = null
var structure_def: StructureDef = null
var structure_id: int = 0
var tile_px: int = 32
var hp: int = 0
var max_hp: int = 0
var vfx_pool: NodePool = null
var is_breached: bool = false

var _flash_tween: Tween = null
var _badge_colors: Array[Color] = []
var _drawn_ring_pct: int = -1
var _hijack_left_s: float = 0.0
var _drawn_hijack_s: int = 0


func setup(p_state: StructureState, p_def: StructureDef, p_tile_px: int, p_vfx_pool: NodePool) -> void:
	structure_state = p_state
	structure_def = p_def
	structure_id = p_state.id
	tile_px = p_tile_px
	vfx_pool = p_vfx_pool

	hp = p_state.hp
	max_hp = p_state.max_hp
	is_breached = false
	_badge_colors.clear()
	_drawn_ring_pct = -1
	_hijack_left_s = 0.0
	_drawn_hijack_s = 0

	position = Vector2(p_state.origin) * float(tile_px)
	modulate = Color.WHITE
	visible = true
	queue_redraw()


func set_breached(val: bool) -> void:
	if is_breached != val:
		is_breached = val
		queue_redraw()


func set_hijacked(duration_s: float) -> void:
	_hijack_left_s = maxf(duration_s, 0.0)
	queue_redraw()


func on_damaged(amount: int, new_hp: int) -> void:
	hp = new_hp
	queue_redraw()

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(2.0, 2.0, 2.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.1)


func on_destroyed() -> void:
	hp = 0
	_hijack_left_s = 0.0
	visible = false

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
		_flash_tween = null
	modulate = Color.WHITE

	if vfx_pool != null and structure_state != null:
		var vfx = vfx_pool.acquire() as DeathVfx
		if vfx != null:
			var w: float = float(structure_state.footprint.x * tile_px)
			var h: float = float(structure_state.footprint.y * tile_px)
			var center: Vector2 = position + Vector2(w * 0.5, h * 0.5)
			var entity_size: float = maxf(w, h)
			var c: Color = structure_def.placeholder_color if structure_def != null else Color.WHITE
			vfx.play_death_puff(center, entity_size, c)


func _exit_tree() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
		_flash_tween = null


func add_analysis_badge(color: Color) -> void:
	_badge_colors.append(color)
	queue_redraw()


func _analysis_ring_pct() -> int:
	if structure_state == null or structure_state.def == null or not structure_state.def.has_analysis:
		return -1
	var key: String = structure_state.analysis_focus_key
	if key == "" or structure_state.is_analyzed(key):
		return -1
	return structure_state.analysis_progress_pct(key)


func _process(delta: float) -> void:
	if _hijack_left_s > 0.0:
		_hijack_left_s = maxf(0.0, _hijack_left_s - delta)
		queue_redraw()
	elif _drawn_hijack_s != 0:
		queue_redraw()
	if is_breached:
		queue_redraw()
	elif _analysis_ring_pct() != _drawn_ring_pct:
		queue_redraw()


func get_crack_count() -> int:
	if max_hp <= 0:
		return 1
	if hp <= max_hp / 3:
		return 3
	elif hp <= (max_hp * 2) / 3:
		return 2
	return 1


func _draw_cracks(w: float, h: float, count: int, crack_color: Color) -> void:
	if w <= 0.0 or h <= 0.0:
		return
	if count >= 1:
		var crack1 := PackedVector2Array([
			Vector2(w * 0.2, 0.0),
			Vector2(w * 0.38, h * 0.28),
			Vector2(w * 0.28, h * 0.52),
			Vector2(w * 0.52, h * 0.78),
			Vector2(w * 0.45, h * 1.0)
		])
		draw_polyline(crack1, crack_color, 2.0)
	if count >= 2:
		var crack2 := PackedVector2Array([
			Vector2(w * 0.75, 0.0),
			Vector2(w * 0.58, h * 0.32),
			Vector2(w * 0.78, h * 0.64),
			Vector2(w * 0.68, h * 1.0)
		])
		draw_polyline(crack2, crack_color, 2.0)
	if count >= 3:
		var crack3 := PackedVector2Array([
			Vector2(0.0, h * 0.5),
			Vector2(w * 0.32, h * 0.38),
			Vector2(w * 0.58, h * 0.62),
			Vector2(w * 0.82, h * 0.44),
			Vector2(w * 1.0, h * 0.52)
		])
		draw_polyline(crack3, crack_color, 2.0)


func _draw() -> void:
	if structure_state == null:
		return

	var w: float = float(structure_state.footprint.x * tile_px)
	var h: float = float(structure_state.footprint.y * tile_px)
	var s_rect := Rect2(0.0, 0.0, w, h)

	var shape: String = structure_def.placeholder_shape if structure_def != null else "square"
	var color: Color = structure_def.placeholder_color if structure_def != null else Color.WHITE
	PlaceholderShapes.draw_shape(self, shape, s_rect, color)

	# Blocker crack overlay
	if is_breached and hp > 0:
		var pulse_time: float = fmod(float(Time.get_ticks_msec()) / 1000.0, 0.8)
		var pulse_alpha: float = lerpf(0.6, 1.0, 0.5 + 0.5 * sin((pulse_time / 0.8) * TAU))
		var crack_color := Color(0.23, 0.18, 0.18, pulse_alpha)
		var crack_count: int = get_crack_count()
		_draw_cracks(w, h, crack_count, crack_color)

	# Health bar: shown only when hp < max_hp and hp > 0
	if hp < max_hp and hp > 0:
		var bar_w: float = w * 0.8
		var bar_h: float = 4.0
		var bar_x: float = (w - bar_w) * 0.5
		var bar_y: float = -bar_h - 2.0

		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.7), true)

		var ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
		var fill_color := Color("#2ecc71")
		if ratio < 0.25:
			fill_color = Color("#e74c3c")
		elif ratio <= 0.5:
			fill_color = Color("#f1c40f")

		draw_rect(Rect2(bar_x, bar_y, bar_w * ratio, bar_h), fill_color, true)

	_draw_analysis(w, h)
	_draw_hijack(w, h)


func _draw_hijack(w: float, h: float) -> void:
	if _hijack_left_s <= 0.0:
		_drawn_hijack_s = 0
		return
	draw_rect(Rect2(0.0, 0.0, w, h), Color("#8e44ad", 0.4), true)
	_drawn_hijack_s = ceili(_hijack_left_s)
	var font: Font = ThemeDB.fallback_font
	var fs: int = 16
	var txt: String = "%d" % _drawn_hijack_s
	var tsize: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2((w - tsize.x) * 0.5, (h + tsize.y * 0.5) * 0.5 + 2.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_analysis(w: float, h: float) -> void:
	if structure_state == null or structure_state.def == null or not structure_state.def.has_analysis:
		return
	var ring_color := Color("#48dbfb")
	var ring_pct: int = _analysis_ring_pct()
	_drawn_ring_pct = ring_pct
	if ring_pct >= 0:
		var center := Vector2(w * 0.5, h * 0.5)
		var radius: float = 0.6 * maxf(w, h)
		draw_arc(center, radius, 0.0, TAU, 48, Color(ring_color, 0.25), 3.0)
		if ring_pct > 0:
			var sweep: float = deg_to_rad(float(ring_pct * 360) / 100.0)
			draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + sweep, 48, ring_color, 3.0)
	var badge_r: float = float(tile_px) * 0.18
	for i: int in range(_badge_colors.size()):
		var c := Vector2(badge_r * (1.0 + 2.2 * float(i)), -badge_r - 1.0)
		draw_circle(c, badge_r, _badge_colors[i])
		draw_arc(c, badge_r, 0.0, TAU, 16, Color.WHITE, 1.0)
