class_name ProjectileView
extends Node2D

var pool: NodePool = null
var runner: BattleRunner = null

var proj_id: int = 0
var proj_state: ProjectileState = null
var tile_px: int = 32
var color: Color = Color.WHITE

var prev_pos: Vector2 = Vector2.ZERO
var curr_pos: Vector2 = Vector2.ZERO
var trail: Array[Vector2] = []


func setup(p_state: ProjectileState, p_color: Color, p_tile_px: int, p_runner: BattleRunner) -> void:
	proj_state = p_state
	proj_id = p_state.id
	color = p_color
	tile_px = p_tile_px
	runner = p_runner

	var px_pos: Vector2 = Vector2(
		float(p_state.pos.x) * float(tile_px) / 1000.0,
		float(p_state.pos.y) * float(tile_px) / 1000.0
	)
	prev_pos = px_pos
	curr_pos = px_pos
	position = px_pos
	trail.clear()
	visible = true
	queue_redraw()


func on_ticked() -> void:
	if proj_state != null:
		prev_pos = curr_pos
		curr_pos = Vector2(
			float(proj_state.pos.x) * float(tile_px) / 1000.0,
			float(proj_state.pos.y) * float(tile_px) / 1000.0
		)


func release_projectile() -> void:
	if pool != null:
		pool.release(self)
	else:
		hide()


func on_release() -> void:
	trail.clear()
	proj_state = null
	runner = null


func _process(_delta: float) -> void:
	var alpha: float = runner.alpha if runner != null else 1.0
	var new_pos: Vector2 = prev_pos.lerp(curr_pos, alpha)
	if trail.is_empty() or position.distance_squared_to(new_pos) > 1.0:
		trail.append(position)
		if trail.size() > 3:
			trail.pop_front()
	position = new_pos
	queue_redraw()


func _draw() -> void:
	for i in range(trail.size()):
		var pt: Vector2 = trail[i] - position
		var t_alpha: float = (float(i + 1) / float(trail.size() + 1)) * 0.5
		draw_circle(pt, 1.5, Color(color.r, color.g, color.b, t_alpha))
	# Small 4 px circle
	draw_circle(Vector2.ZERO, 2.0, color)
