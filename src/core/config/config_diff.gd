class_name ConfigDiff
extends RefCounted

## Counts how many leaf values differ between two parsed JSON trees.
## Dictionary keys starting with "_" are comments and never count.
## A leaf is any value that is not a non-empty Dictionary or Array.
## Added or removed entries count as one change per leaf they contain.

static func count_changed_leaves(old_value: Variant, new_value: Variant) -> int:
	if typeof(old_value) == TYPE_DICTIONARY and typeof(new_value) == TYPE_DICTIONARY:
		return _diff_dicts(old_value, new_value)
	if typeof(old_value) == TYPE_ARRAY and typeof(new_value) == TYPE_ARRAY:
		return _diff_arrays(old_value, new_value)
	if _leaf_equal(old_value, new_value):
		return 0
	return 1


static func count_leaves(value: Variant) -> int:
	if typeof(value) == TYPE_DICTIONARY:
		var total: int = 0
		var dict: Dictionary = value
		for k: Variant in dict.keys():
			if _is_comment_key(k):
				continue
			total += count_leaves(dict[k])
		return maxi(total, 1)
	if typeof(value) == TYPE_ARRAY:
		var total: int = 0
		for item: Variant in value:
			total += count_leaves(item)
		return maxi(total, 1)
	return 1


static func _diff_dicts(old_dict: Dictionary, new_dict: Dictionary) -> int:
	var total: int = 0
	for k: Variant in old_dict.keys():
		if _is_comment_key(k):
			continue
		if new_dict.has(k):
			total += count_changed_leaves(old_dict[k], new_dict[k])
		else:
			total += count_leaves(old_dict[k])
	for k: Variant in new_dict.keys():
		if _is_comment_key(k):
			continue
		if not old_dict.has(k):
			total += count_leaves(new_dict[k])
	return total


static func _diff_arrays(old_arr: Array, new_arr: Array) -> int:
	var total: int = 0
	var common: int = mini(old_arr.size(), new_arr.size())
	for i in range(common):
		total += count_changed_leaves(old_arr[i], new_arr[i])
	for i in range(common, old_arr.size()):
		total += count_leaves(old_arr[i])
	for i in range(common, new_arr.size()):
		total += count_leaves(new_arr[i])
	return total


static func _is_comment_key(key: Variant) -> bool:
	return typeof(key) == TYPE_STRING and str(key).begins_with("_")


static func _leaf_equal(a: Variant, b: Variant) -> bool:
	var a_num: bool = typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num: bool = typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b
