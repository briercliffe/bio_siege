class_name StructureView
extends Node2D

var structure_state: StructureState = null
var structure_def: StructureDef = null
var structure_id: int = 0
var tile_px: int = 32
var hp: int = 0
var max_hp: int = 0
var vfx_pool: NodePool = null

var _flash_tween: Tween = null


func setup(p_state: StructureState, p_def: StructureDef, p_tile_px: int, p_vfx_pool: NodePool) -> void:
	structure_state = p_state
	structure_def = p_def
	structure_id = p_state.id
	tile_px = p_tile_px
	vfx_pool = p_vfx_pool

	hp = p_state.hp
	max_hp = p_state.max_hp

	position = Vector2(p_state.origin) * float(tile_px)
	modulate = Color.WHITE
	visible = true
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


func _draw() -> void:
	if structure_state == null:
		return

	var w: float = float(structure_state.footprint.x * tile_px)
	var h: float = float(structure_state.footprint.y * tile_px)
	var s_rect := Rect2(0.0, 0.0, w, h)

	var shape: String = structure_def.placeholder_shape if structure_def != null else "square"
	var color: Color = structure_def.placeholder_color if structure_def != null else Color.WHITE
	PlaceholderShapes.draw_shape(self, shape, s_rect, color)

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
