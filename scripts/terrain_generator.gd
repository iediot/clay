@tool
extends MeshInstance3D

@export_group("Shape")
@export var size_x: float = 80.0: set = _s1
@export var size_z: float = 8.0: set = _s2
@export var resolution: int = 110: set = _s3
@export var depth: float = 30.0: set = _s4
@export var corner_sharpness: float = 4.0: set = _s5
@export var edge_wobble: float = 0.7: set = _s6
@export var edge_wobble_scale: float = 0.05: set = _s7

@export_group("Grass overhang")
@export var grass_overhang: float = 1.0: set = _s8
@export var grass_thickness: float = 0.8: set = _s9
@export var drip_length: float = 4.2: set = _s10
@export var drip_scale: float = 0.14: set = _s11
@export var drip_bias: float = 0.05: set = _s12
@export_range(0.0, 1.0) var drip_min: float = 0.3: set = _s28
@export var drip_segments: int = 6: set = _s13
@export var drip_bulge: float = 0.3: set = _s14
@export var drip_taper: float = 0.5: set = _s15

@export_group("Clay noise")
@export var noise_frequency: float = 0.045: set = _s16
@export var noise_octaves: int = 2: set = _s17
@export var noise_gain: float = 0.4: set = _s18
@export var height_scale: float = 2.5: set = _s19
@export var noise_seed: int = 0: set = _s20

@export_group("Look")
@export var grass_color: Color = Color(0.36, 0.72, 0.19): set = _s21
@export var dirt_color: Color = Color(0.62, 0.4, 0.21): set = _s22
@export var fingerprint_strength: float = 16.0: set = _s23
@export var texture_scale: float = 0.12: set = _s24
@export var triplanar: bool = false: set = _s27
@export_range(0.0, 1.0) var roughness: float = 0.9: set = _s25
@export var fingerprint_normal: Texture2D = preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png"): set = _s26

@export_group("")
@export_tool_button("Regenerate") var regen_button = generate

var noise := FastNoiseLite.new()
var edge_noise := FastNoiseLite.new()
var drip_noise := FastNoiseLite.new()
var _queued := false

func _s1(v): size_x = v; _dirty()
func _s2(v): size_z = v; _dirty()
func _s3(v): resolution = maxi(4, v); _dirty()
func _s4(v): depth = v; _dirty()
func _s5(v): corner_sharpness = maxf(2.0, v); _dirty()
func _s6(v): edge_wobble = v; _dirty()
func _s7(v): edge_wobble_scale = v; _dirty()
func _s8(v): grass_overhang = v; _dirty()
func _s9(v): grass_thickness = v; _dirty()
func _s10(v): drip_length = v; _dirty()
func _s11(v): drip_scale = v; _dirty()
func _s12(v): drip_bias = v; _dirty()
func _s13(v): drip_segments = maxi(1, v); _dirty()
func _s14(v): drip_bulge = v; _dirty()
func _s15(v): drip_taper = v; _dirty()
func _s16(v): noise_frequency = v; _dirty()
func _s17(v): noise_octaves = maxi(1, v); _dirty()
func _s18(v): noise_gain = v; _dirty()
func _s19(v): height_scale = v; _dirty()
func _s20(v): noise_seed = v; _dirty()
func _s21(v): grass_color = v; _dirty()
func _s22(v): dirt_color = v; _dirty()
func _s23(v): fingerprint_strength = v; _dirty()
func _s24(v): texture_scale = v; _dirty()
func _s25(v): roughness = v; _dirty()
func _s26(v): fingerprint_normal = v; _dirty()
func _s27(v): triplanar = v; _dirty()
func _s28(v): drip_min = v; _dirty()

func _ready():
	generate()

# Keep the generated mesh out of the .tscn; it is rebuilt on load.
func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE

func _dirty():
	if not is_node_ready() or _queued:
		return
	_queued = true
	_regen.call_deferred()

func _regen():
	_queued = false
	generate()

func _grid_divs() -> Vector2i:
	var cell: float = maxf(size_x, size_z) / float(maxi(4, resolution))
	return Vector2i(maxi(4, int(ceil(size_x / cell))), maxi(4, int(ceil(size_z / cell))))

func generate():
	noise.seed = noise_seed
	noise.frequency = noise_frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = noise_octaves
	noise.fractal_gain = noise_gain

	edge_noise.seed = noise_seed + 101
	edge_noise.frequency = edge_wobble_scale
	edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	edge_noise.fractal_octaves = 2

	drip_noise.seed = noise_seed + 202
	drip_noise.frequency = drip_scale
	drip_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	drip_noise.fractal_octaves = 2

	var am := ArrayMesh.new()
	var ring := _build_grass(am)
	_build_dirt(am, ring)
	mesh = am

	if not Engine.is_editor_hint():
		_build_collision()

func _height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * height_scale

# Hand-wobbled footprint. A superellipse is used rather than a rounded
# rectangle: it has no tangent break, so the wobble cannot notch the outline.
func _outline(dir: Vector2) -> Vector2:
	var hx := size_x * 0.5
	var hz := size_z * 0.5
	var e := maxf(corner_sharpness, 2.0)
	var t := pow(pow(absf(dir.x), e) + pow(absf(dir.y), e), 1.0 / e)
	if t < 0.0001:
		return Vector2.ZERO
	var sx := dir.x / t
	var sz := dir.y / t
	var p := Vector2(hx * sx, hz * sz)
	var grad := Vector2(pow(absf(sx), e - 1.0) * signf(sx) / hx, pow(absf(sz), e - 1.0) * signf(sz) / hz)
	var n := grad.normalized() if grad.length() > 0.0001 else p.normalized()
	return p + n * edge_noise.get_noise_2d(p.x, p.y) * edge_wobble

# Godot front-faces are clockwise, so the visible normal is -(geometric CCW normal).
func _push_quad(idx: PackedInt32Array, v: PackedVector3Array, a: int, b: int, c: int, d: int, want: Vector3) -> void:
	if (v[b] - v[a]).cross(v[c] - v[a]).dot(want) > 0.0:
		idx.append_array([a, c, b, c, d, b])
	else:
		idx.append_array([a, b, c, b, d, c])

func _smooth_normals(v: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(v.size())
	for i in range(0, idx.size(), 3):
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var fn := (v[b] - v[a]).cross(v[c] - v[a])
		n[a] += fn
		n[b] += fn
		n[c] += fn
	for i in n.size():
		n[i] = (-n[i]).normalized() if n[i].length() > 0.0 else Vector3.UP
	return n

func _outward(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var c := pts.size()
	for i in c:
		var pv := pts[(i - 1 + c) % c]
		var nx := pts[(i + 1) % c]
		var t := Vector2(nx.x - pv.x, nx.z - pv.z).normalized()
		var o := Vector2(t.y, -t.x)
		if o.dot(Vector2(pts[i].x, pts[i].z)) < 0.0:
			o = -o
		out.append(Vector3(o.x, 0.0, o.y))
	return out

func _commit(am: ArrayMesh, v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, axis: PackedInt32Array, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in v.size():
		st.set_normal(n[i])
		st.set_uv(_uv(v[i], axis[i]))
		st.add_vertex(v[i])
	for i in idx:
		st.add_index(i)
	st.generate_tangents()
	st.set_material(_mat(col))
	st.commit(am)

# Projection axis is fixed per vertex when it is built, so a triangle never
# interpolates between two different projections.
func _axis_of(out: Vector3) -> int:
	return 1 if absf(out.x) >= absf(out.z) else 2

func _uv(p: Vector3, axis: int) -> Vector2:
	match axis:
		1: return Vector2(p.z, -p.y) * texture_scale
		2: return Vector2(p.x, -p.y) * texture_scale
	return Vector2(p.x, p.z) * texture_scale

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.0
	m.metallic_specular = 0.15
	m.roughness = roughness
	m.uv1_triplanar = triplanar
	m.uv1_scale = Vector3.ONE * texture_scale
	if fingerprint_normal:
		m.normal_enabled = true
		m.normal_texture = fingerprint_normal
		m.normal_scale = fingerprint_strength
	return m

func _build_grass(am: ArrayMesh) -> PackedVector3Array:
	var div := _grid_divs()
	var nx := div.x
	var nz := div.y
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var axis := PackedInt32Array()

	# Top surface: a grid warped onto the rounded footprint.
	for z in nz + 1:
		for x in nx + 1:
			var u := -1.0 + 2.0 * x / nx
			var w := -1.0 + 2.0 * z / nz
			var r := maxf(absf(u), absf(w))
			var xz := Vector2.ZERO if r < 0.0001 else _outline(Vector2(u / r, w / r)) * r
			v.append(Vector3(xz.x, _height(xz.x, xz.y), xz.y))
			axis.append(0)

	for z in nz:
		for x in nx:
			_push_quad(idx, v, z * (nx + 1) + x, z * (nx + 1) + x + 1,
				(z + 1) * (nx + 1) + x, (z + 1) * (nx + 1) + x + 1, Vector3.UP)

	# Ordered boundary loop of that grid.
	var ring_id := PackedInt32Array()
	for x in nx:
		ring_id.append(x)
	for z in nz:
		ring_id.append(z * (nx + 1) + nx)
	for x in nx:
		ring_id.append(nz * (nx + 1) + (nx - x))
	for z in nz:
		ring_id.append((nz - z) * (nx + 1))

	var ring_pos := PackedVector3Array()
	for i in ring_id:
		ring_pos.append(v[i])
	var out := _outward(ring_pos)
	var n := ring_id.size()

	# Drips: big lobes of grass sagging over the edge, continuous with the top.
	var prev := ring_id
	for s in range(1, drip_segments + 1):
		var frac := float(s) / drip_segments
		var cur := PackedInt32Array()
		for i in n:
			var p := ring_pos[i]
			var n01 := drip_noise.get_noise_2d(p.x, p.z) * 0.5 + 0.5
			var lobe := drip_min + (1.0 - drip_min) * smoothstep(0.0, 1.0, clampf(n01 + drip_bias, 0.0, 1.0))
			var dep := grass_thickness + lobe * drip_length
			var radial := drip_bulge * sin(frac * PI) - drip_taper * frac * frac
			cur.append(v.size())
			v.append(Vector3(p.x + out[i].x * radial, p.y - dep * frac, p.z + out[i].z * radial))
			axis.append(_axis_of(out[i]))
		for i in n:
			var j := (i + 1) % n
			_push_quad(idx, v, prev[i], prev[j], cur[i], cur[j], out[i])
		prev = cur

	# Underside of the grass mat, closing back to the dirt footprint.
	var under := PackedInt32Array()
	for i in n:
		var p := ring_pos[i]
		var ix := p.x - out[i].x * grass_overhang
		var iz := p.z - out[i].z * grass_overhang
		under.append(v.size())
		v.append(Vector3(ix, _height(ix, iz) - grass_thickness, iz))
		axis.append(0)

	for i in n:
		var j := (i + 1) % n
		# This cap is nearly vertical, so DOWN alone is an unstable winding hint.
		_push_quad(idx, v, prev[i], prev[j], under[i], under[j], (out[i] + Vector3.DOWN).normalized())

	_commit(am, v, _smooth_normals(v, idx), idx, axis, grass_color)

	var dirt_ring := PackedVector3Array()
	for i in under:
		dirt_ring.append(v[i])
	return dirt_ring

func _build_dirt(am: ArrayMesh, ring: PackedVector3Array) -> void:
	var n := ring.size()
	var floor_y := minf(-depth, -height_scale - grass_thickness - drip_length - 1.0)
	var out := _outward(ring)
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var axis := PackedInt32Array()

	for i in n:
		v.append(ring[i])
		axis.append(_axis_of(out[i]))

	for i in n:
		v.append(Vector3(ring[i].x, floor_y, ring[i].z))
		axis.append(_axis_of(out[i]))

	var centre := v.size()
	v.append(Vector3(0.0, floor_y, 0.0))
	axis.append(0)

	for i in n:
		var j := (i + 1) % n
		_push_quad(idx, v, i, j, n + i, n + j, out[i])
		var a := n + i
		var b := n + j
		if (v[b] - v[a]).cross(v[centre] - v[a]).dot(Vector3.DOWN) > 0.0:
			idx.append_array([a, centre, b])
		else:
			idx.append_array([a, b, centre])

	_commit(am, v, _smooth_normals(v, idx), idx, axis, dirt_color)

func _build_collision() -> void:
	var old := get_node_or_null("TerrainCollision")
	if old:
		old.free()
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
