extends GutTest

## The Mutation Lab screen, the Living Base strain picker and the online unlock flow.

const DIR: String = "user://test_mutation_lab"
const T0: int = 1800000000

var _cfg: GameConfig


func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	_cfg = GameConfig.load_from_dir("res://data", {"living_base": true, "strains": true, "debug_dna": true}).config


func after_each() -> void:
	_clean()


func _clean() -> void:
	var d: DirAccess = DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _offline_session(dna: int = 0) -> Session:
	var store := LivingBaseStore.new()
	store.path = DIR + "/living_base.json"
	var session := Session.new(_cfg)
	LivingBaseFlow.new(store).enter(session)
	session.wallet.set_amount("dna", dna)
	return session


func _screen(session: Session) -> MutationLabScreen:
	var screen := MutationLabScreen.new()
	add_child_autofree(screen)
	screen.setup(session)
	return screen


func _wait_frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().process_frame


func test_every_variant_has_a_card_with_its_modifier_text() -> void:
	var screen: MutationLabScreen = _screen(_offline_session())
	assert_eq(screen.cards.size(), 9, "three variants for each of three pathogens")
	assert_eq(screen.explainer_label.text, MutationLabScreen.EXPLAINER_TEXT)
	var card: Control = (screen.cards["rhinovirus/capsid_hardening"] as Dictionary)["card"] as Control
	assert_eq((card.find_child("ModifierLabel", true, false) as Label).text, "+15% HP, -10% speed")


func test_free_variants_show_unlocked_and_the_rest_a_dna_cost_with_an_unlock_button() -> void:
	var screen: MutationLabScreen = _screen(_offline_session(100))
	var free: Dictionary = screen.cards["rhinovirus/capsid_hardening"] as Dictionary
	assert_eq((free["status"] as Label).text, "Unlocked")
	assert_null(free["button"])
	var second: Dictionary = screen.cards["rhinovirus/rapid_replication"] as Dictionary
	assert_eq((second["status"] as Label).text, "20 DNA")
	var third: Dictionary = screen.cards["rhinovirus/antigenic_masking"] as Dictionary
	assert_eq((third["status"] as Label).text, "40 DNA")
	for d: Dictionary in [second, third]:
		var b: PillButton = d["button"] as PillButton
		assert_gte(b.custom_minimum_size.x, 48.0)
		assert_gte(b.custom_minimum_size.y, 48.0)
		assert_false(b.disabled)
	assert_eq(screen.dna_label.text, "DNA: 100")


func test_an_unaffordable_variant_is_disabled() -> void:
	var screen: MutationLabScreen = _screen(_offline_session(10))
	assert_true(((screen.cards["rhinovirus/rapid_replication"] as Dictionary)["button"] as PillButton).disabled)


func test_an_offline_unlock_spends_dna_and_shows_unlocked() -> void:
	var session: Session = _offline_session(25)
	var screen: MutationLabScreen = _screen(session)
	watch_signals(screen)
	((screen.cards["rhinovirus/rapid_replication"] as Dictionary)["button"] as PillButton).pressed.emit()
	await _wait_frames(2)
	assert_signal_emitted(screen, "strain_unlocked")
	assert_eq(session.wallet.get_amount("dna"), 5)
	assert_true(session.profile.unlocked_strains.has("rhinovirus/rapid_replication"))
	assert_eq(((screen.cards["rhinovirus/rapid_replication"] as Dictionary)["status"] as Label).text, "Unlocked")
	assert_eq(screen.dna_label.text, "DNA: 5")
	assert_true(session.strain_unlocked("rhinovirus", "rapid_replication"))


func test_an_online_unlock_is_a_worker_job_and_adopts_the_result() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true, "strains": true}).config
	var backend := OfflineBackend.new()
	backend.set_status_for_tests("online")
	var server: LivingBaseProfile = LivingBaseProfile.create_new(cfg, 5, T0)
	server.wallet["dna"] = 30
	backend.respond("profile_get", {"ok": true, "error": "", "profile": JSON.parse_string(JSON.stringify(server.to_dict())), "job_id": "t"})
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	var flow := LivingBaseFlow.new(store)
	flow.online_cache_path = DIR + "/online.json"
	flow.local_base_path = DIR + "/none.json"
	flow.import_answered_path = DIR + "/answered.txt"
	var session := Session.new(cfg)
	var api := ProfileApi.new(backend)
	api.poll_interval_s = 0.0
	await flow.enter_online(session, api)
	var after: LivingBaseProfile = LivingBaseProfile.create_new(cfg, 5, T0)
	after.wallet["dna"] = 10
	after.unlocked_strains = StrainUnlocks.normalize(cfg, ["rhinovirus/rapid_replication"])
	backend.respond("mutation_unlock", {"ok": true, "error": "", "job_id": "m1"})
	backend.respond("job_status", {"ok": true, "status": "done", "result": {"profile": JSON.parse_string(JSON.stringify(after.to_dict())), "cost": 20}})
	var screen: MutationLabScreen = _screen(session)
	assert_false(session.strain_unlocked("rhinovirus", "rapid_replication"))
	((screen.cards["rhinovirus/rapid_replication"] as Dictionary)["button"] as PillButton).pressed.emit()
	await _wait_frames(3)
	var sent: Dictionary = {}
	for c: Dictionary in backend.calls:
		if c["name"] == "mutation_unlock":
			sent = c["payload"] as Dictionary
	assert_eq(sent, {"type": "rhinovirus", "variant": "rapid_replication"})
	assert_true(session.strain_unlocked("rhinovirus", "rapid_replication"))
	assert_eq(session.wallet.get_amount("dna"), 10)
	assert_eq(((screen.cards["rhinovirus/rapid_replication"] as Dictionary)["status"] as Label).text, "Unlocked")


func test_an_online_refusal_shows_the_reason() -> void:
	var cfg: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true, "online": true, "strains": true}).config
	var backend := OfflineBackend.new()
	backend.set_status_for_tests("online")
	var server: LivingBaseProfile = LivingBaseProfile.create_new(cfg, 5, T0)
	server.wallet["dna"] = 500
	backend.respond("profile_get", {"ok": true, "error": "", "profile": JSON.parse_string(JSON.stringify(server.to_dict())), "job_id": "t"})
	var store := LivingBaseStore.new()
	store.path = DIR + "/store.json"
	var flow := LivingBaseFlow.new(store)
	flow.online_cache_path = DIR + "/online.json"
	flow.local_base_path = DIR + "/none.json"
	flow.import_answered_path = DIR + "/answered.txt"
	var session := Session.new(cfg)
	var api := ProfileApi.new(backend)
	api.poll_interval_s = 0.0
	await flow.enter_online(session, api)
	backend.respond("mutation_unlock", {"ok": true, "error": "", "job_id": "m1"})
	backend.respond("job_status", {"ok": true, "status": "failed", "job_error": "already_unlocked"})
	var screen: MutationLabScreen = _screen(session)
	((screen.cards["rhinovirus/rapid_replication"] as Dictionary)["button"] as PillButton).pressed.emit()
	await _wait_frames(3)
	assert_eq(screen.message_label.text, NetCopy.error_text("already_unlocked"))


# --- the Incubation strain picker ---------------------------------------------------------------

func _hud(session: Session) -> HudSpawn:
	var hud: HudSpawn = (load("res://src/ui/hud_spawn.tscn") as PackedScene).instantiate() as HudSpawn
	add_child_autofree(hud)
	hud.setup(session)
	hud.get_card("rhinovirus").selected.emit()
	return hud


func test_in_living_base_locked_variants_cannot_be_selected_and_show_a_lock() -> void:
	var session: Session = _offline_session()
	var hud: HudSpawn = _hud(session)
	assert_true(hud.strain_lock_row.visible)
	assert_true(hud.strain_lock_label.text.contains("Rapid Replication (20 DNA)"))
	assert_true(hud.strain_lock_label.text.contains("Antigenic Masking (40 DNA)"))
	assert_not_null(hud.strain_lock_row.get_child(0) as LockIcon)
	var seen: Array[String] = []
	for i: int in range(4):
		hud.strain_button.pressed.emit()
		seen.append(session.army.strain_of("rhinovirus"))
	assert_false(seen.has("rapid_replication"))
	assert_false(seen.has("antigenic_masking"))
	assert_true(seen.has("capsid_hardening"))
	assert_true(seen.has("wild"))


func test_an_unlocked_variant_becomes_selectable() -> void:
	var session: Session = _offline_session(100)
	assert_true(await session.living_flow.unlock_strain_async("rhinovirus", "rapid_replication"))
	var hud: HudSpawn = _hud(session)
	assert_false(hud.strain_lock_label.text.contains("Rapid Replication"))
	var seen: Array[String] = []
	for i: int in range(4):
		hud.strain_button.pressed.emit()
		seen.append(session.army.strain_of("rhinovirus"))
	assert_true(seen.has("rapid_replication"))
	assert_false(seen.has("antigenic_masking"))


func test_in_lab_everything_is_selectable_and_nothing_is_locked() -> void:
	var session := Session.new(_cfg)
	assert_eq(session.mode, Session.Mode.LAB)
	var hud: HudSpawn = _hud(session)
	assert_false(hud.strain_lock_row.visible)
	var seen: Array[String] = []
	for i: int in range(4):
		hud.strain_button.pressed.emit()
		seen.append(session.army.strain_of("rhinovirus"))
	assert_eq(seen, ["capsid_hardening", "rapid_replication", "antigenic_masking", "wild"] as Array[String])


func test_the_hud_button_shows_with_the_strains_flag_in_living_base_only() -> void:
	var session: Session = _offline_session()
	var grid_view := GridView.new()
	add_child_autofree(grid_view)
	grid_view.setup(session.grid, _cfg)
	var bc := BuildController.new()
	add_child_autofree(bc)
	bc.setup(session, grid_view)
	var hud: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
	add_child_autofree(hud)
	hud.setup(session, bc)
	assert_true(hud.btn_mutation_lab.visible)
	assert_gte(hud.btn_mutation_lab.custom_minimum_size.y, 48.0)
	var plain: GameConfig = GameConfig.load_from_dir("res://data", {"living_base": true}).config
	var s2 := Session.new(plain)
	var store := LivingBaseStore.new()
	store.path = DIR + "/plain.json"
	LivingBaseFlow.new(store).enter(s2)
	var gv2 := GridView.new()
	add_child_autofree(gv2)
	gv2.setup(s2.grid, plain)
	var bc2 := BuildController.new()
	add_child_autofree(bc2)
	bc2.setup(s2, gv2)
	var hud2: HudBuild = (load("res://src/ui/hud_build.tscn") as PackedScene).instantiate() as HudBuild
	add_child_autofree(hud2)
	hud2.setup(s2, bc2)
	assert_false(hud2.btn_mutation_lab.visible, "no strains flag, no Mutation Lab")
