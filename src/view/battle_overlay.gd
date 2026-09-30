class_name BattleOverlay
extends Node2D

## Screen-space legibility overlay drawn after every sprite: projectiles, splash rings, health
## bars, analysis rings and badges, hijack timers and channel arcs. Minimal port of the old per-node
## views to the isometric projection; the finished effect layer is a later issue. Read-only.

const PROJECTILE_LIFT_T: float = 1.5
const SPLASH_TICKS: int = 5
const SPLASH_STEPS: int = 40
const BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.65)
const BAR_GREEN: Color = Color("#2ecc71")
const BAR_AMBER: Color = Color("#f5b041")
const BAR_RED: Color = Color("#e74c3c")
const ANALYSIS_COLOR: Color = Color("#48dbfb")
const HIJACK_COLOR: Color = Color("#8e44ad")
const CHANNEL_COLOR: Color = Color("#e67e22")
const DEFAULT_SPLASH_COLOR: Color = Color(0.3, 0.7, 1.0, 0.9)

var sim: BattleSim = null
var config: GameConfig = null
var projection: IsoProjection = null
var snapshots: BattleSnapshotBuffer = null
var runner: BattleRunner = null

var _ring_pos: PackedVector2Array = PackedVector2Array()     # ground tiles
var _ring_radius: PackedFloat32Array = PackedFloat32Array()  # tiles
var _ring_start: PackedInt32Array = PackedInt32Array()
var _ring_color: PackedColorArray = PackedColorArray()
var _hijack_until: Dictionary = {}
var _badges: Dictionary = {}


func setup(p_sim: BattleSim, p_config: GameConfig, p_projection: IsoProjection, p_snapshots: BattleSnapshotBuffer, p_runner: BattleRunner) -> void:
	sim = p_sim
	config = p_config
	projection = p_projection
	snapshots = p_snapshots
	runner = p_runner
	_ring_pos.clear()
	_ring_radius.clear()
	_ring_start.clear()
	_ring_color.clear()
	_hijack_until.clear()
	_badges.clear()
	queue_redraw()


func _process(_delta: float) -> void:
	if sim != null:
		queue_redraw()


func on_event(ev: Dictionary) -> void:
	if sim == null:
		return
	match str(ev.get("type", "")):
		SimEvents.SPLASH:
			var s: StructureState = sim.structure(int(ev.get("structure_id", 0)))
			var color: Color = s.def.placeholder_color if (s != null and s.def != null) else DEFAULT_SPLASH_COLOR
			var pos_mt: Vector2i = ev.get("pos", Vector2i.ZERO)
			_ring_pos.append(Vector2(pos_mt) / 1000.0)
			_ring_radius.append(float(int(ev.get("radius", 0))) / 1000.0)
			_ring_start.append(sim.tick)
			_ring_color.append(color)
		SimEvents.HIJACK_COMPLETE:
			_hijack_until[int(ev.get("structure_id", 0))] = sim.tick + int(ev.get("duration_ticks", 0))
		SimEvents.ANALYSIS_COMPLETE:
			var sid: int = int(ev.get("structure_id", 0))
			var pdef: PathogenDef = config.pathogens.get(str(ev.get("unit_type", ""))) if config != null else null
			if not _badges.has(sid):
				_badges[sid] = PackedColorArray()
			var cols: PackedColorArray = _badges[sid]
			cols.append(pdef.placeholder_color if pdef != null else Color.WHITE)
			_badges[sid] = cols


## Screen polyline of an arc on a ground circle, so rings read as ellipses in the projection.
func _ground_arc(center_g: Vector2, radius: float, from: float, to: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(steps + 1):
		var a: float = lerpf(from, to, float(i) / float(steps))
		pts.append(projection.ground_to_screen(center_g + Vector2(cos(a), sin(a)) * radius))
	return pts


func _draw() -> void:
	if sim == null or projection == null:
		return
	var k: float = projection.tile_px / 14.0
	var now: float = float(sim.tick) + (runner.alpha if runner != null else 0.0)
	_draw_splashes(now, k)
	_draw_structure_marks(k)
	_draw_pathogen_marks(k)
	_draw_projectiles(k)
	_draw_health_bars(k)


func _draw_splashes(now: float, k: float) -> void:
	var i: int = 0
	while i < _ring_start.size():
		var age: float = now - float(_ring_start[i])
		if age >= float(SPLASH_TICKS):
			_ring_pos.remove_at(i)
			_ring_radius.remove_at(i)
			_ring_start.remove_at(i)
			_ring_color.remove_at(i)
			continue
		var c: Color = _ring_color[i]
		c.a *= 1.0 - maxf(age, 0.0) / float(SPLASH_TICKS)
		draw_polyline(_ground_arc(_ring_pos[i], _ring_radius[i], 0.0, TAU, SPLASH_STEPS), c, 2.0 * k, true)
		i += 1


func _draw_projectiles(k: float) -> void:
	if snapshots == null:
		return
	var alpha: float = runner.alpha if runner != null else 1.0
	var lift := Vector2(0.0, -PROJECTILE_LIFT_T * projection.tile_px)
	for j: ProjectileState in sim.projectiles:
		if j == null or not j.alive:
			continue
		var src: StructureState = sim.structure(j.source_id)
		var color: Color = src.def.placeholder_color if (src != null and src.def != null) else Color.WHITE
		var head_g: Vector2 = snapshots.projectile_ground(j.id, alpha) if snapshots.has_projectile(j.id) else Vector2(j.pos) / 1000.0
		var tail_g: Vector2 = snapshots.projectile_ground(j.id, alpha - 1.0) if snapshots.has_projectile(j.id) else head_g
		var head: Vector2 = projection.ground_to_screen(head_g) + lift
		var tail: Vector2 = projection.ground_to_screen(tail_g) + lift
		if head.distance_squared_to(tail) > 1.0:
			draw_line(tail, head, Color(color, 0.5), 1.5 * k)
		draw_circle(head, 2.0 * k, color)


func _draw_structure_marks(k: float) -> void:
	var t: float = projection.tile_px
	var font: Font = ThemeDB.fallback_font
	for s: StructureState in sim.structures:
		if not s.alive or s.def == null:
			continue
		var anchor_g: Vector2 = UnitLayer.structure_anchor(s)
		var size: Vector2 = UnitLayer.structure_size_px(s, projection)
		var foot: Vector2 = projection.ground_to_screen(anchor_g)

		if s.def.has_analysis:
			var key: String = s.analysis_focus_key
			if key != "" and not s.is_analyzed(key):
				var pct: int = s.analysis_progress_pct(key)
				var radius: float = 0.6 * float(maxi(s.footprint.x, s.footprint.y)) + 0.6
				draw_polyline(_ground_arc(anchor_g, radius, 0.0, TAU, 48), Color(ANALYSIS_COLOR, 0.25), 3.0 * k, true)
				if pct > 0:
					var sweep: float = TAU * float(pct) / 100.0
					draw_polyline(_ground_arc(anchor_g, radius, -PI * 0.5, -PI * 0.5 + sweep, 48), ANALYSIS_COLOR, 3.0 * k, true)
			if _badges.has(s.id):
				var cols: PackedColorArray = _badges[s.id]
				var badge_r: float = t * 0.18
				for i: int in range(cols.size()):
					var c := Vector2(foot.x - size.x * 0.5 + badge_r * (1.0 + 2.2 * float(i)), foot.y - size.y - badge_r - 1.0)
					draw_circle(c, badge_r, cols[i])
					draw_arc(c, badge_r, 0.0, TAU, 16, Color.WHITE, 1.0, true)

		if _hijack_until.has(s.id) and sim.tick < int(_hijack_until[s.id]):
			draw_polyline(_ground_arc(anchor_g, float(s.footprint.x) * 0.5, 0.0, TAU, 32), Color(HIJACK_COLOR, 0.8), 3.0 * k, true)
			var seconds: int = ceili(float(int(_hijack_until[s.id]) - sim.tick) / float(maxi(_tick_rate(), 1)))
			var fs: int = maxi(int(16.0 * k), 12)
			var txt: String = "%d" % seconds
			var tsize: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string(font, Vector2(foot.x - tsize.x * 0.5, foot.y - size.y * 0.5 + tsize.y * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _tick_rate() -> int:
	return config.tick_rate if config != null else 20


func _draw_pathogen_marks(k: float) -> void:
	var alpha: float = runner.alpha if runner != null else 1.0
	for p: PathogenState in sim.pathogens:
		if p == null or not p.alive or p.def == null:
			continue
		var ground: Vector2 = Vector2(p.pos) / 1000.0
		if snapshots != null and snapshots.has_unit(p.id):
			ground = snapshots.unit_ground(p.id, alpha)
		var size_t: Vector2 = UnitLayer.pathogen_size_t(p.type_id)
		if p.channel_target_id != 0 and p.def.hijack_channel_ticks > 0:
			var frac: float = 1.0 - float(p.channel_ticks_left) / float(p.def.hijack_channel_ticks)
			draw_polyline(_ground_arc(ground, size_t.x * 0.7, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 32), CHANNEL_COLOR, 3.0 * k, true)
		if p.strain_id != "wild":
			var dots: int = p.def.strain_ids().find(p.strain_id)
			if dots > 0:
				var top: Vector2 = projection.ground_to_screen(ground) + Vector2(0.0, -size_t.y * projection.tile_px - 12.0 * k)
				var spacing: float = 6.0 * k
				var x0: float = -float(dots - 1) * spacing * 0.5
				for i: int in range(dots):
					draw_circle(top + Vector2(x0 + float(i) * spacing, 0.0), 2.0 * k, Color(1.0, 1.0, 1.0, 0.9))


func _draw_health_bars(k: float) -> void:
	var alpha: float = runner.alpha if runner != null else 1.0
	for s: StructureState in sim.structures:
		if not s.alive or s.hp >= s.max_hp or s.hp <= 0:
			continue
		var size: Vector2 = UnitLayer.structure_size_px(s, projection)
		var foot: Vector2 = projection.ground_to_screen(UnitLayer.structure_anchor(s))
		_draw_bar(Vector2(foot.x, foot.y - size.y), maxf(size.x * 0.8, projection.tile_px * 0.9), float(s.hp) / float(s.max_hp), k)
	for p: PathogenState in sim.pathogens:
		if p == null or not p.alive or p.hp >= p.max_hp or p.hp <= 0:
			continue
		var ground: Vector2 = Vector2(p.pos) / 1000.0
		if snapshots != null and snapshots.has_unit(p.id):
			ground = snapshots.unit_ground(p.id, alpha)
		var size_t: Vector2 = UnitLayer.pathogen_size_t(p.type_id)
		var foot: Vector2 = projection.ground_to_screen(ground)
		_draw_bar(Vector2(foot.x, foot.y - size_t.y * projection.tile_px), maxf(size_t.x * projection.tile_px * 0.8, projection.tile_px * 0.9), float(p.hp) / float(p.max_hp), k)


## Health bar centred on `top`, sitting just above it.
func _draw_bar(top: Vector2, width: float, ratio: float, k: float) -> void:
	var h: float = 4.0 * k
	var rect := Rect2(top.x - width * 0.5, top.y - h - 2.0 * k, width, h)
	draw_rect(rect, BAR_BG, true)
	var color: Color = BAR_GREEN
	if ratio < 0.25:
		color = BAR_RED
	elif ratio <= 0.5:
		color = BAR_AMBER
	draw_rect(Rect2(rect.position, Vector2(width * clampf(ratio, 0.0, 1.0), h)), color, true)
