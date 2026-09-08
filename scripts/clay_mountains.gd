@tool
extends MeshInstance3D

# The range behind the landform, built as one height field rather than a row of
# cones. Each mountain is described by a crest line — a short polyline of points
# with a height and a flank width — so the large forms are the ones real
# mountains have: a summit, ridges running off it, saddles between tops, and
# flanks that fall away at different angles on each side. Everything is then
# blurred, which is what turns those forms into plasticine: broad blunt surfaces
# and rounded crests, with no small detail anywhere.
#
# Snow is a second sheet over the same field. It is clipped to a wandering
# contour, lifted along the surface normal, and closed by a lip that rolls over
# and comes back down onto the rock a little way downhill — so it sags on the
# slopes it is thickest on and can never read as a floating shell.

# Cell of the range's own grid, and how far past the track's ends it reaches.
const CELL := 1.6
const SHOULDER := 420.0
const SPACING := 168.0
const Z_NEAR := -212.0
const Z_FAR := -348.0
const BLUR := 3

# Crest lines in unit space: x across, z into the screen, height as a fraction
# of the mountain's own height. Each is a silhouette you could name.
const FORMS := {
	"horn": [Vector3(-0.62, -0.18, 0.36), Vector3(-0.16, -0.04, 0.86), Vector3(0.04, 0.0, 1.0),
		Vector3(0.46, 0.16, 0.44), Vector3(0.86, 0.30, 0.16)],
	"crest": [Vector3(-1.15, 0.14, 0.24), Vector3(-0.62, 0.02, 0.86), Vector3(-0.22, -0.04, 0.62),
		Vector3(0.26, -0.02, 0.97), Vector3(0.82, 0.10, 0.44), Vector3(1.25, 0.20, 0.18)],
	"shoulder": [Vector3(-0.92, 0.10, 0.22), Vector3(-0.26, -0.02, 1.0), Vector3(0.24, -0.06, 0.70),
		Vector3(0.74, -0.04, 0.63), Vector3(1.30, 0.10, 0.20)],
	"twin": [Vector3(-0.86, 0.10, 0.22), Vector3(-0.42, 0.0, 0.92), Vector3(-0.02, 0.10, 0.50),
		Vector3(0.40, -0.02, 1.0), Vector3(0.88, 0.12, 0.26)],
	"saddle": [Vector3(-1.05, 0.04, 0.30), Vector3(-0.55, -0.02, 0.78), Vector3(0.0, 0.06, 0.40),
		Vector3(0.55, -0.02, 0.70), Vector3(1.05, 0.06, 0.26)],
	"dome": [Vector3(-0.80, 0.02, 0.44), Vector3(-0.10, -0.02, 0.80), Vector3(0.62, 0.04, 0.52),
		Vector3(1.05, 0.10, 0.22)],
}

@export var terrain_path: NodePath = ^"../Terrain": set = _s0
@export var rock_color: Color = Color(0.55, 0.55, 0.58): set = _s1
@export var snow_color: Color = Color(0.94, 0.95, 0.97): set = _s2
@export_range(0.0, 1.0) var snow_line: float = 0.62: set = _s3
@export var snow_thickness: float = 3.4: set = _s4
@export var snow_wobble: float = 8.5: set = _s5
@export var snow_tongue: float = 16.0: set = _s6
@export var snow_drip: float = 10.0: set = _s7
@export var grain: float = 30.0: set = _s10
@export var fingerprint_strength: float = 14.0: set = _s11
@export_range(0.0, 1.0) var roughness: float = 0.92: set = _s12
@export var range_seed: int = 12: set = _s14
@export var fingerprint_normal: Texture2D = preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png"): set = _s13

@export_tool_button("Regenerate") var regen_button = generate

var _wob := FastNoiseLite.new()
var _sag := FastNoiseLite.new()
var _queued := false

var _cols := 0
var _rows := 0
var _x0 := 0.0
var _h := PackedFloat32Array()
var _top := PackedFloat32Array()
var _nrm := PackedVector3Array()

func _s0(v): terrain_path = v; _dirty()
func _s1(v): rock_color = v; _dirty()
func _s2(v): snow_color = v; _dirty()
func _s3(v): snow_line = v; _dirty()
func _s4(v): snow_thickness = v; _dirty()
func _s5(v): snow_wobble = v; _dirty()
func _s6(v): snow_tongue = v; _dirty()
func _s7(v): snow_drip = v; _dirty()
func _s10(v): grain = v; _dirty()
func _s11(v): fingerprint_strength = v; _dirty()
func _s12(v): roughness = v; _dirty()
func _s13(v): fingerprint_normal = v; _dirty()
func _s14(v): range_seed = v; _dirty()

func _ready() -> void:
	generate()

func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE

func _dirty() -> void:
	if not is_node_ready() or _queued:
		return
	_queued = true
	_regen.call_deferred()

func _regen() -> void:
	_queued = false
	generate()

func _half_span() -> float:
	var t := get_node_or_null(terrain_path)
	var half: float = (t.size_x * 0.5) if t and "size_x" in t else 40.0
	return half + SHOULDER

func _idx(c: int, r: int) -> int:
	return r * _cols + c

func _pos(c: int, r: int) -> Vector3:
	return Vector3(_x0 + float(c) * CELL, _h[_idx(c, r)], Z_NEAR - float(r) * CELL)

# Stations march across the span, alternating a major summit with something
# lower, and no silhouette repeats twice running.
func _compose() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = range_seed
	var span := _half_span()
	var names: Array = FORMS.keys()
	var out: Array = []
	var x := -span - 40.0
	var major := true
	var last := ""
	while x < span + 40.0:
		var form: String = names[rng.randi() % names.size()]
		if form == last or (major and form == "dome"):
			form = names[(names.find(form) + 1) % names.size()]
		last = form
		var h: float = rng.randf_range(86.0, 116.0) if major else rng.randf_range(46.0, 70.0)
		if form == "dome":
			h *= 0.62
		var rx: float = h * rng.randf_range(0.70, 0.95)
		var flip: float = 1.0 if rng.randf() < 0.5 else -1.0
		var lean := rng.randf_range(-0.10, 0.10)
		var nodes := PackedVector3Array()
		var wid := PackedFloat32Array()
		var cz: float = rng.randf_range(-296.0, -252.0)
		for u in FORMS[form]:
			var f: Vector3 = u
			nodes.append(Vector3(x + f.x * rx * flip + f.z * lean * rx,
				cz + f.y * rx * 0.8, f.z * h))
			# Flanks are wider where the crest is lower, so ridges taper.
			wid.append(rx * (0.42 + 0.34 * (1.0 - f.z)))
		out.append({
			"nodes": nodes, "wid": wid, "peak": h,
			"base": rng.randf_range(12.0, 22.0),
			# Below 1 the flanks are concave and the form reads steep; the blur
			# afterwards is what blunts the crest.
			"sharp": rng.randf_range(0.82, 1.10),
			"bias": rng.randf_range(-0.30, 0.30),
		})
		x += SPACING * rng.randf_range(0.70, 1.30)
		major = not major
	return out

func _smax(a: float, b: float, k: float) -> float:
	var t := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(a, b, t) + k * t * (1.0 - t)

# Rasterise one mountain into the shared field, only over the cells it can
# reach. `_top` keeps the height of whichever mountain owns each cell, so the
# snow line can be a fraction of that summit rather than one flat altitude.
func _stamp(m: Dictionary) -> void:
	var nodes: PackedVector3Array = m.nodes
	var wid: PackedFloat32Array = m.wid
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in nodes.size():
		var w: float = wid[i] * 1.35
		lo.x = minf(lo.x, nodes[i].x - w)
		hi.x = maxf(hi.x, nodes[i].x + w)
		lo.y = minf(lo.y, nodes[i].y - w)
		hi.y = maxf(hi.y, nodes[i].y + w)
	var c0 := clampi(int(floor((lo.x - _x0) / CELL)), 0, _cols - 1)
	var c1 := clampi(int(ceil((hi.x - _x0) / CELL)), 0, _cols - 1)
	var r0 := clampi(int(floor((Z_NEAR - hi.y) / CELL)), 0, _rows - 1)
	var r1 := clampi(int(ceil((Z_NEAR - lo.y) / CELL)), 0, _rows - 1)

	for r in range(r0, r1 + 1):
		var pz := Z_NEAR - float(r) * CELL
		for c in range(c0, c1 + 1):
			var px := _x0 + float(c) * CELL
			var best := 0.0
			for i in nodes.size() - 1:
				var a: Vector3 = nodes[i]
				var b: Vector3 = nodes[i + 1]
				var ax := b.x - a.x
				var az := b.y - a.y
				var len2: float = ax * ax + az * az
				var t: float = 0.0 if len2 < 1e-6 else clampf(((px - a.x) * ax + (pz - a.y) * az) / len2, 0.0, 1.0)
				var qx: float = a.x + ax * t
				var qz: float = a.y + az * t
				var dx: float = px - qx
				var dz: float = pz - qz
				var d := sqrt(dx * dx + dz * dz)
				# Which side of the crest, so one flank can run out further.
				var side: float = signf(ax * dz - az * dx)
				var w: float = lerpf(wid[i], wid[i + 1], t) * (1.0 + float(m.bias) * side)
				if w < 0.001 or d >= w:
					continue
				var crest: float = lerpf(a.z, b.z, t)
				best = maxf(best, crest * pow(1.0 - d / w, float(m.sharp)))
			if best <= 0.0:
				continue
			var k := _idx(c, r)
			var y: float = float(m.base) + best
			var was := _h[k]
			_h[k] = _smax(was, y, 6.0)
			if y > was:
				_top[k] = float(m.base) + float(m.peak)

func _build_field() -> void:
	var span := _half_span() + 60.0
	_x0 = -span
	_cols = maxi(8, int(ceil(2.0 * span / CELL)) + 1)
	_rows = maxi(8, int(ceil((Z_NEAR - Z_FAR) / CELL)) + 1)
	_h = PackedFloat32Array()
	_h.resize(_cols * _rows)
	_top = PackedFloat32Array()
	_top.resize(_cols * _rows)
	for m in _compose():
		_stamp(m)

	# Blur: this is the step that makes them plasticine. It rounds every crest
	# and flank into a broad blunt surface while leaving the large forms alone.
	# Separable: two three-tap passes instead of one nine-tap, same result.
	for pass_i in BLUR:
		var src := _h.duplicate()
		for r in _rows:
			var row := r * _cols
			for c in _cols:
				_h[row + c] = (src[row + maxi(c - 1, 0)] + src[row + c] * 2.0
					+ src[row + mini(c + 1, _cols - 1)]) * 0.25
		src = _h.duplicate()
		for r in _rows:
			var up := maxi(r - 1, 0) * _cols
			var dn := mini(r + 1, _rows - 1) * _cols
			var row := r * _cols
			for c in _cols:
				_h[row + c] = (src[up + c] + src[row + c] * 2.0 + src[dn + c]) * 0.25

	_nrm = PackedVector3Array()
	_nrm.resize(_cols * _rows)
	for r in _rows:
		for c in _cols:
			var dx: float = _h[_idx(mini(c + 1, _cols - 1), r)] - _h[_idx(maxi(c - 1, 0), r)]
			var dz: float = _h[_idx(c, mini(r + 1, _rows - 1))] - _h[_idx(c, maxi(r - 1, 0))]
			_nrm[_idx(c, r)] = Vector3(-dx, 2.0 * CELL, dz).normalized()

func generate() -> void:
	_wob.seed = range_seed + 91
	_wob.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wob.frequency = 0.018
	_wob.fractal_octaves = 2

	_sag.seed = range_seed + 137
	_sag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_sag.frequency = 0.016
	_sag.fractal_octaves = 2

	_build_field()
	var am := ArrayMesh.new()
	_mesh_rock(am)
	_mesh_snow(am)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = am

# Winding from grid topology: c advances +X, r advances -Z.
func _quad(idx: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	idx.append_array([a, c, b, c, d, b])

func _mesh_rock(am: ArrayMesh) -> void:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for r in _rows:
		for c in _cols:
			v.append(_pos(c, r))
			n.append(_nrm[_idx(c, r)])
	for r in _rows - 1:
		for c in _cols - 1:
			_quad(idx, _idx(c, r), _idx(c + 1, r), _idx(c, r + 1), _idx(c + 1, r + 1))
	# Skirt round the field, dropping below the landform that stands in front.
	var edge := PackedInt32Array()
	for c in _cols:
		edge.append(_idx(c, 0))
	for r in range(1, _rows):
		edge.append(_idx(_cols - 1, r))
	for c in range(_cols - 2, -1, -1):
		edge.append(_idx(c, _rows - 1))
	for r in range(_rows - 2, 0, -1):
		edge.append(_idx(0, r))
	var foot := PackedInt32Array()
	for i in edge.size():
		var p := v[edge[i]]
		foot.append(v.size())
		v.append(Vector3(p.x, -40.0, p.z))
		n.append(Vector3(0.0, 0.0, 1.0))
	for i in edge.size() - 1:
		idx.append_array([edge[i], edge[i + 1], foot[i], edge[i + 1], foot[i + 1], foot[i]])
	_commit(am, v, n, idx, rock_color)

# Height of the snow field at a grid node: positive inside the snow.
func _snow_at(c: int, r: int) -> float:
	var k := _idx(c, r)
	if _top[k] <= 0.0:
		return -1.0
	var p := _pos(c, r)
	var line: float = _top[k] * snow_line
	line += _wob.get_noise_2d(p.x, p.z) * snow_wobble
	# Tongues, stretched along z so they run down the slopes that face us.
	var n01: float = _sag.get_noise_2d(p.x, p.z * 0.32) * 0.5 + 0.5
	line -= snow_tongue * pow(n01, 2.2)
	return p.y - line

func _lerp_node(c0: int, r0: int, c1: int, r1: int, w: float) -> Array:
	return [_pos(c0, r0).lerp(_pos(c1, r1), w),
		_nrm[_idx(c0, r0)].lerp(_nrm[_idx(c1, r1)], w).normalized()]

# Height of the rock at an arbitrary column, so a drip's foot lands on it.
func _rock_at(x: float, z: float) -> float:
	var fc := clampf((x - _x0) / CELL, 0.0, float(_cols - 1))
	var fr := clampf((Z_NEAR - z) / CELL, 0.0, float(_rows - 1))
	var c := int(fc)
	var r := int(fr)
	var c2 := mini(c + 1, _cols - 1)
	var r2 := mini(r + 1, _rows - 1)
	var tx := fc - float(c)
	var tz := fr - float(r)
	return lerpf(lerpf(_h[_idx(c, r)], _h[_idx(c2, r)], tx),
		lerpf(_h[_idx(c, r2)], _h[_idx(c2, r2)], tx), tz)

func _mesh_snow(am: ArrayMesh) -> void:
	var f := PackedFloat32Array()
	f.resize(_cols * _rows)
	for r in _rows:
		for c in _cols:
			f[_idx(c, r)] = _snow_at(c, r)

	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	# Reverse-cyclic corner walk, so a fan over it matches the rock's winding.
	var corner := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]

	for r in _rows - 1:
		for c in _cols - 1:
			# Most of the field carries no snow at all; skipping those cells before
			# any array is built is what keeps this loop off the critical path.
			var f0: float = f[_idx(c, r)]
			if f0 <= 0.0 and f[_idx(c, r + 1)] <= 0.0 \
					and f[_idx(c + 1, r)] <= 0.0 and f[_idx(c + 1, r + 1)] <= 0.0:
				continue
			var poly: Array = []
			for i in 4:
				var a: Vector2i = corner[i]
				var b: Vector2i = corner[(i + 1) % 4]
				var fa: float = f[_idx(c + a.x, r + a.y)]
				var fb: float = f[_idx(c + b.x, r + b.y)]
				if fa > 0.0:
					poly.append([_pos(c + a.x, r + a.y), _nrm[_idx(c + a.x, r + a.y)], fa, false])
				if (fa > 0.0) != (fb > 0.0):
					var w: float = fa / (fa - fb)
					var lp := _lerp_node(c + a.x, r + a.y, c + b.x, r + b.y, w)
					poly.append([lp[0], lp[1], 0.0, true])
			if poly.size() >= 3:
				_sheet(v, n, idx, poly)
	if idx.is_empty():
		return
	_commit(am, v, n, idx, snow_color)

# One clipped cell of the sheet: the covered polygon lifted along the surface
# normal, and where its own edge falls, a lip that bulges out and then comes
# back down onto the rock a little way downhill — the same idea as the track's
# grass overhang, so the snow sags rather than ending in a wall.
func _sheet(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, poly: Array) -> void:
	var m := poly.size()
	var top := PackedInt32Array()
	var centre := Vector3.ZERO
	for i in m:
		var p: Vector3 = poly[i][0]
		var nn: Vector3 = poly[i][1]
		var d: float = poly[i][2]
		var thick: float = snow_thickness * (0.55 + 0.45 * clampf(d / 9.0, 0.0, 1.0))
		top.append(v.size())
		v.append(p + nn * thick)
		n.append(nn)
		centre += p
	centre /= float(m)
	for i in range(1, m - 1):
		idx.append_array([top[0], top[i], top[i + 1]])

	for i in m:
		var j := (i + 1) % m
		if not (poly[i][3] and poly[j][3]):
			continue
		_drip(v, n, idx, poly[i], poly[j], top[i], top[j], centre)

# The lip below the contour. Everything about it is a function of the contour
# point alone — how far it runs, which way it sags — never of the cell it came
# from, so neighbouring cells produce the same two points where their contours
# meet and the lip is one continuous skirt. Deriving it per edge instead left a
# comb of loose ribbons hanging off the snowline.
# Thickness down the roll-off, from the contour to where the sheet runs out.
# It thins the whole way instead of standing proud: a lip that bulges out reads
# as a separate shell stuck on the mountain rather than snow lying against it.
const ROLL := [0.72, 0.34, 0.06]

func _lip_at(p: Vector3, nrm: Vector3) -> Array:
	var dh := Vector3(-nrm.x, 0.0, -nrm.z)
	dh = dh.normalized() if dh.length() > 0.0001 else Vector3.FORWARD
	var lobe: float = _sag.get_noise_2d(p.x, p.z) * 0.5 + 0.5
	var run: float = snow_drip * (0.2 + 0.8 * lobe * lobe)
	var out: Array = []
	for i in ROLL.size():
		var f: float = float(i + 1) / float(ROLL.size())
		var x: float = p.x + dh.x * run * f
		var z: float = p.z + dh.z * run * f
		out.append(Vector3(x, _rock_at(x, z) + snow_thickness * ROLL[i], z))
	out.append(dh)
	return out

func _drip(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array,
		pa: Array, pb: Array, ta: int, tb: int, _centre: Vector3) -> void:
	var la := _lip_at(pa[0], pa[1])
	var lb := _lip_at(pb[0], pb[1])
	var away: Vector3 = (la[ROLL.size()] + lb[ROLL.size()]).normalized()
	var col_a := PackedInt32Array([ta])
	var col_b := PackedInt32Array([tb])
	for i in ROLL.size():
		# Normals lean further under as the sheet thins, so the roll-off shades
		# as a rounded edge settling onto the rock.
		var lean: float = float(i + 1) / float(ROLL.size())
		col_a.append(v.size())
		v.append(la[i])
		n.append((pa[1] + away * lean * 0.9).normalized())
		col_b.append(v.size())
		v.append(lb[i])
		n.append((pb[1] + away * lean * 0.9).normalized())
	# Marching squares walks some cells the other way round, so each rung is
	# turned to face out and down the slope rather than trusting its order.
	for i in ROLL.size():
		_face_quad(v, idx, col_a[i], col_b[i], col_a[i + 1], col_b[i + 1],
			away * 0.5 + Vector3.UP * (1.0 - 0.25 * float(i)))

# Emit a quad wound so its visible face points along `want`.
func _face_quad(v: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int, d: int, want: Vector3) -> void:
	if (v[b] - v[a]).cross(v[c] - v[a]).dot(want) > 0.0:
		idx.append_array([a, c, b, c, d, b])
	else:
		idx.append_array([a, b, c, b, d, c])

# Handed over as finished arrays. The material is triplanar, so these surfaces
# carry no unwrap to derive a tangent from and SurfaceTool's generator was only
# producing a degenerate frame at considerable cost; a stable frame taken off
# the normal is what the triplanar normal map wants anyway.
func _commit(am: ArrayMesh, v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array,
		col: Color, two_sided: bool = false) -> void:
	var tan := PackedFloat32Array()
	tan.resize(v.size() * 4)
	var uv := PackedVector2Array()
	uv.resize(v.size())
	for i in v.size():
		var nn: Vector3 = n[i]
		var t := Vector3.RIGHT - nn * nn.dot(Vector3.RIGHT)
		if t.length_squared() < 0.000001:
			t = Vector3.BACK - nn * nn.dot(Vector3.BACK)
		t = t.normalized() if t.length_squared() > 0.000001 else Vector3.RIGHT
		tan[i * 4] = t.x
		tan[i * 4 + 1] = t.y
		tan[i * 4 + 2] = t.z
		tan[i * 4 + 3] = 1.0
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(am.get_surface_count() - 1, _mat(col, two_sided))

func _mat(col: Color, two_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	m.metallic = 0.0
	m.metallic_specular = 0.12
	m.roughness = roughness
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / maxf(grain, 0.001)
	if fingerprint_normal:
		m.normal_enabled = true
		m.normal_texture = fingerprint_normal
		m.normal_scale = fingerprint_strength
	return m
