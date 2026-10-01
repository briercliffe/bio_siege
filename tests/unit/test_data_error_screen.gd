extends GutTest

const GameDataScript: GDScript = preload("res://src/game/game_data.gd")
const DataErrorScene: PackedScene = preload("res://src/ui/screens/data_error_screen.tscn")
const TEMP_DIR: String = "user://test_data_error_screen"
const DATA_FILES: Array[String] = ["game_rules.json", "structures.json", "pathogens.json"]

const ERRORS: Array[String] = [
	"structures.json: mucous_wall.cost.atp: must be > 0 (got -5)",
	"pathogens.json: bacteriophage.hp: must be > 0 (got 0)",
	"game_rules.json: grid.width: missing required field (got null)",
]


func after_each() -> void:
	_remove_temp_dir()


func _remove_temp_dir() -> void:
	var dir: DirAccess = DirAccess.open(TEMP_DIR)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute(TEMP_DIR + "/" + file_name)
	DirAccess.remove_absolute(TEMP_DIR)


func _write_temp_data(structures_text: String = "") -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	for file_name: String in DATA_FILES:
		var text: String = FileAccess.get_file_as_string("res://data/" + file_name)
		if file_name == "structures.json" and structures_text != "":
			text = structures_text
		var f: FileAccess = FileAccess.open(TEMP_DIR + "/" + file_name, FileAccess.WRITE)
		f.store_string(text)
		f.close()


func _make_screen(source: Node = null) -> DataErrorScreen:
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	add_child_autofree(host)
	var screen: DataErrorScreen = DataErrorScene.instantiate() as DataErrorScreen
	screen.data_source = source
	host.add_child(screen)
	return screen


func _errors() -> PackedStringArray:
	return PackedStringArray(ERRORS)


# -----------------------------------------------------------------------------
# DataErrorFormat
# -----------------------------------------------------------------------------

func test_parse_structure_error() -> void:
	var e: Dictionary = DataErrorFormat.parse("structures.json: mucous_wall.cost.atp: must be > 0 (got -5)")
	assert_eq(e, {"file": "structures.json", "entity": "mucous_wall", "field": "cost.atp", "message": "must be > 0 (got -5)"})


func test_parse_game_rules_has_no_entity() -> void:
	var e: Dictionary = DataErrorFormat.parse("game_rules.json: grid.width: missing required field (got null)")
	assert_eq(e["file"], "game_rules.json")
	assert_eq(e["entity"], "")
	assert_eq(e["field"], "grid.width")
	assert_eq(e["message"], "missing required field (got null)")


func test_parse_json_error_keeps_line_text_in_message() -> void:
	var e: Dictionary = DataErrorFormat.parse("pathogens.json: JSON parse error at line 12: Unexpected character")
	assert_eq(e["file"], "pathogens.json")
	assert_eq(e["entity"], "")
	assert_eq(e["field"], "")
	assert_eq(e["message"], "JSON parse error at line 12: Unexpected character")


func test_parse_unmatched_is_all_message() -> void:
	var e: Dictionary = DataErrorFormat.parse("weird")
	assert_eq(e, {"file": "", "entity": "", "field": "", "message": "weird"})
	e = DataErrorFormat.parse("not a file: x: y")
	assert_eq(e["file"], "")
	assert_eq(e["message"], "not a file: x: y")


func test_parse_entity_without_field() -> void:
	var e: Dictionary = DataErrorFormat.parse("structures.json: mucous_wall: missing")
	assert_eq(e["entity"], "mucous_wall")
	assert_eq(e["field"], "")
	assert_eq(DataErrorFormat.body_text(e), "missing")


func test_chip_and_body_text() -> void:
	var e: Dictionary = DataErrorFormat.parse(ERRORS[0])
	assert_eq(DataErrorFormat.chip_text(e), "structures.json · mucous_wall")
	assert_eq(DataErrorFormat.body_text(e), "cost.atp must be > 0 (got -5)")
	e = DataErrorFormat.parse(ERRORS[2])
	assert_eq(DataErrorFormat.chip_text(e), "game_rules.json")
	assert_eq(DataErrorFormat.body_text(e), "grid.width missing required field (got null)")


func test_report_has_header_and_one_line_per_error() -> void:
	var lines: PackedStringArray = DataErrorFormat.report(_errors()).split("\n")
	assert_eq(lines.size(), 4)
	assert_eq(lines[0], "Bio Siege data errors (3)")
	for i: int in range(ERRORS.size()):
		assert_eq(lines[i + 1], "- " + ERRORS[i])


# -----------------------------------------------------------------------------
# DataErrorScreen
# -----------------------------------------------------------------------------

func test_hidden_until_errors_shown() -> void:
	var screen: DataErrorScreen = _make_screen()
	assert_false(screen.visible)
	screen.show_errors(_errors())
	assert_true(screen.visible)


func test_show_errors_creates_one_item_per_error() -> void:
	var screen: DataErrorScreen = _make_screen()
	screen.show_errors(_errors())
	assert_eq(screen.items.size(), 3)
	assert_eq(screen.chips[0].text, "structures.json · mucous_wall")
	assert_eq(screen.chips[1].text, "pathogens.json · bacteriophage")
	assert_eq(screen.chips[2].text, "game_rules.json")
	screen.show_errors(PackedStringArray([ERRORS[0]]))
	assert_eq(screen.items.size(), 1)


func test_copy_report_sets_clipboard_text_and_label() -> void:
	var screen: DataErrorScreen = _make_screen()
	screen.show_errors(_errors())
	screen.copy_button.pressed.emit()
	assert_eq(screen.last_report, DataErrorFormat.report(_errors()))
	assert_eq(screen.copy_button.text, "Copied")
	screen._on_copy_timeout()
	assert_eq(screen.copy_button.text, "Copy report")


func test_reload_hides_screen_once_files_are_fixed() -> void:
	var broken: String = FileAccess.get_file_as_string("res://data/structures.json").replace("\"mucous_wall\"", "mucous_wall")
	_write_temp_data(broken)
	var data: Node = GameDataScript.new()
	autofree(data)
	data.load_data(TEMP_DIR)
	assert_push_error("GameData failed to load config")
	assert_false(data.load_errors.is_empty())
	var screen: DataErrorScreen = _make_screen(data)
	screen.show_errors(data.load_errors)

	# Still broken: the screen stays and shows the fresh errors.
	screen.reload_button.pressed.emit()
	assert_true(screen.visible)
	assert_gt(screen.items.size(), 0)

	_write_temp_data()
	screen.reload_button.pressed.emit()
	assert_false(screen.visible)
	assert_true(data.load_errors.is_empty())


func test_buttons_are_at_least_48_px_tall() -> void:
	var screen: DataErrorScreen = _make_screen()
	screen.show_errors(_errors())
	for control: Control in screen.tappable_controls():
		assert_gte(control.get_combined_minimum_size().y, 48.0, control.name)
		assert_gte(control.size.y, 48.0, control.name)
