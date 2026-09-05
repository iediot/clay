class_name ClayDeform
extends RefCounted

# Plastic landing deformation for the clay player. Visual only: it swaps the
# imported StandardMaterial3D surfaces for one shared deformation shader and
# drives its world-space field, so the body and the face meshes riding it
# deform together.
#
# A landing presses a facet into the ball and that shape is kept, in the ball's
# own frame, until rolling works it out again. Nothing here decays with time.

const SHADER := "res://shaders/clay_deform.gdshader"
const DENTS := 4

# World units one fingerprint tile spans. `terrain_generator.gd` lays its own
# fingerprint map out over 1/texture_scale^2 units, so matching that keeps the
# clay grain the same size on the character as on the ground it rolls over.
var fingerprint_size := 69.4
# Relief depth for that grain. The imported materials ask for 30, which was
# authored for the much finer tiling; the terrain uses its own fingerprint_strength.
var fingerprint_relief := 16.0

# Landing speeds below min_speed leave no mark; ref_speed presses a full facet.
var min_speed := 2.0
var ref_speed := 11.0
# Deepest single facet, as a fraction of the ball's radius.
var dent_max := 0.26
# Clay pushed out of a facet swells around its rim by this much of the depth.
var bulge_gain := 0.8
# Ground-contact travel that fully remoulds a full-depth facet. A facet only
# collects this while it is passing through the contact patch, and one pass is
# worth roughly 0.7 of it, so a deep facet needs several turns to work out.
var knead_contact := 4.5
# The contact patch, as cosines between a facet's axis and the ground direction:
# kneading fades in from the edge and is at full strength under the ball.
var contact_edge := 0.88
var contact_core := 0.99
# Facets nearer than this (cosine) deepen an existing one instead of taking a slot.
var merge_dot := 0.86
# Ground contact also works the whole ball smoother, but only ever this far, and
# only slowly: the sculpted lumps stay readable however long the ball rolls.
var round_max := 0.55
var round_length := 90.0

var _mats: Array[ShaderMaterial] = []
var _radmap: PackedFloat32Array
var _celldir: PackedVector3Array
var _radius := 1.0

# Facet state, in the body's rest frame so it rides along as the ball rolls.
var _axis: Array[Vector3] = []
var _base: PackedFloat32Array
var _depth: PackedFloat32Array
var _depth0: PackedFloat32Array
# Contact travel each facet has taken, and how far the ball has rolled on ground.
var _knead: PackedFloat32Array

var _round := 0.0
var _contact_roll := 0.0
var _shift := Vector3.ZERO

func setup(nodes: Array, radmap: PackedFloat32Array, celldir: PackedVector3Array, radius: float) -> void:
	_radmap = radmap
	_celldir = celldir
	_radius = radius
	_base.resize(DENTS)
	_depth.resize(DENTS)
	_depth0.resize(DENTS)
	_knead.resize(DENTS)
	for i in DENTS:
		_axis.append(Vector3.UP)

	var sh: Shader = load(SHADER)
	for n in nodes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("albedo", src.albedo_color)
			m.set_shader_parameter("roughness", src.roughness)
			m.set_shader_parameter("specular", src.metallic_specular)
			m.set_shader_parameter("normal_tex", src.normal_texture)
			m.set_shader_parameter("normal_scale", fingerprint_relief if src.normal_enabled else 0.0)
			m.set_shader_parameter("rough_tex", src.roughness_texture)
			m.set_shader_parameter("rough_mask", _channel_mask(src.roughness_texture_channel))
			m.set_shader_parameter("uv_scale", src.uv1_scale * _uv_scale_for(mi, i))
			m.set_shader_parameter("uv_offset", src.uv1_offset)
			m.set_shader_parameter("field_radius", _radius)
			mi.set_surface_override_material(i, m)
			_mats.append(m)

# Each surface has its own imported unwrap, so each needs its own factor to land
# on one shared world-space fingerprint size.
func _uv_scale_for(mi: MeshInstance3D, surface: int) -> float:
	var arr: Array = mi.mesh.surface_get_arrays(surface)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if uv.is_empty() or idx.size() < 3:
		return 1.0
	# Every eighth triangle is plenty to get the area ratio.
	var wa := 0.0
	var ua := 0.0
	for t in range(0, idx.size() - 2, 24):
		var a: int = idx[t]
		var b: int = idx[t + 1]
		var c: int = idx[t + 2]
		wa += (v[b] - v[a]).cross(v[c] - v[a]).length()
		ua += absf((uv[b] - uv[a]).cross(uv[c] - uv[a]))
	if ua <= 0.0:
		return 1.0
	var s: Vector3 = mi.global_transform.basis.get_scale()
	var lin: float = pow(maxf(s.x * s.y * s.z, 0.0001), 1.0 / 3.0)
	return sqrt(wa / ua) * lin / maxf(fingerprint_size, 0.0001)

# Called on the air-to-floor transition, with the downward speed lost to it and
# the world direction the ball was pressed in.
func land(contact: Vector3, body_off: Basis, speed: float) -> void:
	var k := clampf((speed - min_speed) / maxf(ref_speed - min_speed, 0.0001), 0.0, 1.0)
	if k <= 0.0:
		return
	var dir := (body_off.inverse() * contact).normalized()
	var add := dent_max * _radius * k

	# Landing on ground the ball is already flattened against deepens that facet
	# rather than carving a second one beside it.
	var slot := -1
	for i in DENTS:
		if _depth[i] > 0.0 and _axis[i].dot(dir) >= merge_dot:
			slot = i
			break
	if slot < 0:
		slot = _spare_slot()
		_depth[slot] = 0.0
		_axis[slot] = dir
		# Measure the surface this landing actually met, other facets included.
		_base[slot] = _extent(dir, slot)

	_depth[slot] = minf(_depth[slot] + add, dent_max * _radius)
	_depth0[slot] = _depth[slot]
	_knead[slot] = 0.0

# Being pressed against the ground is the only thing that remoulds the clay.
# `contact` is the world direction the ball is pressed in, or zero while
# airborne; `distance` is how far it travelled this step. A facet is worked only
# while it is the part actually rolling through that contact patch, so one on the
# side or the top is left alone however far the ball travels.
func knead(distance: float, body_off: Basis, contact: Vector3) -> void:
	if distance <= 0.0 or contact.length_squared() < 0.0001:
		return
	var down := contact.normalized()

	# Rolling on the ground also works the whole surface gradually smoother.
	_contact_roll += distance
	_round = round_max * (1.0 - exp(-_contact_roll / maxf(round_length, 0.0001)))

	for i in DENTS:
		if _depth0[i] <= 0.0:
			continue
		var w := smoothstep(contact_edge, contact_core, (body_off * _axis[i]).dot(down))
		if w <= 0.0:
			continue
		_knead[i] += distance * w
		var span := knead_contact * clampf(_depth0[i] / maxf(dent_max * _radius, 0.0001), 0.35, 1.0)
		var ease := clampf(_knead[i] / maxf(span, 0.0001), 0.0, 1.0)
		_depth[i] = _depth0[i] * (1.0 - ease)
		if ease >= 1.0:
			_depth0[i] = 0.0

func update(centre: Vector3, body_off: Basis, contact: Vector3) -> void:
	if _mats.is_empty():
		return

	var axes := PackedVector4Array()
	var form := PackedVector4Array()
	var active := false
	for i in DENTS:
		var world: Vector3 = (body_off * _axis[i]).normalized()
		if _depth[i] <= 0.0001:
			# Park the slot far outside the ball so its clamp is a no-op.
			axes.append(Vector4(world.x, world.y, world.z, 1e3))
			form.append(Vector4(1e-5, 0.0, 1.0, 0.0))
			continue
		active = true
		var plane: float = _base[i] - _depth[i]
		axes.append(Vector4(world.x, world.y, world.z, plane))
		form.append(Vector4(maxf(_depth[i] * 0.8, 1e-5), bulge_gain * _depth[i],
			clampf(plane / _radius, -1.0, 1.0), 0.0))

	# Collision stays a sphere, so the visual ball has to be placed back onto the
	# ground itself: match the deformed silhouette's reach to the original one.
	_shift = Vector3.ZERO
	if (active or _round > 0.0) and contact.length_squared() > 0.0001:
		var down := (body_off.inverse() * contact.normalized())
		_shift = contact.normalized() * (_extent_plain(down) - _extent(down, -1))

	for m in _mats:
		m.set_shader_parameter("field_centre", centre)
		m.set_shader_parameter("field_shift", _shift)
		m.set_shader_parameter("rounding", _round)
		m.set_shader_parameter("dent_axis", axes)
		m.set_shader_parameter("dent_form", form)

# How far the sculpted ball reaches along a direction in its own frame, before
# any of this runs. Ground contact was set up against this shape, so it is what
# the deformed silhouette gets placed back onto.
func _extent_plain(q: Vector3) -> float:
	var best := -1e20
	for c in _radmap.size():
		if _celldir[c].dot(q) > 0.0:
			best = maxf(best, _radmap[c] * _celldir[c].dot(q))
	return best

# The same reach for the deformed ball. `skip` leaves one facet out, so a fresh
# landing can measure the surface it actually met.
func _extent(q: Vector3, skip: int) -> float:
	var best := -1e20
	for c in _radmap.size():
		var dir: Vector3 = _celldir[c]
		if dir.dot(q) <= 0.0:
			continue
		var r: Vector3 = (dir * _radmap[c]).lerp(dir * _radius, _round)
		for i in DENTS:
			if i != skip and _depth[i] > 0.0001:
				r = _press(r, dir, i)
		best = maxf(best, r.dot(q))
	return best

# The shader's facet press, in the body's rest frame. Kept in step with
# clay_deform.gdshader so ground contact matches what is actually drawn.
func _press(r: Vector3, nrm: Vector3, i: int) -> Vector3:
	if _depth[i] <= 0.0001:
		return r
	var plane: float = _base[i] - _depth[i]
	var h: float = r.dot(_axis[i])
	var lat: Vector3 = r - h * _axis[i]
	h = _smin(h, plane, maxf(_depth[i] * 0.8, 1e-5))
	var d: float = nrm.dot(_axis[i]) - clampf(plane / _radius, -1.0, 1.0)
	var ll := lat.length()
	if ll > 1e-4:
		lat += (lat / ll) * (bulge_gain * _depth[i]) * exp(-(d * d) / 0.0338)
	return lat + h * _axis[i]

func _smin(a: float, b: float, k: float) -> float:
	var d := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - d * d * k * 0.25

# Prefer an empty slot, else the facet that rolling has almost worked out.
func _spare_slot() -> int:
	var best := 0
	for i in DENTS:
		if _depth[i] <= 0.0001:
			return i
		if _depth[i] < _depth[best]:
			best = i
	return best

func _channel_mask(ch: int) -> Plane:
	match ch:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Plane(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Plane(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Plane(0.0, 0.0, 0.0, 1.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Plane(0.3333, 0.3333, 0.3333, 0.0)
		_:
			return Plane(1.0, 0.0, 0.0, 0.0)
