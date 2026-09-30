class_name GameConfig
extends RefCounted

const KNOWN_TAGS: Array[String] = [
	"core", "wall", "defense", "resource", "virus", "bacteria", "small", "hidden"
]
const KNOWN_CURRENCIES: Array[String] = [
	"atp"
]
const KNOWN_SHAPES: Array[String] = [
	"square", "rounded_square", "circle", "triangle", "diamond", "lander", "cluster"
]

var grid_width: int = 0
var grid_height: int = 0
var deploy_ring: int = 0
var tile_px: int = 0
var grid_scale: int = 1
var tick_rate: int = 20
var battle_timeout_ticks: int = 0
var max_path_recalcs_per_tick: int = 0
var empty_path_weight: float = 1.0
var deploy_hold_interval_s: float = 0.1
var start_wallet: Dictionary = {}
var default_seed: int = 0
var feature_flags: Dictionary = {}
var structures: Dictionary = {} # String -> StructureDef
var pathogens: Dictionary = {} # String -> PathogenDef
var content_hash: String = ""
var source_data: Dictionary = {} # "game_rules" / "structures" / "pathogens" -> parsed JSON root

func structure_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in structures.keys():
		ids.append(str(k))
	ids.sort()
	return ids

func pathogen_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in pathogens.keys():
		ids.append(str(k))
	ids.sort()
	return ids

func buildable_structure_ids() -> Array[String]:
	var buildable: Array[StructureDef] = []
	for s: StructureDef in structures.values():
		if s.buildable:
			buildable.append(s)
	buildable.sort_custom(func(a: StructureDef, b: StructureDef) -> bool:
		var cost_a: int = int(a.cost.get("atp", 0))
		var cost_b: int = int(b.cost.get("atp", 0))
		if cost_a != cost_b:
			return cost_a < cost_b
		return a.id < b.id
	)
	var result: Array[String] = []
	for s: StructureDef in buildable:
		result.append(s.id)
	return result

func core_structure_id() -> String:
	for s: StructureDef in structures.values():
		if s.has_tag("core"):
			return s.id
	return ""

## True when the named feature flag is set in data/game_rules.json (missing = false).
func flag(flag_name: String) -> bool:
	return bool(feature_flags.get(flag_name, false))

func move_nucleus_enabled() -> bool:
	return bool(feature_flags.get("move_nucleus", false))

static func load_from_dir(dir_path: String) -> ConfigLoadResult:
	var result := ConfigLoadResult.new()
	var base: String = dir_path
	if not base.ends_with("/"):
		base += "/"

	var rules_path: String = base + "game_rules.json"
	var structures_path: String = base + "structures.json"
	var pathogens_path: String = base + "pathogens.json"

	var rules_str: String = ""
	var structures_str: String = ""
	var pathogens_str: String = ""
	var file_errors: PackedStringArray = PackedStringArray()

	if not FileAccess.file_exists(rules_path):
		file_errors.append("game_rules.json: file not found (got %s)" % [rules_path])
	else:
		var f: FileAccess = FileAccess.open(rules_path, FileAccess.READ)
		if f == null:
			file_errors.append("game_rules.json: failed to open file (got %s)" % [rules_path])
		else:
			rules_str = f.get_as_text()

	if not FileAccess.file_exists(structures_path):
		file_errors.append("structures.json: file not found (got %s)" % [structures_path])
	else:
		var f: FileAccess = FileAccess.open(structures_path, FileAccess.READ)
		if f == null:
			file_errors.append("structures.json: failed to open file (got %s)" % [structures_path])
		else:
			structures_str = f.get_as_text()

	if not FileAccess.file_exists(pathogens_path):
		file_errors.append("pathogens.json: file not found (got %s)" % [pathogens_path])
	else:
		var f: FileAccess = FileAccess.open(pathogens_path, FileAccess.READ)
		if f == null:
			file_errors.append("pathogens.json: failed to open file (got %s)" % [pathogens_path])
		else:
			pathogens_str = f.get_as_text()

	if not file_errors.is_empty():
		result.errors = file_errors
		return result

	return load_from_strings(rules_str, structures_str, pathogens_str)

static func load_from_strings(rules_str: String, structures_str: String, pathogens_str: String) -> ConfigLoadResult:
	var result := ConfigLoadResult.new()
	var errors: PackedStringArray = PackedStringArray()

	var json_rules := JSON.new()
	var err_rules: Error = json_rules.parse(rules_str)
	if err_rules != OK:
		errors.append("game_rules.json: JSON parse error at line %d: %s" % [json_rules.get_error_line(), json_rules.get_error_message()])

	var json_structures := JSON.new()
	var err_structures: Error = json_structures.parse(structures_str)
	if err_structures != OK:
		errors.append("structures.json: JSON parse error at line %d: %s" % [json_structures.get_error_line(), json_structures.get_error_message()])

	var json_pathogens := JSON.new()
	var err_pathogens: Error = json_pathogens.parse(pathogens_str)
	if err_pathogens != OK:
		errors.append("pathogens.json: JSON parse error at line %d: %s" % [json_pathogens.get_error_line(), json_pathogens.get_error_message()])

	var rules_data: Dictionary = {}
	if err_rules == OK:
		if typeof(json_rules.data) != TYPE_DICTIONARY:
			errors.append("game_rules.json: root: must be a JSON object (got %s)" % [_format_val(json_rules.data)])
		else:
			rules_data = json_rules.data
			_validate_rules(rules_data, errors)

	var structures_data: Dictionary = {}
	if err_structures == OK:
		if typeof(json_structures.data) != TYPE_DICTIONARY:
			errors.append("structures.json: root: must be a JSON object (got %s)" % [_format_val(json_structures.data)])
		else:
			structures_data = json_structures.data
			_validate_structures(structures_data, errors)

	var pathogens_data: Dictionary = {}
	if err_pathogens == OK:
		if typeof(json_pathogens.data) != TYPE_DICTIONARY:
			errors.append("pathogens.json: root: must be a JSON object (got %s)" % [_format_val(json_pathogens.data)])
		else:
			pathogens_data = json_pathogens.data
			_validate_pathogens(pathogens_data, errors)

	if not errors.is_empty():
		result.errors = errors
		return result

	var config := GameConfig.new()
	config.content_hash = (rules_str + structures_str + pathogens_str).sha256_text()
	config.source_data = {
		"game_rules": rules_data,
		"structures": structures_data,
		"pathogens": pathogens_data,
	}

	var grid_dict: Dictionary = rules_data.get("grid", {})
	config.grid_width = int(grid_dict.get("width", 20))
	config.grid_height = int(grid_dict.get("height", 20))
	config.deploy_ring = int(grid_dict.get("deploy_ring", 1))
	config.tile_px = int(grid_dict.get("tile_px", 32))

	config.grid_scale = int(rules_data.get("grid_scale", 1))
	config.tick_rate = int(rules_data.get("tick_rate", 20))
	config.battle_timeout_ticks = int(roundi(float(rules_data.get("battle_timeout_s", 180)) * float(config.tick_rate)))
	config.max_path_recalcs_per_tick = int(rules_data.get("max_path_recalcs_per_tick", 20))
	config.empty_path_weight = float(rules_data.get("empty_path_weight", 1.0))
	config.deploy_hold_interval_s = float(rules_data.get("deploy_hold_interval_s", 0.1))

	config.start_wallet = {}
	var sw_raw: Dictionary = rules_data.get("start_wallet", {})
	for cur_var: Variant in sw_raw.keys():
		config.start_wallet[str(cur_var)] = int(sw_raw[cur_var])

	config.default_seed = int(rules_data.get("default_seed", 0))
	config.feature_flags = (rules_data.get("feature_flags", {}) as Dictionary).duplicate(true)

	for id_variant: Variant in structures_data.keys():
		var id: String = str(id_variant)
		if id.begins_with("_"):
			continue
		var s_data: Dictionary = structures_data[id]
		var s := StructureDef.new()
		s.id = id
		s.display_name = str(s_data.get("display_name", ""))
		s.role = str(s_data.get("role", ""))

		s.cost = {}
		var cost_raw: Dictionary = s_data.get("cost", {})
		for cur_var: Variant in cost_raw.keys():
			s.cost[str(cur_var)] = int(cost_raw[cur_var])

		s.hp = int(s_data.get("hp", 0))
		var fp_arr: Array = s_data.get("footprint", [1, 1])
		s.footprint = Vector2i(int(fp_arr[0]), int(fp_arr[1]))
		s.buildable = bool(s_data.get("buildable", false))
		s.is_targetable = bool(s_data.get("is_targetable", true))
		s.visible_to_attacker = bool(s_data.get("visible_to_attacker", true))
		s.path_weight = float(s_data.get("path_weight", 1.0))

		s.tags = PackedStringArray()
		for t: Variant in s_data.get("tags", []):
			s.tags.append(str(t))

		s.levels = (s_data.get("levels", []) as Array).duplicate(true)

		var ph_data: Dictionary = s_data.get("placeholder", {})
		s.placeholder_shape = str(ph_data.get("shape", ""))
		s.placeholder_color = Color.from_string(str(ph_data.get("color", "#ffffff")), Color.WHITE)

		var mults_data: Dictionary = s_data.get("damage_multipliers", {})
		s.damage_multipliers_pct = {}
		for mk: Variant in mults_data.keys():
			s.damage_multipliers_pct[str(mk)] = roundi(float(mults_data[mk]) * 100.0)

		var atk_val: Variant = s_data.get("attack", null)
		if atk_val == null:
			s.has_attack = false
			s.attack_damage = 0
			s.attack_interval_ticks = 0
			s.attack_range_mt = 0
			s.splash_radius_mt = 0
			s.projectile_speed_mt_per_tick = 0
		else:
			var atk: Dictionary = atk_val
			s.has_attack = true
			s.attack_damage = int(atk.get("damage", 0))
			s.attack_interval_ticks = maxi(1, roundi(float(atk.get("interval_s", 1.0)) * float(config.tick_rate)))
			s.attack_range_mt = roundi(float(atk.get("range_tiles", 0.0)) * float(config.grid_scale) * 1000.0)
			s.splash_radius_mt = roundi(float(atk.get("splash_radius_tiles", 0.0)) * float(config.grid_scale) * 1000.0)
			s.projectile_speed_mt_per_tick = roundi(float(atk.get("projectile_speed_tiles_s", 0.0)) * float(config.grid_scale) * 1000.0 / float(config.tick_rate))

		var an_cfg: Variant = s_data.get("analysis", null)
		if an_cfg is Dictionary:
			var an: Dictionary = an_cfg
			s.has_analysis = true
			s.analysis_threshold_ticks = maxi(1, roundi(float(an.get("exposure_s", 1.0)) * float(config.tick_rate)))
			s.analysis_multiplier_pct = roundi(float(an.get("damage_multiplier", 1.0)) * 100.0)

		config.structures[id] = s

	for id_variant: Variant in pathogens_data.keys():
		var id: String = str(id_variant)
		if id.begins_with("_"):
			continue
		var p_data: Dictionary = pathogens_data[id]
		var p := PathogenDef.new()
		p.id = id
		p.display_name = str(p_data.get("display_name", ""))
		p.role = str(p_data.get("role", ""))

		p.cost = {}
		var p_cost_raw: Dictionary = p_data.get("cost", {})
		for cur_var: Variant in p_cost_raw.keys():
			p.cost[str(cur_var)] = int(p_cost_raw[cur_var])

		p.hp = int(p_data.get("hp", 0))
		p.speed_mt_per_tick = roundi(float(p_data.get("speed_tiles_s", 0.0)) * float(config.grid_scale) * 1000.0 / float(config.tick_rate))

		p.tags = PackedStringArray()
		for t: Variant in p_data.get("tags", []):
			p.tags.append(str(t))

		var tgt_data: Dictionary = p_data.get("targeting", {})
		p.priority_tags = PackedStringArray()
		for pt: Variant in tgt_data.get("priority_tags", []):
			p.priority_tags.append(str(pt))
		p.targeting_fallback = str(tgt_data.get("fallback", "nearest"))

		p.levels = (p_data.get("levels", []) as Array).duplicate(true)

		var ph_data: Dictionary = p_data.get("placeholder", {})
		p.placeholder_shape = str(ph_data.get("shape", ""))
		p.placeholder_color = Color.from_string(str(ph_data.get("color", "#ffffff")), Color.WHITE)

		var mults_data: Dictionary = p_data.get("damage_multipliers", {})
		p.damage_multipliers_pct = {}
		for mk: Variant in mults_data.keys():
			p.damage_multipliers_pct[str(mk)] = roundi(float(mults_data[mk]) * 100.0)

		var atk: Dictionary = p_data.get("attack", {})
		p.attack_damage = int(atk.get("damage", 0))
		p.attack_interval_ticks = maxi(1, roundi(float(atk.get("interval_s", 1.0)) * float(config.tick_rate)))
		p.attack_range_mt = roundi(float(atk.get("range_tiles", 0.0)) * float(config.grid_scale) * 1000.0)

		var bf_cfg: Variant = p_data.get("biofilm", null)
		if bf_cfg is Dictionary:
			var bf: Dictionary = bf_cfg
			p.has_biofilm = true
			p.biofilm_link_mt = roundi(float(bf.get("link_radius_tiles", 0.0)) * float(config.grid_scale) * 1000.0)
			p.biofilm_break_mt = roundi(float(bf.get("break_radius_tiles", 0.0)) * float(config.grid_scale) * 1000.0)
			p.biofilm_damage_taken_pct = roundi(float(bf.get("damage_taken_multiplier", 1.0)) * 100.0)
			p.biofilm_regroup_ticks = maxi(1, roundi(float(bf.get("regroup_interval_s", 1.0)) * float(config.tick_rate)))

		var hj_cfg: Variant = p_data.get("hijack", null)
		if hj_cfg is Dictionary:
			var hj: Dictionary = hj_cfg
			p.has_hijack = true
			p.hijack_channel_ticks = maxi(1, roundi(float(hj.get("channel_s", 1.0)) * float(config.tick_rate)))
			p.hijack_disable_ticks = maxi(1, roundi(float(hj.get("disable_s", 1.0)) * float(config.tick_rate)))
			p.hijack_target_tags = PackedStringArray()
			for t_var: Variant in hj.get("target_tags", []):
				p.hijack_target_tags.append(str(t_var))

		var st_cfg: Variant = p_data.get("strains", null)
		if st_cfg is Array:
			for st_var: Variant in st_cfg:
				var st_d: Dictionary = st_var
				var sd := StrainDef.new()
				sd.id = str(st_d.get("id", ""))
				sd.display_name = str(st_d.get("display_name", ""))
				var mods: Dictionary = st_d.get("modifiers", {})
				sd.hp_pct = roundi(float(mods.get("hp", 1.0)) * 100.0)
				sd.speed_pct = roundi(float(mods.get("speed", 1.0)) * 100.0)
				sd.damage_pct = roundi(float(mods.get("damage", 1.0)) * 100.0)
				sd.cost_pct = roundi(float(mods.get("cost", 1.0)) * 100.0)
				sd.analysis_rate_pct = roundi(float(mods.get("analysis_rate", 1.0)) * 100.0)
				p.strains.append(sd)

		config.pathogens[id] = p

	result.config = config
	return result

static func _validate_biofilm(id: String, bf_val: Variant, errors: PackedStringArray) -> void:
	if typeof(bf_val) != TYPE_DICTIONARY:
		errors.append("pathogens.json: %s.biofilm: must be a JSON object (got %s)" % [id, _format_val(bf_val)])
		return
	var bf: Dictionary = bf_val
	var bf_keys: Array[String] = ["link_radius_tiles", "break_radius_tiles", "damage_taken_multiplier", "regroup_interval_s"]
	for bk_var: Variant in bf.keys():
		var bk: String = str(bk_var)
		if not bf_keys.has(bk):
			errors.append("pathogens.json: %s.biofilm.%s: unknown key (got %s)" % [id, bk, bk])
	var numeric_ok: bool = true
	for req_bk: String in bf_keys:
		if not bf.has(req_bk):
			errors.append("pathogens.json: %s.biofilm.%s: missing required field (got null)" % [id, req_bk])
			numeric_ok = false
		elif not _is_number(bf[req_bk]):
			errors.append("pathogens.json: %s.biofilm.%s: must be a number (got %s)" % [id, req_bk, _format_val(bf[req_bk])])
			numeric_ok = false
	if not numeric_ok:
		return
	var link_r: float = float(bf["link_radius_tiles"])
	var break_r: float = float(bf["break_radius_tiles"])
	var mult: float = float(bf["damage_taken_multiplier"])
	if link_r <= 0.0:
		errors.append("pathogens.json: %s.biofilm.link_radius_tiles: must be > 0 (got %s)" % [id, _format_val(bf["link_radius_tiles"])])
	if break_r < link_r:
		errors.append("pathogens.json: %s.biofilm.break_radius_tiles: must be >= link_radius_tiles (got %s)" % [id, _format_val(bf["break_radius_tiles"])])
	if mult <= 0.0 or mult > 1.0:
		errors.append("pathogens.json: %s.biofilm.damage_taken_multiplier: must be > 0 and <= 1 (got %s)" % [id, _format_val(bf["damage_taken_multiplier"])])
	if float(bf["regroup_interval_s"]) <= 0.0:
		errors.append("pathogens.json: %s.biofilm.regroup_interval_s: must be > 0 (got %s)" % [id, _format_val(bf["regroup_interval_s"])])

static func _validate_hijack(id: String, hj_val: Variant, errors: PackedStringArray) -> void:
	if typeof(hj_val) != TYPE_DICTIONARY:
		errors.append("pathogens.json: %s.hijack: must be a JSON object (got %s)" % [id, _format_val(hj_val)])
		return
	var hj: Dictionary = hj_val
	var hj_keys: Array[String] = ["channel_s", "disable_s", "target_tags"]
	for hk_var: Variant in hj.keys():
		var hk: String = str(hk_var)
		if not hj_keys.has(hk):
			errors.append("pathogens.json: %s.hijack.%s: unknown key (got %s)" % [id, hk, hk])
	for num_key: String in ["channel_s", "disable_s"]:
		if not hj.has(num_key):
			errors.append("pathogens.json: %s.hijack.%s: missing required field (got null)" % [id, num_key])
		elif not _is_number(hj[num_key]):
			errors.append("pathogens.json: %s.hijack.%s: must be a number (got %s)" % [id, num_key, _format_val(hj[num_key])])
		elif float(hj[num_key]) <= 0.0:
			errors.append("pathogens.json: %s.hijack.%s: must be > 0 (got %s)" % [id, num_key, _format_val(hj[num_key])])
	if not hj.has("target_tags"):
		errors.append("pathogens.json: %s.hijack.target_tags: missing required field (got null)" % [id])
	elif typeof(hj["target_tags"]) != TYPE_ARRAY:
		errors.append("pathogens.json: %s.hijack.target_tags: must be an array of strings (got %s)" % [id, _format_val(hj["target_tags"])])
	else:
		var tags: Array = hj["target_tags"]
		if tags.is_empty():
			errors.append("pathogens.json: %s.hijack.target_tags: cannot be empty (got empty)" % [id])
		for t_var: Variant in tags:
			if typeof(t_var) != TYPE_STRING:
				errors.append("pathogens.json: %s.hijack.target_tags: tag must be a string (got %s)" % [id, _format_val(t_var)])
			elif not KNOWN_TAGS.has(str(t_var)):
				errors.append("pathogens.json: %s.hijack.target_tags: unknown tag (got %s)" % [id, str(t_var)])

static func _validate_analysis(id: String, s_data: Dictionary, errors: PackedStringArray) -> void:
	var an_val: Variant = s_data["analysis"]
	if typeof(an_val) != TYPE_DICTIONARY:
		errors.append("structures.json: %s.analysis: must be a JSON object (got %s)" % [id, _format_val(an_val)])
		return
	if s_data.get("attack", null) == null:
		errors.append("structures.json: %s.analysis: only allowed on structures with an attack (got %s)" % [id, _format_val(an_val)])
	var an: Dictionary = an_val
	var an_keys: Array[String] = ["exposure_s", "damage_multiplier"]
	for ak_var: Variant in an.keys():
		var ak: String = str(ak_var)
		if not an_keys.has(ak):
			errors.append("structures.json: %s.analysis.%s: unknown key (got %s)" % [id, ak, ak])
	for req_ak: String in an_keys:
		if not an.has(req_ak):
			errors.append("structures.json: %s.analysis.%s: missing required field (got null)" % [id, req_ak])
	if an.has("exposure_s"):
		var ex: Variant = an["exposure_s"]
		if not _is_number(ex):
			errors.append("structures.json: %s.analysis.exposure_s: must be a number (got %s)" % [id, _format_val(ex)])
		elif float(ex) <= 0.0:
			errors.append("structures.json: %s.analysis.exposure_s: must be > 0 (got %s)" % [id, _format_val(ex)])
	if an.has("damage_multiplier"):
		var dm: Variant = an["damage_multiplier"]
		if not _is_number(dm):
			errors.append("structures.json: %s.analysis.damage_multiplier: must be a number (got %s)" % [id, _format_val(dm)])
		elif float(dm) < 1.0:
			errors.append("structures.json: %s.analysis.damage_multiplier: must be >= 1 (got %s)" % [id, _format_val(dm)])

static func _format_val(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		if is_finite(f) and floor(f) == f:
			return str(int(f))
	return str(v)

static func _is_whole_number(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return is_finite(f) and floor(f) == f
	return false

static func _is_number(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return is_finite(float(v))
	return false

static func _validate_rules(data: Dictionary, errors: PackedStringArray) -> void:
	var allowed_keys: Array[String] = [
		"version", "grid", "grid_scale", "start_wallet", "tick_rate",
		"battle_timeout_s", "max_path_recalcs_per_tick", "empty_path_weight",
		"deploy_hold_interval_s", "default_seed", "feature_flags"
	]
	for k_var: Variant in data.keys():
		var k: String = str(k_var)
		if not k.begins_with("_") and not allowed_keys.has(k):
			errors.append("game_rules.json: %s: unknown key (got %s)" % [k, k])

	for req_key: String in allowed_keys:
		if not data.has(req_key):
			errors.append("game_rules.json: %s: missing required field (got null)" % [req_key])

	if data.has("version"):
		var v: Variant = data["version"]
		if not _is_whole_number(v):
			errors.append("game_rules.json: version: must be an integer (got %s)" % [_format_val(v)])
		elif int(v) < 1:
			errors.append("game_rules.json: version: must be >= 1 (got %s)" % [_format_val(v)])

	if data.has("grid"):
		var g_val: Variant = data["grid"]
		if typeof(g_val) != TYPE_DICTIONARY:
			errors.append("game_rules.json: grid: must be a JSON object (got %s)" % [_format_val(g_val)])
		else:
			var grid: Dictionary = g_val
			var grid_allowed: Array[String] = ["width", "height", "deploy_ring", "tile_px"]
			for gk_var: Variant in grid.keys():
				var gk: String = str(gk_var)
				if not gk.begins_with("_") and not grid_allowed.has(gk):
					errors.append("game_rules.json: grid.%s: unknown key (got %s)" % [gk, gk])
			for req_gk: String in grid_allowed:
				if not grid.has(req_gk):
					errors.append("game_rules.json: grid.%s: missing required field (got null)" % [req_gk])

			if grid.has("width"):
				if not _is_whole_number(grid["width"]):
					errors.append("game_rules.json: grid.width: must be an integer (got %s)" % [_format_val(grid["width"])])
				elif int(grid["width"]) <= 0:
					errors.append("game_rules.json: grid.width: must be > 0 (got %s)" % [_format_val(grid["width"])])

			if grid.has("height"):
				if not _is_whole_number(grid["height"]):
					errors.append("game_rules.json: grid.height: must be an integer (got %s)" % [_format_val(grid["height"])])
				elif int(grid["height"]) <= 0:
					errors.append("game_rules.json: grid.height: must be > 0 (got %s)" % [_format_val(grid["height"])])

			if grid.has("deploy_ring"):
				if not _is_whole_number(grid["deploy_ring"]):
					errors.append("game_rules.json: grid.deploy_ring: must be an integer (got %s)" % [_format_val(grid["deploy_ring"])])
				elif int(grid["deploy_ring"]) < 0:
					errors.append("game_rules.json: grid.deploy_ring: must be >= 0 (got %s)" % [_format_val(grid["deploy_ring"])])
				elif _is_whole_number(grid.get("width", 0)) and _is_whole_number(grid.get("height", 0)):
					var w: int = int(grid.get("width", 0))
					var h: int = int(grid.get("height", 0))
					var dr: int = int(grid["deploy_ring"])
					if w > 0 and h > 0 and (dr * 2 >= w or dr * 2 >= h):
						errors.append("game_rules.json: grid.deploy_ring: deploy ring too large for grid (got %s)" % [_format_val(dr)])

			if grid.has("tile_px"):
				if not _is_whole_number(grid["tile_px"]):
					errors.append("game_rules.json: grid.tile_px: must be an integer (got %s)" % [_format_val(grid["tile_px"])])
				elif int(grid["tile_px"]) <= 0:
					errors.append("game_rules.json: grid.tile_px: must be > 0 (got %s)" % [_format_val(grid["tile_px"])])

	if data.has("grid_scale"):
		var gs: Variant = data["grid_scale"]
		if not _is_whole_number(gs):
			errors.append("game_rules.json: grid_scale: must be an integer (got %s)" % [_format_val(gs)])
		elif int(gs) <= 0:
			errors.append("game_rules.json: grid_scale: must be > 0 (got %s)" % [_format_val(gs)])

	if data.has("start_wallet"):
		var w_val: Variant = data["start_wallet"]
		if typeof(w_val) != TYPE_DICTIONARY:
			errors.append("game_rules.json: start_wallet: must be a JSON object (got %s)" % [_format_val(w_val)])
		else:
			var wallet: Dictionary = w_val
			if wallet.is_empty():
				errors.append("game_rules.json: start_wallet: cannot be empty (got empty)")
			for cur_var: Variant in wallet.keys():
				var cur: String = str(cur_var)
				if not KNOWN_CURRENCIES.has(cur):
					errors.append("game_rules.json: start_wallet.%s: unknown currency (got %s)" % [cur, cur])
				var amt: Variant = wallet[cur_var]
				if not _is_whole_number(amt):
					errors.append("game_rules.json: start_wallet.%s: must be an integer >= 0 (got %s)" % [cur, _format_val(amt)])
				elif int(amt) < 0:
					errors.append("game_rules.json: start_wallet.%s: must be >= 0 (got %s)" % [cur, _format_val(amt)])

	if data.has("tick_rate"):
		var tr: Variant = data["tick_rate"]
		if not _is_whole_number(tr):
			errors.append("game_rules.json: tick_rate: must be an integer (got %s)" % [_format_val(tr)])
		elif int(tr) <= 0:
			errors.append("game_rules.json: tick_rate: must be > 0 (got %s)" % [_format_val(tr)])

	if data.has("battle_timeout_s"):
		var bts: Variant = data["battle_timeout_s"]
		if not _is_number(bts):
			errors.append("game_rules.json: battle_timeout_s: must be a number (got %s)" % [_format_val(bts)])
		elif float(bts) <= 0.0:
			errors.append("game_rules.json: battle_timeout_s: must be > 0 (got %s)" % [_format_val(bts)])

	if data.has("max_path_recalcs_per_tick"):
		var mr: Variant = data["max_path_recalcs_per_tick"]
		if not _is_whole_number(mr):
			errors.append("game_rules.json: max_path_recalcs_per_tick: must be an integer (got %s)" % [_format_val(mr)])
		elif int(mr) <= 0:
			errors.append("game_rules.json: max_path_recalcs_per_tick: must be > 0 (got %s)" % [_format_val(mr)])

	if data.has("empty_path_weight"):
		var epw: Variant = data["empty_path_weight"]
		if not _is_number(epw):
			errors.append("game_rules.json: empty_path_weight: must be a number (got %s)" % [_format_val(epw)])
		elif float(epw) <= 0.0:
			errors.append("game_rules.json: empty_path_weight: must be > 0 (got %s)" % [_format_val(epw)])

	if data.has("deploy_hold_interval_s"):
		var dhi: Variant = data["deploy_hold_interval_s"]
		if not _is_number(dhi):
			errors.append("game_rules.json: deploy_hold_interval_s: must be a number (got %s)" % [_format_val(dhi)])
		elif float(dhi) <= 0.0:
			errors.append("game_rules.json: deploy_hold_interval_s: must be > 0 (got %s)" % [_format_val(dhi)])

	if data.has("default_seed"):
		var ds: Variant = data["default_seed"]
		if not _is_whole_number(ds):
			errors.append("game_rules.json: default_seed: must be an integer (got %s)" % [_format_val(ds)])

	if data.has("feature_flags"):
		var ff_val: Variant = data["feature_flags"]
		if typeof(ff_val) != TYPE_DICTIONARY:
			errors.append("game_rules.json: feature_flags: must be a JSON object (got %s)" % [_format_val(ff_val)])
		else:
			var flags: Dictionary = ff_val
			for fk_var: Variant in flags.keys():
				var fk: String = str(fk_var)
				if typeof(flags[fk_var]) != TYPE_BOOL:
					errors.append("game_rules.json: feature_flags.%s: must be a boolean (got %s)" % [fk, _format_val(flags[fk_var])])

static func _validate_structures(data: Dictionary, errors: PackedStringArray) -> void:
	if data.is_empty():
		errors.append("structures.json: root: structures cannot be empty (got empty)")
		return

	var required_keys: Array[String] = [
		"display_name", "role", "cost", "hp", "footprint", "buildable",
		"is_targetable", "visible_to_attacker", "path_weight", "tags",
		"attack", "damage_multipliers", "levels", "placeholder"
	]
	var optional_keys: Array[String] = ["analysis"]

	var core_count: int = 0

	for id_var: Variant in data.keys():
		var id: String = str(id_var)
		if id.begins_with("_"):
			continue

		var s_val: Variant = data[id_var]
		if typeof(s_val) != TYPE_DICTIONARY:
			errors.append("structures.json: %s: must be a JSON object (got %s)" % [id, _format_val(s_val)])
			continue

		var s_data: Dictionary = s_val

		for k_var: Variant in s_data.keys():
			var k: String = str(k_var)
			if not k.begins_with("_") and not required_keys.has(k) and not optional_keys.has(k):
				errors.append("structures.json: %s.%s: unknown key (got %s)" % [id, k, k])

		for req_key: String in required_keys:
			if not s_data.has(req_key):
				errors.append("structures.json: %s.%s: missing required field (got null)" % [id, req_key])

		if s_data.has("analysis"):
			_validate_analysis(id, s_data, errors)

		if s_data.has("display_name"):
			var dn: Variant = s_data["display_name"]
			if typeof(dn) != TYPE_STRING or str(dn).is_empty():
				errors.append("structures.json: %s.display_name: must be a non-empty string (got %s)" % [id, _format_val(dn)])

		if s_data.has("role"):
			var r: Variant = s_data["role"]
			if typeof(r) != TYPE_STRING:
				errors.append("structures.json: %s.role: must be a string (got %s)" % [id, _format_val(r)])

		if s_data.has("cost"):
			var c_val: Variant = s_data["cost"]
			if typeof(c_val) != TYPE_DICTIONARY:
				errors.append("structures.json: %s.cost: must be a JSON object (got %s)" % [id, _format_val(c_val)])
			else:
				var cost: Dictionary = c_val
				if cost.is_empty():
					errors.append("structures.json: %s.cost: cannot be empty (got empty)" % [id])
				for cur_var: Variant in cost.keys():
					var cur: String = str(cur_var)
					if not KNOWN_CURRENCIES.has(cur):
						errors.append("structures.json: %s.cost.%s: unknown currency (got %s)" % [id, cur, cur])
					var amt: Variant = cost[cur_var]
					if not _is_whole_number(amt):
						errors.append("structures.json: %s.cost.%s: must be an integer >= 0 (got %s)" % [id, cur, _format_val(amt)])
					elif int(amt) < 0:
						errors.append("structures.json: %s.cost.%s: must be >= 0 (got %s)" % [id, cur, _format_val(amt)])

		if s_data.has("hp"):
			var hp: Variant = s_data["hp"]
			if not _is_whole_number(hp):
				errors.append("structures.json: %s.hp: must be an integer > 0 (got %s)" % [id, _format_val(hp)])
			elif int(hp) <= 0:
				errors.append("structures.json: %s.hp: must be > 0 (got %s)" % [id, _format_val(hp)])

		if s_data.has("footprint"):
			var fp_val: Variant = s_data["footprint"]
			if typeof(fp_val) != TYPE_ARRAY or (fp_val as Array).size() != 2:
				errors.append("structures.json: %s.footprint: must be an array of 2 integers [w, h] (got %s)" % [id, _format_val(fp_val)])
			else:
				var fp: Array = fp_val
				if not _is_whole_number(fp[0]) or int(fp[0]) <= 0:
					errors.append("structures.json: %s.footprint[0]: must be an integer > 0 (got %s)" % [id, _format_val(fp[0])])
				if not _is_whole_number(fp[1]) or int(fp[1]) <= 0:
					errors.append("structures.json: %s.footprint[1]: must be an integer > 0 (got %s)" % [id, _format_val(fp[1])])

		if s_data.has("buildable"):
			if typeof(s_data["buildable"]) != TYPE_BOOL:
				errors.append("structures.json: %s.buildable: must be a boolean (got %s)" % [id, _format_val(s_data["buildable"])])

		if s_data.has("is_targetable"):
			if typeof(s_data["is_targetable"]) != TYPE_BOOL:
				errors.append("structures.json: %s.is_targetable: must be a boolean (got %s)" % [id, _format_val(s_data["is_targetable"])])

		if s_data.has("visible_to_attacker"):
			if typeof(s_data["visible_to_attacker"]) != TYPE_BOOL:
				errors.append("structures.json: %s.visible_to_attacker: must be a boolean (got %s)" % [id, _format_val(s_data["visible_to_attacker"])])

		if s_data.has("path_weight"):
			var pw: Variant = s_data["path_weight"]
			if not _is_number(pw):
				errors.append("structures.json: %s.path_weight: must be a number > 0 (got %s)" % [id, _format_val(pw)])
			elif float(pw) <= 0.0:
				errors.append("structures.json: %s.path_weight: must be > 0 (got %s)" % [id, _format_val(pw)])

		var is_core: bool = false
		if s_data.has("tags"):
			var tags_val: Variant = s_data["tags"]
			if typeof(tags_val) != TYPE_ARRAY:
				errors.append("structures.json: %s.tags: must be an array of strings (got %s)" % [id, _format_val(tags_val)])
			else:
				var tags_arr: Array = tags_val
				for t_var: Variant in tags_arr:
					var t_str: String = str(t_var)
					if typeof(t_var) != TYPE_STRING:
						errors.append("structures.json: %s.tags: tag must be a string (got %s)" % [id, t_str])
					elif not KNOWN_TAGS.has(t_str):
						errors.append("structures.json: %s.tags: unknown tag (got %s)" % [id, t_str])
					elif t_str == "core":
						is_core = true

		if is_core:
			core_count += 1
			if s_data.has("buildable") and typeof(s_data["buildable"]) == TYPE_BOOL and bool(s_data["buildable"]) == true:
				errors.append("structures.json: %s.buildable: core structure must not be buildable (got true)" % [id])

		if s_data.has("attack"):
			var atk_val: Variant = s_data["attack"]
			if atk_val != null:
				if typeof(atk_val) != TYPE_DICTIONARY:
					errors.append("structures.json: %s.attack: must be a JSON object or null (got %s)" % [id, _format_val(atk_val)])
				else:
					var atk: Dictionary = atk_val
					var atk_allowed: Array[String] = [
						"damage", "interval_s", "range_tiles", "splash_radius_tiles", "projectile_speed_tiles_s"
					]
					for ak_var: Variant in atk.keys():
						var ak: String = str(ak_var)
						if not ak.begins_with("_") and not atk_allowed.has(ak):
							errors.append("structures.json: %s.attack.%s: unknown key (got %s)" % [id, ak, ak])
					for req_ak: String in atk_allowed:
						if not atk.has(req_ak):
							errors.append("structures.json: %s.attack.%s: missing required field (got null)" % [id, req_ak])

					if atk.has("damage"):
						var dmg: Variant = atk["damage"]
						if not _is_whole_number(dmg):
							errors.append("structures.json: %s.attack.damage: must be an integer (got %s)" % [id, _format_val(dmg)])
						elif int(dmg) <= 0:
							errors.append("structures.json: %s.attack.damage: must be > 0 (got %s)" % [id, _format_val(dmg)])

					if atk.has("interval_s"):
						var intv: Variant = atk["interval_s"]
						if not _is_number(intv):
							errors.append("structures.json: %s.attack.interval_s: must be a number (got %s)" % [id, _format_val(intv)])
						elif float(intv) <= 0.0:
							errors.append("structures.json: %s.attack.interval_s: must be > 0 (got %s)" % [id, _format_val(intv)])

					if atk.has("range_tiles"):
						var rng: Variant = atk["range_tiles"]
						if not _is_number(rng):
							errors.append("structures.json: %s.attack.range_tiles: must be a number (got %s)" % [id, _format_val(rng)])
						elif float(rng) <= 0.0:
							errors.append("structures.json: %s.attack.range_tiles: must be > 0 (got %s)" % [id, _format_val(rng)])

					if atk.has("splash_radius_tiles"):
						var sr: Variant = atk["splash_radius_tiles"]
						if not _is_number(sr):
							errors.append("structures.json: %s.attack.splash_radius_tiles: must be a number (got %s)" % [id, _format_val(sr)])
						elif float(sr) < 0.0:
							errors.append("structures.json: %s.attack.splash_radius_tiles: must be >= 0 (got %s)" % [id, _format_val(sr)])

					if atk.has("projectile_speed_tiles_s"):
						var ps: Variant = atk["projectile_speed_tiles_s"]
						if not _is_number(ps):
							errors.append("structures.json: %s.attack.projectile_speed_tiles_s: must be a number (got %s)" % [id, _format_val(ps)])
						elif float(ps) < 0.0:
							errors.append("structures.json: %s.attack.projectile_speed_tiles_s: must be >= 0 (got %s)" % [id, _format_val(ps)])

		if s_data.has("damage_multipliers"):
			var dm_val: Variant = s_data["damage_multipliers"]
			if typeof(dm_val) != TYPE_DICTIONARY:
				errors.append("structures.json: %s.damage_multipliers: must be a JSON object (got %s)" % [id, _format_val(dm_val)])
			else:
				var dm: Dictionary = dm_val
				for mk_var: Variant in dm.keys():
					var mk: String = str(mk_var)
					if not KNOWN_TAGS.has(mk):
						errors.append("structures.json: %s.damage_multipliers.%s: unknown tag (got %s)" % [id, mk, mk])
					var mv: Variant = dm[mk_var]
					if not _is_number(mv):
						errors.append("structures.json: %s.damage_multipliers.%s: must be a number (got %s)" % [id, mk, _format_val(mv)])
					elif float(mv) <= 0.0:
						errors.append("structures.json: %s.damage_multipliers.%s: must be > 0 (got %s)" % [id, mk, _format_val(mv)])

		if s_data.has("levels"):
			var lvls_val: Variant = s_data["levels"]
			if typeof(lvls_val) != TYPE_ARRAY:
				errors.append("structures.json: %s.levels: must be an array (got %s)" % [id, _format_val(lvls_val)])
			else:
				var lvls: Array = lvls_val
				for idx in range(lvls.size()):
					if typeof(lvls[idx]) != TYPE_DICTIONARY:
						errors.append("structures.json: %s.levels[%d]: must be a JSON object (got %s)" % [id, idx, _format_val(lvls[idx])])

		if s_data.has("placeholder"):
			var ph_val: Variant = s_data["placeholder"]
			if typeof(ph_val) != TYPE_DICTIONARY:
				errors.append("structures.json: %s.placeholder: must be a JSON object (got %s)" % [id, _format_val(ph_val)])
			else:
				var ph: Dictionary = ph_val
				var ph_allowed: Array[String] = ["shape", "color"]
				for pk_var: Variant in ph.keys():
					var pk: String = str(pk_var)
					if not pk.begins_with("_") and not ph_allowed.has(pk):
						errors.append("structures.json: %s.placeholder.%s: unknown key (got %s)" % [id, pk, pk])
				for req_pk: String in ph_allowed:
					if not ph.has(req_pk):
						errors.append("structures.json: %s.placeholder.%s: missing required field (got null)" % [id, req_pk])
				if ph.has("shape"):
					var sh: String = str(ph["shape"])
					if not KNOWN_SHAPES.has(sh):
						errors.append("structures.json: %s.placeholder.shape: unknown shape (got %s)" % [id, sh])
				if ph.has("color"):
					var clr: String = str(ph["color"])
					if typeof(ph["color"]) != TYPE_STRING or not Color.html_is_valid(clr):
						errors.append("structures.json: %s.placeholder.color: invalid color hex (got %s)" % [id, clr])

	if core_count != 1:
		errors.append("structures.json: structures: must contain exactly one core structure (got %d)" % [core_count])

static func _validate_strains(id: String, st_val: Variant, errors: PackedStringArray) -> void:
	if typeof(st_val) != TYPE_ARRAY:
		errors.append("pathogens.json: %s.strains: must be an array (got %s)" % [id, _format_val(st_val)])
		return
	var arr: Array = st_val
	var seen: Dictionary = {}
	var st_keys: Array[String] = ["id", "display_name", "modifiers"]
	var mod_keys: Array[String] = ["hp", "speed", "damage", "cost", "analysis_rate"]
	var id_re := RegEx.new()
	id_re.compile("^[a-z][a-z0-9_]*$")
	for idx: int in range(arr.size()):
		var pre: String = "pathogens.json: %s.strains[%d]" % [id, idx]
		if typeof(arr[idx]) != TYPE_DICTIONARY:
			errors.append("%s: must be a JSON object (got %s)" % [pre, _format_val(arr[idx])])
			continue
		var st: Dictionary = arr[idx]
		for k_var: Variant in st.keys():
			var k: String = str(k_var)
			if not st_keys.has(k):
				errors.append("%s.%s: unknown key (got %s)" % [pre, k, k])
		for req: String in st_keys:
			if not st.has(req):
				errors.append("%s.%s: missing required field (got null)" % [pre, req])
		if st.has("id"):
			var sid: Variant = st["id"]
			if typeof(sid) != TYPE_STRING or id_re.search(str(sid)) == null:
				errors.append("%s.id: must match ^[a-z][a-z0-9_]*$ (got %s)" % [pre, _format_val(sid)])
			elif str(sid) == "wild":
				errors.append("%s.id: reserved id (got wild)" % [pre])
			elif seen.has(str(sid)):
				errors.append("%s.id: duplicate id (got %s)" % [pre, str(sid)])
			else:
				seen[str(sid)] = true
		if st.has("display_name"):
			var dn: Variant = st["display_name"]
			if typeof(dn) != TYPE_STRING or str(dn).is_empty():
				errors.append("%s.display_name: must be a non-empty string (got %s)" % [pre, _format_val(dn)])
		if st.has("modifiers"):
			var mv: Variant = st["modifiers"]
			if typeof(mv) != TYPE_DICTIONARY:
				errors.append("%s.modifiers: must be a JSON object (got %s)" % [pre, _format_val(mv)])
			else:
				var mods: Dictionary = mv
				for mk_var: Variant in mods.keys():
					var mk: String = str(mk_var)
					if not mod_keys.has(mk):
						errors.append("%s.modifiers.%s: unknown key (got %s)" % [pre, mk, mk])
					var val: Variant = mods[mk_var]
					if not _is_number(val):
						errors.append("%s.modifiers.%s: must be a number > 0 (got %s)" % [pre, mk, _format_val(val)])
					elif float(val) <= 0.0:
						errors.append("%s.modifiers.%s: must be > 0 (got %s)" % [pre, mk, _format_val(val)])

static func _validate_pathogens(data: Dictionary, errors: PackedStringArray) -> void:
	if data.is_empty():
		errors.append("pathogens.json: root: pathogens cannot be empty (got empty)")
		return

	var allowed_keys: Array[String] = [
		"display_name", "role", "cost", "hp", "speed_tiles_s", "attack",
		"tags", "targeting", "damage_multipliers", "placeholder", "levels"
	]
	var optional_keys: Array[String] = ["biofilm", "hijack", "strains"]

	for id_var: Variant in data.keys():
		var id: String = str(id_var)
		if id.begins_with("_"):
			continue

		var p_val: Variant = data[id_var]
		if typeof(p_val) != TYPE_DICTIONARY:
			errors.append("pathogens.json: %s: must be a JSON object (got %s)" % [id, _format_val(p_val)])
			continue

		var p_data: Dictionary = p_val

		for k_var: Variant in p_data.keys():
			var k: String = str(k_var)
			if not k.begins_with("_") and not allowed_keys.has(k) and not optional_keys.has(k):
				errors.append("pathogens.json: %s.%s: unknown key (got %s)" % [id, k, k])

		for req_key: String in allowed_keys:
			if not p_data.has(req_key):
				errors.append("pathogens.json: %s.%s: missing required field (got null)" % [id, req_key])

		if p_data.has("biofilm"):
			_validate_biofilm(id, p_data["biofilm"], errors)
		if p_data.has("hijack"):
			_validate_hijack(id, p_data["hijack"], errors)
		if p_data.has("strains"):
			_validate_strains(id, p_data["strains"], errors)

		if p_data.has("display_name"):
			var dn: Variant = p_data["display_name"]
			if typeof(dn) != TYPE_STRING or str(dn).is_empty():
				errors.append("pathogens.json: %s.display_name: must be a non-empty string (got %s)" % [id, _format_val(dn)])

		if p_data.has("role"):
			var r: Variant = p_data["role"]
			if typeof(r) != TYPE_STRING:
				errors.append("pathogens.json: %s.role: must be a string (got %s)" % [id, _format_val(r)])

		if p_data.has("cost"):
			var c_val: Variant = p_data["cost"]
			if typeof(c_val) != TYPE_DICTIONARY:
				errors.append("pathogens.json: %s.cost: must be a JSON object (got %s)" % [id, _format_val(c_val)])
			else:
				var cost: Dictionary = c_val
				if cost.is_empty():
					errors.append("pathogens.json: %s.cost: cannot be empty (got empty)" % [id])
				for cur_var: Variant in cost.keys():
					var cur: String = str(cur_var)
					if not KNOWN_CURRENCIES.has(cur):
						errors.append("pathogens.json: %s.cost.%s: unknown currency (got %s)" % [id, cur, cur])
					var amt: Variant = cost[cur_var]
					if not _is_whole_number(amt):
						errors.append("pathogens.json: %s.cost.%s: must be an integer >= 0 (got %s)" % [id, cur, _format_val(amt)])
					elif int(amt) < 0:
						errors.append("pathogens.json: %s.cost.%s: must be >= 0 (got %s)" % [id, cur, _format_val(amt)])

		if p_data.has("hp"):
			var hp: Variant = p_data["hp"]
			if not _is_whole_number(hp):
				errors.append("pathogens.json: %s.hp: must be an integer > 0 (got %s)" % [id, _format_val(hp)])
			elif int(hp) <= 0:
				errors.append("pathogens.json: %s.hp: must be > 0 (got %s)" % [id, _format_val(hp)])

		if p_data.has("speed_tiles_s"):
			var spd: Variant = p_data["speed_tiles_s"]
			if not _is_number(spd):
				errors.append("pathogens.json: %s.speed_tiles_s: must be a number > 0 (got %s)" % [id, _format_val(spd)])
			elif float(spd) <= 0.0:
				errors.append("pathogens.json: %s.speed_tiles_s: must be > 0 (got %s)" % [id, _format_val(spd)])

		if p_data.has("attack"):
			var atk_val: Variant = p_data["attack"]
			if typeof(atk_val) != TYPE_DICTIONARY:
				errors.append("pathogens.json: %s.attack: must be a JSON object (got %s)" % [id, _format_val(atk_val)])
			else:
				var atk: Dictionary = atk_val
				var atk_allowed: Array[String] = ["damage", "interval_s", "range_tiles"]
				for ak_var: Variant in atk.keys():
					var ak: String = str(ak_var)
					if not ak.begins_with("_") and not atk_allowed.has(ak):
						errors.append("pathogens.json: %s.attack.%s: unknown key (got %s)" % [id, ak, ak])
				for req_ak: String in atk_allowed:
					if not atk.has(req_ak):
						errors.append("pathogens.json: %s.attack.%s: missing required field (got null)" % [id, req_ak])

				if atk.has("damage"):
					var dmg: Variant = atk["damage"]
					if not _is_whole_number(dmg):
						errors.append("pathogens.json: %s.attack.damage: must be an integer (got %s)" % [id, _format_val(dmg)])
					elif int(dmg) <= 0:
						errors.append("pathogens.json: %s.attack.damage: must be > 0 (got %s)" % [id, _format_val(dmg)])

				if atk.has("interval_s"):
					var intv: Variant = atk["interval_s"]
					if not _is_number(intv):
						errors.append("pathogens.json: %s.attack.interval_s: must be a number (got %s)" % [id, _format_val(intv)])
					elif float(intv) <= 0.0:
						errors.append("pathogens.json: %s.attack.interval_s: must be > 0 (got %s)" % [id, _format_val(intv)])

				if atk.has("range_tiles"):
					var rng: Variant = atk["range_tiles"]
					if not _is_number(rng):
						errors.append("pathogens.json: %s.attack.range_tiles: must be a number (got %s)" % [id, _format_val(rng)])
					elif float(rng) <= 0.0:
						errors.append("pathogens.json: %s.attack.range_tiles: must be > 0 (got %s)" % [id, _format_val(rng)])

		if p_data.has("tags"):
			var tags_val: Variant = p_data["tags"]
			if typeof(tags_val) != TYPE_ARRAY:
				errors.append("pathogens.json: %s.tags: must be an array of strings (got %s)" % [id, _format_val(tags_val)])
			else:
				var tags_arr: Array = tags_val
				for t_var: Variant in tags_arr:
					var t_str: String = str(t_var)
					if typeof(t_var) != TYPE_STRING:
						errors.append("pathogens.json: %s.tags: tag must be a string (got %s)" % [id, t_str])
					elif not KNOWN_TAGS.has(t_str):
						errors.append("pathogens.json: %s.tags: unknown tag (got %s)" % [id, t_str])

		if p_data.has("targeting"):
			var tgt_val: Variant = p_data["targeting"]
			if typeof(tgt_val) != TYPE_DICTIONARY:
				errors.append("pathogens.json: %s.targeting: must be a JSON object (got %s)" % [id, _format_val(tgt_val)])
			else:
				var tgt: Dictionary = tgt_val
				var tgt_allowed: Array[String] = ["priority_tags", "fallback"]
				for tk_var: Variant in tgt.keys():
					var tk: String = str(tk_var)
					if not tk.begins_with("_") and not tgt_allowed.has(tk):
						errors.append("pathogens.json: %s.targeting.%s: unknown key (got %s)" % [id, tk, tk])
				for req_tk: String in tgt_allowed:
					if not tgt.has(req_tk):
						errors.append("pathogens.json: %s.targeting.%s: missing required field (got null)" % [id, req_tk])

				if tgt.has("priority_tags"):
					var pt_val: Variant = tgt["priority_tags"]
					if typeof(pt_val) != TYPE_ARRAY:
						errors.append("pathogens.json: %s.targeting.priority_tags: must be an array (got %s)" % [id, _format_val(pt_val)])
					else:
						var pt_arr: Array = pt_val
						for pt_item: Variant in pt_arr:
							var pt_str: String = str(pt_item)
							if typeof(pt_item) != TYPE_STRING:
								errors.append("pathogens.json: %s.targeting.priority_tags: tag must be a string (got %s)" % [id, pt_str])
							elif not KNOWN_TAGS.has(pt_str):
								errors.append("pathogens.json: %s.targeting.priority_tags: unknown tag (got %s)" % [id, pt_str])

				if tgt.has("fallback"):
					var fb: Variant = tgt["fallback"]
					if typeof(fb) != TYPE_STRING or str(fb).is_empty():
						errors.append("pathogens.json: %s.targeting.fallback: must be a non-empty string (got %s)" % [id, _format_val(fb)])

		if p_data.has("damage_multipliers"):
			var dm_val: Variant = p_data["damage_multipliers"]
			if typeof(dm_val) != TYPE_DICTIONARY:
				errors.append("pathogens.json: %s.damage_multipliers: must be a JSON object (got %s)" % [id, _format_val(dm_val)])
			else:
				var dm: Dictionary = dm_val
				for mk_var: Variant in dm.keys():
					var mk: String = str(mk_var)
					if not KNOWN_TAGS.has(mk):
						errors.append("pathogens.json: %s.damage_multipliers.%s: unknown tag (got %s)" % [id, mk, mk])
					var mv: Variant = dm[mk_var]
					if not _is_number(mv):
						errors.append("pathogens.json: %s.damage_multipliers.%s: must be a number (got %s)" % [id, mk, _format_val(mv)])
					elif float(mv) <= 0.0:
						errors.append("pathogens.json: %s.damage_multipliers.%s: must be > 0 (got %s)" % [id, mk, _format_val(mv)])

		if p_data.has("placeholder"):
			var ph_val: Variant = p_data["placeholder"]
			if typeof(ph_val) != TYPE_DICTIONARY:
				errors.append("pathogens.json: %s.placeholder: must be a JSON object (got %s)" % [id, _format_val(ph_val)])
			else:
				var ph: Dictionary = ph_val
				var ph_allowed: Array[String] = ["shape", "color"]
				for pk_var: Variant in ph.keys():
					var pk: String = str(pk_var)
					if not pk.begins_with("_") and not ph_allowed.has(pk):
						errors.append("pathogens.json: %s.placeholder.%s: unknown key (got %s)" % [id, pk, pk])
				for req_pk: String in ph_allowed:
					if not ph.has(req_pk):
						errors.append("pathogens.json: %s.placeholder.%s: missing required field (got null)" % [id, req_pk])
				if ph.has("shape"):
					var sh: String = str(ph["shape"])
					if not KNOWN_SHAPES.has(sh):
						errors.append("pathogens.json: %s.placeholder.shape: unknown shape (got %s)" % [id, sh])
				if ph.has("color"):
					var clr: String = str(ph["color"])
					if typeof(ph["color"]) != TYPE_STRING or not Color.html_is_valid(clr):
						errors.append("pathogens.json: %s.placeholder.color: invalid color hex (got %s)" % [id, clr])

		if p_data.has("levels"):
			var lvls_val: Variant = p_data["levels"]
			if typeof(lvls_val) != TYPE_ARRAY:
				errors.append("pathogens.json: %s.levels: must be an array (got %s)" % [id, _format_val(lvls_val)])
			else:
				var lvls: Array = lvls_val
				for idx in range(lvls.size()):
					if typeof(lvls[idx]) != TYPE_DICTIONARY:
						errors.append("pathogens.json: %s.levels[%d]: must be a JSON object (got %s)" % [id, idx, _format_val(lvls[idx])])
