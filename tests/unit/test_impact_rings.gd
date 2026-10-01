extends GutTest

var config: GameConfig = null


func before_all() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load cleanly")
	config = res.config


func after_each() -> void:
	ImpactRings.enabled = false


## Runs a scripted battle until the first damage event of either kind, returning the sim and that event.
func _first_damage() -> Array:
	var sim: BattleSim = BattleSim.new(config, Scenarios.open_field(42))
	while not sim.finished:
		sim.step()
		for ev: Dictionary in sim.drain_events():
			var t: String = str(ev.get("type", ""))
			if t == SimEvents.PATHOGEN_DAMAGED or t == SimEvents.STRUCTURE_DAMAGED:
				return [sim, ev]
	return [sim, {}]


func _make(sim: BattleSim) -> ImpactRings:
	var rings: ImpactRings = ImpactRings.new()
	add_child_autofree(rings)
	rings.setup(sim, IsoProjection.new(), null)
	return rings


func test_off_by_default_records_nothing() -> void:
	var found: Array = _first_damage()
	var ev: Dictionary = found[1]
	assert_false(ev.is_empty(), "the scripted battle must produce a damage event")
	var rings: ImpactRings = _make(found[0])
	rings.on_event(ev)
	assert_eq(rings.active_count((found[0] as BattleSim).tick), 0)


func test_records_a_ring_for_a_damage_event_and_expires_it() -> void:
	ImpactRings.enabled = true
	var found: Array = _first_damage()
	var sim: BattleSim = found[0]
	var rings: ImpactRings = _make(sim)
	rings.on_event(found[1])
	assert_eq(rings.active_count(sim.tick), 1)
	assert_eq(rings.active_count(sim.tick + ImpactRings.LIFE_TICKS + 2), 0, "a ring expires after LIFE_TICKS")


func test_ignores_other_events_and_never_overflows() -> void:
	ImpactRings.enabled = true
	var found: Array = _first_damage()
	var sim: BattleSim = found[0]
	var rings: ImpactRings = _make(sim)
	rings.on_event({"type": SimEvents.TOWER_FIRED, "structure_id": 1})
	assert_eq(rings.active_count(sim.tick), 0)
	for i: int in range(ImpactRings.CAPACITY * 2):
		rings.on_event(found[1])
	assert_eq(rings.active_count(sim.tick), ImpactRings.CAPACITY)


func test_debug_overlay_toggle_flips_the_switch() -> void:
	var overlay: DebugOverlay = (load("res://src/ui/debug_overlay.tscn") as PackedScene).instantiate() as DebugOverlay
	add_child_autofree(overlay)
	overlay.check_debug_build(true)
	assert_not_null(overlay.chk_impact_ticks)
	assert_true(overlay.chk_impact_ticks.custom_minimum_size.y >= 48.0)
	overlay.chk_impact_ticks.button_pressed = true
	assert_true(ImpactRings.enabled)
	overlay.chk_impact_ticks.button_pressed = false
	assert_false(ImpactRings.enabled)
