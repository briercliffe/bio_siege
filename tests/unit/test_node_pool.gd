extends GutTest

var test_scene: PackedScene
var root: Node2D


func before_each() -> void:
	var proto := Node2D.new()
	test_scene = PackedScene.new()
	test_scene.pack(proto)
	proto.free()
	root = Node2D.new()
	add_child(root)


func after_each() -> void:
	for c in root.get_children():
		c.free()
	root.free()


func test_node_pool_lifecycle() -> void:
	var pool := NodePool.new(test_scene, 2, root)
	assert_eq(pool.created_count, 2, "Prewarm 2 should have created_count == 2")

	var n1: Node = pool.acquire()
	var n2: Node = pool.acquire()
	assert_eq(pool.created_count, 2, "Acquiring prewarmed nodes shouldn't increment created_count")
	assert_not_null(n1)
	assert_not_null(n2)
	assert_ne(n1, n2)

	var n3: Node = pool.acquire()
	assert_eq(pool.created_count, 3, "Acquiring 3rd node should grow pool and set created_count == 3")
	assert_push_warning("pool grew")

	pool.release(n1)
	var n4: Node = pool.acquire()
	assert_eq(n4, n1, "Released node should be reused")
	assert_eq(pool.created_count, 3, "Reusing node shouldn't increment created_count")
