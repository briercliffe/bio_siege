class_name SideSwitchOverlay
extends Control

signal finished(duration_ms: int, skipped: bool)

var background_rect: TextureRect = null
var title_label: Label = null
var subtitle_label: Label = null
var body_label: Label = null

var _start_time_ms: int = 0
var _is_dismissing: bool = false
var _active_tween: Tween = null

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ensure_nodes() -> void:
	if background_rect != null:
		return

	background_rect = get_node_or_null("Background") as TextureRect
	title_label = get_node_or_null("CenterContainer/VBoxContainer/TitleLabel") as Label
	subtitle_label = get_node_or_null("CenterContainer/VBoxContainer/SubtitleLabel") as Label
	body_label = get_node_or_null("CenterContainer/VBoxContainer/BodyLabel") as Label

	if background_rect != null:
		_setup_gradient()
		return

	# Fallback programmatic node creation (e.g. for unit tests)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	background_rect = TextureRect.new()
	background_rect.name = "Background"
	background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_rect.stretch_mode = TextureRect.STRETCH_SCALE
	background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_rect)
	_setup_gradient()

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(600.0, 0.0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Switching sides"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.text = "You are now the Pathogen"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 24)
	subtitle_label.add_theme_color_override("font_color", Color("#c0392b"))
	vbox.add_child(subtitle_label)

	body_label = Label.new()
	body_label.name = "BodyLabel"
	body_label.text = "Spend your remaining 0 ATP on an army and raid the base you just built."
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 18)
	body_label.add_theme_color_override("font_color", Color("#f5e6e8"))
	vbox.add_child(body_label)

func _setup_gradient() -> void:
	if background_rect == null:
		return
	var grad := Gradient.new()
	grad.set_color(0, Color("#3a0d12"))
	grad.set_color(1, Color.BLACK)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	background_rect.texture = tex

func _ready() -> void:
	_ensure_nodes()

func play(remaining_atp: int) -> void:
	_ensure_nodes()
	set_remaining_atp(remaining_atp)

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	_is_dismissing = false
	_start_time_ms = Time.get_ticks_msec()
	visible = true
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_active_tween.tween_interval(2.0)
	_active_tween.tween_callback(func(): dismiss(false))

func set_remaining_atp(remaining_atp: int) -> void:
	_ensure_nodes()
	if body_label != null:
		body_label.text = "Spend your remaining %d ATP on an army and raid the base you just built." % remaining_atp

func dismiss(skipped: bool = false) -> void:
	if _is_dismissing:
		return
	_is_dismissing = true

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	var duration_ms: int = Time.get_ticks_msec() - _start_time_ms
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("side_switch", {
			"duration_ms": duration_ms,
			"skipped": skipped
		})

	_active_tween = create_tween()
	if _active_tween != null:
		_active_tween.tween_property(self, "modulate:a", 0.0, 0.3)
		_active_tween.tween_callback(func():
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			finished.emit(duration_ms, skipped)
		)
	else:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		finished.emit(duration_ms, skipped)

func _gui_input(event: InputEvent) -> void:
	if not visible or _is_dismissing:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			dismiss(true)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			accept_event()
			dismiss(true)
