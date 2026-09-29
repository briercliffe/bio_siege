extends SceneTree

## Headless CLI Balance Simulator for Bio Siege.
## Runs batch battles with deploy jitter, stat overrides, parameter sweeps, and CSV output.

const USAGE: String = """Usage: godot --headless --path . -s tools/balance_sim.gd -- [inputs] [options]

Inputs (exactly one required):
  --scenario=<name>    Scenario name: open_field, walled_nucleus, short_wall,
                       long_wall, phage_priority, mixed, stress
  --battle=<file>      Path to battle snapshot JSON file
  --base=<file> --army=<file>
                       Paths to base and army snapshot JSON files

Options:
  --runs=N             Number of runs per sweep value (default: 100)
  --seed=S             Base random seed (default: -1, uses config default_seed)
  --jitter=J           Deploy jitter radius in ring cells (default: 2)
  --set=<path>=<value> Override a config value (e.g. --set=pathogens.rhinovirus.hp=50)
                       Can be specified multiple times
  --sweep=<path>:<start>:<end>:<step>
                       Sweep a config stat over a range (e.g. structures.mucous_wall.hp:100:500:100)
  --out=<file>         Output CSV file path (default: stdout)
  --help, -h           Show this help message and exit
"""

const CSV_HEADER: String = "sweep_path,sweep_value,run,seed,outcome,end_reason,battle_s,nucleus_hp_remaining,structures_destroyed,walls_destroyed,walls_damaged,pathogens_alive,first_destroyed_type,first_contact_s"


func _init() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.is_empty() or "--help" in user_args or "-h" in user_args:
		print(USAGE)
		quit(1)
		return

	var string_args: Array[String] = []
	for a: String in user_args:
		string_args.append(a)

	var parsed: Dictionary = BalanceSimArgs.parse_args(string_args)
	if not parsed.get("ok", false):
		printerr("Error: %s\n" % parsed.get("error", "Unknown error"))
		printerr(USAGE)
		quit(parsed.get("exit_code", 1))
		return

	var inputs: Dictionary = parsed.get("inputs", {})
	var options: Dictionary = parsed.get("options", {})

	# Load raw JSON strings from data files
	var rules_path: String = "res://data/game_rules.json"
	if not FileAccess.file_exists(rules_path) and FileAccess.file_exists("res://data/rules.json"):
		rules_path = "res://data/rules.json"
	var structures_path: String = "res://data/structures.json"
	var pathogens_path: String = "res://data/pathogens.json"

	var rules_str: String = _read_file_text(rules_path)
	if rules_str.is_empty() and not FileAccess.file_exists(rules_path):
		printerr("Error: Rules config file not found: %s" % rules_path)
		quit(1)
		return

	var structures_str: String = _read_file_text(structures_path)
	if structures_str.is_empty() and not FileAccess.file_exists(structures_path):
		printerr("Error: Structures config file not found: %s" % structures_path)
		quit(1)
		return

	var pathogens_str: String = _read_file_text(pathogens_path)
	if pathogens_str.is_empty() and not FileAccess.file_exists(pathogens_path):
		printerr("Error: Pathogens config file not found: %s" % pathogens_path)
		quit(1)
		return

	var rules_val: Variant = JSON.parse_string(rules_str)
	var structures_val: Variant = JSON.parse_string(structures_str)
	var pathogens_val: Variant = JSON.parse_string(pathogens_str)

	if not (rules_val is Dictionary) or not (structures_val is Dictionary) or not (pathogens_val is Dictionary):
		printerr("Error: Failed to parse raw JSON configs to dictionaries")
		quit(1)
		return

	var json_roots: Dictionary = {
		"rules": rules_val as Dictionary,
		"structures": structures_val as Dictionary,
		"pathogens": pathogens_val as Dictionary,
	}

	# Apply all --set overrides
	var set_overrides: Array = options.get("set", [])
	for override_var: Variant in set_overrides:
		var s: String = str(override_var)
		var eq_idx: int = s.find("=")
		if eq_idx == -1:
			printerr("Error: Invalid --set format: '%s'" % s)
			quit(1)
			return
		var dotted_path: String = s.substr(0, eq_idx).strip_edges()
		var val_str: String = s.substr(eq_idx + 1).strip_edges()
		var set_err: String = BalanceSimArgs.apply_override(json_roots, dotted_path, val_str)
		if not set_err.is_empty():
			printerr("Error applying override '--set=%s': %s" % [s, set_err])
			quit(1)
			return

	# Sweep values
	var sweep_str: String = str(options.get("sweep", "")).strip_edges()
	var sweep_path: String = ""
	var sweep_values: Array = [null]
	if not sweep_str.is_empty():
		var sweep_info: Dictionary = BalanceSimArgs.parse_sweep(sweep_str)
		if not sweep_info.get("ok", false):
			printerr("Error parsing --sweep: %s" % sweep_info.get("error", "Unknown error"))
			quit(1)
			return
		sweep_path = sweep_info.get("path", "")
		sweep_values = sweep_info.get("values", [])
		if sweep_values.is_empty():
			printerr("Error: Sweep produced no values")
			quit(1)
			return

	# Jitter warning
	var jitter: int = int(options.get("jitter", 2))
	if jitter == 0:
		printerr("warning: jitter=0: all runs are identical\n")

	var runs_count: int = int(options.get("runs", 100))
	var option_seed: int = int(options.get("seed", -1))
	var csv_rows: Array[String] = []

	# Run simulation sweeps
	for sweep_value: Variant in sweep_values:
		var cloned_roots: Dictionary = {
			"rules": (json_roots["rules"] as Dictionary).duplicate(true),
			"structures": (json_roots["structures"] as Dictionary).duplicate(true),
			"pathogens": (json_roots["pathogens"] as Dictionary).duplicate(true),
		}

		if sweep_value != null:
			var sw_err: String = BalanceSimArgs.apply_override(cloned_roots, sweep_path, str(sweep_value))
			if not sw_err.is_empty():
				printerr("Error applying sweep override '%s = %s': %s" % [sweep_path, str(sweep_value), sw_err])
				quit(1)
				return

		var r_str: String = JSON.stringify(cloned_roots["rules"])
		var s_str: String = JSON.stringify(cloned_roots["structures"])
		var p_str: String = JSON.stringify(cloned_roots["pathogens"])

		var cfg_res: ConfigLoadResult = GameConfig.load_from_strings(r_str, s_str, p_str)
		if cfg_res == null or not cfg_res.errors.is_empty():
			if cfg_res != null:
				for err_msg: String in cfg_res.errors:
					printerr("Config error: %s" % err_msg)
			else:
				printerr("Config error: load_from_strings returned null")
			quit(2)
			return

		var config: GameConfig = cfg_res.config
		var base_seed: int = option_seed if option_seed != -1 else config.default_seed

		# Resolve base setup
		var base_setup: BattleSetup = _resolve_setup(inputs, config, base_seed)
		if base_setup == null:
			quit(1)
			return

		var setup_errors: PackedStringArray = base_setup.validate(config)
		if not setup_errors.is_empty():
			for serr: String in setup_errors:
				printerr("Battle setup error: %s" % serr)
			quit(1)
			return

		var ring_cells: Array[Vector2i] = Scenarios.ring_cells(config.grid_width, config.grid_height)

		var attacker_wins: int = 0
		var total_battle_s: float = 0.0
		var total_nucleus_hp: int = 0
		var runs_with_wall_damage_count: int = 0
		var progress_interval: int = maxi(1, runs_count / 10)

		for run_idx in range(runs_count):
			var run_seed: int = base_seed + run_idx
			var jittered_units: Array = BalanceSimArgs.apply_jitter(base_setup.units, jitter, run_seed, ring_cells)
			var run_setup: BattleSetup = BattleSetup.create(base_setup.structures, jittered_units, run_seed)
			var sim := BattleSim.new(config, run_setup)

			while not sim.finished:
				sim.step()

			var walls_damaged: int = 0
			var walls_destroyed: int = 0
			for s: StructureState in sim.structures:
				if s.def != null and s.def.has_tag("wall"):
					if s.hp < s.def.hp:
						walls_damaged += 1
					if not s.alive:
						walls_destroyed += 1

			if walls_damaged > 0:
				runs_with_wall_damage_count += 1

			if sim.outcome == "attacker":
				attacker_wins += 1

			var battle_s: float = float(sim.tick) / float(config.tick_rate)
			total_battle_s += battle_s

			var nuc: StructureState = sim.structure(sim.nucleus_id)
			var nucleus_hp: int = nuc.hp if nuc != null else 0
			total_nucleus_hp += nucleus_hp

			var pathogens_alive: int = 0
			for p: PathogenState in sim.pathogens:
				if p != null and p.alive:
					pathogens_alive += 1

			var first_contact_str: String = "-1.0"
			if sim.first_contact_tick >= 0:
				first_contact_str = "%.2f" % (float(sim.first_contact_tick) / float(config.tick_rate))

			# sweep_path,sweep_value,run,seed,outcome,end_reason,battle_s,nucleus_hp_remaining,structures_destroyed,walls_destroyed,walls_damaged,pathogens_alive,first_destroyed_type,first_contact_s
			var row: String = "%s,%s,%d,%d,%s,%s,%.2f,%d,%d,%d,%d,%d,%s,%s" % [
				sweep_path,
				str(sweep_value) if sweep_value != null else "",
				run_idx,
				run_seed,
				sim.outcome,
				sim.end_reason,
				battle_s,
				nucleus_hp,
				sim.structures_destroyed,
				walls_destroyed,
				walls_damaged,
				pathogens_alive,
				sim.first_destroyed_structure_type,
				first_contact_str,
			]
			csv_rows.append(row)

			if (run_idx + 1) % progress_interval == 0 or (run_idx + 1) == runs_count:
				var pct: float = float(run_idx + 1) / float(runs_count) * 100.0
				printerr("Progress: %d/%d runs (%.0f%%)" % [run_idx + 1, runs_count, pct])

		# Summary block
		var attacker_win_pct: float = float(attacker_wins) / float(runs_count) * 100.0
		var avg_battle_s: float = total_battle_s / float(runs_count)
		var avg_nuc_hp: float = float(total_nucleus_hp) / float(runs_count)
		var wall_damage_pct: float = float(runs_with_wall_damage_count) / float(runs_count) * 100.0

		var sweep_prefix: String = ""
		if not sweep_path.is_empty():
			sweep_prefix = "[%s = %s]  " % [sweep_path, str(sweep_value)]

		printerr("%sruns=%d  attacker_win=%.1f%%  avg_battle_s=%.1f  avg_nucleus_hp_left=%d  runs_with_wall_damage=%.1f%%" % [
			sweep_prefix,
			runs_count,
			attacker_win_pct,
			avg_battle_s,
			int(round(avg_nuc_hp)),
			wall_damage_pct,
		])

	# Write CSV output
	var out_path: String = str(options.get("out", "")).strip_edges()
	if not out_path.is_empty():
		var dir_path: String = out_path.get_base_dir()
		if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		var out_f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if out_f == null:
			printerr("Error: Failed to open output file: %s" % out_path)
			quit(1)
			return
		out_f.store_line(CSV_HEADER)
		for r: String in csv_rows:
			out_f.store_line(r)
		out_f.close()
	else:
		print(CSV_HEADER)
		for r: String in csv_rows:
			print(r)

	quit(0)


func _resolve_setup(inputs: Dictionary, config: GameConfig, seed: int) -> BattleSetup:
	var itype: String = inputs.get("type", "")
	if itype == "scenario":
		var sname: String = inputs.get("scenario", "")
		match sname:
			"open_field":
				return Scenarios.open_field(seed)
			"walled_nucleus":
				return Scenarios.walled_nucleus(seed)
			"short_wall":
				return Scenarios.short_wall(seed)
			"long_wall":
				return Scenarios.long_wall(seed)
			"phage_priority":
				return Scenarios.phage_priority(seed)
			"mixed":
				return Scenarios.mixed([], seed)
			"stress":
				return Scenarios.stress([], seed)
			_:
				printerr("Error: Unknown scenario '%s'" % sname)
				return null
	elif itype == "battle":
		var bfile: String = inputs.get("battle", "")
		if not FileAccess.file_exists(bfile):
			printerr("Error: Battle file not found: %s" % bfile)
			return null
		var f := FileAccess.open(bfile, FileAccess.READ)
		if f == null:
			printerr("Error: Failed to open battle file: %s" % bfile)
			return null
		var btext: String = f.get_as_text()
		var bres: Dictionary = SnapshotIO.parse_battle(btext, config)
		if not bres.get("ok", false):
			printerr("Error parsing battle file: %s" % bres.get("error", "Unknown error"))
			return null
		var setup: BattleSetup = bres.get("setup")
		if setup != null:
			setup.seed = seed
		return setup
	elif itype == "base_army":
		var base_file: String = inputs.get("base", "")
		var army_file: String = inputs.get("army", "")
		if not FileAccess.file_exists(base_file):
			printerr("Error: Base file not found: %s" % base_file)
			return null
		var fb := FileAccess.open(base_file, FileAccess.READ)
		if fb == null:
			printerr("Error: Failed to open base file: %s" % base_file)
			return null
		var base_text: String = fb.get_as_text()
		var base_res: Dictionary = SnapshotIO.parse_base(base_text, config)
		if not base_res.get("ok", false):
			printerr("Error parsing base file: %s" % base_res.get("error", "Unknown error"))
			return null

		if not FileAccess.file_exists(army_file):
			printerr("Error: Army file not found: %s" % army_file)
			return null
		var fa := FileAccess.open(army_file, FileAccess.READ)
		if fa == null:
			printerr("Error: Failed to open army file: %s" % army_file)
			return null
		var army_text: String = fa.get_as_text()
		var army_res: Dictionary = SnapshotIO.parse_army(army_text, config)
		if not army_res.get("ok", false):
			printerr("Error parsing army file: %s" % army_res.get("error", "Unknown error"))
			return null

		return BattleSetup.create(base_res.get("layout", []), army_res.get("units", []), seed)

	printerr("Error: Unrecognized input type '%s'" % itype)
	return null


func _read_file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()
