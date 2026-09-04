@tool
extends EditorScript

func _run():
	var mesh_lib = MeshLibrary.new()
	var scene = load("res://scenes/grass_tile.tscn")
	var instance = scene.instantiate()

	var id = 0
	mesh_lib.create_item(id)
	mesh_lib.set_item_name(id, "GroundTile")

	var mesh_instances = []
	find_mesh_instances(instance, mesh_instances)

	# First pass: compute combined bounding box to find center
	var combined_aabb = AABB()
	var first = true
	for mi in mesh_instances:
		var mesh = mi.mesh
		if mesh == null:
			continue
		var local_xform = get_relative_transform(instance, mi)
		var mesh_aabb = mesh.get_aabb()
		var world_aabb = local_xform * mesh_aabb
		if first:
			combined_aabb = world_aabb
			first = false
		else:
			combined_aabb = combined_aabb.merge(world_aabb)

	var center = combined_aabb.position + combined_aabb.size / 2.0
	# Only center X and Z, keep Y so the tile still sits on the ground plane correctly
	var offset = Vector3(-center.x, 0, -center.z)

	var combined_mesh = ArrayMesh.new()
	for mi in mesh_instances:
		var mesh = mi.mesh
		if mesh == null:
			continue
		var local_xform = get_relative_transform(instance, mi)
		for surface_idx in range(mesh.get_surface_count()):
			var arrays = mesh.surface_get_arrays(surface_idx)
			var verts = arrays[Mesh.ARRAY_VERTEX]
			var new_verts = PackedVector3Array()
			for v in verts:
				new_verts.append(local_xform * v + offset)
			arrays[Mesh.ARRAY_VERTEX] = new_verts
			combined_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(surface_idx), arrays)
			var mat = mi.get_active_material(surface_idx)
			if mat:
				combined_mesh.surface_set_material(combined_mesh.get_surface_count() - 1, mat)

	mesh_lib.set_item_mesh(id, combined_mesh)

	var collision_nodes = []
	find_collision_shapes(instance, collision_nodes)

	var shapes = []
	for cs in collision_nodes:
		if cs.shape:
			var shape_xform = get_relative_transform(instance, cs)
			shape_xform.origin += offset
			shapes.append(cs.shape)
			shapes.append(shape_xform)

	mesh_lib.set_item_shapes(id, shapes)

	var save_path = "res://assets/tile_library.tres"
	ResourceSaver.save(mesh_lib, save_path)
	print("Saved MeshLibrary: ", mesh_instances.size(), " mesh(es), ", collision_nodes.size(), " collision shape(s), offset=", offset)

	instance.queue_free()

func find_mesh_instances(node, list):
	if node is MeshInstance3D:
		list.append(node)
	for child in node.get_children():
		find_mesh_instances(child, list)

func find_collision_shapes(node, list):
	if node is CollisionShape3D:
		list.append(node)
	for child in node.get_children():
		find_collision_shapes(child, list)

func get_relative_transform(root, node):
	var xform = Transform3D()
	var current = node
	while current != root and current != null:
		xform = current.transform * xform
		current = current.get_parent()
	return xform
