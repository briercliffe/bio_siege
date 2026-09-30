extends GutTest

func _load_config() -> GameConfig:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok(), "Config should load successfully from res://data")
	return res.config

func test_army_init_defaults() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)

	assert_eq(army.reserve.size(), 0)
	assert_eq(army.deployments.size(), 0)
	assert_eq(army.reserve_count("rhinovirus"), 0)
	assert_eq(army.deployed_count("rhinovirus"), 0)
	assert_eq(army.total_count(), 0)
	assert_eq(army.total_cost(), {})

func test_army_buy_success_and_wallet_spend() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 100})
	watch_signals(army)

	# Rhinovirus cost: 10 ATP
	var ok: bool = army.buy("rhinovirus", wallet)
	assert_true(ok)
	assert_signal_emitted(army, "changed")
	assert_eq(wallet.get_amount("atp"), 90)
	assert_eq(army.reserve_count("rhinovirus"), 1)
	assert_eq(army.total_count(), 1)
	assert_eq(army.total_cost(), {"atp": 10})

	# Buy another rhinovirus
	ok = army.buy("rhinovirus", wallet)
	assert_true(ok)
	assert_eq(wallet.get_amount("atp"), 80)
	assert_eq(army.reserve_count("rhinovirus"), 2)
	assert_eq(army.total_count(), 2)
	assert_eq(army.total_cost(), {"atp": 20})

	# Buy bacteriophage: 40 ATP
	ok = army.buy("bacteriophage", wallet)
	assert_true(ok)
	assert_eq(wallet.get_amount("atp"), 40)
	assert_eq(army.reserve_count("bacteriophage"), 1)
	assert_eq(army.total_count(), 3)
	assert_eq(army.total_cost(), {"atp": 60})

func test_army_buy_insufficient_funds() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 5})
	watch_signals(army)

	# Rhinovirus cost is 10 ATP, wallet only has 5
	var ok: bool = army.buy("rhinovirus", wallet)
	assert_false(ok)
	assert_signal_not_emitted(army, "changed")
	assert_eq(wallet.get_amount("atp"), 5)
	assert_eq(army.reserve_count("rhinovirus"), 0)
	assert_eq(army.total_count(), 0)

func test_army_buy_unknown_type() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 100})
	watch_signals(army)

	var ok: bool = army.buy("non_existent_type", wallet)
	assert_false(ok)
	assert_signal_not_emitted(army, "changed")
	assert_eq(wallet.get_amount("atp"), 100)

func test_army_unbuy_success_and_wallet_refund() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 100})

	assert_true(army.buy("bacteriophage", wallet)) # costs 40 -> 60 left
	assert_eq(wallet.get_amount("atp"), 60)
	assert_eq(army.reserve_count("bacteriophage"), 1)

	watch_signals(army)
	var ok: bool = army.unbuy("bacteriophage", wallet)
	assert_true(ok)
	assert_signal_emitted(army, "changed")
	assert_eq(wallet.get_amount("atp"), 100)
	assert_eq(army.reserve_count("bacteriophage"), 0)
	assert_eq(army.total_count(), 0)
	assert_eq(army.total_cost(), {})

func test_army_unbuy_not_in_reserve() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 100})
	watch_signals(army)

	var ok: bool = army.unbuy("rhinovirus", wallet)
	assert_false(ok)
	assert_signal_not_emitted(army, "changed")
	assert_eq(wallet.get_amount("atp"), 100)

func test_army_deploy_and_deployed_count() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 100})

	assert_true(army.buy("rhinovirus", wallet))
	assert_true(army.buy("rhinovirus", wallet))
	assert_eq(army.reserve_count("rhinovirus"), 2)
	assert_eq(army.deployed_count("rhinovirus"), 0)

	watch_signals(army)
	var ok: bool = army.deploy("rhinovirus", Vector2i(1, 1))
	assert_true(ok)
	assert_signal_emitted(army, "changed")
	assert_eq(army.reserve_count("rhinovirus"), 1)
	assert_eq(army.deployed_count("rhinovirus"), 1)
	assert_eq(army.total_count(), 2) # 1 reserve + 1 deployed
	assert_eq(army.deployments.size(), 1)
	assert_eq(army.deployments[0]["type"], "rhinovirus")
	assert_eq(army.deployments[0]["cell"], Vector2i(1, 1))

	# Deploy second unit
	ok = army.deploy("rhinovirus", Vector2i(1, 2))
	assert_true(ok)
	assert_eq(army.reserve_count("rhinovirus"), 0)
	assert_eq(army.deployed_count("rhinovirus"), 2)
	assert_eq(army.total_count(), 2)

	# Deploy when reserve is 0 fails
	ok = army.deploy("rhinovirus", Vector2i(1, 3))
	assert_false(ok)

func test_army_deployed_at() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 100})

	assert_true(army.buy("rhinovirus", wallet))
	assert_true(army.buy("bacteriophage", wallet))
	assert_true(army.buy("rhinovirus", wallet))

	assert_true(army.deploy("rhinovirus", Vector2i(2, 3)))
	assert_true(army.deploy("bacteriophage", Vector2i(2, 3)))
	assert_true(army.deploy("rhinovirus", Vector2i(5, 5)))

	var at_23: Array[String] = army.deployed_at(Vector2i(2, 3))
	assert_eq(at_23.size(), 2)
	assert_eq(at_23[0], "rhinovirus")
	assert_eq(at_23[1], "bacteriophage")

	var at_55: Array[String] = army.deployed_at(Vector2i(5, 5))
	assert_eq(at_55.size(), 1)
	assert_eq(at_55[0], "rhinovirus")

	var at_empty: Array[String] = army.deployed_at(Vector2i(0, 0))
	assert_eq(at_empty.size(), 0)

func test_army_recall_last_at_lifo() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 200})

	assert_true(army.buy("rhinovirus", wallet))
	assert_true(army.buy("bacteriophage", wallet))
	assert_true(army.buy("staphylococcus", wallet))

	var target_cell := Vector2i(3, 4)
	var other_cell := Vector2i(0, 0)

	assert_true(army.deploy("rhinovirus", target_cell))
	assert_true(army.deploy("staphylococcus", other_cell))
	assert_true(army.deploy("bacteriophage", target_cell))

	# At target_cell: first deployed was rhinovirus, second was bacteriophage
	# recall_last_at should search from back to front and return bacteriophage first
	watch_signals(army)
	var recalled: String = army.recall_last_at(target_cell)
	assert_eq(recalled, "bacteriophage")
	assert_signal_emitted(army, "changed")
	assert_eq(army.reserve_count("bacteriophage"), 1)
	assert_eq(army.deployed_count("bacteriophage"), 0)

	# Second recall at target_cell should return rhinovirus
	recalled = army.recall_last_at(target_cell)
	assert_eq(recalled, "rhinovirus")
	assert_eq(army.reserve_count("rhinovirus"), 1)
	assert_eq(army.deployed_count("rhinovirus"), 0)

	# Third recall at target_cell has none left
	recalled = army.recall_last_at(target_cell)
	assert_eq(recalled, "")

	# other_cell still has staphylococcus
	assert_eq(army.deployed_count("staphylococcus"), 1)
	recalled = army.recall_last_at(other_cell)
	assert_eq(recalled, "staphylococcus")
	assert_eq(army.reserve_count("staphylococcus"), 1)
	assert_eq(army.deployed_count("staphylococcus"), 0)

func test_army_refund_all() -> void:
	var cfg: GameConfig = _load_config()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 200})

	# Buy units totaling 10 + 40 + 100 = 150 ATP
	assert_true(army.buy("rhinovirus", wallet)) # 10
	assert_true(army.buy("bacteriophage", wallet)) # 40
	assert_true(army.buy("staphylococcus", wallet)) # 100
	assert_eq(wallet.get_amount("atp"), 50)

	# Deploy some units
	assert_true(army.deploy("rhinovirus", Vector2i(1, 1)))
	assert_true(army.deploy("staphylococcus", Vector2i(2, 2)))
	# bacteriophage remains in reserve

	assert_eq(army.reserve_count("bacteriophage"), 1)
	assert_eq(army.deployed_count("rhinovirus"), 1)
	assert_eq(army.deployed_count("staphylococcus"), 1)
	assert_eq(army.total_count(), 3)
	assert_eq(army.total_cost(), {"atp": 150})

	watch_signals(army)
	army.refund_all(wallet)

	assert_signal_emitted(army, "changed")
	assert_eq(wallet.get_amount("atp"), 200, "Wallet should be fully refunded to 200 ATP")
	assert_eq(army.total_count(), 0)
	assert_eq(army.reserve.size(), 0)
	assert_eq(army.deployments.size(), 0)
	assert_eq(army.total_cost(), {})

func test_army_session_integration() -> void:
	var cfg: GameConfig = _load_config()
	var session := Session.new(cfg)

	assert_not_null(session.army)
	assert_eq(session.army.total_count(), 0)
	var ok: bool = session.army.buy("rhinovirus", session.wallet)
	assert_true(ok)
	assert_eq(session.army.total_count(), 1)
	assert_eq(session.wallet.get_amount("atp"), 1000 - 10)


func _strain_cfg() -> GameConfig:
	var cfg: GameConfig = _load_config()
	cfg.feature_flags["strains"] = true
	return cfg

func test_strain_default_and_set() -> void:
	var army := Army.new(_strain_cfg())
	assert_eq(army.strain_of("rhinovirus"), "wild")
	assert_true(army.set_strain("rhinovirus", "capsid_hardening"))
	assert_eq(army.strain_of("rhinovirus"), "capsid_hardening")
	assert_true(army.set_strain("rhinovirus", "wild"))
	assert_false(army.strain_by_type.has("rhinovirus"))

func test_set_strain_refused() -> void:
	var cfg: GameConfig = _strain_cfg()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 1000})
	assert_false(army.set_strain("rhinovirus", "nope"))
	assert_false(army.set_strain("nope", "wild"))
	army.buy("rhinovirus", wallet)
	assert_false(army.set_strain("rhinovirus", "capsid_hardening"), "reserve unit blocks change")
	army.deploy("rhinovirus", Vector2i(0, 0))
	assert_false(army.set_strain("rhinovirus", "capsid_hardening"), "deployed unit blocks change")
	assert_true(army.set_strain("bacteriophage", "capsid_hardening"), "other types are unaffected")

func test_strain_unit_cost_buy_refund() -> void:
	var cfg: GameConfig = _strain_cfg()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 1000})
	var def: PathogenDef = cfg.pathogens["rhinovirus"]
	var expected: int = maxi(1, FixedMath.apply_pct(int(def.cost["atp"]), 80))
	army.set_strain("rhinovirus", "rapid_replication")
	assert_eq(army.unit_cost("rhinovirus"), {"atp": expected})
	army.buy("rhinovirus", wallet)
	assert_eq(wallet.get_amount("atp"), 1000 - expected)
	assert_eq(army.total_cost(), {"atp": expected})
	army.refund_all(wallet)
	assert_eq(wallet.get_amount("atp"), 1000)
	assert_eq(army.strain_of("rhinovirus"), "rapid_replication", "refund_all keeps the strain")

func test_strain_deploy_records_strain() -> void:
	var cfg: GameConfig = _strain_cfg()
	var army := Army.new(cfg)
	var wallet := Wallet.new({"atp": 1000})
	army.set_strain("rhinovirus", "antigenic_masking")
	army.buy("rhinovirus", wallet)
	army.deploy("rhinovirus", Vector2i(2, 2))
	assert_eq(army.deployments[0]["strain"], "antigenic_masking")
	army.refund_all(wallet)
	assert_true(army.strain_by_type.has("rhinovirus"))
