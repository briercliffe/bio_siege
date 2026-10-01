class_name SavedScreen
extends Control

## Screen 03 (Saved bases and armies): the player's library of save slots, with Bases and Armies tabs,
## Load, Share, Delete and Import file. Positions come from the mockup canvas source SavedLayouts.dc.html
## at 1280x720; a wider or taller viewport keeps the content centred. Nothing is read from disk until
## setup() names the library folder (Main passes the game's, tests pass a temp one).

signal back_requested

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const HEADER_TOP: float = 26.0
const KICKER_TEXT: String = "YOUR LIBRARY"
const KICKER_PX: int = 12
const KICKER_SPACING: int = 2
const TITLE_TEXT: String = "Saved bases and armies"
const TITLE_PX: int = 40
const TITLE_GAP: int = 2

const IMPORT_TEXT: String = "Import file"
const IMPORT_SIZE: Vector2 = Vector2(136.0, 52.0)
const IMPORT_MARGIN_RIGHT: float = 32.0
const IMPORT_TOP: float = 28.0
const IMPORT_PX: int = 16

const TAB_LABELS: Array[String] = ["Bases", "Armies"]
const TAB_KINDS: Array[String] = [SaveLibrary.KIND_BASE, SaveLibrary.KIND_ARMY]
const TABS_TOP: float = 112.0

const CONTENT_WIDTH: float = 1184.0
const GRID_TOP: float = 196.0
const COLUMNS: int = 4
const CARD_SIZE: Vector2 = Vector2(281.0, 292.0)
const CARD_GAP: int = 20
const CARD_RADIUS: int = 36
const CARD_PAD: float = 18.0
const CARD_INNER_GAP: int = 12
const CARD_ALPHA: float = 0.92
const CARD_SHADOW: Color = Color(0.0706, 0.1882, 0.3098, 0.18)
## Room around the grid inside the scroll area so card shadows are not clipped.
const SCROLL_BLEED: Vector2 = Vector2(28.0, 12.0)
const SCROLL_BOTTOM_GAP: float = 16.0

const THUMB_SIZE: Vector2 = Vector2(200.0, 118.0)
const NAME_PX: int = 20
const SUMMARY_PX: int = 14
const TIME_PX: int = 12
const BUTTON_GAP: int = 8
const LOAD_SIZE: Vector2 = Vector2(112.0, 48.0)
const LOAD_PX: int = 15
const SHARE_SIZE: Vector2 = Vector2(64.0, 48.0)
const DELETE_SIZE: Vector2 = Vector2(48.0, 48.0)
const SMALL_BUTTON_PX: int = 14

const EMPTY_TITLE: String = "Empty slot"
const EMPTY_BODY: Dictionary = {
	SaveLibrary.KIND_BASE: "Build a base, then save it from the menu.",
	SaveLibrary.KIND_ARMY: "Buy an army, then save it from the menu.",
}
const EMPTY_BORDER: Color = Color("#8fa3b8")
const EMPTY_FILL: Color = Color(1.0, 1.0, 1.0, 0.45)
const EMPTY_BODY_COLOR: Color = Color("#3f5670")

const FOOTER_TEXT: String = "Shared files are versioned JSON, so friends and the balance tools can load them."
const FOOTER_TOP: float = 660.0
const FOOTER_PX: int = 13
const FOOTER_COLOR: Color = Color("#3f5670")

const TOAST_COPIED: String = "Copied to clipboard"
const TOAST_ARMY_FROM_TITLE: String = "Load armies from the Incubation menu"
const TOAST_BASE_LOADED: String = "Base loaded"
const DELETE_TITLE: String = "Delete slot"
const DELETE_MESSAGE: String = "Delete '%s'?"

## Rendered base thumbnails by "path|saved_unix", so reopening the screen or switching tabs is instant.
static var _thumb_cache: Dictionary = {}

var library: SaveLibrary = null
var fsm: GameStateMachine = null
var config: GameConfig = null
var kind: String = SaveLibrary.KIND_BASE
## Pins "Saved today" and friends for tests; 0 uses the system clock.
var now_unix: int = 0

var background: AmbientBackground = null
var back_button: IconButton = null
var header: VBoxContainer = null
var kicker_label: Label = null
var title_label: Label = null
var import_button: CardButton = null
var tabs: SegmentedTabs = null
var scroll: ScrollContainer = null
var grid_box: GridContainer = null
var slot_cards: Array[SlotCard] = []
var empty_card: EmptyCard = null
var footer_label: Label = null
var confirm_popup: ConfirmationPopup = null
var import_dialog: ImportDialog = null
var toast: Toast = null

var _pending_delete: Dictionary = {}
var _file_picker: WebFilePicker = null


## A kit pill with the card sizes from the mockup (the kit's own labels start at 17 px).
class CardButton extends PillButton:
	var shadow: bool = false

	func set_font_px(value: int) -> void:
		font_px = maxi(value, UiFonts.MIN_SIZE)
		queue_redraw()

	func _draw() -> void:
		if shadow:
			var pal: Dictionary = UiPalette.for_theme(night)
			KitDraw.draw_box(self, Rect2(Vector2.ZERO, size), pal["panel"] as Color, -1.0, 0, Color.TRANSPARENT,
					pal["panel_shadow"] as Color, 22, Vector2(0.0, 8.0))
		super._draw()


## One saved slot: thumbnail, name, summary, relative time and Load, Share and Del.
class SlotCard extends FloatingCard:
	var slot: Dictionary = {}
	var kind: String = SaveLibrary.KIND_BASE
	var thumb: Control = null
	var name_label: Label = null
	var summary_label: Label = null
	var time_label: Label = null
	var load_button: CardButton = null
	var share_button: CardButton = null
	var delete_button: CardButton = null


## The dashed "Empty slot" card shown last while the library has room.
class EmptyCard extends Control:
	var body: String = ""

	func _init(p_body: String) -> void:
		body = p_body
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = CARD_SIZE

	func _draw() -> void:
		var rect := Rect2(Vector2(1.5, 1.5), size - Vector2(3.0, 3.0))
		draw_colored_polygon(KitDraw.rounded_rect_points(rect, float(CARD_RADIUS)), EMPTY_FILL)
		KitDraw.draw_dashed_rounded(self, rect, float(CARD_RADIUS), EMPTY_BORDER, 3.0, 9.0, 6.0)
		var pal: Dictionary = UiPalette.for_theme(false)
		var font_title: Font = UiFonts.weight(800)
		var font_body: Font = UiFonts.weight(400)
		var body_w: float = size.x - CARD_PAD * 2.0
		var lines: PackedStringArray = _wrap(body, font_body, 14, body_w)
		var line_h: float = 14.0 * 1.4
		var block_h: float = 64.0 + 10.0 + font_title.get_height(18) + 10.0 + line_h * float(lines.size())
		var y: float = (size.y - block_h) * 0.5
		var c := Vector2(size.x * 0.5, y + 32.0)
		draw_circle(c, 32.0, Color(1.0, 1.0, 1.0, 0.8))
		var accent: Color = pal["accent"] as Color
		draw_line(c + Vector2(-8.0, 0.0), c + Vector2(8.0, 0.0), accent, 3.0, true)
		draw_line(c + Vector2(0.0, -8.0), c + Vector2(0.0, 8.0), accent, 3.0, true)
		y += 64.0 + 10.0
		KitDraw.draw_text_centered(self, EMPTY_TITLE, Rect2(0.0, y, size.x, font_title.get_height(18)), 18, 800,
				pal["ink"] as Color)
		y += font_title.get_height(18) + 10.0
		for line: String in lines:
			KitDraw.draw_text_centered(self, line, Rect2(0.0, y, size.x, line_h), 14, 400, EMPTY_BODY_COLOR)
			y += line_h

	static func _wrap(text: String, font: Font, px: int, width: float) -> PackedStringArray:
		var lines := PackedStringArray()
		var line: String = ""
		for word: String in text.split(" "):
			var candidate: String = word if line.is_empty() else line + " " + word
			if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
				lines.append(line)
				line = word
			else:
				line = candidate
		if not line.is_empty():
			lines.append(line)
		return lines


## A display-only day island of a saved base, rendered once through a SubViewport and kept as an
## ImageTexture so the list scrolls without redrawing every wall.
class BaseThumb extends Control:
	const RENDER_FRAMES: int = 2

	var cache_key: String = ""
	var texture: Texture2D = null
	var viewport: SubViewport = null
	var _frames: int = 0

	func _init(key: String) -> void:
		cache_key = key
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = THUMB_SIZE
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		texture = SavedScreen._thumb_cache.get(cache_key) as Texture2D
		set_process(false)

	## Starts the one-off render unless the cache already had it.
	func render(grid: GridModel, cfg: GameConfig) -> void:
		if texture != null or grid == null or cfg == null:
			return
		viewport = SubViewport.new()
		viewport.name = "Render"
		viewport.size = Vector2i(THUMB_SIZE)
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(viewport)
		var view: GridView = (load("res://src/view/grid_view.tscn") as PackedScene).instantiate() as GridView
		viewport.add_child(view)
		view.set_process_unhandled_input(false)
		view.set_process(false)
		view.setup(grid, cfg)
		view.set_night(false)
		view.fit_to_rect(Rect2(Vector2.ZERO, THUMB_SIZE))
		_frames = 0
		set_process(true)

	func is_rendering() -> bool:
		return viewport != null

	func _process(_delta: float) -> void:
		_frames += 1
		if _frames < RENDER_FRAMES or viewport == null:
			return
		set_process(false)
		# The headless dummy renderer has no readable render target; keep showing the viewport itself.
		var image: Image = null if DisplayServer.get_name() == "headless" else viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
			SavedScreen._thumb_cache[cache_key] = texture
			viewport.queue_free()
			viewport = null
		else:
			texture = viewport.get_texture()
		queue_redraw()

	func _draw() -> void:
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, THUMB_SIZE), false)


## An army: up to three capsules of "icon count × Pathogen", the last one "+N more" when needed.
class ArmyThumb extends Control:
	const ROW_H: float = 34.0
	const ROW_GAP: float = 9.0
	const MAX_ROWS: int = 3
	const ICON_PX: float = 16.0
	const PAD_X: float = 14.0
	const TEXT_PX: int = 15

	var rows: Array[Dictionary] = []
	var cfg: GameConfig = null

	func _init(types: Dictionary, p_cfg: GameConfig) -> void:
		cfg = p_cfg
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = THUMB_SIZE
		size_flags_horizontal = Control.SIZE_FILL
		var ids: Array = types.keys()
		for i: int in range(ids.size()):
			if i == MAX_ROWS - 1 and ids.size() > MAX_ROWS:
				rows.append({"id": "", "count": 0, "text": "+%d more" % (ids.size() - i)})
				break
			var type_id: String = str(ids[i])
			rows.append({"id": type_id, "count": int(types[type_id]), "text": ArmyThumb.pathogen_name(type_id, cfg)})

	static func pathogen_name(type_id: String, p_cfg: GameConfig) -> String:
		var pdef: PathogenDef = p_cfg.pathogens.get(type_id) as PathogenDef if p_cfg != null else null
		return pdef.display_name if pdef != null and not pdef.display_name.is_empty() else type_id.capitalize()

	func _draw() -> void:
		var pal: Dictionary = UiPalette.for_theme(false)
		var ink: Color = pal["ink"] as Color
		var block_h: float = float(rows.size()) * ROW_H + float(maxi(rows.size() - 1, 0)) * ROW_GAP
		var y: float = (size.y - block_h) * 0.5
		for row: Dictionary in rows:
			var rect := Rect2(0.0, y, size.x, ROW_H)
			KitDraw.draw_box(self, rect, pal["chip"] as Color, -1.0)
			var x: float = PAD_X
			var id: String = str(row["id"])
			if not id.is_empty():
				IconPainter.draw_icon(self, id, Rect2(x, y + (ROW_H - ICON_PX) * 0.5, ICON_PX, ICON_PX), cfg)
				x += ICON_PX + 10.0
				var count_text: String = "%d ×" % int(row["count"])
				KitDraw.draw_text_at(self, count_text, x, y + ROW_H * 0.5, TEXT_PX, 800, ink)
				x += UiFonts.text_size(count_text, TEXT_PX, 800).x + 6.0
			KitDraw.draw_text_at(self, str(row["text"]), x, y + ROW_H * 0.5, TEXT_PX, 400, ink)
			y += ROW_H + ROW_GAP


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout)


func _ready() -> void:
	_layout()


## Main calls this when the screen opens: the library folder and the FSM (for Load). `cfg` defaults to
## the session's config.
func setup(root: String = SaveLibrary.DEFAULT_ROOT, p_fsm: GameStateMachine = null, cfg: GameConfig = null) -> void:
	fsm = p_fsm
	if cfg == null and fsm != null and fsm.session != null:
		cfg = fsm.session.config
	if cfg == null and GameData != null:
		cfg = GameData.config
	config = cfg
	library = SaveLibrary.new(root)
	refresh()


## Shows the Bases ("base") or Armies ("army") tab.
func open_tab(p_kind: String) -> void:
	var index: int = TAB_KINDS.find(p_kind)
	if index < 0:
		return
	kind = p_kind
	tabs.select(index)
	refresh()


## Rebuilds the cards for the current tab from the library.
func refresh() -> void:
	# Freed at once: refresh() never runs from a card's own button, and tests count orphans.
	for child: Node in grid_box.get_children():
		grid_box.remove_child(child)
		child.free()
	slot_cards.clear()
	empty_card = null
	if library == null:
		return
	var slots: Array[Dictionary] = library.list(kind)
	for slot: Dictionary in slots:
		var card: SlotCard = _make_slot_card(slot)
		grid_box.add_child(card)
		slot_cards.append(card)
	if slots.size() < SaveLibrary.MAX_SLOTS:
		empty_card = EmptyCard.new(str(EMPTY_BODY[kind]))
		empty_card.name = "EmptySlot"
		grid_box.add_child(empty_card)
	_render_thumbnails(slots)


## Every control the player can tap, for the 48x48 minimum check.
func tappable_controls() -> Array[Control]:
	var out: Array[Control] = [back_button, import_button]
	for node: Node in tabs.get_children():
		if node is Button:
			out.append(node as Control)
	for card: SlotCard in slot_cards:
		out.append_array([card.load_button, card.share_button, card.delete_button] as Array[Control])
	return out


func load_slot(slot: Dictionary) -> void:
	if library == null:
		return
	var res: Dictionary = library.load_slot(str(slot.get("path", "")), config)
	if not bool(res.get("ok", false)):
		toast.show_message(str(res.get("error", "")))
		return
	var session: Session = fsm.session if fsm != null else null
	if str(res["kind"]) == SaveLibrary.KIND_ARMY:
		_load_army(session, res["parsed"] as Dictionary)
	else:
		_load_base(session, res["parsed"] as Dictionary)


## On the web the slot downloads as a .json file; elsewhere its JSON goes to the clipboard.
func share_slot(slot: Dictionary) -> void:
	if library == null:
		return
	var json: String = library.export_json(str(slot.get("path", "")))
	if json.is_empty():
		toast.show_message("Could not read this slot")
		return
	if OS.has_feature("web"):
		var slug: String = SaveLibrary.slugify(str(slot.get("name", "")))
		JavaScriptBridge.download_buffer(json.to_utf8_buffer(), "%s.json" % (slug if not slug.is_empty() else kind),
				"application/json")
	else:
		DisplayServer.clipboard_set(json)
		toast.show_message(TOAST_COPIED)


## Asks first; the slot goes when the player confirms.
func request_delete(slot: Dictionary) -> void:
	_pending_delete = slot
	confirm_popup.show_dialog(DELETE_MESSAGE % str(slot.get("name", "")))


func open_import() -> void:
	import_dialog.open(IMPORT_TEXT)
	import_dialog.show_file_button(WebFilePicker.is_available())


## Validates and saves pasted or picked JSON as a new slot, then shows its tab. Errors stay in the dialog.
func import_text(text: String) -> bool:
	if library == null:
		return false
	var res: Dictionary = library.import_json(text, "", config)
	if not bool(res.get("ok", false)):
		import_dialog.set_error(str(res.get("error", "")))
		return false
	import_dialog.close()
	open_tab(str(res["kind"]))
	toast.show_message("Imported '%s'" % str(res.get("name", "")))
	return true


func _load_base(session: Session, parsed: Dictionary) -> void:
	var err: String = SaveLibrary.apply_base(session, parsed)
	if not err.is_empty():
		toast.show_message(err)
		return
	if fsm.phase == GameStateMachine.Phase.SYNTHESIS:
		_phase_toast(TOAST_BASE_LOADED)
		back_requested.emit()
	elif not fsm.request_transition(GameStateMachine.Phase.SYNTHESIS):
		toast.show_message(TOAST_BASE_LOADED)


func _load_army(session: Session, parsed: Dictionary) -> void:
	if fsm == null or session == null or fsm.phase != GameStateMachine.Phase.INCUBATION:
		toast.show_message(TOAST_ARMY_FROM_TITLE)
		return
	var result: Dictionary = SaveLibrary.apply_army(session, parsed)
	_phase_toast(HudSpawn.army_loaded_message(result))
	back_requested.emit()


## Messages that outlive the screen go to the phase's own toast.
func _phase_toast(msg: String) -> void:
	var scene: Node = fsm.current_phase_scene if fsm != null else null
	var phase_toast: Toast = scene.get_node_or_null("Toast") as Toast if scene != null else null
	(phase_toast if phase_toast != null else toast).show_message(msg)


func _on_tab_changed(index: int) -> void:
	kind = TAB_KINDS[index]
	refresh()


func _on_delete_confirmed() -> void:
	if _pending_delete.is_empty() or library == null:
		return
	_thumb_cache.erase(_cache_key(_pending_delete))
	library.delete_slot(str(_pending_delete.get("path", "")))
	_pending_delete = {}
	refresh()


func _on_delete_canceled() -> void:
	_pending_delete = {}


func _on_file_requested() -> void:
	if _file_picker == null:
		_file_picker = WebFilePicker.new()
	_file_picker.pick(_on_file_picked)


func _on_file_picked(text: String) -> void:
	import_dialog.set_text(text)
	import_text(text)


func _render_thumbnails(slots: Array[Dictionary]) -> void:
	if kind != SaveLibrary.KIND_BASE or config == null:
		return
	for i: int in range(slots.size()):
		var thumb: BaseThumb = slot_cards[i].thumb as BaseThumb
		if thumb == null or thumb.texture != null:
			continue
		var res: Dictionary = library.load_slot(str(slots[i]["path"]), config)
		if not bool(res.get("ok", false)):
			continue
		var grid := GridModel.new(config)
		var layout: Array = (res["parsed"] as Dictionary).get("layout", [])
		var wallet := Wallet.new(Wallet.sum_costs(_layout_costs(layout)))
		grid.load_layout(layout, wallet)
		thumb.render(grid, config)


func _layout_costs(layout: Array) -> Array[Dictionary]:
	var costs: Array[Dictionary] = []
	for item: Variant in layout:
		var sdef: StructureDef = config.structures.get(str((item as Dictionary).get("type", ""))) as StructureDef
		if sdef != null:
			costs.append(sdef.cost)
	return costs


func _relative_time(saved_unix: int) -> String:
	var now: int = now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	return SaveLibrary.relative_time(saved_unix, now, bias_minutes * 60)


static func _cache_key(slot: Dictionary) -> String:
	return "%s|%d" % [str(slot.get("path", "")), int(slot.get("saved_unix", 0))]


func _make_slot_card(slot: Dictionary) -> SlotCard:
	var pal: Dictionary = UiPalette.for_theme(false)
	var ink: Color = pal["ink"] as Color
	var muted: Color = pal["muted"] as Color
	var card := SlotCard.new()
	card.name = "Slot_%s" % SaveLibrary.slugify(str(slot.get("name", "")))
	card.slot = slot
	card.kind = kind
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: Color = pal["panel"] as Color
	panel.a = CARD_ALPHA
	var sb: StyleBoxFlat = KitDraw.make_box(panel, float(CARD_RADIUS), 2, pal["panel_border"] as Color,
			CARD_SHADOW, 30, Vector2(0.0, 12.0))
	sb.set_content_margin_all(CARD_PAD)
	card.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", CARD_INNER_GAP)
	card.add_child(box)

	var summary: Dictionary = slot.get("summary", {}) as Dictionary
	if kind == SaveLibrary.KIND_ARMY:
		var types: Variant = summary.get("types", {})
		card.thumb = ArmyThumb.new(types if types is Dictionary else {}, config)
	else:
		card.thumb = BaseThumb.new(_cache_key(slot))
	card.thumb.name = "Thumb"
	box.add_child(card.thumb)

	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	card.name_label = _make_label("Name", str(slot.get("name", "")), NAME_PX, 800, ink)
	card.name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.name_label.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PAD * 2.0, 0.0)
	text.add_child(card.name_label)
	card.summary_label = _make_label("Summary", SaveLibrary.summary_text(kind, summary), SUMMARY_PX, 400, muted)
	text.add_child(card.summary_label)
	card.time_label = _make_label("Time", _relative_time(int(slot.get("saved_unix", 0))), TIME_PX, 400, muted)
	text.add_child(card.time_label)

	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", BUTTON_GAP)
	box.add_child(row)
	card.load_button = _make_button("BtnLoad", "Load", PillButton.Variant.PRIMARY, LOAD_SIZE, LOAD_PX, 800)
	card.load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.load_button.pressed.connect(load_slot.bind(slot))
	row.add_child(card.load_button)
	card.share_button = _make_button("BtnShare", "Share", PillButton.Variant.SECONDARY, SHARE_SIZE, SMALL_BUTTON_PX, 700)
	card.share_button.pressed.connect(share_slot.bind(slot))
	row.add_child(card.share_button)
	card.delete_button = _make_button("BtnDelete", "Del", PillButton.Variant.DANGER_OUTLINE, DELETE_SIZE, SMALL_BUTTON_PX, 700)
	card.delete_button.pressed.connect(request_delete.bind(slot))
	row.add_child(card.delete_button)
	return card


func _build() -> void:
	var pal: Dictionary = UiPalette.for_theme(false)
	background = AmbientBackground.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	back_button = IconButton.new(IconButton.Kind.BACK)
	back_button.name = "BtnBack"
	back_button.pressed.connect(back_requested.emit)
	add_child(back_button)

	header = VBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", TITLE_GAP)
	add_child(header)
	kicker_label = _make_label("Kicker", KICKER_TEXT, KICKER_PX, 700, pal["accent"] as Color)
	var kicker_font := FontVariation.new()
	kicker_font.base_font = UiFonts.weight(700)
	kicker_font.spacing_glyph = KICKER_SPACING
	kicker_label.add_theme_font_override("font", kicker_font)
	kicker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(kicker_label)
	title_label = _make_label("Title", TITLE_TEXT, TITLE_PX, 800, pal["ink"] as Color)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	import_button = _make_button("BtnImport", IMPORT_TEXT, PillButton.Variant.SECONDARY, IMPORT_SIZE, IMPORT_PX, 700)
	import_button.shadow = true
	import_button.pressed.connect(open_import)
	add_child(import_button)

	tabs = SegmentedTabs.new(TAB_LABELS)
	tabs.name = "Tabs"
	tabs.tab_changed.connect(_on_tab_changed)
	add_child(tabs)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(SCROLL_BLEED.x))
	margin.add_theme_constant_override("margin_right", int(SCROLL_BLEED.x))
	margin.add_theme_constant_override("margin_top", int(SCROLL_BLEED.y))
	margin.add_theme_constant_override("margin_bottom", int(SCROLL_BLEED.x))
	scroll.add_child(margin)
	grid_box = GridContainer.new()
	grid_box.name = "Cards"
	grid_box.columns = COLUMNS
	grid_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_box.add_theme_constant_override("h_separation", CARD_GAP)
	grid_box.add_theme_constant_override("v_separation", CARD_GAP)
	margin.add_child(grid_box)

	footer_label = _make_label("Footer", FOOTER_TEXT, FOOTER_PX, 400, FOOTER_COLOR)
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer_label)

	var dialogs: Theme = dialog_theme()
	import_dialog = (load("res://src/ui/import_dialog.tscn") as PackedScene).instantiate() as ImportDialog
	import_dialog.name = "ImportDialog"
	import_dialog.theme = dialogs
	import_dialog.load_requested.connect(import_text)
	import_dialog.file_requested.connect(_on_file_requested)
	add_child(import_dialog)

	confirm_popup = (load("res://src/ui/confirmation_popup.tscn") as PackedScene).instantiate() as ConfirmationPopup
	confirm_popup.name = "ConfirmDelete"
	confirm_popup.theme = dialogs
	add_child(confirm_popup)
	confirm_popup.confirmed.connect(_on_delete_confirmed)
	confirm_popup.canceled.connect(_on_delete_canceled)
	var popup_title: Label = confirm_popup.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/TitleLabel") as Label
	if popup_title != null:
		popup_title.text = DELETE_TITLE
	confirm_popup.get_ok_button().text = "Delete"
	confirm_popup.get_cancel_button().text = "Keep"

	toast = Toast.new()
	toast.name = "Toast"
	toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(toast)


## Day styling for the shared import and confirmation dialogs, which otherwise use Godot's dark default.
static func dialog_theme() -> Theme:
	var pal: Dictionary = UiPalette.for_theme(false)
	var ink: Color = pal["ink"] as Color
	var t := Theme.new()
	var panel: StyleBoxFlat = KitDraw.make_box(pal["panel_border"] as Color, float(FloatingCard.RADIUS), 2,
			pal["panel_border"] as Color, pal["panel_shadow"] as Color, 28, Vector2(0.0, 10.0))
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", ink)
	t.set_font("font", "Label", UiFonts.weight(600))
	var normal: StyleBoxFlat = KitDraw.make_box(pal["secondary_btn_bg"] as Color, 24.0, 2, pal["secondary_btn_border"] as Color)
	var pressed: StyleBoxFlat = KitDraw.make_box(pal["chip"] as Color, 24.0, 2, pal["accent"] as Color)
	for state: String in ["normal", "hover", "focus", "disabled"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", ink)
	t.set_font("font", "Button", UiFonts.weight(700))
	t.set_font_size("font_size", "Button", 16)
	var field: StyleBoxFlat = KitDraw.make_box(pal["stepper_bg"] as Color, 16.0, 2, pal["stepper_border"] as Color)
	field.set_content_margin_all(12.0)
	t.set_stylebox("normal", "TextEdit", field)
	var field_focus: StyleBoxFlat = field.duplicate() as StyleBoxFlat
	field_focus.border_color = pal["accent"] as Color
	t.set_stylebox("focus", "TextEdit", field_focus)
	t.set_color("font_color", "TextEdit", ink)
	t.set_color("font_placeholder_color", "TextEdit", pal["muted"] as Color)
	t.set_color("caret_color", "TextEdit", ink)
	return t


func _make_button(node_name: String, label: String, v: PillButton.Variant, min_size: Vector2, px: int, w: int) -> CardButton:
	var b := CardButton.new(label, v)
	b.name = node_name
	b.custom_minimum_size = min_size
	b.font_px = px
	b.font_weight = w
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b


static func _make_label(node_name: String, text: String, px: int, w: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.style_label(label, px, w, color)
	return label


func _layout() -> void:
	var view: Vector2 = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = DESIGN_SIZE
	var left: float = roundf((view.x - CONTENT_WIDTH) * 0.5)
	var dy: float = roundf(maxf(view.y - DESIGN_SIZE.y, 0.0) * 0.5)
	back_button.position = BACK_POS
	back_button.size = back_button.get_combined_minimum_size()
	import_button.size = IMPORT_SIZE
	import_button.position = Vector2(view.x - IMPORT_MARGIN_RIGHT - IMPORT_SIZE.x, IMPORT_TOP)
	header.position = Vector2(0.0, HEADER_TOP)
	header.size = Vector2(view.x, 0.0)
	tabs.size = SegmentedTabs.SIZE_DEFAULT
	tabs.position = Vector2(roundf((view.x - SegmentedTabs.SIZE_DEFAULT.x) * 0.5), TABS_TOP)
	var footer_top: float = FOOTER_TOP + dy * 2.0
	scroll.position = Vector2(left - SCROLL_BLEED.x, GRID_TOP - SCROLL_BLEED.y)
	scroll.size = Vector2(CONTENT_WIDTH + SCROLL_BLEED.x * 2.0, footer_top - SCROLL_BOTTOM_GAP - scroll.position.y)
	var footer_h: float = footer_label.get_combined_minimum_size().y
	footer_label.position = Vector2(0.0, footer_top)
	footer_label.size = Vector2(view.x, footer_h)
