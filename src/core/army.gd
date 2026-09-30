class_name Army
extends RefCounted

signal changed

var reserve: Dictionary = {} # pathogen id -> int count
var deployments: Array[Dictionary] = [] # [{"type": String, "cell": Vector2i, "strain": String}] in deploy order
var strain_by_type: Dictionary = {} # type_id -> variant_id (missing = "wild")

var _config: GameConfig = null

func _init(p_config: GameConfig = null) -> void:
	_config = p_config

func set_config(p_config: GameConfig) -> void:
	_config = p_config

func remove_unknown_types() -> int:
	var removed: int = 0
	if _config == null:
		return removed
	for t: Variant in reserve.keys():
		if not _config.pathogens.has(str(t)):
			removed += int(reserve[t])
			reserve.erase(t)
	for i in range(deployments.size() - 1, -1, -1):
		if not _config.pathogens.has(str(deployments[i].get("type", ""))):
			deployments.remove_at(i)
			removed += 1
	for t: Variant in strain_by_type.keys():
		var p_def: PathogenDef = _config.pathogens.get(str(t))
		if p_def == null or p_def.strain(str(strain_by_type[t])) == null:
			strain_by_type.erase(t)
			removed += 1
	if removed > 0:
		changed.emit()
	return removed

func strain_of(type_id: String) -> String:
	return str(strain_by_type.get(type_id, "wild"))

func set_strain(type_id: String, variant_id: String) -> bool:
	if _config == null:
		return false
	var p_def: PathogenDef = _config.pathogens.get(type_id)
	if p_def == null or p_def.strain(variant_id) == null:
		return false
	if reserve_count(type_id) + deployed_count(type_id) > 0:
		return false
	if variant_id == "wild":
		strain_by_type.erase(type_id)
	else:
		strain_by_type[type_id] = variant_id
	changed.emit()
	return true

## Per-unit cost of a type under the army's current strain for it.
func unit_cost(type_id: String) -> Dictionary:
	var result: Dictionary = {}
	if _config == null:
		return result
	var p_def: PathogenDef = _config.pathogens.get(type_id)
	if p_def == null:
		return result
	var strain: StrainDef = p_def.strain(strain_of(type_id))
	if strain == null:
		strain = StrainDef.wild()
	for cur: Variant in p_def.cost.keys():
		var amt: int = int(p_def.cost[cur])
		if amt > 0:
			amt = maxi(1, FixedMath.apply_pct(amt, strain.cost_pct))
		result[str(cur)] = amt
	return result

func buy(type_id: String, wallet: Wallet) -> bool:
	if _config == null or wallet == null:
		return false
	var p_def: PathogenDef = _config.pathogens.get(type_id)
	if p_def == null:
		return false
	if not wallet.spend(unit_cost(type_id)):
		return false

	reserve[type_id] = int(reserve.get(type_id, 0)) + 1
	changed.emit()
	return true

func unbuy(type_id: String, wallet: Wallet) -> bool:
	var current: int = int(reserve.get(type_id, 0))
	if current <= 0:
		return false

	if _config != null and wallet != null:
		var p_def: PathogenDef = _config.pathogens.get(type_id)
		if p_def != null:
			wallet.refund(unit_cost(type_id))

	if current == 1:
		reserve.erase(type_id)
	else:
		reserve[type_id] = current - 1

	changed.emit()
	return true

func deploy(type_id: String, cell: Vector2i) -> bool:
	var current: int = int(reserve.get(type_id, 0))
	if current <= 0:
		return false

	if current == 1:
		reserve.erase(type_id)
	else:
		reserve[type_id] = current - 1

	deployments.append({"type": type_id, "cell": cell, "strain": strain_of(type_id)})
	changed.emit()
	return true

func recall_last_at(cell: Vector2i) -> String:
	for i in range(deployments.size() - 1, -1, -1):
		var dep: Dictionary = deployments[i]
		if dep.get("cell") == cell:
			var t: String = str(dep.get("type", ""))
			deployments.remove_at(i)
			reserve[t] = int(reserve.get(t, 0)) + 1
			changed.emit()
			return t
	return ""

func refund_all(wallet: Wallet) -> void:
	if wallet != null:
		var costs: Dictionary = total_cost()
		if not costs.is_empty():
			wallet.refund(costs)
	reserve.clear()
	deployments.clear()
	changed.emit()

func reserve_count(type_id: String) -> int:
	return int(reserve.get(type_id, 0))

func deployed_count(type_id: String) -> int:
	var count: int = 0
	for dep: Dictionary in deployments:
		if str(dep.get("type", "")) == type_id:
			count += 1
	return count

func total_count() -> int:
	var total: int = 0
	for c: Variant in reserve.values():
		total += int(c)
	total += deployments.size()
	return total

func total_cost() -> Dictionary:
	var total: Dictionary = {}
	if _config == null:
		return total

	var type_counts: Dictionary = {}
	for t: Variant in reserve.keys():
		var tid: String = str(t)
		type_counts[tid] = int(type_counts.get(tid, 0)) + int(reserve[t])
	for dep: Dictionary in deployments:
		var tid: String = str(dep.get("type", ""))
		type_counts[tid] = int(type_counts.get(tid, 0)) + 1

	for tid: String in type_counts.keys():
		var p_def: PathogenDef = _config.pathogens.get(tid)
		if p_def == null:
			continue
		var count: int = int(type_counts[tid])
		var unit: Dictionary = unit_cost(tid)
		for cur: Variant in unit.keys():
			var currency: String = str(cur)
			var amt: int = int(unit[cur]) * count
			total[currency] = int(total.get(currency, 0)) + amt

	return total

func deployed_at(cell: Vector2i) -> Array[String]:
	var result: Array[String] = []
	for dep: Dictionary in deployments:
		if dep.get("cell") == cell:
			result.append(str(dep.get("type", "")))
	return result
