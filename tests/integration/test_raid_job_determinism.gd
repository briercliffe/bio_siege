extends GutTest

## The worker is the authority, so one raid job must always give the same bytes.

const T0: int = 1800000000


func _job(cfg: GameConfig) -> Dictionary:
	var grid := GridModel.new(cfg)
	var layout: Array = [{"type": "nucleus", "origin": [18, 18]}, {"type": "mitochondria", "origin": [10, 10]},
			{"type": "macrophage", "origin": [14, 10]}, {"type": "b_cell", "origin": [24, 10]}]
	grid.load_layout(layout, LivingBaseProfile.unlimited_wallet())
	var defender: LivingBaseProfile = LivingBaseProfile.create_new(cfg, 2, T0)
	defender.layout = grid.to_layout()
	defender.stored_atp = 300
	var d: Dictionary = JSON.parse_string(JSON.stringify(defender.to_dict())) as Dictionary
	var attacker: Dictionary = JSON.parse_string(JSON.stringify(LivingBaseProfile.create_new(cfg, 1, T0).to_dict())) as Dictionary
	var ring: Array[Vector2i] = grid.ring_cells()
	var army: Array = []
	for i: int in range(10):
		army.append({"type": "rhinovirus" if i % 2 == 0 else "bacteriophage", "cell": [ring[i * 9].x, ring[i * 9].y], "strain": "wild"})
	return {"job_id": "j", "type": "raid_validate", "created_unix": T0, "config_hash": cfg.content_hash, "payload": {
		"raid": {"raid_id": "r", "seed": 99, "defender_snapshot": ProfileJobs.snapshot_of(cfg, d, T0), "attacker_pools": {},
				"submission": {"army": army, "client_final_hash": ""}},
		"attacker_profile": attacker, "defender_profile": d, "now_unix": T0}}


func test_one_raid_job_run_twice_is_byte_identical() -> void:
	for flags: Dictionary in [{}, {"coevolution": true, "immune_memory": true, "bcell_analysis": true, "dendritic_cell": true}]:
		var overrides: Dictionary = {"living_base": true}
		for k: Variant in flags.keys():
			overrides[k] = flags[k]
		var cfg: GameConfig = GameConfig.load_from_dir("res://data", overrides).config
		var first: String = JSON.stringify(JobRules.process(cfg, _job(cfg)), "", true)
		var second: String = JSON.stringify(JobRules.process(GameConfig.load_from_dir("res://data", overrides).config, _job(cfg)), "", true)
		assert_true(first.length() > 1000)
		assert_eq(first, second)
		assert_true(JSON.parse_string(first)["ok"])
