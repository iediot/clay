class_name ClayBackland
extends RefCounted

# Continuation of the terrain slab behind the playable track: one clay landform,
# not a backdrop. Its first row of vertices IS the track's rear top edge (same
# outline call, same height noise), so the two weld exactly; from there the
# surface fans out and banks up into grass hills and a closing ridge. Grass
# only — the dirt cutaway stays unique to the track, and the mountains are
# separate objects standing behind this landform.

const RIM_START := 0.80

# Row spacing bands: [depth_to, step]. Dense against the seam so the bank reads,
# coarse once the land is far enough away to be silhouette only.
const BANDS := [
	[10.0, 0.7],
	[52.0, 2.0],
	[210.0, 2.4],
	[250.0, 9.0],
]

var t: Node
var _hill := FastNoiseLite.new()
var _lump := FastNoiseLite.new()
var _swell := FastNoiseLite.new()


var _pos: Array[PackedVector3Array] = []
var _nrm: Array[PackedVector3Array] = []


func _init(owner: Node) -> void:
	t = owner

# Surface query for anything that has to be planted on this landform. Reads the
# built grid, so a prop sits on the mesh that is actually drawn.
func height_at(x: float, z: float) -> float:
	var c := _cell(x, z)
	if c.x < 0:
		return 0.0
	var j: int = c.x
	var k: int = c.y
	var x0: float = _pos[j][k].x
	var x1: float = _pos[j][k + 1].x
	var z0: float = _pos[j][k].z
	var z1: float = _pos[j + 1][k].z
	var fx: float = 0.0 if absf(x1 - x0) < 0.0001 else clampf((x - x0) / (x1 - x0), 0.0, 1.0)
	var fz: float = 0.0 if absf(z1 - z0) < 0.0001 else clampf((z - z0) / (z1 - z0), 0.0, 1.0)
	var a := lerpf(_pos[j][k].y, _pos[j][k + 1].y, fx)
	var b := lerpf(_pos[j + 1][k].y, _pos[j + 1][k + 1].y, fx)
	return lerpf(a, b, fz)

func _cell(x: float, z: float) -> Vector2i:
	if _pos.is_empty():
		return Vector2i(-1, -1)
	var rows := _pos.size()
	var cols := _pos[0].size()
	var mid := cols / 2
	if z > _pos[0][mid].z or z < _pos[rows - 1][mid].z:
		return Vector2i(-1, -1)
	var lo := 0
	var hi := rows - 1
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if _pos[m][mid].z >= z:
			lo = m
		else:
			hi = m
	if x < _pos[lo][0].x or x > _pos[lo][cols - 1].x:
		return Vector2i(-1, -1)
	var klo := 0
	var khi := cols - 1
	while khi - klo > 1:
		var m := (klo + khi) / 2
		if _pos[lo][m].x <= x:
			klo = m
		else:
			khi = m
	return Vector2i(lo, klo)

func build(am: ArrayMesh) -> void:
	_setup_noise()
	_grid()
	_commit_land(am)
	if t.stream_enabled:
		_commit_water(am)

func _setup_noise() -> void:
	_hill.seed = t.noise_seed + 311
	_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hill.frequency = 0.011
	_hill.fractal_octaves = 3
	_hill.fractal_gain = 0.45

	_lump.seed = t.noise_seed + 407
	_lump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lump.frequency = 0.035
	_lump.fractal_octaves = 2

	_swell.seed = t.noise_seed + 733
	_swell.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_swell.frequency = 0.0055
	_swell.fractal_octaves = 2

func _row_depths() -> PackedFloat32Array:
	var d := PackedFloat32Array([0.0])
	var cur := 0.0
	for b in BANDS:
		var to: float = minf(b[0], t.backland_depth)
		var step: float = b[1]
		while cur < to - 0.0001:
			cur = minf(cur + step, to)
			d.append(cur)
		if cur >= t.backland_depth:
			break
	return d

# Lateral fan. The seam row keeps the track's own rear outline; behind it the
# land opens out to the full landmass width.
func _spread(d: float) -> float:
	return pow(smoothstep(0.0, t.backland_depth * 0.28, d), 0.4)

func _width(d: float) -> float:
	return lerpf(t.size_x * 0.5, t.backland_width, _spread(d))

# Ground profile behind the track: a close bank the track edge climbs into, then
# a long rise toward the mountain feet.
func _base(d: float) -> float:
	return 1.5 * smoothstep(0.0, 5.0, d) + 3.0 * smoothstep(5.0, 40.0, d) + 5.0 * smoothstep(40.0, 140.0, d)

func _hills(x: float, z: float, d: float) -> float:
	var amp := minf(2.1 + 0.095 * d, 12.0)
	var y := _hill.get_noise_2d(x, z) * amp + _lump.get_noise_2d(x, z) * 1.2
	# Broad swells, so the near ground has knolls to overlap rather than a ramp.
	y += _swell.get_noise_2d(x, z) * minf(0.8 + 0.075 * d, 8.0)
	# Low ridge closing the far side, so the peaks stand on land rather than air.
	var ridge := smoothstep(110.0, 190.0, d)
	y += ridge * 13.0 * (0.5 + 0.5 * _hill.get_noise_2d(x * 0.55, z * 0.55 - 400.0))
	return y

func _height(x: float, z: float, d: float, u: float) -> float:
	return _land(x, z, d, u) + _channel(x, d)

func _land(x: float, z: float, d: float, u: float) -> float:
	# Seam gate: every backland term is zero at d = 0, so the first row is
	# exactly the track's rear edge.
	var gate := smoothstep(0.0, 2.5, d)
	var y: float = t.surface_height(x, z) * (1.0 - smoothstep(0.0, 30.0, d))
	y += (_base(d) + _hills(x, z, d)) * gate
	# Roll the outer rim down so the landmass reads as a sculpted, finite object.
	y -= t.rim_drop * smoothstep(RIM_START, 1.0, absf(u)) * smoothstep(0.0, 14.0, d)
	return y

# The stream bed is pressed into the same clay as everything else: a rounded
# groove with a raised lip either side, wandering across the middle distance.
func _bed_depth(x: float) -> float:
	return 36.0 + 9.0 * sin(x * 0.026) + 4.5 * sin(x * 0.012 + 1.1) + 0.00020 * x * x

func _bed_half(x: float) -> float:
	return 14.0 + 3.6 * sin(x * 0.045 + 0.7)

# How far a point is from the stream centre, in channel half-widths. Used to
# keep planting out of the water.
func bank_z(x: float, e: float) -> float:
	return -t.size_z * 0.5 - (_bed_depth(x) + e * _bed_half(x))

func bank_distance(x: float, z: float) -> float:
	if not t.stream_enabled:
		return 99.0
	var d: float = -t.size_z * 0.5 - z
	return absf(d - _bed_depth(x)) / _bed_half(x)

func _channel(x: float, d: float) -> float:
	if not t.stream_enabled:
		return 0.0
	var reach := 1.0 - smoothstep(118.0, 168.0, absf(x))
	if reach <= 0.0:
		return 0.0
	var e: float = (d - _bed_depth(x)) / _bed_half(x)
	var y := 0.0
	if absf(e) < 1.0:
		y -= t.stream_depth * pow(cos(e * PI * 0.5), 1.6)
	var lip: float = (absf(e) - 1.12) / 0.42
	y += t.stream_depth * 0.22 * exp(-lip * lip)
	# The far bank is lifted, so the camera looks into the channel instead of
	# skimming a flat ribbon.
	y += t.stream_depth * 0.55 * smoothstep(0.75, 2.4, e)
	return y * reach

# The water itself: a ribbon lying in the groove, its edges tucked under the
# banks so the channel shape reads rather than a flat strip laid on the field.
func _commit_water(am: ArrayMesh) -> void:
	var span := 150.0
	var steps := 220
	var across := 7
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var cols := across + 1

	for i in steps + 1:
		var x := lerpf(-span, span, float(i) / float(steps))
		var reach := 1.0 - smoothstep(118.0, 168.0, absf(x))
		var cd := _bed_depth(x)
		var hw := _bed_half(x) * 0.82
		var u: float = clampf(x / maxf(_width(cd), 1.0), -1.0, 1.0)
		var floor_y: float = _land(x, -t.size_z * 0.5 - cd, cd, u) - t.stream_depth * reach
		for k in cols:
			var e := -1.0 + 2.0 * float(k) / float(across)
			var d := cd + e * hw
			v.append(Vector3(x, floor_y + t.stream_fill * reach, -t.size_z * 0.5 - d))
			n.append(Vector3.UP)

	for i in steps:
		for k in across:
			var a := i * cols + k
			var b := i * cols + k + 1
			var c := (i + 1) * cols + k
			var d2 := (i + 1) * cols + k + 1
			idx.append_array([a, b, c, b, d2, c])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in v.size():
		st.set_normal(n[i])
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v[i])
	for i in idx:
		st.add_index(i)
	st.generate_tangents()
	st.set_material(t.water_material())
	st.commit(am)

func _grid() -> void:
	var depths := _row_depths()
	var k_max: int = t.grid_divs().x
	_pos.clear()
	for j in depths.size():
		var d := depths[j]
		var row := PackedVector3Array()
		for k in k_max + 1:
			var u := -1.0 + 2.0 * k / float(k_max)
			var seam: Vector2 = t.rear_edge_point(u)
			var x := lerpf(seam.x, u * _width(d), _spread(d))
			var z := seam.y - d
			row.append(Vector3(x, _height(x, z, d, u), z))
		_pos.append(row)
	_normals()

func _normals() -> void:
	_nrm.clear()
	var rows := _pos.size()
	var cols := _pos[0].size()
	for j in rows:
		var row := PackedVector3Array()
		row.resize(cols)
		_nrm.append(row)
	var cell: float = t.cell_size()
	for j in rows:
		for k in cols:
			var p := _pos[j][k]
			var dk := _pos[j][mini(k + 1, cols - 1)] - _pos[j][maxi(k - 1, 0)]
			var back := _pos[mini(j + 1, rows - 1)][k]
			var front := _pos[maxi(j - 1, 0)][k]
			if j == 0:
				# Borrow the track's own slope in front of the seam, so the two
				# surfaces shade as one instead of creasing along the weld.
				front = Vector3(p.x, t.surface_height(p.x, p.z + cell), p.z + cell)
			var dj := back - front
			var n := dj.cross(dk)
			if n.dot(Vector3.UP) < 0.0:
				n = -n
			_nrm[j][k] = n.normalized() if n.length() > 0.0 else Vector3.UP

# Winding comes from grid topology, not a world-up hint: k advances +X and j
# advances -Z, so this order is front-facing on every slope however steep.
func _quad(idx: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	idx.append_array([a, c, b, c, d, b])

func _commit_land(am: ArrayMesh) -> void:
	var rows := _pos.size()
	var cols := _pos[0].size()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in rows:
		for k in cols:
			v.append(_pos[j][k])
			n.append(_nrm[j][k])
	for j in rows - 1:
		for k in cols - 1:
			_quad(idx, j * cols + k, j * cols + k + 1, (j + 1) * cols + k, (j + 1) * cols + k + 1)
	_rim(v, n, idx, rows, cols)
	t.commit_surface(am, v, n, idx, t.grass_color)

# Rolled clay edge round the free sides of the landmass: the same idea as the
# track's grass overhang, minus the cutaway, then a skirt down out of sight.
# The seam row is left open — it is welded to the track.
func _rim(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, rows: int, cols: int) -> void:
	var edge := PackedInt32Array()
	for j in rows:
		edge.append(j * cols + cols - 1)
	for k in range(cols - 2, -1, -1):
		edge.append((rows - 1) * cols + k)
	for j in range(rows - 2, -1, -1):
		edge.append(j * cols)

	var m := edge.size()
	var out := PackedVector3Array()
	for i in m:
		var a := v[edge[maxi(i - 1, 0)]]
		var b := v[edge[mini(i + 1, m - 1)]]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var o := Vector3(-dir.z, 0.0, dir.x)
		out.append(o.normalized() if o.length() > 0.0001 else Vector3.RIGHT)

	var lip := PackedInt32Array()
	var foot := PackedInt32Array()
	for i in m:
		var p := v[edge[i]]
		var o := out[i]
		var sag: float = t.rim_overhang * (0.55 + 0.45 * (_lump.get_noise_2d(p.x, p.z) * 0.5 + 0.5))
		lip.append(v.size())
		v.append(p + o * sag * 0.8 - Vector3(0.0, sag, 0.0))
		n.append((o + Vector3.UP * 0.35).normalized())
		foot.append(v.size())
		v.append(Vector3(p.x + o.x * sag * 0.3, t.backland_floor, p.z + o.z * sag * 0.3))
		n.append(o)

	for i in m - 1:
		_strip(idx, edge[i], edge[i + 1], lip[i], lip[i + 1])
		_strip(idx, lip[i], lip[i + 1], foot[i], foot[i + 1])

# A wall strip below a boundary walked so the land stays on its left; the
# outward face is then fixed, so the order is topological too.
func _strip(idx: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	idx.append_array([a, b, c, b, d, c])
