class_name ClayBackland
extends RefCounted

# Continuation of the terrain slab behind the playable track: one clay landform,
# not a backdrop. Its first row of vertices IS the track's rear top edge (same
# outline call, same height noise), so the two weld exactly; from there the
# surface fans out and banks up into grass hills and a closing ridge. Grass
# only — the dirt cutaway stays unique to the track, and the mountains are
# separate objects standing behind this landform.

# Depth out to which the fan keeps the track's own column density. The seam has
# to match the track vertex for vertex or the weld cracks, and the bank just
# behind it is close enough to the camera to need that grain — but carrying
# 3000 columns across a 1000-unit-wide fan all the way to the back of the world
# is most of the mesh for none of the detail, so past this the columns thin out
# and one stitched strip joins the two densities.
const FINE_DEPTH := 12.0
const COARSE_CELL := 1.9

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
var _seam_x := 0.0
var _seam_z := 0.0
var _fine := PackedInt32Array()
var _coarse := PackedInt32Array()
var _stitch := -1


func _init(owner: Node) -> void:
	t = owner

# Surface query for anything that has to be planted on this landform. Reads the
# built grid, so a prop sits on the mesh that is actually drawn.
func height_at(x: float, z: float) -> float:
	if _pos.is_empty():
		return 0.0
	var j := _row_of(z)
	var j2 := mini(j + 1, _pos.size() - 1)
	var z0: float = _row_z(j)
	var z1: float = _row_z(j2)
	var fz: float = 0.0 if absf(z1 - z0) < 0.0001 else clampf((z - z0) / (z1 - z0), 0.0, 1.0)
	return lerpf(_row_y(j, x), _row_y(j2, x), fz)

func _row_z(j: int) -> float:
	return _pos[j][_pos[j].size() / 2].z

func _row_of(z: float) -> int:
	var lo := 0
	var hi := _pos.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if _row_z(m) >= z:
			lo = m
		else:
			hi = m
	return lo

# Height along one row at an arbitrary x. Rows do not all hold the same number
# of columns, so each is searched on its own.
func _row_y(j: int, x: float) -> float:
	var row: PackedVector3Array = _pos[j]
	var last := row.size() - 1
	if x <= row[0].x:
		return row[0].y
	if x >= row[last].x:
		return row[last].y
	var lo := 0
	var hi := last
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if row[m].x <= x:
			lo = m
		else:
			hi = m
	var span: float = row[lo + 1].x - row[lo].x
	var f: float = 0.0 if absf(span) < 0.0001 else (x - row[lo].x) / span
	return lerpf(row[lo].y, row[lo + 1].y, f)

# Analytic, not a grid search: the fan's extent at a depth is exactly the lerp
# the grid columns were laid out with. Planting asks this for every candidate it
# tries, so it has to be O(1).
func has_ground(x: float, z: float) -> bool:
	var d: float = _seam_z - z
	if d < 0.0 or d > t.backland_depth:
		return false
	return absf(x) <= lerpf(_seam_x, _width(d), _spread(d))

# Lay out the landform without emitting anything. Planting reads the grid for
# surface heights, so it is still needed on the runs where the mesh itself was
# loaded from the cache rather than built.
func prepare() -> void:
	var seam: Vector2 = t.rear_edge_point(1.0)
	_seam_x = absf(seam.x)
	_seam_z = seam.y
	_setup_noise()
	_grid()

func build(am: ArrayMesh) -> void:
	prepare()
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
	return lerpf(t.size_x * 0.5, t.landform_half_width(), _spread(d))

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
	# Most rows are in front of it, and the noise lookup is not free.
	if d > 110.0:
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
	# Keyed on how far the point lies BEYOND the track, not on its fraction of the
	# fan's width: as a fraction, the outer fifth of the track's own length got
	# rolled down with it, so the ground sank away alongside a track that stayed
	# level and the two read as disconnected. Ground level with the route stays
	# level with it; only the shoulder past the ends drops.
	var beyond: float = (absf(x) - t.size_x * 0.5) / maxf(t.backland_margin, 1.0)
	y -= t.rim_drop * smoothstep(0.08, 0.80, beyond) * smoothstep(0.0, 70.0, d)
	return y

# The stream bed is pressed into the same clay as everything else: a rounded
# groove with a raised lip either side, wandering across the middle distance.
# Meander wavelengths stay in world units, so a longer stream simply has more
# bends rather than stretched ones; only the slow drift away from camera is
# expressed against the landform's own width.
func _bed_depth(x: float) -> float:
	var hw: float = maxf(t.landform_half_width(), 1.0)
	return 36.0 + 9.0 * sin(x * 0.026) + 4.5 * sin(x * 0.012 + 1.1) + 8.8 * pow(x / hw, 2.0)

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

# The stream runs out before the landform's own edge does, at the same fraction
# of the width whatever the track's length.
func _reach(x: float) -> float:
	var hw: float = maxf(t.landform_half_width(), 1.0)
	return 1.0 - smoothstep(hw * 0.56, hw * 0.80, absf(x))

func _channel(x: float, d: float) -> float:
	if not t.stream_enabled:
		return 0.0
	var reach := _reach(x)
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
	var span: float = t.landform_half_width() * 0.80
	var steps: int = clampi(int(span * 2.0 / 1.36), 60, 1200)
	var across := 7
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var cols := across + 1

	for i in steps + 1:
		var x := lerpf(-span, span, float(i) / float(steps))
		var reach := _reach(x)
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
	# One column list at the track's density for the near rows, one thinned list
	# for everything behind them.
	var stride := clampi(int(round(COARSE_CELL / maxf(2.0 * t.landform_half_width() / float(k_max), 0.0001))), 1, 48)
	_fine = PackedInt32Array()
	for k in k_max + 1:
		_fine.append(k)
	_coarse = PackedInt32Array()
	var k := 0
	while k < k_max:
		_coarse.append(k)
		k += stride
	_coarse.append(k_max)
	if stride <= 1:
		_coarse = _fine

	_pos.clear()
	_stitch = -1
	for j in depths.size():
		var d := depths[j]
		var cols: PackedInt32Array = _fine if d <= FINE_DEPTH else _coarse
		if _stitch < 0 and cols == _coarse and j > 0:
			_stitch = j - 1
		var row := PackedVector3Array()
		for c in cols:
			var u := -1.0 + 2.0 * c / float(k_max)
			var seam: Vector2 = t.rear_edge_point(u)
			var x := lerpf(seam.x, u * _width(d), _spread(d))
			var z := seam.y - d
			row.append(Vector3(x, _height(x, z, d, u), z))
		_pos.append(row)
	_normals()

func _normals() -> void:
	_nrm.clear()
	var rows := _pos.size()
	for j in rows:
		var row := PackedVector3Array()
		row.resize(_pos[j].size())
		_nrm.append(row)
	var cell: float = t.cell_size()
	for j in rows:
		var cols := _pos[j].size()
		var jb := mini(j + 1, rows - 1)
		var jf := maxi(j - 1, 0)
		# Only the one stitched row has neighbours at a different density; every
		# other row can read its neighbours by column index instead of searching
		# them by x, which is most of this loop's cost on a long track.
		var same_b: bool = _pos[jb].size() == cols
		var same_f: bool = _pos[jf].size() == cols
		for k in cols:
			var p := _pos[j][k]
			var dk := _pos[j][mini(k + 1, cols - 1)] - _pos[j][maxi(k - 1, 0)]
			var back := _pos[jb][k] if same_b else Vector3(p.x, _row_y(jb, p.x), _row_z(jb))
			var front := _pos[jf][k] if same_f else Vector3(p.x, _row_y(jf, p.x), _row_z(jf))
			if j == 0:
				# Borrow the track's own slope in front of the seam, so the two
				# surfaces shade as one instead of creasing along the weld.
				front = Vector3(p.x, t.surface_height(p.x, p.z + cell), p.z + cell)
			var n := (back - front).cross(dk)
			if n.dot(Vector3.UP) < 0.0:
				n = -n
			_nrm[j][k] = n.normalized() if n.length() > 0.0 else Vector3.UP

# Winding comes from grid topology, not a world-up hint: k advances +X and j
# advances -Z, so this order is front-facing on every slope however steep.
func _quad(idx: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	idx.append_array([a, c, b, c, d, b])

func _commit_land(am: ArrayMesh) -> void:
	var rows := _pos.size()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var base := PackedInt32Array()
	for j in rows:
		base.append(v.size())
		for k in _pos[j].size():
			v.append(_pos[j][k])
			n.append(_nrm[j][k])

	for j in rows - 1:
		var a := _pos[j].size()
		var b := _pos[j + 1].size()
		if a == b:
			for k in a - 1:
				_quad(idx, base[j] + k, base[j] + k + 1, base[j + 1] + k, base[j + 1] + k + 1)
		else:
			_stitch_rows(idx, base[j], base[j + 1])

	_collar(v, n, idx, base)

	var dv := PackedVector3Array()
	var dn := PackedVector3Array()
	var didx := PackedInt32Array()
	_falloff(v, n, idx, dv, dn, didx, rows, base)

	t.commit_surface(am, v, n, idx, t.grass_color)
	if not didx.is_empty():
		t.commit_surface(am, dv, dn, didx, t.dirt_color)

# A short wall hung straight down from the weld, facing the camera.
#
# The two surfaces share the seam exactly, but a ray that grazes that shared
# edge passes just under the landform and then out through the track's rear
# drips, which face away and are culled — so the world was see-through along a
# hairline at the join. Nothing is wrong with the weld; the wedge beneath it
# simply had no front face. This gives it one. It sits inside the slab behind
# the track's own overhang, so it is only ever seen in that grazing sliver.
func _collar(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, base: PackedInt32Array) -> void:
	var cols := _pos[0].size()
	var drop: float = t.grass_thickness + t.drip_length + 4.0
	var skirt := PackedInt32Array()
	for k in cols:
		var p := _pos[0][k]
		skirt.append(v.size())
		v.append(Vector3(p.x, p.y - drop, p.z))
		n.append(Vector3(0.0, 0.2, 1.0).normalized())
	for k in cols - 1:
		_strip(idx, base[0] + k, base[0] + k + 1, skirt[k], skirt[k + 1])

# The one strip where the fine columns meet the thinned ones. Every fine vertex
# is used, so the two densities share an edge exactly and cannot crack; the
# winding matches _quad's, clockwise in (column, row).
func _stitch_rows(idx: PackedInt32Array, fine_base: int, coarse_base: int) -> void:
	for i in _coarse.size() - 1:
		var a: int = _coarse[i]
		var b: int = _coarse[i + 1]
		for k in range(a, b):
			idx.append_array([fine_base + k, coarse_base + i, fine_base + k + 1])
		idx.append_array([fine_base + b, coarse_base + i, coarse_base + i + 1])

# Where the landform's grass runs out it is built exactly like the track's edge
# and never as a cut sheet: the mat rolls over into irregular drips hung off the
# shared profile, closes back underneath at its own thickness, and stands on a
# real mass of dirt. The seam row is skipped — it is welded to the track, and
# the track's own edge already carries the cutaway.
func _falloff(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array,
		dv: PackedVector3Array, dn: PackedVector3Array, didx: PackedInt32Array,
		rows: int, base: PackedInt32Array) -> void:
	var edge := PackedInt32Array()
	for j in rows:
		edge.append(base[j] + _pos[j].size() - 1)
	for k in range(_pos[rows - 1].size() - 2, -1, -1):
		edge.append(base[rows - 1] + k)
	for j in range(rows - 2, -1, -1):
		edge.append(base[j])

	var m := edge.size()
	var out := PackedVector3Array()
	for i in m:
		var a := v[edge[maxi(i - 1, 0)]]
		var b := v[edge[mini(i + 1, m - 1)]]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var o := Vector3(-dir.z, 0.0, dir.x)
		out.append(o.normalized() if o.length() > 0.0001 else Vector3.RIGHT)

	# Grass sagging over the edge, in the same lobes as the track's overhang.
	var segs: int = maxi(int(t.drip_segments), 1)
	var prev := edge
	for seg in range(1, segs + 1):
		var frac := float(seg) / float(segs)
		# Roll the shading from up, through out, to slightly under.
		var ang := frac * PI * 0.62
		var cur := PackedInt32Array()
		for i in m:
			var p := v[edge[i]]
			var o := out[i]
			var drip: Vector2 = t.drip_profile(p.x, p.z, frac)
			cur.append(v.size())
			v.append(Vector3(p.x + o.x * drip.x, p.y - drip.y, p.z + o.z * drip.x))
			n.append((Vector3.UP * cos(ang) + o * sin(ang)).normalized())
		for i in m - 1:
			_strip(idx, prev[i], prev[i + 1], cur[i], cur[i + 1])
		prev = cur

	# Underside of the mat, closing back in to the dirt footprint.
	var under := PackedInt32Array()
	var foot := PackedInt32Array()
	for i in m:
		var p := v[edge[i]]
		var o := out[i]
		var ix: float = p.x - o.x * t.grass_overhang
		var iz: float = p.z - o.z * t.grass_overhang
		var iy: float = (height_at(ix, iz) if has_ground(ix, iz) else p.y) - t.grass_thickness
		under.append(v.size())
		v.append(Vector3(ix, iy, iz))
		n.append((o * 0.3 - Vector3.UP * 0.9).normalized())
		# Same rim in the dirt surface, plus the foot it stands on.
		foot.append(dv.size())
		dv.append(Vector3(ix, iy, iz))
		dn.append(o)
		dv.append(Vector3(ix, t.backland_floor, iz))
		dn.append(o)
	for i in m - 1:
		_strip(idx, prev[i], prev[i + 1], under[i], under[i + 1])
		_strip(didx, foot[i], foot[i + 1], foot[i] + 1, foot[i + 1] + 1)

# A wall strip below a boundary walked so the land stays on its left; the
# outward face is then fixed, so the order is topological too.
func _strip(idx: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	idx.append_array([a, b, c, b, d, c])
