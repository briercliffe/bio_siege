extends GutTest

var cfg: GameConfig
var link_mt: int
var break_mt: int


func before_each() -> void:
	cfg = GameConfig.load_from_dir("res://data").config
	var d: PathogenDef = cfg.pathogens["staphylococcus"]
	link_mt = d.biofilm_link_mt
	break_mt = d.biofilm_break_mt


func _unit(id: int, type_id: String, pos_mt: Vector2i) -> PathogenState:
	var p: PathogenState = PathogenState.create(id, type_id, cfg.pathogens[type_id], Vector2i.ZERO)
	p.pos = pos_mt
	return p


func _staph(id: int, x_mt: int, y_mt: int = 5000) -> PathogenState:
	return _unit(id, "staphylococcus", Vector2i(x_mt, y_mt))


func _list(units: Array[PathogenState]) -> Array[PathogenState]:
	return units


func test_row_forms_one_group() -> void:
	var tile: int = 1000 * cfg.grid_scale
	var a: PathogenState = _staph(1, 5000)
	var b: PathogenState = _staph(2, 5000 + tile)
	var c: PathogenState = _staph(3, 5000 + 2 * tile)
	var far: PathogenState = _staph(4, 5000 + 7 * tile)
	var bf := Biofilm.new()
	assert_true(bf.regroup(_list([a, b, c, far])))
	assert_eq(bf.groups.size(), 1)
	assert_eq(bf.groups[1], [1, 2, 3])
	assert_eq(bf.group_of[3], 1)
	assert_false(bf.group_of.has(4))
	assert_eq(bf.members(4), [4])
	assert_eq(bf.members(2), [1, 2, 3])


func test_other_type_never_links() -> void:
	var s: PathogenState = _staph(1, 5000)
	var r: PathogenState = _unit(2, "rhinovirus", Vector2i(5000, 5000))
	var bf := Biofilm.new()
	bf.regroup(_list([s, r]))
	assert_true(bf.group_of.is_empty())


func test_dead_units_ignored() -> void:
	var a: PathogenState = _staph(1, 5000)
	var b: PathogenState = _staph(2, 5100)
	b.alive = false
	var bf := Biofilm.new()
	bf.regroup(_list([a, b]))
	assert_true(bf.group_of.is_empty())


func test_hysteresis() -> void:
	var a: PathogenState = _staph(1, 5000)
	var b: PathogenState = _staph(2, 5000 + link_mt - 100)
	var bf := Biofilm.new()
	bf.regroup(_list([a, b]))
	assert_true(bf.group_of.has(1))
	b.pos = Vector2i(5000 + break_mt - 100, 5000)
	assert_false(bf.regroup(_list([a, b])))
	assert_true(bf.group_of.has(2))
	b.pos = Vector2i(5000 + break_mt + 100, 5000)
	assert_true(bf.regroup(_list([a, b])))
	assert_true(bf.group_of.is_empty())

	var fresh := Biofilm.new()
	b.pos = Vector2i(5000 + break_mt - 100, 5000)
	fresh.regroup(_list([a, b]))
	assert_true(fresh.group_of.is_empty())


func test_regroup_returns_false_when_unchanged() -> void:
	var a: PathogenState = _staph(1, 5000)
	var b: PathogenState = _staph(2, 5500)
	var bf := Biofilm.new()
	assert_true(bf.regroup(_list([a, b])))
	assert_false(bf.regroup(_list([a, b])))
	var empty := Biofilm.new()
	assert_false(empty.regroup(_list([a])))


func test_remove_dissolves_pair() -> void:
	var a: PathogenState = _staph(1, 5000)
	var b: PathogenState = _staph(2, 5500)
	var bf := Biofilm.new()
	bf.regroup(_list([a, b]))
	bf.remove(1)
	assert_true(bf.group_of.is_empty())
	assert_true(bf.groups.is_empty())
	assert_eq(bf.members(2), [2])


func test_remove_root_reroots_larger_group() -> void:
	var bf := Biofilm.new()
	bf.regroup(_list([_staph(1, 5000), _staph(2, 5500), _staph(3, 6000)]))
	bf.remove(1)
	assert_eq(bf.groups.size(), 1)
	assert_eq(bf.groups[2], [2, 3])
	assert_eq(bf.group_of[3], 2)
