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

@export_group("Backland")
@export var backland_enabled: bool = false: set = _s29
@export var backland_depth: float = 250.0: set = _s30
@export var backland_width: float = 210.0: set = _s31
@export var backland_floor: float = -40.0: set = _s32
@export var rim_drop: float = 7.0: set = _s33
@export var rim_overhang: float = 1.6: set = _s34
@export var stream_enabled: bool = true: set = _s41
@export var stream_depth: float = 3.4: set = _s42
@export var stream_fill: float = 2.3: set = _s43
@export var water_color: Color = Color(0.25, 0.58, 0.8): set = _s44

@export_group("")
@export_tool_button("Regenerate") var regen_button = generate

var backland: ClayBackland
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
func _s29(v): backland_enabled = v; _dirty()
func _s30(v): backland_depth = v; _dirty()
func _s31(v): backland_width = v; _dirty()
func _s32(v): backland_floor = v; _dirty()
func _s33(v): rim_drop = v; _dirty()
func _s34(v): rim_overhang = v; _dirty()
func _s41(v): stream_enabled = v; _dirty()
func _s42(v): stream_depth = v; _dirty()
func _s43(v): stream_fill = v; _dirty()
func _s44(v): water_color = v; _dirty()

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

# Grain, not a division count. Everything this slab has to resolve — the drip
# lobes, the overhang, the height noise, the fingerprint tile — is fixed in
# world units, so the cell has to be fixed in world units too. Spreading
# `resolution` cells over the whole length instead made the mesh coarser the
# longer the track got: the overhang went low-poly and the top surface banded.
# `resolution` is the cell count across GRAIN_SPAN units, the length the current
# look was authored at.
const GRAIN_SPAN := 80.0

# Arc-uniform samples along one half of an end cap. Only has to beat the grid,
# which takes about 55 steps over the whole cap at the default grain.
const CAP_SAMPLES := 128

# One end cap, walked at equal arc from shoulder to tip to shoulder, and the
# shape it was built for.
var _cap_pts := PackedVector2Array()
var _cap_arc := 0.0
var _cap_key := Vector3.INF

func cell_size() -> float:
	return GRAIN_SPAN / float(maxi(4, resolution))

# How deep each end cap reaches back along the slab. Tied to the half-width, so
# the ends keep their shape and their share of the grid at any length.
func _cap_depth() -> float:
	return minf(size_z, size_x) * 0.5

# Columns span the length, rows span an end cap, both at one cell. The cap's arc
# does not depend on size_x, so neither does the row count: the ends are sampled
# as finely on a 400-long track as on an 80-long one. Columns are counted over
# the whole length, not just the straight run, because the middle rows reach
# through the caps to the tips.
func _grid_divs() -> Vector2i:
	_build_cap()
	var cell := cell_size()
	return Vector2i(maxi(4, int(round(size_x / cell))), maxi(4, int(round(_cap_arc / cell))))

# The cap is a superellipse quarter, and for a blunt one most of its length sits
# in the shoulder. Walking it in x or in z would step straight over that, so it
# is walked in the angle form and then resampled by arc.
func _build_cap() -> void:
	var key := Vector3(size_x, size_z, corner_sharpness)
	if key.is_equal_approx(_cap_key) and not _cap_pts.is_empty():
		return
	_cap_key = key
	var hz := size_z * 0.5
	var cap := _cap_depth()
	var e := maxf(corner_sharpness, 2.0)
	var steps := 2048
	var fine := PackedVector2Array()
	var run := PackedFloat32Array()
	var total := 0.0
	for i in steps + 1:
		var phi := PI * 0.5 * float(i) / float(steps)
		var p := Vector2(cap * pow(cos(phi), 2.0 / e), hz * pow(sin(phi), 2.0 / e))
		if i > 0:
			total += p.distance_to(fine[i - 1])
		fine.append(p)
		run.append(total)
	_cap_arc = total * 2.0

	var half := PackedVector2Array()
	var k := 0
	for j in CAP_SAMPLES + 1:
		var target: float = total * float(j) / float(CAP_SAMPLES)
		while k < steps and run[k + 1] < target:
			k += 1
		var span: float = run[mini(k + 1, steps)] - run[k]
		var f: float = 0.0 if span < 1e-9 else (target - run[k]) / span
		half.append(fine[k].lerp(fine[mini(k + 1, steps)], f))

	_cap_pts = PackedVector2Array()
	for j in range(CAP_SAMPLES, 0, -1):
		_cap_pts.append(Vector2(half[j].x, -half[j].y))
	for j in CAP_SAMPLES + 1:
		_cap_pts.append(half[j])

# Point on one cap for t in [-1, 1]: a shoulder at -1, the tip at 0, the other
# shoulder at +1, spaced evenly along the curve.
func _cap_point(t: float) -> Vector2:
	var last := _cap_pts.size() - 1
	var f: float = clampf((t + 1.0) * 0.5, 0.0, 1.0) * float(last)
	var i := mini(int(f), last - 1)
	return _cap_pts[i].lerp(_cap_pts[i + 1], f - float(i))

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

	# Collision is the playable track only; the landform behind it is scenery.
	var track := ArrayMesh.new()
	for i in am.get_surface_count():
		track.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(i))

	backland = null
	if backland_enabled:
		backland = ClayBackland.new(self)
		backland.build(am)
	mesh = am

	if not Engine.is_editor_hint():
		_build_collision(track)

func _height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * height_scale

# Hand-wobbled footprint, from a point on the unit square's edge: the square's
# two end edges are the slab's end caps and its two long edges are the straight
# sides. Written this way round because the grid is that square — the caps
# always get the row budget and the sides the column budget, so neither can be
# starved by the aspect ratio.
#
# The shape is a straight run closed by superellipse caps rather than one
# superellipse over the whole slab. A single superellipse tapers over a fixed
# *fraction* of the length, so a long track ended in a metre-long spike that no
# fixed row count could describe; a cap is always the same size.
func _outline(q: Vector2) -> Vector2:
	_build_cap()
	var hz := size_z * 0.5
	var cap := _cap_depth()
	var flat: float = size_x * 0.5 - cap
	var p: Vector2
	if absf(q.x) >= absf(q.y):
		var c := _cap_point(q.y)
		p = Vector2(signf(q.x) * (flat + c.x), c.y)
	else:
		p = Vector2(flat * q.x, hz * signf(q.y))
	if edge_wobble == 0.0:
		return p
	return p + _edge_normal(p) * edge_noise.get_noise_2d(p.x, p.y) * edge_wobble

# Outward normal of that footprint: the gradient of
# (max(|x| - flat, 0) / cap)^e + (|z| / hz)^e = 1, which flattens to straight up
# the side once x is inside the straight run.
func _edge_normal(p: Vector2) -> Vector2:
	var hz := maxf(size_z * 0.5, 0.0001)
	var cap := maxf(_cap_depth(), 0.0001)
	var flat: float = size_x * 0.5 - cap
	var e := maxf(corner_sharpness, 2.0)
	var ax: float = maxf(absf(p.x) - flat, 0.0) / cap
	var az: float = absf(p.y) / hz
	var n := Vector2(pow(ax, e - 1.0) * signf(p.x) / cap, pow(az, e - 1.0) * signf(p.y) / hz)
	return n.normalized() if n.length() > 0.0001 else Vector2(0.0, signf(p.y))

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

# Which way an ordered footprint loop turns, in XZ. A wall hung off that loop
# has a winding that follows from this, so it does not need a per-quad normal
# test — and a per-quad test is what fails on the sliver quads at the ends of a
# long slab, where the hint is nowhere near perpendicular to the quad.
func _loop_ccw(pts: PackedVector3Array) -> bool:
	var a := 0.0
	var c := pts.size()
	for i in c:
		var p := pts[i]
		var q := pts[(i + 1) % c]
		a += p.x * q.z - q.x * p.z
	return a > 0.0

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

	var norm := _smooth_normals(v, idx)
	if backland_enabled:
		# The landform behind continues this boundary. Give the rear row the
		# height field's own normal on both sides of the weld, so the drips
		# hanging under it cannot darken the seam into a visible line.
		for k in nx + 1:
			norm[k] = seam_normal(v[k].x, v[k].z)
	_commit(am, v, norm, idx, axis, grass_color)

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

	# Wall and floor winding come from the loop's own turn, not a normal test.
	var ccw := _loop_ccw(ring)
	for i in n:
		var j := (i + 1) % n
		var a := n + i
		var b := n + j
		if ccw:
			idx.append_array([i, a, j, a, b, j])
			idx.append_array([a, centre, b])
		else:
			idx.append_array([i, j, a, j, b, a])
			idx.append_array([a, b, centre])

	_commit(am, v, _smooth_normals(v, idx), idx, axis, dirt_color)

func _build_collision(source: ArrayMesh) -> void:
	var old := get_node_or_null("TerrainCollision")
	if old:
		old.free()
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var cs := CollisionShape3D.new()
	cs.shape = source.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)

# --- Seams for the backland continuation -------------------------------------
# The landform behind the track is built from these, so it shares this slab's
# outline, height field, grain size and materials by construction.

func grid_divs() -> Vector2i:
	return _grid_divs()

func surface_height(x: float, z: float) -> float:
	return _height(x, z)

# The top grid's rear boundary at lateral coordinate u in [-1, 1]: the exact
# vertices the backland's first row has to land on.
func rear_edge_point(u: float) -> Vector2:
	return _outline(Vector2(u, -1.0))

# Analytic normal of the top height field, so both sides of the weld agree.
func seam_normal(x: float, z: float) -> Vector3:
	var c := cell_size()
	var dx := _height(x + c, z) - _height(x - c, z)
	var dz := _height(x, z + c) - _height(x, z - c)
	return Vector3(-dx, 2.0 * c, -dz).normalized()

# Surface of the whole landform in this node's local space, for planting props.
func landform_height(x: float, z: float) -> float:
	if backland and z < -size_z * 0.5:
		return backland.height_at(x, z)
	return _height(x, z)

func stream_distance(x: float, z: float) -> float:
	return backland.bank_distance(x, z) if backland else 99.0

# Local z of a point `e` channel half-widths from the stream centre at this x.
func stream_bank_z(x: float, e: float) -> float:
	return backland.bank_z(x, e) if backland else -size_z * 0.5

# World-space triplanar at the track's own grain size: the slab lays its
# fingerprint over 1/texture_scale^2 units, so the same tile spans the same
# distance on terrain that has no sensible flat projection.
func clay_material(col: Color) -> StandardMaterial3D:
	var m := _mat(col)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * texture_scale * texture_scale
	return m

func water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/clay_water.gdshader")
	m.set_shader_parameter("albedo", water_color)
	m.set_shader_parameter("fingerprint", fingerprint_normal)
	m.set_shader_parameter("grain", 1.0 / maxf(texture_scale * texture_scale, 0.0001) * 0.35)
	m.set_shader_parameter("relief", 9.0)
	return m

func commit_surface(am: ArrayMesh, v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array,
		col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in v.size():
		st.set_normal(n[i])
		st.set_uv(Vector2(v[i].x, v[i].z) * texture_scale)
		st.add_vertex(v[i])
	for i in idx:
		st.add_index(i)
	st.generate_tangents()
	st.set_material(clay_material(col))
	st.commit(am)
