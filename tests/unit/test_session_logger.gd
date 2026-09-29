extends GutTest

const SessionLoggerScript = preload("res://src/telemetry/session_logger.gd")
const TEST_FILE_PATH: String = "user://telemetry/test_session_log.jsonl"
const TEST_OTHER_FILE_PATH: String = "user://telemetry/test_session_log_other.jsonl"

func before_each() -> void:
	if FileAccess.file_exists(TEST_FILE_PATH):
		DirAccess.remove_absolute(TEST_FILE_PATH)
	if FileAccess.file_exists(TEST_OTHER_FILE_PATH):
		DirAccess.remove_absolute(TEST_OTHER_FILE_PATH)

func after_each() -> void:
	if FileAccess.file_exists(TEST_FILE_PATH):
		DirAccess.remove_absolute(TEST_FILE_PATH)
	if FileAccess.file_exists(TEST_OTHER_FILE_PATH):
		DirAccess.remove_absolute(TEST_OTHER_FILE_PATH)

func test_logger_custom_file_and_event_logging() -> void:
	var logger := SessionLoggerScript.new()
	add_child_autoqfree(logger)
	logger.set_custom_file_path(TEST_FILE_PATH)

	logger.log_event("test_event", {"foo": "bar", "number": 42})

	assert_true(FileAccess.file_exists(TEST_FILE_PATH), "Log file should exist")

	var f := FileAccess.open(TEST_FILE_PATH, FileAccess.READ)
	assert_not_null(f)
	var content: String = f.get_as_text()
	f.close()

	assert_true(content.contains("\"event\":\"test_event\""))
	assert_true(content.contains("\"foo\":\"bar\""))
	assert_true(content.contains("\"number\":42"))
	assert_true(content.contains("\"t_ms\":"))

	# Verify JSON parsing
	var lines := content.strip_edges().split("\n")
	assert_eq(lines.size(), 1)
	var json := JSON.new()
	var parse_err := json.parse(lines[0])
	assert_eq(parse_err, OK)
	var parsed: Dictionary = json.data as Dictionary
	assert_eq(parsed.get("event"), "test_event")
	assert_eq(parsed.get("foo"), "bar")
	assert_eq(int(parsed.get("number")), 42)
	assert_true(parsed.has("t_ms"))

func test_vector2i_conversion() -> void:
	var logger := SessionLoggerScript.new()
	add_child_autoqfree(logger)
	logger.set_custom_file_path(TEST_FILE_PATH)

	logger.log_event("coord_event", {
		"single_cell": Vector2i(3, 7),
		"nested_cells": [Vector2i(1, 2), Vector2i(4, 5)],
		"nested_dict": {"pos": Vector2i(10, 20)}
	})

	var f := FileAccess.open(TEST_FILE_PATH, FileAccess.READ)
	assert_not_null(f)
	var content: String = f.get_as_text()
	f.close()

	var lines := content.strip_edges().split("\n")
	assert_eq(lines.size(), 1)
	var json := JSON.new()
	assert_eq(json.parse(lines[0]), OK)
	var parsed: Dictionary = json.data as Dictionary
	assert_eq(parsed.get("event"), "coord_event")
	var cell: Array = parsed.get("single_cell", [])
	assert_eq(int(cell[0]), 3)
	assert_eq(int(cell[1]), 7)

	var nested: Array = parsed.get("nested_cells", [])
	assert_eq(int(nested[0][0]), 1)
	assert_eq(int(nested[0][1]), 2)
	assert_eq(int(nested[1][0]), 4)
	assert_eq(int(nested[1][1]), 5)

	var dict_cell: Array = parsed.get("nested_dict", {}).get("pos", [])
	assert_eq(int(dict_cell[0]), 10)
	assert_eq(int(dict_cell[1]), 20)

func test_all_sessions_text() -> void:
	var logger1 := SessionLoggerScript.new()
	add_child_autoqfree(logger1)
	logger1.set_custom_file_path(TEST_FILE_PATH)
	logger1.log_event("event_a", {"msg": "hello"})

	var logger2 := SessionLoggerScript.new()
	add_child_autoqfree(logger2)
	logger2.set_custom_file_path(TEST_OTHER_FILE_PATH)
	logger2.log_event("event_b", {"msg": "world"})

	var all_text: String = SessionLogger.all_sessions_text()
	assert_true(all_text.contains("\"event\":\"event_a\""))
	assert_true(all_text.contains("\"event\":\"event_b\""))
	assert_true(all_text.contains("\"msg\":\"hello\""))
	assert_true(all_text.contains("\"msg\":\"world\""))
