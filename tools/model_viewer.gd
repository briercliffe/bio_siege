extends Control

## Developer scene for building and reviewing model painters without playing a battle (#66,
## docs/MODEL_PIPELINE_PLAN.md section 7.1). Open tools/model_viewer.tscn and press F6. It is not part
## of the shipped game and nothing in src/ references it.
##
## Contact sheet from the command line (needs a renderer, so not --headless; on a Linux machine
## without a display wrap it in xvfb-run):
##   godot --path . tools/model_viewer.tscn -- --contact-sheet=<absolute path to a .png>
## The PNG is written and the editor quits. Never commit contact sheets: attach them to PRs.
## --walls-sheet=<absolute path to a .png> writes the "walls" layout alone at T = 40 instead.

const POST_ID: String = "post"
const WALLS_ID: String = "walls"
const STATE_NAMES: Array[String] = ["IDLE", "MOVE", "WINDUP", "STRIKE", "RECOVER", "HIT", "DEAD", "Attack loop"]
const STATE_ATTACK_LOOP: int = 7
const TILE_SIZES: Array[int] = [14, 28, 40, 56]
const SCRUB_MAX_S: float = 2.0
const TICKS_PER_S: float = 20.0
const SPEEDS: Array[float] = [0.25, 1.0]
const SPEED_LABELS: Array[String] = ["0.25x", "1x"]
const BTN_H: float = 48.0
const LEFT_W: float = 300.0
const RIGHT_W: float = 200.0
const STAGE_PAD_TILES: float = 6.0
const CELL_PAD_TILES: float = 3.4
const CELL_SIZE: Vector2i = Vector2i(240, 240)
const CELL_TILE_PX: float = 56.0
const CELL_ANCHOR: Vector2 = Vector2(120.0, 185.0)
const CELL_DEATH_T: float = 0.5
const CELL_GAIT: float = 0.25
const DEFAULT_ATTACK_INTERVAL_TICKS: int = 20
const ANCHOR_CROSS_PX: float = 10.0
const MIN_CYCLE_TICKS: int = 2

## The walls_sheet.png layout: a straight run, two columns hanging off it, a hurt pair and a gap.
const WALL_RUN: Vector4i = Vector4i(12, 16, 22, 16)
const WALL_COLUMNS: Array[Vector4i] = [Vector4i(17, 17, 17, 20), Vector4i(12, 17, 12, 20)]
const WALL_HURT: Array[Vector2i] = [Vector2i(20, 16), Vector2i(21, 16)]
const WALL_GONE: Array[Vector2i] = [Vector2i(15, 16)]
## Ground point drawn at the stage centre, so the layout sits in the middle.
const WALLS_FOCUS: Vector2 = Vector2(16.0, 17.0)
const WALLS_PAD_TILES: float = 16.0
const WALLS_CELL_TILE_PX: float = 16.0
const WALLS_SHEET_TILE_PX: float = 40.0
const WALLS_SHEET_SIZE: Vector2i = Vector2i(1000, 460)
const WALL_HURT_FRAC: float = 0.3
const WALL_TAP_MODES: Array[String] = ["hurt", "destroy", "attack"]

## Columns of the contact sheet, in order.
const SHEET_STATES: Array[int] = [
	ModelPose.Anim.IDLE, ModelPose.Anim.MOVE, ModelPose.Anim.WINDUP,
	ModelPose.Anim.STRIKE, ModelPose.Anim.HIT, ModelPose.Anim.DEAD,
]

const DAY_BG: Color = Color("#d8e9f7")
const NIGHT_BG: Color = Color("#241017")
const PAD_TOP_DAY: Color = Color("#eef6fc")
const PAD_TOP_NIGHT: Color = Color("#34111a")
const PAD_RIM_DAY: Color = Color("#a9c8e4")
const PAD_RIM_NIGHT: Color = Color("#6b2632")
const PAD_SHADOW_DAY: Color = Color("#7f9fbd")
const PAD_SHADOW_NIGHT: Color = Color("#2c0e15")
const DEBUG_RED: Color = Color("#e74c3c")
const DEBUG_BOX: Color = Color("#2ecc71")
const DEBUG_FOOT: Color = Color("#f39c12")
const LABEL_DAY: Color = Color("#12304f")
const LABEL_NIGHT: Color = Color("#f4d9de")
const PAD_SLAB_T: float = 0.25

const THEME_DAY: String = "res://src/ui/theme_day.tres"
const THEME_NIGHT: String = "res://src/ui/theme_night.tres"


## A Node2D that forwards _draw to a callable, and counts its redraws for the tests.
class Stage extends Node2D:
	var draw_cb: Callable = Callable()
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		if draw_cb.is_valid():
			draw_cb.call(self)


## One clipped contact-sheet cell.
class Cell extends Control:
	var draw_cb: Callable = Callable()

	func _draw() -> void:
		if draw_cb.is_valid():
			draw_cb.call(self)


var config: GameConfig = null
var model_ids: Array[String] = []

var model_id: String = ""
var state_index: int = 0
var facing_right: bool = true
var tile_px: int = 14
var night: bool = false
var time_s: float = 0.0
var playing: bool = false
var speed: float = 1.0
var show_anchor: bool = false
var show_footprint: bool = false
var show_gait: bool = false
var show_bounds: bool = false

## Walls entry state: layout cells, and the cells marked hurt, destroyed or under attack (cell -> true).
var wall_cells: Array[Vector2i] = []
var wall_hurt: Dictionary = {}
var wall_gone: Dictionary = {}
var wall_attacked: Dictionary = {}
## What a tap on the stage does to a wall cell: "" (nothing), "hurt", "destroy" or "attack".
var wall_tap_mode: String = ""
var wall_tap_buttons: Array[Button] = []

var stage: Stage = null
var model_option: OptionButton = null
var state_option: OptionButton = null
var scrubber: HSlider = null
var play_button: Button = null
var export_button: Button = null
var path_label: Label = null
var gait_label: Label = null
var facing_buttons: Array[Button] = []
var tile_buttons: Array[Button] = []
var theme_buttons: Array[Button] = []
var speed_buttons: Array[Button] = []

var _holder: Control = null
var _bg: ColorRect = null
var _updating_ui: bool = false
var _exporting: bool = false
var _post_painter: WallPainter = WallPainter.new(true)
## One cache per projection, so the stage, the contact sheet cells and the walls sheet do not rebuild each
## other's geometry every frame.
var _walls: WallsCache = WallsCache.new()
var _sheet_walls: WallsCache = WallsCache.new()
var _walls_sheet_walls: WallsCache = WallsCache.new()
var _walls_order: Array[Vector2i] = []
var _walls_version: int = 0


## A WallRenderer and the projection and layout version it was last rebuilt for.
class WallsCache extends RefCounted:
	var renderer: WallRenderer = WallRenderer.new()
	var key: Vector4 = Vector4(-1.0, 0.0, 0.0, 0.0)
	var rebuilds: int = 0


## Size in px of a contact sheet: states are columns, models are rows.
static func contact_sheet_size(models: int, states: int, cell: Vector2i) -> Vector2i:
	return Vector2i(states * cell.x, models * cell.y)


func _ready() -> void:
	config = GameData.config
	if config == null:
		config = GameConfig.load_from_dir("res://data").config
	ModelRegistry.configure(config)
	model_ids = _collect_model_ids()
	model_id = model_ids[0]
	wall_cells = _layout_cells()
	reset_walls()
	_build_ui()
	_apply_theme()
	_refresh()
	var sheet_path: String = _cli_arg("--contact-sheet=")
	if sheet_path != "":
		_run_cli_export.call_deferred(sheet_path)
	var walls_path: String = _cli_arg("--walls-sheet=")
	if walls_path != "":
		_run_cli_walls_export.call_deferred(walls_path)


func _collect_model_ids() -> Array[String]:
	var ids: Array[String] = []
	if config != null:
		for id_var: Variant in config.pathogens:
			ids.append(str(id_var))
		for id_var: Variant in config.structures:
			ids.append(str(id_var))
	ids.append(POST_ID)
	ids.append(WALLS_ID)
	return ids


# --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_left_panel())

	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 0)
	root.add_child(centre)

	var upper := HBoxContainer.new()
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper.add_theme_constant_override("separation", 0)
	centre.add_child(upper)

	_holder = Control.new()
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.clip_contents = true
	_holder.resized.connect(_on_holder_resized)
	_holder.gui_input.connect(_on_holder_input)
	upper.add_child(_holder)
	stage = Stage.new()
	stage.draw_cb = _draw_stage
	_holder.add_child(stage)
	gait_label = Label.new()
	gait_label.position = Vector2(12.0, 8.0)
	_holder.add_child(gait_label)
	path_label = Label.new()
	path_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	path_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	path_label.offset_left = 12.0
	path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_holder.add_child(path_label)

	upper.add_child(_build_right_panel())
	centre.add_child(_build_bottom_bar())


func _margin_box(panel: Container, margin_px: int, separation: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, margin_px)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	margin.add_child(box)
	return box


func _build_left_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(LEFT_W, 0.0)
	var box: VBoxContainer = _margin_box(panel, 10, 8)

	box.add_child(_caption("Model"))
	model_option = _option(model_ids)
	model_option.item_selected.connect(_on_model_selected)
	box.add_child(model_option)

	box.add_child(_caption("State"))
	state_option = _option(STATE_NAMES)
	state_option.item_selected.connect(_on_state_selected)
	box.add_child(state_option)

	box.add_child(_caption("Facing"))
	facing_buttons = _radio_row(box, ["Right", "Left"], 0, _on_facing_pressed)

	box.add_child(_caption("Tile size"))
	var tile_labels: Array[String] = []
	for t: int in TILE_SIZES:
		tile_labels.append(str(t))
	tile_buttons = _radio_row(box, tile_labels, 0, _on_tile_pressed)

	box.add_child(_caption("Theme"))
	theme_buttons = _radio_row(box, ["Day", "Night"], 0, _on_theme_pressed)

	export_button = _button("Export contact sheet", false)
	export_button.pressed.connect(func() -> void: export_contact_sheet())
	box.add_child(export_button)
	return panel


func _build_right_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(RIGHT_W, 0.0)
	var box: VBoxContainer = _margin_box(panel, 10, 8)
	box.add_child(_caption("Debug"))
	var specs: Array[Array] = [["Anchor cross", "show_anchor"], ["Footprint", "show_footprint"],
			["Gait phase", "show_gait"], ["Bounding box", "show_bounds"]]
	for spec: Array in specs:
		var b: Button = _button(str(spec[0]), true)
		var prop: String = str(spec[1])
		b.toggled.connect(func(on: bool) -> void: _on_debug_toggled(prop, on))
		box.add_child(b)

	box.add_child(_caption("Walls: tap a cell to"))
	wall_tap_buttons = []
	for mode: String in WALL_TAP_MODES:
		var b: Button = _button(mode.capitalize(), true)
		var m: String = mode
		b.pressed.connect(func() -> void: set_wall_tap_mode("" if wall_tap_mode == m else m))
		wall_tap_buttons.append(b)
		box.add_child(b)
	var reset: Button = _button("Reset walls", false)
	reset.pressed.connect(func() -> void: reset_walls())
	box.add_child(reset)
	return panel


func _build_bottom_bar() -> Control:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	play_button = _button("Play", false)
	play_button.custom_minimum_size = Vector2(88.0, BTN_H)
	play_button.pressed.connect(_on_play_pressed)
	row.add_child(play_button)

	scrubber = HSlider.new()
	scrubber.min_value = 0.0
	scrubber.max_value = SCRUB_MAX_S
	scrubber.step = 0.01
	scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrubber.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scrubber.custom_minimum_size = Vector2(160.0, BTN_H)
	scrubber.value_changed.connect(_on_scrub)
	row.add_child(scrubber)

	speed_buttons = []
	for i: int in range(SPEEDS.size()):
		var b: Button = _button(SPEED_LABELS[i], true)
		b.button_pressed = SPEEDS[i] == speed
		var idx: int = i
		b.pressed.connect(func() -> void: _on_speed_pressed(idx))
		speed_buttons.append(b)
		row.add_child(b)

	var specs: Array[Array] = [["Hit", "hit"], ["Attack", "attack"], ["Death", "death"]]
	for spec: Array in specs:
		var b: Button = _button(str(spec[0]), false)
		var kind: String = str(spec[1])
		b.pressed.connect(func() -> void: trigger(kind))
		row.add_child(b)
	return panel


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BTN_H, BTN_H)
	return b


func _option(items: Array[String]) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(BTN_H, BTN_H)
	o.focus_mode = Control.FOCUS_NONE
	for s: String in items:
		o.add_item(s)
	o.get_popup().add_theme_constant_override("v_separation", 14)
	return o


## A row of mutually exclusive toggle buttons, with button `selected` pressed.
func _radio_row(parent: Control, labels: Array[String], selected: int, cb: Callable) -> Array[Button]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var out: Array[Button] = []
	for i: int in range(labels.size()):
		var b: Button = _button(labels[i], true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == selected
		var idx: int = i
		b.pressed.connect(func() -> void: cb.call(idx))
		out.append(b)
		row.add_child(b)
	return out


func _set_radio(buttons: Array[Button], index: int) -> void:
	for i: int in range(buttons.size()):
		buttons[i].set_pressed_no_signal(i == index)


# --- handlers ---------------------------------------------------------------

func _on_model_selected(index: int) -> void:
	select_model(model_ids[index])


func _on_state_selected(index: int) -> void:
	state_index = index
	_refresh()


func _on_facing_pressed(index: int) -> void:
	facing_right = index == 0
	_set_radio(facing_buttons, index)
	_refresh()


func _on_tile_pressed(index: int) -> void:
	tile_px = TILE_SIZES[index]
	_set_radio(tile_buttons, index)
	_refresh()


func _on_theme_pressed(index: int) -> void:
	night = index == 1
	_set_radio(theme_buttons, index)
	_apply_theme()
	_refresh()


func _on_debug_toggled(prop: String, on: bool) -> void:
	set(prop, on)
	_refresh()


func _on_play_pressed() -> void:
	playing = not playing
	_refresh()


func _on_speed_pressed(index: int) -> void:
	speed = SPEEDS[index]
	_set_radio(speed_buttons, index)


func _on_scrub(value: float) -> void:
	if _updating_ui:
		return
	time_s = value
	_refresh()


func _on_holder_input(event: InputEvent) -> void:
	if not event is InputEventScreenTouch:
		return
	var touch: InputEventScreenTouch = event
	if touch.pressed or model_id != WALLS_ID or wall_tap_mode == "":
		return
	tap_wall_cell(_walls_projection(float(tile_px)).screen_to_cell(touch.position - stage.position))


func _on_holder_resized() -> void:
	if stage != null and _holder != null:
		stage.position = (_holder.size * 0.5).round()
		stage.queue_redraw()


# --- walls entry --------------------------------------------------------------

func _layout_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: int in range(WALL_RUN.x, WALL_RUN.z + 1):
		out.append(Vector2i(c, WALL_RUN.y))
	for col: Vector4i in WALL_COLUMNS:
		for r: int in range(col.y, col.w + 1):
			out.append(Vector2i(col.x, r))
	return out


## Back to the sheet: the hurt pair and the gap, nothing under attack.
func reset_walls() -> void:
	wall_hurt.clear()
	wall_gone.clear()
	wall_attacked.clear()
	for c: Vector2i in WALL_HURT:
		wall_hurt[c] = true
	for c: Vector2i in WALL_GONE:
		wall_gone[c] = true
	_walls_version += 1
	_refresh()


func set_wall_tap_mode(mode: String) -> void:
	wall_tap_mode = mode if WALL_TAP_MODES.has(mode) else ""
	for i: int in range(wall_tap_buttons.size()):
		wall_tap_buttons[i].set_pressed_no_signal(WALL_TAP_MODES[i] == wall_tap_mode)


## Toggles the tapped layout cell for the current tap mode. Returns false when the cell is not in the layout.
func tap_wall_cell(cell: Vector2i) -> bool:
	if not wall_cells.has(cell) or wall_tap_mode == "":
		return false
	var target: Dictionary = wall_hurt
	match wall_tap_mode:
		"destroy":
			target = wall_gone
		"attack":
			target = wall_attacked
	if target.has(cell):
		target.erase(cell)
	else:
		target[cell] = true
	_walls_version += 1
	_refresh()
	return true


func _walls_projection(t: float) -> IsoProjection:
	var proj := IsoProjection.new(t, Vector2.ZERO)
	proj.origin = -proj.ground_to_screen(WALLS_FOCUS)
	return proj


func _ensure_walls(cache: WallsCache, proj: IsoProjection) -> void:
	var key := Vector4(proj.tile_px, proj.origin.x, proj.origin.y, float(_walls_version))
	if key == cache.key:
		return
	cache.key = key
	cache.rebuilds += 1
	var alive: Dictionary = {}
	for c: Vector2i in wall_cells:
		if not wall_gone.has(c):
			alive[c] = true
	cache.renderer.rebuild(alive, proj)
	_walls_order.clear()
	for c: Vector2i in wall_cells:
		_walls_order.append(c)
	_walls_order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.x < b.x))


## The layout in depth order. Hit shakes every segment; the death state plays the break on destroyed cells.
func _draw_walls(ci: CanvasItem, cache: WallsCache, proj: IsoProjection, pose: ModelPose) -> void:
	_ensure_walls(cache, proj)
	var walls: WallRenderer = cache.renderer
	var dead: bool = pose.anim == ModelPose.Anim.DEAD
	if dead:
		for c: Vector2i in _walls_order:
			if wall_gone.has(c):
				walls.paint_goo(ci, c, pose.death_t)
	walls.paint_shadows(ci)
	var crack_alpha: float = UnitLayer.crack_pulse_alpha(pose.time)
	for c: Vector2i in _walls_order:
		if wall_gone.has(c):
			if dead:
				walls.paint_break(ci, c, pose.death_t)
			continue
		var hurt: bool = wall_hurt.has(c)
		if wall_attacked.has(c):
			# The battle order: body, post at full health, then the pulsing cracks in place of the resting ones.
			walls.paint_body(ci, c, hurt, pose)
			if not hurt:
				walls.paint_post(ci, c, pose)
			walls.paint_cracks(ci, c, hurt, crack_alpha, pose)
		else:
			walls.paint_cell(ci, c, WALL_HURT_FRAC if hurt else 1.0, pose)


## Selects a model by id (also updates the option button).
func select_model(id: String) -> void:
	var idx: int = model_ids.find(id)
	if idx < 0:
		return
	model_id = id
	model_option.select(idx)
	_refresh()


func select_state(index: int) -> void:
	state_index = clampi(index, 0, STATE_NAMES.size() - 1)
	state_option.select(state_index)
	_refresh()


## Sets the pose as if the event had just happened and starts playing.
func trigger(kind: String) -> void:
	match kind:
		"hit":
			state_index = ModelPose.Anim.HIT
		"attack":
			state_index = STATE_ATTACK_LOOP
		"death":
			state_index = ModelPose.Anim.DEAD
		_:
			return
	state_option.select(state_index)
	time_s = 0.0
	playing = true
	_refresh()


func _apply_theme() -> void:
	theme = load(THEME_NIGHT if night else THEME_DAY) as Theme
	_bg.color = NIGHT_BG if night else DAY_BG
	var ink: Color = LABEL_NIGHT if night else LABEL_DAY
	gait_label.add_theme_color_override("font_color", ink)
	path_label.add_theme_color_override("font_color", ink)


func _process(delta: float) -> void:
	if not playing:
		return
	time_s = fposmod(time_s + delta * speed, SCRUB_MAX_S)
	_refresh()


func _refresh() -> void:
	if stage == null:
		return
	_updating_ui = true
	scrubber.value = time_s
	_updating_ui = false
	play_button.text = "Pause" if playing else "Play"
	var pose: ModelPose = pose_for(model_id, state_index, time_s)
	gait_label.visible = show_gait
	gait_label.text = "gait phase %.3f" % pose.gait_phase
	stage.queue_redraw()


# --- poses ------------------------------------------------------------------

func _attack_interval_ticks(id: String) -> int:
	if config != null:
		if config.pathogens.has(id):
			var pd: PathogenDef = config.pathogens[id]
			if pd.attack_interval_ticks > 0:
				return pd.attack_interval_ticks
		elif config.structures.has(id):
			var sd: StructureDef = config.structures[id]
			if sd.attack_interval_ticks > 0:
				return sd.attack_interval_ticks
	return DEFAULT_ATTACK_INTERVAL_TICKS


func _speed_tiles_s(id: String) -> float:
	if config != null and config.pathogens.has(id):
		var pd: PathogenDef = config.pathogens[id]
		return float(pd.speed_mt_per_tick) * TICKS_PER_S / 1000.0
	return 0.0


## Builds a pose straight from a state and the scrubber time. No sim runs: the fake tick counter is
## time * 20 ticks/s, and AnimDriver supplies the same timing the game uses.
func pose_for(id: String, state: int, time: float) -> ModelPose:
	var pose := ModelPose.new()
	pose.facing_right = facing_right
	pose.time = time
	pose.seed = absi(id.hash())
	var ticks: int = int(floorf(time * TICKS_PER_S))
	var interval: int = _attack_interval_ticks(id)
	match state:
		ModelPose.Anim.MOVE:
			pose.anim = ModelPose.Anim.MOVE
			var stride: float = float(AnimDriver.STRIDE_TILES.get(id, AnimDriver.DEFAULT_STRIDE_TILES))
			pose.gait_phase = fposmod(time * _speed_tiles_s(id) / stride, 1.0)
		ModelPose.Anim.WINDUP:
			var windup: int = maxi(AnimDriver.windup_ticks(interval), 1)
			pose.anim = ModelPose.Anim.WINDUP
			pose.attack_t = 0.4 * clampf(float(ticks) / float(windup), 0.0, 1.0)
		ModelPose.Anim.STRIKE:
			pose.anim = ModelPose.Anim.STRIKE
			pose.attack_t = AnimDriver.STRIKE_T
		ModelPose.Anim.RECOVER:
			var recover: int = maxi(AnimDriver.recover_ticks(interval), 1)
			pose.anim = ModelPose.Anim.RECOVER
			pose.attack_t = 0.6 + 0.4 * clampf(float(ticks) / float(recover), 0.0, 1.0)
		ModelPose.Anim.HIT:
			pose.anim = ModelPose.Anim.HIT
			pose.hit_t = AnimDriver.flash_amount(ticks, false)
			pose.shake = AnimDriver.shake_amount(ticks, false, _shake_ticks(id))
		ModelPose.Anim.DEAD:
			pose.anim = ModelPose.Anim.DEAD
			pose.death_t = AnimDriver.death_t(ticks, AnimDriver.death_ticks_for(_anim_id(id)))
		STATE_ATTACK_LOOP:
			var k: int = ticks % maxi(interval, MIN_CYCLE_TICKS)
			var res: Vector2 = AnimDriver.pathogen_attack(PathogenState.State.ATTACKING, interval - k, interval, k)
			pose.anim = int(res.x) as ModelPose.Anim
			pose.attack_t = res.y
		_:
			pose.anim = ModelPose.Anim.IDLE
	return pose


## Wall entries share the Mucous Wall's timings.
func _anim_id(id: String) -> String:
	return "mucous_wall" if id == WALLS_ID or id == POST_ID else id


func _shake_ticks(id: String) -> int:
	return AnimDriver.WALL_SHAKE_TICKS if _anim_id(id) == "mucous_wall" else AnimDriver.HIT_DECAY_TICKS


## The fixed poses used by the contact sheet columns.
func sheet_pose(id: String, state: int) -> ModelPose:
	var pose := ModelPose.new()
	pose.facing_right = true
	pose.time = 0.5
	pose.seed = absi(id.hash())
	pose.anim = state as ModelPose.Anim
	match state:
		ModelPose.Anim.MOVE:
			pose.gait_phase = CELL_GAIT
		ModelPose.Anim.WINDUP:
			pose.attack_t = 0.4
		ModelPose.Anim.STRIKE:
			pose.attack_t = AnimDriver.STRIKE_T
		ModelPose.Anim.HIT:
			pose.hit_t = 1.0
			pose.shake = 1.0
		ModelPose.Anim.DEAD:
			pose.death_t = CELL_DEATH_T
	return pose


# --- drawing ----------------------------------------------------------------

func _footprint_tiles(id: String) -> Vector2i:
	if config != null and config.structures.has(id):
		var sd: StructureDef = config.structures[id]
		return sd.footprint
	return Vector2i.ONE


func _width_tiles(id: String) -> float:
	if config != null and config.structures.has(id):
		return float(_footprint_tiles(id).x) * IsoProjection.DEFAULT_SCALE * ModelRegistry.STRUCTURE_WIDTH_SCALE
	return float(ModelRegistry.PATHOGEN_WIDTH_T.get(id, ModelRegistry.DEFAULT_PATHOGEN_WIDTH_T))


func _draw_stage(ci: CanvasItem) -> void:
	var proj := IsoProjection.new(float(tile_px), Vector2.ZERO)
	var pose: ModelPose = pose_for(model_id, state_index, time_s)
	if model_id == WALLS_ID:
		_draw_pad(ci, proj, WALLS_PAD_TILES, night)
		_draw_walls(ci, _walls, _walls_projection(float(tile_px)), pose)
		if show_anchor:
			_draw_anchor(ci, proj.origin)
		return
	_draw_pad(ci, proj, STAGE_PAD_TILES, night)
	_draw_model(ci, proj, model_id, pose, facing_right)
	if show_footprint:
		_draw_footprint(ci, proj, model_id)
	if show_bounds:
		_draw_bounds(ci, proj, model_id)
	if show_anchor:
		_draw_anchor(ci, proj.origin)


## The ground pad, drawn like the island top from #63: a slab edge, a rounded top and a rim.
## It is centred on the projection origin.
func _draw_pad(ci: CanvasItem, proj: IsoProjection, tiles: float, is_night: bool) -> void:
	var half: float = tiles * 0.5
	var ground: PackedVector2Array = KitDraw.rounded_rect_points(Rect2(-half, -half, tiles, tiles), 0.6)
	var outline := PackedVector2Array()
	for g: Vector2 in ground:
		outline.append(proj.ground_to_screen(g))
	var slab: Vector2 = Vector2(0.0, PAD_SLAB_T * proj.tile_px)
	var shifted := PackedVector2Array()
	for p: Vector2 in outline:
		shifted.append(p + slab)
	ci.draw_colored_polygon(shifted, PAD_SHADOW_NIGHT if is_night else PAD_SHADOW_DAY)
	ci.draw_colored_polygon(outline, PAD_TOP_NIGHT if is_night else PAD_TOP_DAY)
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	ci.draw_polyline(closed, PAD_RIM_NIGHT if is_night else PAD_RIM_DAY, maxf(1.0, proj.tile_px * 0.1), true)


func _painter_for(id: String) -> ModelPainter:
	return _post_painter if id == POST_ID else ModelRegistry.painter_for(id)


func _draw_model(ci: CanvasItem, proj: IsoProjection, id: String, pose: ModelPose, face_right: bool) -> void:
	var painter: ModelPainter = _painter_for(id)
	# Like UnitLayer: painters take the real anchor and handle pose.facing_right themselves, because they
	# set their own canvas transform (a transform set here would be replaced by theirs).
	pose.facing_right = face_right
	painter.paint_ground(ci, proj.origin, pose, proj.tile_px)
	painter.paint(ci, proj.origin, pose, proj.tile_px)


func _draw_anchor(ci: CanvasItem, at: Vector2) -> void:
	var r: float = ANCHOR_CROSS_PX * 0.5
	ci.draw_line(at + Vector2(-r, 0.0), at + Vector2(r, 0.0), DEBUG_RED, 2.0)
	ci.draw_line(at + Vector2(0.0, -r), at + Vector2(0.0, r), DEBUG_RED, 2.0)


func _draw_footprint(ci: CanvasItem, proj: IsoProjection, id: String) -> void:
	var h: Vector2 = Vector2(_footprint_tiles(id)) * 0.5
	var pts := PackedVector2Array([
		proj.ground_to_screen(Vector2(-h.x, -h.y)), proj.ground_to_screen(Vector2(h.x, -h.y)),
		proj.ground_to_screen(Vector2(h.x, h.y)), proj.ground_to_screen(Vector2(-h.x, h.y)),
	])
	pts.append(pts[0])
	ci.draw_polyline(pts, DEBUG_FOOT, 2.0)


func _draw_bounds(ci: CanvasItem, proj: IsoProjection, id: String) -> void:
	var w: float = _width_tiles(id) * proj.tile_px
	var h: float = _painter_for(id).height_tiles() * proj.tile_px
	ci.draw_rect(Rect2(proj.origin + Vector2(-w * 0.5, -h), Vector2(w, h)), DEBUG_BOX, false, 1.0)


# --- contact sheet ----------------------------------------------------------

func _sheet_cell_draw(cell: Control, id: String, state: int) -> void:
	var proj := IsoProjection.new(CELL_TILE_PX, CELL_ANCHOR)
	cell.draw_rect(Rect2(Vector2.ZERO, Vector2(CELL_SIZE)), NIGHT_BG if night else DAY_BG)
	if id == WALLS_ID:
		var wp: IsoProjection = _walls_projection(WALLS_CELL_TILE_PX)
		wp.origin += Vector2(CELL_SIZE) * 0.5 + Vector2(0.0, 20.0)
		_draw_walls(cell, _sheet_walls, wp, sheet_pose(id, state))
	else:
		_draw_pad(cell, proj, CELL_PAD_TILES, night)
		_draw_model(cell, proj, id, sheet_pose(id, state), true)
	var font: Font = ThemeDB.fallback_font
	var ink: Color = LABEL_NIGHT if night else LABEL_DAY
	cell.draw_string(font, Vector2(8.0, 18.0), id, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, ink)
	cell.draw_string(font, Vector2(8.0, 35.0), STATE_NAMES[state], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, ink)


## Renders the grid to an Image. Needs a renderer.
func render_contact_sheet() -> Image:
	var size: Vector2i = contact_sheet_size(model_ids.size(), SHEET_STATES.size(), CELL_SIZE)
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	for r: int in range(model_ids.size()):
		for c: int in range(SHEET_STATES.size()):
			var cell := Cell.new()
			cell.position = Vector2(c * CELL_SIZE.x, r * CELL_SIZE.y)
			cell.size = Vector2(CELL_SIZE)
			cell.clip_contents = true
			var id: String = model_ids[r]
			var st: int = SHEET_STATES[c]
			cell.draw_cb = func(ci: Control) -> void: _sheet_cell_draw(ci, id, st)
			vp.add_child(cell)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


## Writes user://contact_sheets/contact_<unix>.png (or `path` when given) and shows the absolute path.
## Returns the absolute path, or "" on failure.
func export_contact_sheet(path: String = "") -> String:
	if _exporting:
		return ""
	_exporting = true
	var out: String = path
	if out == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://contact_sheets"))
		out = "user://contact_sheets/contact_%d.png" % int(Time.get_unix_time_from_system())
	var abs_path: String = ProjectSettings.globalize_path(out) if out.begins_with("user://") else out
	var img: Image = await render_contact_sheet()
	var err: int = ERR_UNAVAILABLE
	if img != null:
		err = img.save_png(abs_path)
	_exporting = false
	if err != OK:
		path_label.text = "Export failed (error %d)" % err
		return ""
	path_label.text = abs_path
	return abs_path


func _cli_arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _run_cli_export(path: String) -> void:
	var done: String = await export_contact_sheet(path)
	get_tree().quit(0 if done != "" else 1)


## The walls layout alone at T = 40 on a pad, the framing of walls_sheet.png. Needs a renderer.
func render_walls_sheet() -> Image:
	var vp := SubViewport.new()
	vp.size = WALLS_SHEET_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cell := Cell.new()
	cell.size = Vector2(WALLS_SHEET_SIZE)
	cell.draw_cb = func(ci: Control) -> void:
		var centre: Vector2 = Vector2(WALLS_SHEET_SIZE) * 0.5
		ci.draw_rect(Rect2(Vector2.ZERO, Vector2(WALLS_SHEET_SIZE)), NIGHT_BG if night else DAY_BG)
		_draw_pad(ci, IsoProjection.new(WALLS_SHEET_TILE_PX, centre), WALLS_PAD_TILES, night)
		var wp: IsoProjection = _walls_projection(WALLS_SHEET_TILE_PX)
		wp.origin += centre
		_draw_walls(ci, _walls_sheet_walls, wp, pose_for(WALLS_ID, ModelPose.Anim.IDLE, 0.0))
	vp.add_child(cell)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


func _run_cli_walls_export(path: String) -> void:
	var img: Image = await render_walls_sheet()
	var err: int = img.save_png(path) if img != null else ERR_UNAVAILABLE
	get_tree().quit(0 if err == OK else 1)
