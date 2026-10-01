class_name ScreenStack
extends Control

## Menu screens (How to play, Saved, Settings) opened over the current phase, last in first out.
##
## Screen contract: a screen scene's root is a full-rect Control that blocks input under it and
## declares `signal back_requested`. Emitting it pops the screen; the stack frees it. A screen never
## frees itself or calls pop() on the stack directly.
##
## An id whose scene file does not exist yet opens a PlaceholderScreen (title and Back) instead.

signal screen_opened(id: String)
signal screen_closed(id: String)

const SCREENS: Dictionary = {
	"how_to_play": "res://src/ui/screens/how_to_play_screen.tscn",   # built in #75
	"saved": "res://src/ui/screens/saved_screen.tscn",               # built in #77
	"settings": "res://src/ui/screens/settings_screen.tscn",         # built in #76
	"opponents": "res://src/ui/screens/opponent_screen.tscn",        # built in #161
	"upgrades": "res://src/ui/screens/upgrades_screen.tscn",         # built in #168
}

const TITLES: Dictionary = {
	"how_to_play": "How to play",
	"saved": "Saved bases and armies",
	"settings": "Settings",
	"opponents": "Choose a target",
	"upgrades": "Upgrades",
}

## Per-instance copy of SCREENS so tests can point an id at another path.
var scene_paths: Dictionary = SCREENS.duplicate()

var _ids: Array[String] = []
var _screens: Array[Control] = []


func _init() -> void:
	name = "ScreenStack"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Instantiates the screen for `id` and shows it on top. Unknown ids are ignored with a warning.
func push(id: String) -> void:
	if not scene_paths.has(id):
		push_warning("ScreenStack: unknown screen id '%s'" % id)
		return
	var path: String = str(scene_paths[id])
	var screen: Control = null
	if ResourceLoader.exists(path):
		var packed: PackedScene = load(path) as PackedScene
		if packed != null:
			var node: Node = packed.instantiate()
			screen = node as Control
			if screen == null and node != null:
				node.free()
				push_warning("ScreenStack: scene root of '%s' is not a Control: %s" % [id, path])
	if screen == null:
		screen = PlaceholderScreen.new(str(TITLES.get(id, id)))
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	if screen.has_signal("back_requested"):
		screen.connect("back_requested", _on_back_requested.bind(screen))
	_ids.append(id)
	_screens.append(screen)
	add_child(screen)
	screen_opened.emit(id)


## Closes and frees the top screen. Does nothing when the stack is empty.
func pop() -> void:
	if _screens.is_empty():
		return
	var id: String = _ids.pop_back()
	var screen: Control = _screens.pop_back()
	# Deferred: pop() usually runs from inside the screen's own Back button signal.
	if is_instance_valid(screen):
		screen.queue_free()
	screen_closed.emit(id)


## Closes every open screen, top first. Main calls it on each phase change.
func clear() -> void:
	while not _screens.is_empty():
		pop()


func top_id() -> String:
	return _ids.back() if not _ids.is_empty() else ""


func top_screen() -> Control:
	return _screens.back() if not _screens.is_empty() else null


func is_open() -> bool:
	return not _ids.is_empty()


func depth() -> int:
	return _ids.size()


func _on_back_requested(screen: Control) -> void:
	if top_screen() == screen:
		pop()
