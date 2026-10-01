class_name DataErrorFormat
extends RefCounted

## Splits and formats GameConfig error strings ("<file>: <path>: <message>") for the Data error screen.

const REPORT_HEADER: String = "Bio Siege data errors (%d)"
const SEPARATOR: String = ": "
const NO_ENTITY_FILES: Array[String] = ["game_rules.json"]


## "structures.json: mucous_wall.cost.atp: must be > 0 (got -5)" becomes
## {file: "structures.json", entity: "mucous_wall", field: "cost.atp", message: "must be > 0 (got -5)"}.
## game_rules.json has no entity. Anything that does not look like "<file>.json: ..." is all message.
static func parse(error: String) -> Dictionary:
	var out: Dictionary = {"file": "", "entity": "", "field": "", "message": error}
	var first: int = error.find(SEPARATOR)
	if first <= 0:
		return out
	var file_name: String = error.substr(0, first)
	if not file_name.ends_with(".json") or file_name.contains(" "):
		return out
	out["file"] = file_name
	var rest: String = error.substr(first + SEPARATOR.length())
	out["message"] = rest
	var second: int = rest.find(SEPARATOR)
	if second <= 0:
		return out
	var path: String = rest.substr(0, second)
	# A path never contains a space; "JSON parse error at line 12" is part of the message.
	if path.contains(" "):
		return out
	out["message"] = rest.substr(second + SEPARATOR.length())
	if NO_ENTITY_FILES.has(file_name):
		out["field"] = path
		return out
	var dot: int = path.find(".")
	if dot < 0:
		out["entity"] = path
	else:
		out["entity"] = path.substr(0, dot)
		out["field"] = path.substr(dot + 1)
	return out


## "structures.json · mucous_wall", or just "game_rules.json". Empty when the error has no file.
static func chip_text(e: Dictionary) -> String:
	var file_name: String = str(e.get("file", ""))
	var entity: String = str(e.get("entity", ""))
	if entity == "":
		return file_name
	return "%s · %s" % [file_name, entity]


## "cost.atp must be > 0 (got -5)", or the message alone when there is no field.
static func body_text(e: Dictionary) -> String:
	var field: String = str(e.get("field", ""))
	var message: String = str(e.get("message", ""))
	if field == "":
		return message
	return "%s %s" % [field, message]


## Plain text for the clipboard: a header line, then one "- <error>" line each.
static func report(errors: PackedStringArray) -> String:
	var lines: PackedStringArray = PackedStringArray([REPORT_HEADER % errors.size()])
	for error: String in errors:
		lines.append("- " + error)
	return "\n".join(lines)
