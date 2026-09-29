class_name Toast
extends Control

const ERROR_MESSAGES: Dictionary = {
	GridModel.PlaceError.OUT_OF_BOUNDS: "Outside the map",
	GridModel.PlaceError.DEPLOY_ZONE: "The outer ring is reserved for pathogen deployment",
	GridModel.PlaceError.OCCUPIED: "That tile is taken",
	GridModel.PlaceError.INSUFFICIENT_FUNDS: "Not enough ATP",
}

var last_message: String = ""
var last_floating_text: String = ""
var _current_pill: PanelContainer = null

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func message_for_place_error(reason: int) -> String:
	return ERROR_MESSAGES.get(reason, "")

func show_message(text: String) -> void:
	last_message = text
	if _current_pill != null and is_instance_valid(_current_pill):
		_current_pill.queue_free()
		_current_pill = null

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.9)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)

	add_child(panel)
	_current_pill = panel

	panel.layout_mode = 1
	panel.anchors_preset = Control.PRESET_CENTER
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var tween: Tween = create_tween()
	if tween != null:
		tween.tween_interval(1.0)
		tween.tween_property(panel, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func() -> void:
			if _current_pill == panel:
				_current_pill = null
			panel.queue_free()
		)

func show_floating_text(text: String, global_pos: Vector2) -> void:
	last_floating_text = text
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.modulate = Color("#2ecc71")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	add_child(label)
	label.global_position = global_pos - Vector2(label.size.x * 0.5, label.size.y * 0.5)
	var start_y: float = label.global_position.y

	var tween: Tween = create_tween()
	if tween != null:
		tween.set_parallel(true)
		tween.tween_property(label, "global_position:y", start_y - 20.0, 0.8)
		tween.tween_property(label, "modulate:a", 0.0, 0.8)
		tween.chain().tween_callback(label.queue_free)
