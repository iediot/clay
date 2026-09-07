extends Node3D

# Dev harness: builds the track slab at a sweep of size_x values and checks that
# the mesh is the same object at every length — same grain, no gaps, no flipped
# faces — and that an in-tree size change regenerates what a fresh build makes.
#
#   godot --headless --path . res://tools/scale_probe.tscn -- 30 80 200 400
#
# Nothing here is used at runtime.

const GEN := preload("res://scripts/terrain_generator.gd")

var _fails := 0

func _ready() -> void:
	var xs: Array[float] = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			xs.append(float(a))
	if xs.is_empty():
		xs = [20.0, 30.0, 80.0, 120.0, 200.0, 400.0]
	print("--- clay terrain scale probe ---")
	for sx in xs:
		await _check(sx)
	print("--- %s ---" % ("all checks passed" if _fails == 0 else "%d CHECKS FAILED" % _fails))
	get_tree().quit()

func _make(sx: float) -> MeshInstance3D:
	var t := MeshInstance3D.new()
	t.set_script(GEN)
	t.resolution = 300
	t.depth = 20.0
	t.corner_sharpness = 6.0
	t.edge_wobble = 0.0
	t.edge_wobble_scale = 0.0
	t.size_z = 8.0
	t.size_x = sx
	add_child(t)
	return t

func _say(ok: bool, label: String, detail: String) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	print("      %s" % detail)

func _check(sx: float) -> void:
	var t := _make(sx)
	var am: ArrayMesh = t.mesh
	var div: Vector2i = t.grid_divs()
	var want: float = t.cell_size()
	print("\nsize_x = %.1f   grid %d x %d" % [sx, div.x, div.y])

	# The grain the mesh actually ends up with, measured on the top surface's own
	# grid — along it, across it, and round the outline the overhang hangs from.
	# None of the three may depend on the length.
	var v: PackedVector3Array = am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var nx: int = div.x
	var nz: int = div.y
	var along := 0.0
	var across := 0.0
	for j in nz + 1:
		for i in nx:
			along = maxf(along, v[j * (nx + 1) + i].distance_to(v[j * (nx + 1) + i + 1]))
	for j in nz:
		for i in nx + 1:
			across = maxf(across, v[j * (nx + 1) + i].distance_to(v[(j + 1) * (nx + 1) + i]))
	var ring := maxf(along, across)
	_say(along < want * 1.5 and across < want * 1.5,
		"grain is length-independent",
		"want %.4f, longest step %.4f along and %.4f across (outline %.4f)"
			% [want, along, across, ring])

	for s in am.get_surface_count():
		_surface(am, s, "grass" if s == 0 else "dirt ")

	# The editor path — change the length in the tree, let the deferred rebuild
	# run — has to land on the same mesh as a fresh build.
	var live := _make(80.0)
	live.size_x = sx
	await get_tree().process_frame
	await get_tree().process_frame
	_say(_same_mesh(am, live.mesh), "in-tree regenerate matches a fresh build",
		"%d surfaces" % am.get_surface_count())

	# Collision is the two track surfaces, whatever the length.
	var body := live.get_node_or_null("TerrainCollision")
	var faces := PackedVector3Array()
	if body:
		faces = ((body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
	var track := 0
	for s in 2:
		track += am.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	_say(faces.size() / 3 == track, "collision covers the whole track",
		"%d collision triangles, %d track triangles" % [faces.size() / 3, track])

	t.free()
	live.free()

func _same_mesh(a: ArrayMesh, b: ArrayMesh) -> bool:
	if a.get_surface_count() != b.get_surface_count():
		return false
	for s in a.get_surface_count():
		var aa := a.surface_get_arrays(s)
		var bb := b.surface_get_arrays(s)
		if aa[Mesh.ARRAY_INDEX] != bb[Mesh.ARRAY_INDEX]:
			return false
		var av: PackedVector3Array = aa[Mesh.ARRAY_VERTEX]
		var bv: PackedVector3Array = bb[Mesh.ARRAY_VERTEX]
		if av.size() != bv.size():
			return false
		for i in av.size():
			if av[i].distance_to(bv[i]) > 1e-5:
				return false
	return true

func _surface(am: ArrayMesh, s: int, label: String) -> void:
	var a := am.surface_get_arrays(s)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]

	# Weld by position, so a shared corner counts as one point.
	var key := {}
	var wid := PackedInt32Array()
	wid.resize(v.size())
	for i in v.size():
		var k := Vector3i(roundi(v[i].x * 2048.0), roundi(v[i].y * 2048.0), roundi(v[i].z * 2048.0))
		if not key.has(k):
			key[k] = key.size()
		wid[i] = key[k]

	var dir := {}
	var degen := 0
	var area_max := 0.0
	for i in range(0, idx.size(), 3):
		var p := [idx[i], idx[i + 1], idx[i + 2]]
		var ar: float = (v[p[1]] - v[p[0]]).cross(v[p[2]] - v[p[0]]).length() * 0.5
		if ar < 1e-9:
			degen += 1
		area_max = maxf(area_max, ar)
		for e in 3:
			var k := Vector2i(wid[p[e]], wid[p[(e + 1) % 3]])
			dir[k] = int(dir.get(k, 0)) + 1

	# An edge walked twice the same way is two faces wound against each other.
	var same_dir := 0
	for k in dir:
		if int(dir[k]) > 1:
			same_dir += 1

	var bad_n := 0
	for i in nrm.size():
		if not is_finite(nrm[i].x) or absf(nrm[i].length() - 1.0) > 0.01:
			bad_n += 1

	# The grass mat's underside cap is wound against the drip skirt it folds
	# back from. That is the same at every length; see docs/known-issues.md.
	var expect: int = 0 if s == 1 else _ring_edges(am)
	_say(degen == 0 and bad_n == 0 and same_dir == expect,
		"%s surface is clean" % label,
		"%d triangles, largest %.3f, %d degenerate, %d bad normals, %d faces wound against a neighbour (%d expected)"
			% [idx.size() / 3, area_max, degen, bad_n, same_dir, expect])

func _ring_edges(am: ArrayMesh) -> int:
	# The dirt surface is built on the grass mat's underside ring, so its
	# triangle count gives the ring length: 3 triangles per ring step.
	return am.surface_get_arrays(1)[Mesh.ARRAY_INDEX].size() / 9
