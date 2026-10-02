class_name DeviceId
extends RefCounted

## The anonymous device id used for Nakama device auth (no passwords, no email). Created once and reused.

const DEFAULT_PATH: String = "user://device_id.txt"


static func load_or_create(path: String = DEFAULT_PATH) -> String:
	if FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var existing: String = f.get_as_text().strip_edges()
			if existing.length() >= 16:
				return existing
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out != null:
		out.store_string(id)
	else:
		push_warning("DeviceId: could not write %s; the id will change next run" % path)
	return id
