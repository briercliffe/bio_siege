class_name BattleOverlay
extends Node2D

## Screen-space marks drawn after every sprite: B-Cell analysis rings and badges, hijack timers, channel
## arcs and strain dots. Projectiles, splash rings and health bars belong to EffectLayer. Read-only.

const ANALYSIS_COLOR: Color = Color("#48dbfb")
const HIJACK_COLOR: Color = Color("#8e44ad")
const CHANNEL_COLOR: Color = Color("#e67e22")

var sim: BattleSim = null
var config: GameConfig = null
var projection: IsoProjection = null
var snapshots: BattleSnapshotBuffer = null
var runner: BattleRunner = null

var _hijack_until: Dictionary = {}
var _badges: Dictionary = {}


func setup(p_sim: BattleSim, p_config: GameConfig, p_projection: IsoProjection, p_snapshots: BattleSnapshotBuffer, p_runner: BattleRunner) -> void:
	sim = p_sim
	config = p_config
	projection = p_projection
	snapshots = p_snapshots
	runner = p_runner
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
	_draw_structure_marks(k)
	_draw_pathogen_marks(k)


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
