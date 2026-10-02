class_name ServerAddress
extends RefCounted

## Parses the `bio_siege/server/url` project setting ("https://host:7350") into scheme, host and port.

const DEFAULT_URL: String = "http://127.0.0.1:7350"
const DEFAULT_KEY: String = "defaultkey"

var scheme: String = "http"
var host: String = "127.0.0.1"
var port: int = 7350


static func parse(url: String) -> ServerAddress:
	var addr := ServerAddress.new()
	var rest: String = url.strip_edges()
	var sep: int = rest.find("://")
	if sep >= 0:
		addr.scheme = rest.substr(0, sep).to_lower()
		rest = rest.substr(sep + 3)
	else:
		addr.scheme = "http"
	var slash: int = rest.find("/")
	if slash >= 0:
		rest = rest.substr(0, slash)
	var default_port: int = 443 if addr.scheme == "https" else 7350
	var colon: int = rest.rfind(":")
	if colon >= 0 and rest.substr(colon + 1).is_valid_int():
		addr.port = rest.substr(colon + 1).to_int()
		rest = rest.substr(0, colon)
	else:
		addr.port = default_port
	addr.host = rest if not rest.is_empty() else "127.0.0.1"
	return addr


static func from_project_settings() -> ServerAddress:
	return parse(str(ProjectSettings.get_setting("bio_siege/server/url", DEFAULT_URL)))


static func server_key_from_project_settings() -> String:
	return str(ProjectSettings.get_setting("bio_siege/server/key", DEFAULT_KEY))
