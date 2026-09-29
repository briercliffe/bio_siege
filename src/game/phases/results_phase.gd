class_name ResultsPhase
extends Control

signal choice_made(choice: String)

var session: Session = null
var fsm: GameStateMachine = null

# UI references
var panel: PanelContainer = null
var scroll_container: ScrollContainer = null
var title_label: Label = null
var reason_label: Label = null
var stats_container: VBoxContainer = null

# Stat value labels
var val_battle_time: Label = null
var val_nucleus_hp: Label = null
var val_structures_destroyed: Label = null
var val_pathogens_lost: Label = null
var val_first_structure: Label = null
var val_first_contact: Label = null

var stats: Dictionary = {}

# ATP Split bar
var atp_bar: HBoxContainer = null
var bar_base: ColorRect = null
var bar_army: ColorRect = null
var bar_unspent: ColorRect = null
var legend_label: Label = null

var base_atp: int = 0
var army_atp: int = 0
var unspent_atp: int = 0
var split_widths: Dictionary = {}

# Buttons
var btn_re_raid: Button = null
var btn_edit_base: Button = null
var btn_new_base: Button = null

# Telemetry slots
var survey_slot: VBoxContainer = null
var export_slot: VBoxContainer = null


func _ready() -> void:
	_resolve_nodes()
	_wire_buttons()
	if session != null:
		_populate()


func _resolve_nodes() -> void:
	if panel == null:
		panel = find_child("Panel", true, false) as PanelContainer
	if scroll_container == null:
		scroll_container = find_child("ScrollContainer", true, false) as ScrollContainer
	if title_label == null:
		title_label = find_child("TitleLabel", true, false) as Label
	if reason_label == null:
		reason_label = find_child("ReasonLabel", true, false) as Label
	if stats_container == null:
		stats_container = find_child("StatsContainer", true, false) as VBoxContainer

	if val_battle_time == null:
		val_battle_time = find_child("ValBattleTime", true, false) as Label
	if val_nucleus_hp == null:
		val_nucleus_hp = find_child("ValNucleusHp", true, false) as Label
	if val_structures_destroyed == null:
		val_structures_destroyed = find_child("ValStructuresDestroyed", true, false) as Label
	if val_pathogens_lost == null:
		val_pathogens_lost = find_child("ValPathogensLost", true, false) as Label
	if val_first_structure == null:
		val_first_structure = find_child("ValFirstStructure", true, false) as Label
	if val_first_contact == null:
		val_first_contact = find_child("ValFirstContact", true, false) as Label

	if atp_bar == null:
		atp_bar = find_child("AtpBar", true, false) as HBoxContainer
	if bar_base == null:
		bar_base = find_child("BarBase", true, false) as ColorRect
	if bar_army == null:
		bar_army = find_child("BarArmy", true, false) as ColorRect
	if bar_unspent == null:
		bar_unspent = find_child("BarUnspent", true, false) as ColorRect
	if legend_label == null:
		legend_label = find_child("LegendLabel", true, false) as Label

	if btn_re_raid == null:
		btn_re_raid = find_child("BtnReRaid", true, false) as Button
	if btn_edit_base == null:
		btn_edit_base = find_child("BtnEditBase", true, false) as Button
	if btn_new_base == null:
		btn_new_base = find_child("BtnNewBase", true, false) as Button

	if survey_slot == null:
		survey_slot = find_child("SurveySlot", true, false) as VBoxContainer
	if export_slot == null:
		export_slot = find_child("ExportSlot", true, false) as VBoxContainer

	# If instantiated directly without scene file, build programmatically
	if title_label == null:
		_build_ui_fallback()


func _build_ui_fallback() -> void:
	if theme == null:
		var theme_res: Theme = load("res://src/ui/theme_spawn.tres") as Theme
		if theme_res != null:
			theme = theme_res

	var dummy_label := Label.new()
	dummy_label.name = "Label"
	dummy_label.text = "RESULTS"
	dummy_label.visible = false
	add_child(dummy_label)

	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll_container)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(center)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(640, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "ContentBox"
	content.custom_minimum_size = Vector2(560, 0)
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "IMMUNE RESPONSE WINS"
	content.add_child(title_label)

	reason_label = Label.new()
	reason_label.name = "ReasonLabel"
	reason_label.add_theme_font_size_override("font_size", 18)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(reason_label)

	content.add_child(HSeparator.new())

	stats_container = VBoxContainer.new()
	stats_container.name = "StatsContainer"
	stats_container.add_theme_constant_override("separation", 8)
	content.add_child(stats_container)

	val_battle_time = _add_stat_row(stats_container, "Battle time", "0:00", "ValBattleTime")
	val_nucleus_hp = _add_stat_row(stats_container, "Nucleus HP remaining", "0 / 2000", "ValNucleusHp")
	val_structures_destroyed = _add_stat_row(stats_container, "Structures destroyed", "0 / 0", "ValStructuresDestroyed")
	val_pathogens_lost = _add_stat_row(stats_container, "Pathogens lost", "0 / 0", "ValPathogensLost")
	val_first_structure = _add_stat_row(stats_container, "First structure to fall", "none", "ValFirstStructure")
	val_first_contact = _add_stat_row(stats_container, "Time to first contact", "never", "ValFirstContact")

	content.add_child(HSeparator.new())

	var atp_section := VBoxContainer.new()
	atp_section.name = "AtpSection"
	atp_section.add_theme_constant_override("separation", 8)
	content.add_child(atp_section)

	atp_bar = HBoxContainer.new()
	atp_bar.name = "AtpBar"
	atp_bar.custom_minimum_size = Vector2(560, 24)
	atp_bar.add_theme_constant_override("separation", 0)
	atp_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	atp_section.add_child(atp_bar)

	bar_base = ColorRect.new()
	bar_base.name = "BarBase"
	bar_base.custom_minimum_size = Vector2(0, 24)
	bar_base.color = Color("#1e5aa8")
	atp_bar.add_child(bar_base)

	bar_army = ColorRect.new()
	bar_army.name = "BarArmy"
	bar_army.custom_minimum_size = Vector2(0, 24)
	bar_army.color = Color("#c0392b")
	atp_bar.add_child(bar_army)

	bar_unspent = ColorRect.new()
	bar_unspent.name = "BarUnspent"
	bar_unspent.custom_minimum_size = Vector2(0, 24)
	bar_unspent.color = Color("#7f8c8d")
	atp_bar.add_child(bar_unspent)

	legend_label = Label.new()
	legend_label.name = "LegendLabel"
	legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend_label.text = "Base 0 · Army 0 · Unspent 0"
	atp_section.add_child(legend_label)

	survey_slot = VBoxContainer.new()
	survey_slot.name = "SurveySlot"
	content.add_child(survey_slot)

	export_slot = VBoxContainer.new()
	export_slot.name = "ExportSlot"
	content.add_child(export_slot)

	content.add_child(HSeparator.new())

	var btns_box := VBoxContainer.new()
	btns_box.name = "ButtonsContainer"
	btns_box.add_theme_constant_override("separation", 12)
	content.add_child(btns_box)

	btn_re_raid = Button.new()
	btn_re_raid.name = "BtnReRaid"
	btn_re_raid.custom_minimum_size = Vector2(0, 48)
	btn_re_raid.text = "Raid the same base again"
	btns_box.add_child(btn_re_raid)

	btn_edit_base = Button.new()
	btn_edit_base.name = "BtnEditBase"
	btn_edit_base.custom_minimum_size = Vector2(0, 48)
	btn_edit_base.text = "Go back and change your defenses"
	btns_box.add_child(btn_edit_base)

	btn_new_base = Button.new()
	btn_new_base.name = "BtnNewBase"
	btn_new_base.custom_minimum_size = Vector2(0, 48)
	btn_new_base.text = "Start over with 1000 ATP"
	btns_box.add_child(btn_new_base)


func _add_stat_row(parent_box: VBoxContainer, label_text: String, default_val: String, val_node_name: String) -> Label:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.name = val_node_name
	val.text = default_val
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)

	parent_box.add_child(row)
	return val


func _wire_buttons() -> void:
	if btn_re_raid != null and not btn_re_raid.pressed.is_connected(_on_re_raid_pressed):
		btn_re_raid.pressed.connect(_on_re_raid_pressed)
	if btn_edit_base != null and not btn_edit_base.pressed.is_connected(_on_edit_base_pressed):
		btn_edit_base.pressed.connect(_on_edit_base_pressed)
	if btn_new_base != null and not btn_new_base.pressed.is_connected(_on_new_base_pressed):
		btn_new_base.pressed.connect(_on_new_base_pressed)


func setup(p_session: Session, p_fsm: GameStateMachine = null) -> void:
	session = p_session
	fsm = p_fsm
	_resolve_nodes()
	_wire_buttons()
	_populate()


func _populate() -> void:
	var res: Dictionary = session.last_result if session != null else {}
	var end_reason: String = str(res.get("end_reason", ""))
	var outcome: String = str(res.get("outcome", ""))
	var battle_s: float = float(res.get("battle_s", 0.0))

	var timeout_s: float = float(res.get("timeout_s", 0.0))
	if timeout_s <= 0.0:
		if session != null and session.config != null and session.config.tick_rate > 0 and session.config.battle_timeout_ticks > 0:
			timeout_s = float(session.config.battle_timeout_ticks) / float(session.config.tick_rate)
		else:
			timeout_s = battle_s

	var is_attacker_win: bool = (end_reason == "nucleus_destroyed" or outcome == "attacker")

	# 1. Title
	if title_label != null:
		if is_attacker_win:
			title_label.text = "INFECTION SUCCESSFUL"
			title_label.add_theme_color_override("font_color", Color("#2ecc71"))
		else:
			title_label.text = "IMMUNE RESPONSE WINS"
			title_label.add_theme_color_override("font_color", Color("#48dbfb"))

	# 2. Reason line
	if reason_label != null:
		if end_reason == "nucleus_destroyed" or (is_attacker_win and end_reason.is_empty()):
			reason_label.text = "The Nucleus was destroyed in %d:%02d." % [int(battle_s) / 60, int(battle_s) % 60]
		elif end_reason == "timeout":
			reason_label.text = "Time ran out (%d:%02d). The immune system held." % [int(timeout_s) / 60, int(timeout_s) % 60]
		else:
			reason_label.text = "Every pathogen was eliminated after %d:%02d." % [int(battle_s) / 60, int(battle_s) % 60]

	# 3. Stat rows
	var nucleus_hp: int = int(res.get("nucleus_hp", 0))
	var nucleus_max_hp: int = int(res.get("nucleus_max_hp", 2000))
	var structures_destroyed: int = int(res.get("structures_destroyed", 0))
	var structures_total: int = int(res.get("structures_total", 0))
	var pathogens_lost: int = int(res.get("pathogens_lost", res.get("pathogens_killed", 0)))
	var pathogens_total: int = int(res.get("pathogens_total", 0))
	var first_contact_s: float = float(res.get("first_contact_s", -1.0))

	var first_structure: String = str(res.get("first_structure_to_fall", ""))
	if first_structure.is_empty():
		var f_id: int = int(res.get("first_destroyed_structure_id", 0))
		var f_type: String = str(res.get("first_destroyed_structure_type", ""))
		if f_id > 0 and not f_type.is_empty():
			if session != null and session.config != null and session.config.structures.has(f_type):
				first_structure = session.config.structures[f_type].display_name
			else:
				first_structure = f_type.capitalize()
		else:
			first_structure = "none"

	var time_str: String = "%d:%02d" % [int(battle_s) / 60, int(battle_s) % 60]
	var nucleus_hp_str: String = "%d / %d" % [nucleus_hp, nucleus_max_hp]
	var structures_str: String = "%d / %d" % [structures_destroyed, structures_total]
	var pathogens_str: String = "%d / %d" % [pathogens_lost, pathogens_total]
	var contact_str: String = "never" if first_contact_s < 0.0 else ("%d:%02d" % [int(first_contact_s) / 60, int(first_contact_s) % 60])

	if val_battle_time != null:
		val_battle_time.text = time_str
	if val_nucleus_hp != null:
		val_nucleus_hp.text = nucleus_hp_str
	if val_structures_destroyed != null:
		val_structures_destroyed.text = structures_str
	if val_pathogens_lost != null:
		val_pathogens_lost.text = pathogens_str
	if val_first_structure != null:
		val_first_structure.text = first_structure
	if val_first_contact != null:
		val_first_contact.text = contact_str

	stats = {
		"Battle time": time_str,
		"Nucleus HP remaining": nucleus_hp_str,
		"Structures destroyed": structures_str,
		"Pathogens lost": pathogens_str,
		"First structure to fall": first_structure,
		"Time to first contact": contact_str,
	}

	# 4. ATP split bar
	base_atp = 0
	army_atp = 0
	unspent_atp = 0

	if session != null:
		if not session.last_launch.is_empty():
			base_atp = int(session.last_launch.get("base_atp", 0))
			army_atp = int(session.last_launch.get("army_atp", 0))
			unspent_atp = int(session.last_launch.get("unspent_atp", 0))
		else:
			if session.grid != null:
				base_atp = int(session.grid.total_cost().get("atp", 0))
			if session.army != null:
				army_atp = int(session.army.total_cost().get("atp", 0))
			if session.wallet != null:
				unspent_atp = session.wallet.get_amount("atp")

	var total_atp: int = base_atp + army_atp + unspent_atp
	var w_base: float = 0.0
	var w_army: float = 0.0
	var w_unspent: float = 0.0

	if total_atp > 0:
		w_base = roundf(560.0 * float(base_atp) / float(total_atp))
		w_army = roundf(560.0 * float(army_atp) / float(total_atp))
		w_unspent = maxf(0.0, 560.0 - w_base - w_army)

	split_widths = {
		"base": w_base,
		"army": w_army,
		"unspent": w_unspent,
	}

	if bar_base != null:
		bar_base.custom_minimum_size = Vector2(w_base, 24.0)
		bar_base.size = Vector2(w_base, 24.0)
		bar_base.color = Color("#1e5aa8")
	if bar_army != null:
		bar_army.custom_minimum_size = Vector2(w_army, 24.0)
		bar_army.size = Vector2(w_army, 24.0)
		bar_army.color = Color("#c0392b")
	if bar_unspent != null:
		bar_unspent.custom_minimum_size = Vector2(w_unspent, 24.0)
		bar_unspent.size = Vector2(w_unspent, 24.0)
		bar_unspent.color = Color("#7f8c8d")

	if legend_label != null:
		legend_label.text = "Base %d · Army %d · Unspent %d" % [base_atp, army_atp, unspent_atp]

	# 5. Buttons
	var start_atp: int = 1000
	if session != null and session.config != null:
		start_atp = int(session.config.start_wallet.get("atp", 1000))

	if btn_re_raid != null:
		btn_re_raid.text = "Raid the same base again"
	if btn_edit_base != null:
		btn_edit_base.text = "Go back and change your defenses"
	if btn_new_base != null:
		btn_new_base.text = "Start over with %d ATP" % start_atp


func get_stat(stat_name: String) -> String:
	return str(stats.get(stat_name, ""))


func get_atp_split_widths() -> Dictionary:
	return split_widths.duplicate()


func make_choice(choice: String) -> void:
	choice_made.emit(choice)
	apply_choice(choice, session, fsm)


func _on_re_raid_pressed() -> void:
	make_choice("re_raid")


func _on_edit_base_pressed() -> void:
	make_choice("edit_base")


func _on_new_base_pressed() -> void:
	make_choice("new_base")


static func apply_choice(choice: String, session: Session, fsm: GameStateMachine = null) -> void:
	if session == null:
		return

	match choice:
		"re_raid":
			if session.army != null:
				session.army.refund_all(session.wallet)
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.INCUBATION)
		"edit_base":
			if session.army != null:
				session.army.refund_all(session.wallet)
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
		"new_base":
			if session.wallet != null and session.config != null:
				session.wallet.reset(session.config.start_wallet)
			if session.grid != null:
				session.grid.reset_with_nucleus()
			session.army = Army.new(session.config)
			if fsm != null:
				fsm.request_transition(GameStateMachine.Phase.SYNTHESIS)
