class_name BuildInfo
extends RefCounted

## The short commit SHA written to res://build_info.txt by the Pages deploy (#28), or "dev" when absent.

const DEFAULT_PATH: String = "res://build_info.txt"
const DEV: String = "dev"


static func read(path: String = DEFAULT_PATH) -> String:
	if not FileAccess.file_exists(path):
		return DEV
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return DEV
	var text: String = f.get_as_text().strip_edges()
	f.close()
	return text if not text.is_empty() else DEV
