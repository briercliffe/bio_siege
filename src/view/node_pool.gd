class_name NodePool
extends RefCounted

var scene: PackedScene = null
var parent: Node = null
var created_count: int = 0
var _free_nodes: Array[Node] = []


func _init(p_scene: PackedScene, prewarm: int, p_parent: Node) -> void:
	scene = p_scene
	parent = p_parent
	for i in range(prewarm):
		var n: Node = _instantiate_node()
		if n != null:
			release(n)


func _instantiate_node() -> Node:
	if scene == null:
		return null
	var n: Node = scene.instantiate()
	created_count += 1
	if "pool" in n:
		n.pool = self
	if parent != null:
		parent.add_child(n)
	return n


func acquire() -> Node:
	var n: Node = null
	if not _free_nodes.is_empty():
		n = _free_nodes.pop_back()
	else:
		push_warning("pool grew")
		n = _instantiate_node()

	if n != null:
		if "pool" in n:
			n.pool = self
		if n is CanvasItem:
			(n as CanvasItem).show()
		n.set_process(true)
		if n.has_method("on_acquire"):
			n.on_acquire()
	return n


func release(node: Node) -> void:
	if node == null:
		return
	if node.has_method("on_release"):
		node.on_release()
	if node is CanvasItem:
		(node as CanvasItem).hide()
	node.set_process(false)
	if not _free_nodes.has(node):
		_free_nodes.append(node)
