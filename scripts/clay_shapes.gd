class_name ClayShapes
extends RefCounted

# Small hand-made props, built as clay rather than imported as geometry.
#
# Two primitives: a lumpy ball for masses (rocks, bush lobes, blooms) and a
# swept strand for anything long (grass blades, stems, leaves). The strand is a
# real tapered tube pushed along a bend, not a row of beads, so a blade reads as
# one continuous piece of clay with a point on the end.

# --- lumpy ball --------------------------------------------------------------

static func _blob(st: SurfaceTool, base: int, rng: RandomNumberGenerator, centre: Vector3, r: Vector3,
		lumps: int, amp: float, rings: int = 11, segs: int = 15) -> int:
	var seeds: Array[Vector3] = []
	var gains := PackedFloat32Array()
	for i in lumps:
		seeds.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized())
		gains.append(rng.randf_range(-1.0, 1.0))

	var v := PackedVector3Array()
	for a in rings + 1:
		var phi := PI * float(a) / float(rings)
		for b in segs:
			var th := TAU * float(b) / float(segs)
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var w := 0.0
			for i in lumps:
				w += gains[i] * pow(maxf(d.dot(seeds[i]), 0.0), 2.5)
			v.append(centre + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * (1.0 + amp * w))

	var idx := PackedInt32Array()
	for a in rings:
		for b in segs:
			var b2 := (b + 1) % segs
			idx.append_array([a * segs + b, (a + 1) * segs + b, a * segs + b2,
				a * segs + b2, (a + 1) * segs + b, (a + 1) * segs + b2])

	var n := PackedVector3Array()
	n.resize(v.size())
	for i in range(0, idx.size(), 3):
		var fn := (v[idx[i + 1]] - v[idx[i]]).cross(v[idx[i + 2]] - v[idx[i]])
		n[idx[i]] += fn
		n[idx[i + 1]] += fn
		n[idx[i + 2]] += fn
	for i in v.size():
		var nn: Vector3 = n[i]
		st.set_normal((-nn).normalized() if nn.length() > 0.0 else Vector3.UP)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v[i])
	for i in idx:
		st.add_index(base + i)
	return base + v.size()

# --- swept strand ------------------------------------------------------------

# One continuous strand of clay: a flattened tube swept along a bend that leans
# toward `dir`, sags by `droop`, and tapers to a rounded point. `wide` squashes
# the section across the bend so a blade reads as a blade rather than a wire.
static func _strand(st: SurfaceTool, base: int, root: Vector3, dir: Vector3, height: float,
		bend: float, droop: float, width: float, wide: float,
		rows: int = 7, segs: int = 7) -> int:
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.0001 else Vector3.RIGHT

	var centres := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in rows + 1:
		var u := float(i) / float(rows)
		centres.append(root + Vector3.UP * height * (u - droop * u * u) + dir * (bend * height * u * u))
		# Slightly bellied near the root, tapering to nothing at the tip.
		radii.append(width * (1.0 - u * u * 0.92) * (0.85 + 0.3 * sin(u * PI)))

	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for i in centres.size():
		var ahead: Vector3 = centres[mini(i + 1, centres.size() - 1)]
		var back: Vector3 = centres[maxi(i - 1, 0)]
		var tan := (ahead - back)
		tan = tan.normalized() if tan.length() > 0.0001 else Vector3.UP
		var face := tan.cross(side).normalized()
		var rx: float = radii[i] * wide
		var ry: float = radii[i]
		for s in segs:
			var th := TAU * float(s) / float(segs)
			v.append(centres[i] + side * (rx * cos(th)) + face * (ry * sin(th)))
			n.append((side * (ry * cos(th)) + face * (rx * sin(th))).normalized())

	var tip := v.size()
	var last: Vector3 = centres[centres.size() - 1]
	var tip_dir := (last - centres[centres.size() - 2])
	tip_dir = tip_dir.normalized() if tip_dir.length() > 0.0001 else Vector3.UP
	v.append(last)
	n.append(tip_dir)

	for i in v.size():
		st.set_normal(n[i])
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v[i])

	# Front faces are clockwise, so this order shows the outward wall of the tube.
	for i in rows:
		for s in segs:
			var s2 := (s + 1) % segs
			st.add_index(base + i * segs + s)
			st.add_index(base + (i + 1) * segs + s)
			st.add_index(base + i * segs + s2)
			st.add_index(base + i * segs + s2)
			st.add_index(base + (i + 1) * segs + s)
			st.add_index(base + (i + 1) * segs + s2)
	for s in segs:
		var s2 := (s + 1) % segs
		st.add_index(base + rows * segs + s)
		st.add_index(base + tip)
		st.add_index(base + rows * segs + s2)
	return base + v.size()

static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_tangents()
	return st.commit()

# --- props -------------------------------------------------------------------

# A rounded boulder: pressed down, tilted, sometimes with a smaller stone
# leaning on it or stacked on top, never a ball.
static func rock(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := Vector3(size, size * rng.randf_range(0.55, 0.95), size * rng.randf_range(0.7, 1.2))
	var base := _blob(st, 0, rng, Vector3(0.0, r.y * 0.55, 0.0), r, 6, 0.34, 13, 18)
	for i in rng.randi_range(0, 2):
		var s := size * rng.randf_range(0.28, 0.58)
		var a := rng.randf() * TAU
		var at := Vector3(cos(a) * size * 0.75, s * 0.55, sin(a) * size * 0.75)
		if rng.randf() < 0.4:
			at = Vector3(cos(a) * size * 0.22, r.y * 1.05 + s * 0.5, sin(a) * size * 0.22)
		base = _blob(st, base, rng, at, Vector3(s, s * rng.randf_range(0.6, 0.9), s), 5, 0.32, 10, 14)
	return _finish(st)

# A bush: a few overlapping thumbs of clay squashed into a mound.
static func bush(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rng.randi_range(3, 5)
	var base := 0
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.4, 0.4)
		var off := rng.randf_range(0.15, 0.5) * size
		var s := size * rng.randf_range(0.55, 0.85)
		base = _blob(st, base, rng, Vector3(cos(a) * off, s * rng.randf_range(0.55, 0.9), sin(a) * off),
			Vector3(s, s * 0.85, s), 4, 0.26, 11, 15)
	return _finish(st)

# A tuft: each blade a single swept strand arcing out and over from the clump,
# at its own height, lean and droop.
static func tuft(rng: RandomNumberGenerator, size: float, blades: int, lean: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	var spin := rng.randf() * TAU
	for i in blades:
		var a := spin + TAU * float(i) / float(blades) + rng.randf_range(-0.5, 0.5)
		var dir := Vector3(cos(a), 0.0, sin(a))
		base = _strand(st, base, dir * size * rng.randf_range(0.0, 0.16), dir,
			size * rng.randf_range(0.6, 1.35),
			lean * rng.randf_range(0.5, 1.5), rng.randf_range(0.10, 0.42),
			size * rng.randf_range(0.085, 0.125), 2.1)
	return _finish(st)

# A flower: one bent stem with a leaf or two, and a bloom pressed onto the tip.
# Surface 0 is the plant, surface 1 the bloom, so the two take different clays.
static func flower(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var h := size * rng.randf_range(1.7, 2.6)
	var sway := rng.randf() * TAU
	var dir := Vector3(cos(sway), 0.0, sin(sway))
	var bend := rng.randf_range(0.12, 0.36)
	var droop := rng.randf_range(0.06, 0.22)

	var stalk := SurfaceTool.new()
	stalk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := _strand(stalk, 0, Vector3.ZERO, dir, h, bend, droop, size * 0.085, 1.2, 7, 7)
	for i in rng.randi_range(1, 2):
		var la := sway + PI + rng.randf_range(-1.2, 1.2)
		var ldir := Vector3(cos(la), 0.0, sin(la))
		base = _strand(stalk, base, Vector3.UP * h * rng.randf_range(0.18, 0.45), ldir,
			size * rng.randf_range(0.34, 0.55), rng.randf_range(1.2, 2.1),
			rng.randf_range(0.5, 0.95), size * 0.105, 2.8, 5, 6)
	var am := _finish(stalk)

	var top := Vector3.UP * h * (1.0 - droop) + dir * (bend * h)
	var bloom := SurfaceTool.new()
	bloom.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petals := rng.randi_range(5, 7)
	var pr := size * rng.randf_range(0.18, 0.26)
	var pbase := 0
	for i in petals:
		var a := TAU * float(i) / float(petals) + rng.randf_range(-0.18, 0.18)
		pbase = _blob(bloom, pbase, rng, top + Vector3(cos(a) * pr * 1.15, -pr * 0.12, sin(a) * pr * 1.15),
			Vector3(pr, pr * 0.6, pr), 2, 0.22, 8, 11)
	_blob(bloom, pbase, rng, top + Vector3(0.0, pr * 0.28, 0.0),
		Vector3(pr * 0.7, pr * 0.6, pr * 0.7), 2, 0.15, 8, 11)
	bloom.generate_tangents()
	bloom.commit(am)
	return am

# The pad of clay pushed up round a planted trunk, so nothing looks dropped in.
static func mound(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blob(st, 0, rng, Vector3.ZERO, Vector3(size, size * 0.42, size), 5, 0.28, 9, 14)
	return _finish(st)
