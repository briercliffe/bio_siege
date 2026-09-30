class_name PathogenView
extends Node2D

var pool: NodePool = null
var runner: BattleRunner = null
var vfx_pool: NodePool = null

var pathogen_id: int = 0
var type_id: String = ""
var pathogen_state: PathogenState = null
var pathogen_def: PathogenDef = null
var tile_px: int = 32

var prev_pos: Vector2 = Vector2.ZERO
var curr_pos: Vector2 = Vector2.ZERO
var offset: Vector2 = Vector2.ZERO

var hp: int = 0
var max_hp: int = 0
var entity_size: float = 16.0

var _flash_tween: Tween = null
var _was_channeling: bool = false


func setup(p_state: PathogenState, p_def: PathogenDef, p_tile_px: int, p_runner: BattleRunner, p_vfx_pool: NodePool) -> void:
	pathogen_state = p_state
	pathogen_def = p_def
	pathogen_id = p_state.id
	type_id = p_state.type_id
	tile_px = p_tile_px
	runner = p_runner
	vfx_pool = p_vfx_pool

	hp = p_state.hp
	max_hp = p_state.max_hp

	var size_ratio: float = 0.45
	match type_id.to_lower():
		"staphylococcus":
			size_ratio = 0.55
		"bacteriophage":
			size_ratio = 0.45
		"rhinovirus":
			size_ratio = 0.35
	entity_size = float(tile_px) * size_ratio

	offset = Vector2(
		float(((pathogen_id * 37) % 11 - 5)) * 1.5,
		float(((pathogen_id * 53) % 11 - 5)) * 1.5
	)

	var px_pos: Vector2 = Vector2(
		float(p_state.pos.x) * float(tile_px) / 1000.0,
		float(p_state.pos.y) * float(tile_px) / 1000.0
	)
	prev_pos = px_pos
	curr_pos = px_pos
	position = curr_pos + offset
	modulate = Color.WHITE
	visible = true
	queue_redraw()


func on_ticked() -> void:
	if pathogen_state == null:
		return
	prev_pos = curr_pos
	curr_pos = Vector2(
		float(pathogen_state.pos.x) * float(tile_px) / 1000.0,
		float(pathogen_state.pos.y) * float(tile_px) / 1000.0
	)


func on_damaged(amount: int, new_hp: int) -> void:
	hp = new_hp
	queue_redraw()

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(2.0, 2.0, 2.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.1)


func on_killed() -> void:
	hp = 0
	if vfx_pool != null:
		var vfx = vfx_pool.acquire() as DeathVfx
		if vfx != null:
			var c: Color = pathogen_def.placeholder_color if pathogen_def != null else Color.WHITE
			vfx.play_death_puff(position, entity_size, c)

	if pool != null:
		pool.release(self)
	else:
		hide()


func on_release() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
		_flash_tween = null
	modulate = Color.WHITE
	pathogen_state = null
	pathogen_def = null
	runner = null
	vfx_pool = null


func _exit_tree() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
		_flash_tween = null


func _process(_delta: float) -> void:
	if pathogen_state != null and (pathogen_state.channel_target_id != 0 or _was_channeling):
		_was_channeling = pathogen_state.channel_target_id != 0
		queue_redraw()
	var alpha: float = runner.alpha if runner != null else 1.0
	position = prev_pos.lerp(curr_pos, alpha) + offset


func _draw() -> void:
	if pathogen_def == null:
		return

	var shape: String = pathogen_def.placeholder_shape if pathogen_def != null else "circle"
	var color: Color = pathogen_def.placeholder_color if pathogen_def != null else Color.WHITE
	var rect := Rect2(-entity_size * 0.5, -entity_size * 0.5, entity_size, entity_size)
	PlaceholderShapes.draw_shape(self, shape, rect, color)

	if pathogen_state != null and pathogen_state.channel_target_id != 0 and pathogen_def.hijack_channel_ticks > 0:
		var frac: float = 1.0 - float(pathogen_state.channel_ticks_left) / float(pathogen_def.hijack_channel_ticks)
		draw_arc(Vector2.ZERO, entity_size * 0.85, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 32, Color("#e67e22"), 3.0)

	# Health bar: shown only when hp < max_hp and hp > 0
	if hp < max_hp and hp > 0:
		var bar_w: float = entity_size * 0.8
		var bar_h: float = 4.0
		var bar_x: float = -bar_w * 0.5
		var bar_y: float = -entity_size * 0.5 - bar_h - 2.0

		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.7), true)

		var ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
		var fill_color := Color("#2ecc71")
		if ratio < 0.25:
			fill_color = Color("#e74c3c")
		elif ratio <= 0.5:
			fill_color = Color("#f1c40f")

		draw_rect(Rect2(bar_x, bar_y, bar_w * ratio, bar_h), fill_color, true)
