class_name WebFilePicker
extends RefCounted

## Web builds only: opens the browser's file picker through an `<input type=file>` and hands the chosen
## file's text back. Keep the picker alive until the callback fires, since it owns the JavaScript callback.

const WINDOW_CALLBACK: String = "bioSiegeFilePicked"
const PICK_SCRIPT: String = """(function () {
	var input = document.createElement('input');
	input.type = 'file';
	input.accept = '.json,application/json,text/plain';
	input.onchange = function () {
		var file = input.files && input.files[0];
		if (!file) { return; }
		file.text().then(function (text) { window.%s(text); });
	};
	input.click();
})();"""

var _on_text: Callable = Callable()
var _js_callback: Variant = null


static func is_available() -> bool:
	return OS.has_feature("web")


## Returns false when not running in a browser.
func pick(on_text: Callable) -> bool:
	if not is_available():
		return false
	_on_text = on_text
	if _js_callback == null:
		_js_callback = JavaScriptBridge.create_callback(_on_js_text)
		var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
		window.set(WINDOW_CALLBACK, _js_callback)
	JavaScriptBridge.eval(PICK_SCRIPT % WINDOW_CALLBACK, true)
	return true


func _on_js_text(args: Array) -> void:
	if args.is_empty() or not _on_text.is_valid():
		return
	_on_text.call(str(args[0]))
