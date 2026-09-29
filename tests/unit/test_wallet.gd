extends GutTest

func test_init_default() -> void:
	var wallet: Wallet = Wallet.new()
	assert_eq(wallet.get_amount("atp"), 0)
	assert_eq(wallet.get_amount("dna"), 0)
	assert_true(wallet.to_dict().is_empty())

func test_init_with_values() -> void:
	var wallet: Wallet = Wallet.new({"atp": 1000, "dna": 50})
	assert_eq(wallet.get_amount("atp"), 1000)
	assert_eq(wallet.get_amount("dna"), 50)
	assert_eq(wallet.get_amount("nonexistent"), 0)

func test_init_with_negative_amount_logs_error_and_skips() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "invalid": -25})
	assert_eq(wallet.get_amount("atp"), 100)
	assert_eq(wallet.get_amount("invalid"), 0)
	assert_push_error("negative amount")

func test_can_afford() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "dna": 20})
	assert_true(wallet.can_afford({}))
	assert_true(wallet.can_afford({"atp": 0}))
	assert_true(wallet.can_afford({"atp": 50}))
	assert_true(wallet.can_afford({"atp": 100}))
	assert_false(wallet.can_afford({"atp": 101}))
	assert_true(wallet.can_afford({"atp": 100, "dna": 20}))
	assert_false(wallet.can_afford({"atp": 100, "dna": 21}))
	assert_false(wallet.can_afford({"atp": 101, "dna": 20}))
	assert_false(wallet.can_afford({"missing": 1}))

func test_can_afford_negative_cost() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100})
	assert_false(wallet.can_afford({"atp": -10}))
	assert_push_error("negative amount")
	assert_false(wallet.can_afford({"atp": 50, "dna": -5}))
	assert_push_error("negative amount")

func test_spend_success_and_signal() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "dna": 50})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	var success: bool = wallet.spend({"atp": 40})
	assert_true(success)
	assert_eq(wallet.get_amount("atp"), 60)
	assert_eq(wallet.get_amount("dna"), 50)
	assert_eq(signal_events.size(), 1)
	assert_eq(signal_events[0]["currency"], "atp")
	assert_eq(signal_events[0]["amount"], 60)

func test_spend_multi_currency() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "dna": 50})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	var success: bool = wallet.spend({"atp": 30, "dna": 20})
	assert_true(success)
	assert_eq(wallet.get_amount("atp"), 70)
	assert_eq(wallet.get_amount("dna"), 30)
	assert_eq(signal_events.size(), 2)

	var signal_map: Dictionary = {}
	for ev: Dictionary in signal_events:
		signal_map[str(ev["currency"])] = int(ev["amount"])
	assert_eq(signal_map.get("atp", -1), 70)
	assert_eq(signal_map.get("dna", -1), 30)

func test_spend_zero_amount_does_not_emit_signal() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "dna": 50})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	var success: bool = wallet.spend({"atp": 25, "dna": 0})
	assert_true(success)
	assert_eq(wallet.get_amount("atp"), 75)
	assert_eq(wallet.get_amount("dna"), 50)
	assert_eq(signal_events.size(), 1)
	assert_eq(signal_events[0]["currency"], "atp")
	assert_eq(signal_events[0]["amount"], 75)

func test_spend_atomic_cannot_afford() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "dna": 10})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	# Can afford atp (50 <= 100), but cannot afford dna (20 > 10)
	var success: bool = wallet.spend({"atp": 50, "dna": 20})
	assert_false(success)
	assert_eq(wallet.get_amount("atp"), 100, "atp must remain unchanged")
	assert_eq(wallet.get_amount("dna"), 10, "dna must remain unchanged")
	assert_eq(signal_events.size(), 0, "No changed signal must be emitted on failed spend")

func test_spend_negative_amount_validation() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "dna": 50})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	var success: bool = wallet.spend({"atp": 20, "dna": -10})
	assert_false(success)
	assert_eq(wallet.get_amount("atp"), 100)
	assert_eq(wallet.get_amount("dna"), 50)
	assert_eq(signal_events.size(), 0)
	assert_push_error("negative amount")

func test_refund_success_and_signal() -> void:
	var wallet: Wallet = Wallet.new({"atp": 50})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.refund({"atp": 25})
	assert_eq(wallet.get_amount("atp"), 75)
	assert_eq(signal_events.size(), 1)
	assert_eq(signal_events[0]["currency"], "atp")
	assert_eq(signal_events[0]["amount"], 75)

func test_refund_new_currency() -> void:
	var wallet: Wallet = Wallet.new({"atp": 50})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.refund({"dna": 15})
	assert_eq(wallet.get_amount("atp"), 50)
	assert_eq(wallet.get_amount("dna"), 15)
	assert_eq(signal_events.size(), 1)
	assert_eq(signal_events[0]["currency"], "dna")
	assert_eq(signal_events[0]["amount"], 15)

func test_refund_zero_amount_does_not_emit_signal() -> void:
	var wallet: Wallet = Wallet.new({"atp": 50})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.refund({"atp": 0})
	assert_eq(wallet.get_amount("atp"), 50)
	assert_eq(signal_events.size(), 0)

func test_refund_negative_amount_validation() -> void:
	var wallet: Wallet = Wallet.new({"atp": 50, "dna": 10})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.refund({"atp": 20, "dna": -5})
	assert_eq(wallet.get_amount("atp"), 50, "atp must remain unchanged on negative refund")
	assert_eq(wallet.get_amount("dna"), 10, "dna must remain unchanged on negative refund")
	assert_eq(signal_events.size(), 0)
	assert_push_error("negative amount")

func test_reset() -> void:
	var wallet: Wallet = Wallet.new({"atp": 100, "dna": 20})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.reset({"atp": 1000, "amino": 50})
	assert_eq(wallet.get_amount("atp"), 1000)
	assert_eq(wallet.get_amount("amino"), 50)
	assert_eq(wallet.get_amount("dna"), 0)

	var signal_map: Dictionary = {}
	for ev: Dictionary in signal_events:
		signal_map[str(ev["currency"])] = int(ev["amount"])

	assert_eq(signal_map.get("atp", -1), 1000)
	assert_eq(signal_map.get("amino", -1), 50)
	assert_eq(signal_map.get("dna", -1), 0)

func test_reset_unchanged_currency_does_not_emit() -> void:
	var wallet: Wallet = Wallet.new({"atp": 500, "dna": 10})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.reset({"atp": 500, "dna": 30})
	assert_eq(wallet.get_amount("atp"), 500)
	assert_eq(wallet.get_amount("dna"), 30)
	assert_eq(signal_events.size(), 1)
	assert_eq(signal_events[0]["currency"], "dna")
	assert_eq(signal_events[0]["amount"], 30)

func test_reset_negative_validation() -> void:
	var wallet: Wallet = Wallet.new({"atp": 500})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.reset({"atp": 100, "bad": -10})
	assert_eq(wallet.get_amount("atp"), 500, "wallet must not change when reset has negative value")
	assert_eq(signal_events.size(), 0)
	assert_push_error("negative amount")

func test_reset_default_clears_all() -> void:
	var wallet: Wallet = Wallet.new({"atp": 500, "dna": 20})
	var signal_events: Array[Dictionary] = []
	wallet.changed.connect(func(currency: String, new_amount: int) -> void:
		signal_events.append({"currency": currency, "amount": new_amount})
	)

	wallet.reset()
	assert_eq(wallet.get_amount("atp"), 0)
	assert_eq(wallet.get_amount("dna"), 0)
	assert_true(wallet.to_dict().is_empty())
	assert_eq(signal_events.size(), 2)

func test_to_dict_deep_copy() -> void:
	var wallet: Wallet = Wallet.new({"atp": 1000, "dna": 50})
	var d: Dictionary = wallet.to_dict()
	assert_eq(d.get("atp", 0), 1000)
	assert_eq(d.get("dna", 0), 50)

	# Mutate the returned dictionary
	d["atp"] = 0
	d["dna"] = 9999
	d["new_key"] = 123

	# Verify wallet internal balances are unaffected
	assert_eq(wallet.get_amount("atp"), 1000)
	assert_eq(wallet.get_amount("dna"), 50)
	assert_eq(wallet.get_amount("new_key"), 0)

func test_sum_costs() -> void:
	var empty_result: Dictionary = Wallet.sum_costs([])
	assert_true(empty_result.is_empty())

	var costs: Array = [
		{"atp": 10},
		{"atp": 25, "dna": 5},
		{"atp": 15, "amino": 20},
		"not_a_dict_skipped"
	]
	var total: Dictionary = Wallet.sum_costs(costs)
	assert_eq(total.get("atp", 0), 50)
	assert_eq(total.get("dna", 0), 5)
	assert_eq(total.get("amino", 0), 20)

func test_session_integration() -> void:
	var res: ConfigLoadResult = GameConfig.load_from_dir("res://data")
	assert_true(res.is_ok())
	var config: GameConfig = res.config

	var session: Session = Session.new(config)
	assert_not_null(session.wallet)
	assert_eq(session.wallet.get_amount("atp"), 1000)

	var spent: bool = session.wallet.spend({"atp": 250})
	assert_true(spent)
	assert_eq(session.wallet.get_amount("atp"), 750)

	var null_session: Session = Session.new(null)
	assert_null(null_session.wallet)
