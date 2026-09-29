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

# Telemetry slots and controls
var survey_slot: VBoxContainer = null
var export_slot: VBoxContainer = null
var val_prediction: Label = null

var btn_toggle_survey: Button = null
var survey_body: VBoxContainer = null
var btn_submit_survey: Button = null
var btn_export_logs: Button = null

var survey_pivot: int = 3
var survey_predictability: int = 3
var survey_economy: int = 3
var survey_map_feel: String = "right"
var survey_submitted: bool = false


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
	if val_prediction == null:
		val_prediction = find_child("ValPrediction", true, false) as Label

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

	val_prediction = Label.new()
	val_prediction.name = "ValPrediction"
	val_prediction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_prediction.visible = false
	stats_container.add_child(val_prediction)

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

	var pred_id: int = int(res.get("prediction_structure_id", session.prediction_structure_id if session != null else 0))
	if val_prediction != null:
		if pred_id <= 0:
			val_prediction.visible = false
			val_prediction.text = ""
		else:
			val_prediction.visible = true
			var first_id: int = int(res.get("first_destroyed_structure_id", 0))
			var is_correct: bool = (first_id > 0 and pred_id == first_id)
			if is_correct:
				val_prediction.text = "Your prediction: ✓ correct"
				val_prediction.add_theme_color_override("font_color", Color("#2ecc71"))
			else:
				var first_type: String = str(res.get("first_destroyed_structure_type", ""))
				var display_name: String = ""
				if not first_type.is_empty() and session != null and session.config != null and session.config.structures.has(first_type):
					display_name = session.config.structures[first_type].display_name
				elif not first_type.is_empty():
					display_name = first_type.capitalize()
				else:
					display_name = "none"
				val_prediction.text = "Your prediction: ✗ it was the %s" % display_name
				val_prediction.add_theme_color_override("font_color", Color("#e74c3c"))

	stats = {
		"Battle time": time_str,
		"Nucleus HP remaining": nucleus_hp_str,
		"Structures destroyed": structures_str,
		"Pathogens lost": pathogens_str,
		"First structure to fall": first_structure,
		"Time to first contact": contact_str,
	}
	if val_prediction != null and val_prediction.visible:
		stats["Prediction"] = val_prediction.text

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
	if btn_re_raid != null:
		btn_re_raid.text = "Raid the same base again"
	if btn_edit_base != null:
		btn_edit_base.text = "Go back and change your defenses"
	_update_new_base_label()

	_populate_survey()
	_populate_export()


func _update_new_base_label() -> void:
	var start_atp: int = 1000
	if session != null and session.config != null:
		start_atp = int(session.config.start_wallet.get("atp", 1000))
	if btn_new_base != null:
		btn_new_base.text = "Start over with %d ATP" % start_atp


## Called by GameStateMachine after a config hot reload was applied (#27).
func on_config_changed(_summary: Dictionary) -> void:
	_update_new_base_label()


func get_stat(stat_name: String) -> String:
	return str(stats.get(stat_name, ""))


func get_atp_split_widths() -> Dictionary:
	return split_widths.duplicate()


func make_choice(choice: String) -> void:
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("results_choice", {"choice": choice})
	choice_made.emit(choice)
	apply_choice(choice, session, fsm)


func _populate_survey() -> void:
	if survey_slot == null:
		return
	for c in survey_slot.get_children():
		c.queue_free()

	survey_submitted = false
	survey_pivot = 3
	survey_predictability = 3
	survey_economy = 3
	survey_map_feel = "right"

	btn_toggle_survey = Button.new()
	btn_toggle_survey.name = "BtnToggleSurvey"
	btn_toggle_survey.text = "Quick feedback (optional) ▼"
	btn_toggle_survey.custom_minimum_size = Vector2(0, 48.0)
	survey_slot.add_child(btn_toggle_survey)

	survey_body = VBoxContainer.new()
	survey_body.name = "SurveyBody"
	survey_body.visible = false
	survey_body.add_theme_constant_override("separation", 12)
	survey_slot.add_child(survey_body)

	btn_toggle_survey.pressed.connect(func():
		survey_body.visible = not survey_body.visible
		btn_toggle_survey.text = "Quick feedback (optional) ▲" if survey_body.visible else "Quick feedback (optional) ▼"
	)

	# Row 1: "How did switching from builder to attacker feel?" (1..5: "Jarring" .. "Rewarding")
	var row1 := VBoxContainer.new()
	row1.name = "SurveyRow1"
	var q1_lbl := Label.new()
	q1_lbl.text = "How did switching from builder to attacker feel?"
	row1.add_child(q1_lbl)
	var r1_box := HBoxContainer.new()
	r1_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl_j := Label.new()
	lbl_j.text = "Jarring "
	r1_box.add_child(lbl_j)
	var bg1 := ButtonGroup.new()
	for i in range(1, 6):
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(48.0, 48.0)
		b.toggle_mode = true
		b.button_group = bg1
		if i == 3:
			b.button_pressed = true
		var val: int = i
		b.pressed.connect(func(): survey_pivot = val)
		r1_box.add_child(b)
	var lbl_r := Label.new()
	lbl_r.text = " Rewarding"
	r1_box.add_child(lbl_r)
	row1.add_child(r1_box)
	survey_body.add_child(row1)

	# Row 2: "Could you predict where pathogens would go?" (1..5)
	var row2 := VBoxContainer.new()
	row2.name = "SurveyRow2"
	var q2_lbl := Label.new()
	q2_lbl.text = "Could you predict where pathogens would go?"
	row2.add_child(q2_lbl)
	var r2_box := HBoxContainer.new()
	r2_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var bg2 := ButtonGroup.new()
	for i in range(1, 6):
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(48.0, 48.0)
		b.toggle_mode = true
		b.button_group = bg2
		if i == 3:
			b.button_pressed = true
		var val: int = i
		b.pressed.connect(func(): survey_predictability = val)
		r2_box.add_child(b)
	row2.add_child(r2_box)
	survey_body.add_child(row2)

	# Row 3: "Did sharing ATP between base and army force interesting choices?" (1..5)
	var row3 := VBoxContainer.new()
	row3.name = "SurveyRow3"
	var q3_lbl := Label.new()
	q3_lbl.text = "Did sharing ATP between base and army force interesting choices?"
	row3.add_child(q3_lbl)
	var r3_box := HBoxContainer.new()
	r3_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var bg3 := ButtonGroup.new()
	for i in range(1, 6):
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(48.0, 48.0)
		b.toggle_mode = true
		b.button_group = bg3
		if i == 3:
			b.button_pressed = true
		var val: int = i
		b.pressed.connect(func(): survey_economy = val)
		r3_box.add_child(b)
	row3.add_child(r3_box)
	survey_body.add_child(row3)

	# Row 4: "The map felt:" [Too small] [About right] [Too big]
	var row4 := VBoxContainer.new()
	row4.name = "SurveyRow4"
	var q4_lbl := Label.new()
	q4_lbl.text = "The map felt:"
	row4.add_child(q4_lbl)
	var r4_box := HBoxContainer.new()
	r4_box.alignment = BoxContainer.ALIGNMENT_CENTER
	r4_box.add_theme_constant_override("separation", 8)
	var bg4 := ButtonGroup.new()
	var opts: Array[Dictionary] = [
		{"label": "Too small", "val": "too_small"},
		{"label": "About right", "val": "right"},
		{"label": "Too big", "val": "too_big"}
	]
	for opt in opts:
		var b := Button.new()
		b.text = str(opt["label"])
		b.custom_minimum_size = Vector2(100.0, 48.0)
		b.toggle_mode = true
		b.button_group = bg4
		if str(opt["val"]) == "right":
			b.button_pressed = true
		var val_str: String = str(opt["val"])
		b.pressed.connect(func(): survey_map_feel = val_str)
		r4_box.add_child(b)
	row4.add_child(r4_box)
	survey_body.add_child(row4)

	# Submit button
	btn_submit_survey = Button.new()
	btn_submit_survey.name = "BtnSubmitSurvey"
	btn_submit_survey.text = "Submit feedback"
	btn_submit_survey.custom_minimum_size = Vector2(0, 48.0)
	btn_submit_survey.pressed.connect(_on_submit_survey_pressed)
	survey_body.add_child(btn_submit_survey)


func _on_submit_survey_pressed() -> void:
	if survey_submitted:
		return
	survey_submitted = true
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("survey", {
			"pivot": survey_pivot,
			"predictability": survey_predictability,
			"economy": survey_economy,
			"map_feel": survey_map_feel
		})
	if btn_submit_survey != null:
		btn_submit_survey.disabled = true
		btn_submit_survey.text = "Feedback submitted — thank you!"
	_disable_survey_inputs()


func _disable_survey_inputs() -> void:
	if survey_body == null:
		return
	_disable_buttons_recursive(survey_body)


func _disable_buttons_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Button and child != btn_toggle_survey:
			(child as Button).disabled = true
		_disable_buttons_recursive(child)


func _populate_export() -> void:
	if export_slot == null:
		return
	for c in export_slot.get_children():
		c.queue_free()

	btn_export_logs = Button.new()
	btn_export_logs.name = "BtnExportLogs"
	btn_export_logs.text = "Export playtest logs"
	btn_export_logs.custom_minimum_size = Vector2(0, 48.0)
	btn_export_logs.pressed.connect(_on_export_logs_pressed)
	export_slot.add_child(btn_export_logs)


func _on_export_logs_pressed() -> void:
	export_playtest_logs()


static func export_playtest_logs() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(SessionLogger.all_sessions_text().to_utf8_buffer(), "bio_siege_telemetry.jsonl", "application/x-ndjson")
	else:
		OS.shell_open(ProjectSettings.globalize_path("user://telemetry"))
	if SessionLogger != null and SessionLogger.has_method("log_event"):
		SessionLogger.log_event("logs_exported", {})


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
