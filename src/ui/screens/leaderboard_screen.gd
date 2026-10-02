class_name LeaderboardScreen
extends Control

## Online trophies leaderboard (AM-07): the top 50 and the player's own rank, read-only. Reached from the
## Living Base HUD when the `online` flag is on.

signal back_requested

const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const COLUMN_WIDTH: float = 640.0
const ROW_HEIGHT: float = 48.0
const LOADING_TEXT: String = "Loading..."
const EMPTY_TEXT: String = "No players on the board yet."

var session: Session = null
var backend: BackendClient = null

var background: AmbientBackground = null
var btn_back: IconButton = null
var title_label: Label = null
var status_label: Label = null
var me_label: Label = null
var scroll: ScrollContainer = null
var rows_box: VBoxContainer = null
## One entry per listed player, best first: {"row": Control, "rank": int, "user_id": String}.
var rows: Array[Dictionary] = []


func _init() -> void:
	name = "LeaderboardScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func setup(p_session: Session, p_backend: BackendClient = null) -> void:
	session = p_session
	backend = p_backend if p_backend != null else Net.backend(p_session.config if p_session != null else null)
	_load()


func _build() -> void:
	background = AmbientBackground.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	btn_back = IconButton.new(IconButton.Kind.BACK)
	btn_back.name = "BtnBack"
	btn_back.position = BACK_POS
	btn_back.pressed.connect(func() -> void: back_requested.emit())
	add_child(btn_back)

	var outer := VBoxContainer.new()
	outer.name = "Column"
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_top = 24.0
	outer.offset_bottom = -24.0
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 12)
	add_child(outer)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Leaderboard"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(title_label, 40, 800, UiPalette.color(false, "ink"))
	outer.add_child(title_label)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = LOADING_TEXT
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(status_label, 18, 400, UiPalette.color(false, "muted"))
	outer.add_child(status_label)

	me_label = Label.new()
	me_label.name = "MeLabel"
	me_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	me_label.visible = false
	UiFonts.style_label(me_label, 20, 700, UiPalette.color(false, "accent"))
	outer.add_child(me_label)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	outer.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(center)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	rows_box.mouse_filter = Control.MOUSE_FILTER_PASS
	rows_box.add_theme_constant_override("separation", 8)
	center.add_child(rows_box)


func _load() -> void:
	status_label.text = LOADING_TEXT
	status_label.visible = true
	var res: Dictionary = await backend.rpc("leaderboard_top", {})
	if not bool(res.get("ok", false)):
		status_label.text = NetCopy.error_text(str(res.get("error", "network_error")))
		return
	show_board(res)


## Renders a leaderboard_top response.
func show_board(res: Dictionary) -> void:
	for c: Node in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	rows.clear()
	var records: Array = res.get("records", []) as Array
	var me: Dictionary = res.get("me", {}) as Dictionary
	var mine: String = ""
	if not me.is_empty() and int(me.get("rank", 0)) > 0:
		mine = "You: #%d · %d trophies" % [int(me["rank"]), int(me.get("trophies", 0))]
	me_label.text = mine
	me_label.visible = not mine.is_empty()
	status_label.visible = records.is_empty()
	status_label.text = EMPTY_TEXT
	scroll.visible = not records.is_empty()
	for entry: Variant in records:
		var e: Dictionary = entry as Dictionary
		rows.append({"row": _add_row(e), "rank": int(e.get("rank", 0)), "user_id": str(e.get("user_id", ""))})


func _add_row(e: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(COLUMN_WIDTH, ROW_HEIGHT)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	var rank := Label.new()
	rank.text = "#%d" % int(e.get("rank", 0))
	rank.custom_minimum_size = Vector2(72.0, 0.0)
	UiFonts.style_label(rank, 20, 800, UiPalette.color(false, "ink"))
	row.add_child(rank)
	var name_label := Label.new()
	var player_name: String = str(e.get("name", ""))
	name_label.text = player_name if not player_name.is_empty() else "Player"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	UiFonts.style_label(name_label, 20, 600, UiPalette.color(false, "ink"))
	row.add_child(name_label)
	var trophies := Label.new()
	trophies.text = "%d" % int(e.get("trophies", 0))
	trophies.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiFonts.style_label(trophies, 20, 800, UiPalette.color(false, "accent"))
	row.add_child(trophies)
	card.add_child(row)
	rows_box.add_child(card)
	return card
