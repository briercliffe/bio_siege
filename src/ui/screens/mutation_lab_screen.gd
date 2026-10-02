class_name MutationLabScreen
extends Control

## The Mutation Lab (AM-10, identity section 4.4): per pathogen, a row of strain variant cards. A variant is a new
## set of antigens with its own tradeoff (never a flat stat). Free variants are unlocked; the others cost DNA, which
## is earned only from PvP wins. Living Base only.

signal back_requested
signal strain_unlocked(type_id: String, variant_id: String)

const BACK_POS: Vector2 = Vector2(32.0, 28.0)
const COLUMN_WIDTH: float = 900.0
const CARD_SIZE: Vector2 = Vector2(280.0, 150.0)
const BUTTON_SIZE: Vector2 = Vector2(150.0, 52.0)
const EXPLAINER_TEXT: String = "Variants are new antigens. Bases that remember the old ones are partly fooled."
const UNLOCKED_TEXT: String = "Unlocked"

var session: Session = null

var background: AmbientBackground = null
var btn_back: IconButton = null
var title_label: Label = null
var explainer_label: Label = null
var dna_label: Label = null
var message_label: Label = null
var scroll: ScrollContainer = null
var rows_box: VBoxContainer = null
## "type/variant" -> {"card": Control, "status": Label, "button": PillButton or null}.
var cards: Dictionary = {}


func _init() -> void:
	name = "MutationLabScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func setup(p_session: Session) -> void:
	session = p_session
	refresh()


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
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "Mutation Lab"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(title_label, 40, 800, UiPalette.color(false, "ink"))
	outer.add_child(title_label)

	explainer_label = Label.new()
	explainer_label.name = "ExplainerLabel"
	explainer_label.text = EXPLAINER_TEXT
	explainer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(explainer_label, 16, 400, UiPalette.color(false, "muted"))
	outer.add_child(explainer_label)

	dna_label = Label.new()
	dna_label.name = "DnaLabel"
	dna_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(dna_label, 20, 800, UiPalette.color(false, "accent"))
	outer.add_child(dna_label)

	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFonts.style_label(message_label, 16, 700, UiPalette.color(false, "danger"))
	outer.add_child(message_label)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(center)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	rows_box.mouse_filter = Control.MOUSE_FILTER_PASS
	rows_box.add_theme_constant_override("separation", 18)
	center.add_child(rows_box)


## Rebuilds the cards from the session's profile and wallet.
func refresh() -> void:
	for c: Node in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	cards.clear()
	if session == null or session.config == null:
		return
	var cfg: GameConfig = session.config
	dna_label.text = "DNA: %d" % (session.wallet.get_amount("dna") if session.wallet != null else 0)
	var ids: Array = cfg.pathogens.keys()
	ids.sort()
	for type_var: Variant in ids:
		var type_id: String = str(type_var)
		var pdef: PathogenDef = cfg.pathogens[type_id] as PathogenDef
		if pdef.strains.is_empty():
			continue
		var row := VBoxContainer.new()
		row.name = "Type_%s" % type_id
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var head := Label.new()
		head.text = pdef.display_name
		UiFonts.style_label(head, 24, 800, UiPalette.color(false, "ink"))
		row.add_child(head)
		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.add_theme_constant_override("h_separation", 14)
		flow.add_theme_constant_override("v_separation", 14)
		for s: StrainDef in pdef.strains:
			flow.add_child(_make_card(type_id, s))
		row.add_child(flow)
		rows_box.add_child(row)


func _make_card(type_id: String, s: StrainDef) -> Control:
	var cfg: GameConfig = session.config
	var key: String = StrainUnlocks.key(type_id, s.id)
	var unlocked: bool = session.strain_unlocked(type_id, s.id)
	var card := PanelContainer.new()
	card.name = "Card_%s" % key.replace("/", "_")
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var pal: Dictionary = UiPalette.for_theme(false)
	card.add_theme_stylebox_override("panel", KitDraw.make_box(pal["panel"] as Color, 24.0, 2, pal["panel_border"] as Color,
			pal["panel_shadow"] as Color, 16, Vector2(0.0, 6.0)))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var name_label := Label.new()
	name_label.text = s.display_name
	UiFonts.style_label(name_label, 20, 800, UiPalette.color(false, "ink"))
	box.add_child(name_label)
	var mods := Label.new()
	mods.name = "ModifierLabel"
	mods.text = s.modifier_text()
	mods.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mods.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiFonts.style_label(mods, 15, 400, UiPalette.color(false, "muted"))
	box.add_child(mods)
	var status := Label.new()
	status.name = "StatusLabel"
	var button: PillButton = null
	if unlocked:
		status.text = UNLOCKED_TEXT
		UiFonts.style_label(status, 16, 800, UiPalette.color(false, "status_online"))
		box.add_child(status)
	else:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		status.text = "%d DNA" % s.unlock_dna
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiFonts.style_label(status, 18, 800, UiPalette.color(false, "accent"))
		row.add_child(status)
		button = PillButton.new("Unlock", PillButton.Variant.PRIMARY)
		button.name = "BtnUnlock"
		button.custom_minimum_size = BUTTON_SIZE
		button.disabled = session.wallet == null or session.wallet.get_amount("dna") < s.unlock_dna
		button.pressed.connect(unlock.bind(type_id, s.id))
		row.add_child(button)
		box.add_child(row)
	cards[key] = {"card": card, "status": status, "button": button}
	return card


## Buys a variant (an online worker job, or the local rule offline) and redraws.
func unlock(type_id: String, variant_id: String) -> void:
	if session == null or session.living_flow == null:
		return
	message_label.text = ""
	var ok: bool = await session.living_flow.unlock_strain_async(type_id, variant_id)
	if ok:
		strain_unlocked.emit(type_id, variant_id)
	else:
		message_label.text = session.living_flow.last_error_text
	refresh()
