class_name OfflineBackend
extends BackendClient

## In-memory fake backend: never touches the network. It records every call and returns canned responses
## registered with respond(). Net.backend() returns one when the `online` flag is off.

## One {"name": String, "payload": Dictionary} per rpc() call, in order.
var calls: Array[Dictionary] = []
var _responses: Dictionary = {}


## Registers the response rpc(name, ...) returns. connect_and_auth() uses the name "connect_and_auth".
func respond(name: String, response: Dictionary) -> void:
	_responses[name] = response


func set_status_for_tests(new_status: String) -> void:
	_set_status(new_status)


func call_names() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in calls:
		out.append(str(c["name"]))
	return out


func connect_and_auth() -> Dictionary:
	calls.append({"name": "connect_and_auth", "payload": {}})
	return (_responses["connect_and_auth"] as Dictionary).duplicate(true) if _responses.has("connect_and_auth") \
			else {"ok": false, "error": "offline"}


func rpc(name: String, payload: Dictionary) -> Dictionary:
	calls.append({"name": name, "payload": payload.duplicate(true)})
	if _responses.has(name):
		return (_responses[name] as Dictionary).duplicate(true)
	return {"ok": false, "error": "offline"}
