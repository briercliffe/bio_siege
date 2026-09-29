class_name DeathVfx
extends Node2D

var pool: NodePool = null

enum Mode { PUFF, SPLASH }
var mode: Mode = Mode.PUFF

var _current_radius: float = 0.0
var _current_alpha: float = 1.0
var _color: Color = Color.WHITE
var _tween: Tween = null


func play_death_puff(p_pos: Vector2, entity_size: float, p_color: Color = Color(0.95, 0.95, 0.95, 0.85)) -> void:
	position = p_pos
	mode = Mode.PUFF
	_color = p_color
	var start_r: float = entity_size * 0.25
	var end_r: float = entity_size * 0.75
	_current_radius = start_r
	_current_alpha = _color.a
	show()
	set_process(true)

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "_current_radius", end_r, 0.3)
	_tween.tween_property(self, "_current_alpha", 0.0, 0.3)
	_tween.chain().tween_callback(_finish)


func play_splash_ring(p_pos: Vector2, radius_px: float, p_color: Color = Color(0.3, 0.7, 1.0, 0.9)) -> void:
	position = p_pos
	mode = Mode.SPLASH
	_color = p_color
	_current_radius = radius_px
	_current_alpha = _color.a
	show()
	set_process(true)

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_current_alpha", 0.0, 0.25)
	_tween.tween_callback(_finish)


func _finish() -> void:
	if pool != null:
		pool.release(self)
	else:
		hide()
		set_process(false)


func on_release() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	set_process(false)


func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _current_alpha <= 0.0:
		return
	var c := Color(_color.r, _color.g, _color.b, _current_alpha)
	match mode:
		Mode.PUFF:
			draw_circle(Vector2.ZERO, _current_radius, c)
		Mode.SPLASH:
			draw_arc(Vector2.ZERO, _current_radius, 0.0, TAU, 48, c, 2.0, true)
