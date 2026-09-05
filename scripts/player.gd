extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 9

const MAP_U := 48
const MAP_V := 24

@export var roll_radius: float = 0.0
@export var face_lead_angle: float = 0.45
@export var face_lead_speed: float = 6.0
@export var face_idle_delay: float = 1.0
@export var face_return_time: float = 0.9
@export var face_rest_span: float = 0.3
@export var face_clearance: float = 0.02
@export var face_lift_speed: float = 4.0
@export var fingerprint_size: float = 69.4
@export var fingerprint_relief: float = 16.0
@export var land_ref_speed: float = 11.0
@export var land_dent_max: float = 0.26
@export var land_bulge: float = 0.8
@export var land_knead_contact: float = 4.5
@export var land_round_max: float = 0.55
@export var land_round_length: float = 90.0

@onready var _model: Node3D = $PlayerModel

var _radius: float
var _pivot: Vector3
var _prev_pos: Vector3

var _body: Array = []
var _face: Array = []
var _home: Dictionary = {}
var _m: Transform3D
var _m_inv: Transform3D

var _body_off := Basis.IDENTITY
var _face_roll := Basis.IDENTITY
var _lead := 0.0
var _idle := 0.0

var _radmap: PackedFloat32Array
var _samples: PackedVector3Array
var _face_dir := Vector3.FORWARD
var _lift := 0.0
var _pen_home := 0.0

var _celldir: PackedVector3Array
var _deform: ClayDeform
var _air := 0.0
var _contact := Vector3.DOWN

func _ready() -> void:
	_m = _model.transform
	_m_inv = _m.affine_inverse()
	_split_meshes()
	_pivot = _body_centre()
	_radius = roll_radius if roll_radius > 0.0 else _contact_radius()
	_build_surface_map()
	_pen_home = _penetration(Basis.IDENTITY, Vector3.ZERO, 0.0)
	_prev_pos = global_position
	_setup_deform()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta * 1.8

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("ui_left", "ui_right")
	velocity.x = direction * SPEED
	velocity.z = 0.0

	var was_floor := is_on_floor()
	var fall := -velocity.y
	move_and_slide()

	if is_on_floor():
		_contact = -get_floor_normal()
		# Only a real air-to-floor transition counts, so jump input and brief
		# contact flicker on the generated terrain never trigger a landing.
		if not was_floor and _air > 0.08:
			_deform.land(_contact, _body_off, fall)
		_air = 0.0
	else:
		_air += delta

	_spin(delta, direction)
	_deform.update(global_transform * _pivot, _body_off, _contact)

func _setup_deform() -> void:
	var acc := 0.0
	var cnt := 0
	for r in _radmap:
		if r > 0.0:
			acc += r
			cnt += 1
	_deform = ClayDeform.new()
	_deform.fingerprint_size = fingerprint_size
	_deform.fingerprint_relief = fingerprint_relief
	_deform.ref_speed = land_ref_speed
	_deform.dent_max = land_dent_max
	_deform.bulge_gain = land_bulge
	_deform.knead_contact = land_knead_contact
	_deform.round_max = land_round_max
	_deform.round_length = land_round_length
	_deform.setup(_body + _face, _radmap, _celldir, acc / maxf(float(cnt), 1.0))

func _spin(delta: float, direction: float) -> void:
	var d := global_position - _prev_pos
	_prev_pos = global_position
	d.y = 0.0

	# Rolling without slipping: distance actually travelled becomes spin.
	var roll := Basis.IDENTITY
	if _radius > 0.0 and d.length() > 0.00001:
		roll = Basis(Vector3.UP.cross(d).normalized(), d.length() / _radius)
	_body_off = (roll * _body_off).orthonormalized()

	if d.length() > 0.0001 or absf(direction) > 0.01:
		_idle = 0.0
		_face_roll = (roll * _face_roll).orthonormalized()
		_lead = move_toward(_lead, direction * face_lead_angle, face_lead_speed * delta)
	else:
		_idle += delta
		if _idle >= face_idle_delay:
			# Rest is a band, not a point: the face settles on whichever end of it
			# it is nearest, so it keeps facing the way it last travelled.
			var rest := clampf(_lead, -face_rest_span, face_rest_span)
			var w := clampf(delta / maxf(face_return_time, 0.0001), 0.0, 1.0)
			_face_roll = Basis(Quaternion(_face_roll).slerp(Quaternion.IDENTITY, w)).orthonormalized()
			_lead = lerpf(_lead, rest, w)
			if absf(_lead - rest) < 0.001 and Quaternion(_face_roll).get_angle() < 0.001:
				_lead = rest
				_face_roll = Basis.IDENTITY

	var face_off := Basis(Vector3.UP, _lead) * _face_roll
	# Ride over the ball's lumps instead of sinking into them.
	var want: float = _needed_lift(face_off)
	_lift = move_toward(_lift, want, face_lift_speed * delta)

	_apply(_body, _body_off)
	_apply(_face, face_off, (face_off * _face_dir).normalized() * _lift)

	# Only clay actually pressed against the ground is remoulded, so a facet has
	# to roll back through the contact patch to be worked out.
	_deform.knead(d.length(), _body_off, _contact if is_on_floor() else Vector3.ZERO)

# Rotate a group about the ball centre, working in Player space.
func _apply(nodes: Array, off: Basis, push: Vector3 = Vector3.ZERO) -> void:
	var p := Transform3D(off, _pivot - off * _pivot + push)
	var t := _m_inv * p * _m
	for n in nodes:
		n.transform = t * _home[n]

# Push the face out until it sits no deeper in the clay than it does at rest.
# The ball keeps rolling, so lumps are looked up in the body's current frame.
func _needed_lift(off: Basis) -> float:
	if _samples.is_empty():
		return 0.0
	var c := (off * _face_dir).normalized()
	var l := 0.0
	for i in 2:
		l += maxf(_penetration(off, c, l) - _pen_home, 0.0)
	return l

func _penetration(off: Basis, c: Vector3, l: float) -> float:
	var inv := _body_off.inverse()
	var worst := 0.0
	for s0 in _samples:
		var s: Vector3 = off * s0 + c * l
		worst = maxf(worst, _surface_radius(inv * s) - s.length())
	return worst

func _build_surface_map() -> void:
	_radmap = PackedFloat32Array()
	_radmap.resize(MAP_U * MAP_V)
	for n in _body:
		var mi := n as MeshInstance3D
		var t: Transform3D = _m * _rel_to_model(mi)
		for v in mi.mesh.get_faces():
			var r: Vector3 = t * v - _pivot
			var i: int = _cell(r)
			_radmap[i] = maxf(_radmap[i], r.length())
	for pass_i in 4:
		for i in _radmap.size():
			if _radmap[i] > 0.0:
				continue
			var acc := 0.0
			var cnt := 0
			for step in [-1, 1, -MAP_U, MAP_U]:
				var j: int = i + step
				if j >= 0 and j < _radmap.size() and _radmap[j] > 0.0:
					acc += _radmap[j]
					cnt += 1
			if cnt > 0:
				_radmap[i] = acc / cnt

	_celldir = PackedVector3Array()
	_celldir.resize(MAP_U * MAP_V)
	for w in MAP_V:
		var theta: float = (float(w) + 0.5) / MAP_V * PI
		for u in MAP_U:
			var phi: float = (float(u) + 0.5) / MAP_U * TAU - PI
			_celldir[w * MAP_U + u] = Vector3(
				sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))

	var acc_dir := Vector3.ZERO
	_samples = PackedVector3Array()
	for n in _face:
		var mi := n as MeshInstance3D
		var t: Transform3D = _m * _home[mi]
		var verts: PackedVector3Array = mi.mesh.get_faces()
		for k in range(0, verts.size(), 12):
			var s: Vector3 = t * verts[k] - _pivot
			_samples.append(s)
			acc_dir += s
	if acc_dir.length() > 0.0:
		_face_dir = acc_dir.normalized()

func _surface_radius(v: Vector3) -> float:
	return _radmap[_cell(v)]

func _cell(v: Vector3) -> int:
	var d := v.normalized()
	var u := int((atan2(d.z, d.x) + PI) / TAU * MAP_U) % MAP_U
	var w := clampi(int(acos(clampf(d.y, -1.0, 1.0)) / PI * MAP_V), 0, MAP_V - 1)
	return w * MAP_U + u

# Largest mesh is the body; anything else rides on its surface as the face.
func _split_meshes() -> void:
	var meshes := _model.find_children("*", "MeshInstance3D", false, false)
	var biggest: MeshInstance3D = null
	var best := -1.0
	for n in meshes:
		if n.mesh and n.mesh.get_aabb().get_volume() > best:
			best = n.mesh.get_aabb().get_volume()
			biggest = n
	for n in meshes:
		if n.mesh == null:
			continue
		_home[n] = n.transform
		if n == biggest:
			_body.append(n)
		else:
			_face.append(n)

func _body_centre() -> Vector3:
	var out := AABB()
	var first := true
	for n in _body:
		var mi := n as MeshInstance3D
		var a: AABB = _rel_to_model(mi) * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return (_m * out).get_center()

# The ground contact radius, which is what sets the roll rate.
func _contact_radius() -> float:
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape:
		var s: float = maxf(cs.scale.x, cs.scale.z)
		if cs.shape is SphereShape3D or cs.shape is CapsuleShape3D:
			return cs.shape.radius * s
	return 1.0

func _rel_to_model(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node3D = n
	while cur != null and cur != _model:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t
