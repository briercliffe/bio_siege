class_name Wallet
extends RefCounted

signal changed(currency: String, new_amount: int)

var _balances: Dictionary = {}

func _init(initial: Dictionary = {}) -> void:
	for cur: Variant in initial.keys():
		var currency_name: String = str(cur)
		var amount: int = int(initial[cur])
		if amount < 0:
			push_error("Wallet._init: negative amount for currency '%s': %d" % [currency_name, amount])
			continue
		_balances[currency_name] = amount

func get_amount(currency: String) -> int:
	return int(_balances.get(currency, 0))

func can_afford(cost: Dictionary) -> bool:
	for cur: Variant in cost.keys():
		var currency_name: String = str(cur)
		var amount: int = int(cost[cur])
		if amount < 0:
			push_error("Wallet.can_afford: negative amount for currency '%s': %d" % [currency_name, amount])
			return false
		if get_amount(currency_name) < amount:
			return false
	return true

func spend(cost: Dictionary) -> bool:
	for cur: Variant in cost.keys():
		var currency_name: String = str(cur)
		var amount: int = int(cost[cur])
		if amount < 0:
			push_error("Wallet.spend: negative amount for currency '%s': %d" % [currency_name, amount])
			return false

	for cur: Variant in cost.keys():
		var currency_name: String = str(cur)
		var amount: int = int(cost[cur])
		if get_amount(currency_name) < amount:
			return false

	var changed_currencies: Dictionary = {}
	for cur: Variant in cost.keys():
		var currency_name: String = str(cur)
		var amount: int = int(cost[cur])
		if amount > 0:
			var current: int = get_amount(currency_name)
			var new_amt: int = current - amount
			_balances[currency_name] = new_amt
			changed_currencies[currency_name] = new_amt

	for cur: Variant in changed_currencies.keys():
		var currency_name: String = str(cur)
		changed.emit(currency_name, int(changed_currencies[currency_name]))

	return true

func refund(cost: Dictionary) -> void:
	for cur: Variant in cost.keys():
		var currency_name: String = str(cur)
		var amount: int = int(cost[cur])
		if amount < 0:
			push_error("Wallet.refund: negative amount for currency '%s': %d" % [currency_name, amount])
			return

	var changed_currencies: Dictionary = {}
	for cur: Variant in cost.keys():
		var currency_name: String = str(cur)
		var amount: int = int(cost[cur])
		if amount > 0:
			var current: int = get_amount(currency_name)
			var new_amt: int = current + amount
			_balances[currency_name] = new_amt
			changed_currencies[currency_name] = new_amt

	for cur: Variant in changed_currencies.keys():
		var currency_name: String = str(cur)
		changed.emit(currency_name, int(changed_currencies[currency_name]))

func reset(initial: Dictionary = {}) -> void:
	for cur: Variant in initial.keys():
		var currency_name: String = str(cur)
		var amount: int = int(initial[cur])
		if amount < 0:
			push_error("Wallet.reset: negative amount for currency '%s': %d" % [currency_name, amount])
			return

	var all_keys: Dictionary = {}
	for k: Variant in _balances.keys():
		all_keys[str(k)] = true
	for k: Variant in initial.keys():
		all_keys[str(k)] = true

	var old_balances: Dictionary = _balances.duplicate()
	_balances.clear()
	for cur: Variant in initial.keys():
		_balances[str(cur)] = int(initial[cur])

	for k: Variant in all_keys.keys():
		var currency_name: String = str(k)
		var old_amt: int = int(old_balances.get(currency_name, 0))
		var new_amt: int = get_amount(currency_name)
		if old_amt != new_amt:
			changed.emit(currency_name, new_amt)

func to_dict() -> Dictionary:
	return _balances.duplicate(true)

static func sum_costs(costs: Array) -> Dictionary:
	var total: Dictionary = {}
	for item: Variant in costs:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var cost_dict: Dictionary = item
		for cur: Variant in cost_dict.keys():
			var currency_name: String = str(cur)
			var amount: int = int(cost_dict[cur])
			total[currency_name] = int(total.get(currency_name, 0)) + amount
	return total
