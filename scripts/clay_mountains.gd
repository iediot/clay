@tool
extends MeshInstance3D

# The mountains are their own background objects: a handful of blunt clay cones
# standing behind the grass landform, not part of it. Shapes stay simple — a
# rounded-off cone with a couple of gentle lobes — because the world is meant to
# read as pressed-out plasticine, not as terrain.
#
# Snow is a second clay layer laid over each summit, built with the same idea as
# the track's grass overhang: it has thickness, its edge wanders, and it sags
# down chosen sides in tongues that thin out and close against the rock.

const RINGS := 30
const SEGS := 48
const CAP_ROWS := 10
const DRIP_ROWS := 9

# x, z, base height, cone height, base radii, bluntness, lobe amount, phase.
# Bluntness above 1 rounds the summit off; nearer 1 sharpens it.
const PEAKS := [
	{"x": -300.0, "z": -300.0, "y": 20.0, "h": 58.0, "rx": 56.0, "rz": 52.0, "blunt": 1.40, "lobe": 0.10, "p": 5.6},
	{"x": -222.0, "z": -268.0, "y": 20.0, "h": 84.0, "rx": 62.0, "rz": 56.0, "blunt": 1.16, "lobe": 0.09, "p": 0.6},
	{"x": -166.0, "z": -292.0, "y": 22.0, "h": 52.0, "rx": 44.0, "rz": 41.0, "blunt": 1.50, "lobe": 0.10, "p": 2.1},
	{"x": -58.0, "z": -286.0, "y": 20.0, "h": 104.0, "rx": 78.0, "rz": 70.0, "blunt": 1.10, "lobe": 0.08, "p": 1.3},
	{"x": 6.0, "z": -250.0, "y": 17.0, "h": 47.0, "rx": 40.0, "rz": 44.0, "blunt": 1.58, "lobe": 0.10, "p": 5.0},
	{"x": 112.0, "z": -290.0, "y": 21.0, "h": 90.0, "rx": 68.0, "rz": 61.0, "blunt": 1.14, "lobe": 0.09, "p": 0.2},
	{"x": 178.0, "z": -262.0, "y": 18.0, "h": 55.0, "rx": 46.0, "rz": 43.0, "blunt": 1.46, "lobe": 0.09, "p": 4.2},
	{"x": 272.0, "z": -298.0, "y": 20.0, "h": 74.0, "rx": 60.0, "rz": 55.0, "blunt": 1.24, "lobe": 0.09, "p": 2.8},
]

@export var rock_color: Color = Color(0.55, 0.55, 0.58): set = _s1
@export var snow_color: Color = Color(0.94, 0.95, 0.97): set = _s2
@export_range(0.0, 1.0) var snow_line: float = 0.70: set = _s3
@export var snow_thickness: float = 4.5: set = _s4
@export var snow_wobble: float = 0.15: set = _s5
@export_range(0.0, 1.0) var drip_min: float = 0.14: set = _s6
@export var drip_length: float = 0.52: set = _s7
@export var drip_bias: float = -0.05: set = _s8
@export var drip_bulge: float = 0.65: set = _s9
@export var grain: float = 30.0: set = _s10
@export var fingerprint_strength: float = 15.0: set = _s11
@export_range(0.0, 1.0) var roughness: float = 0.92: set = _s12
@export var fingerprint_normal: Texture2D = preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png"): set = _s13

@export_tool_button("Regenerate") var regen_button = generate

var _wob := FastNoiseLite.new()
var _sag := FastNoiseLite.new()
var _queued := false

func _s1(v): rock_color = v; _dirty()
func _s2(v): snow_color = v; _dirty()
func _s3(v): snow_line = v; _dirty()
func _s4(v): snow_thickness = v; _dirty()
func _s5(v): snow_wobble = v; _dirty()
func _s6(v): drip_min = v; _dirty()
func _s7(v): drip_length = v; _dirty()
func _s8(v): drip_bias = v; _dirty()
func _s9(v): drip_bulge = v; _dirty()
func _s10(v): grain = v; _dirty()
func _s11(v): fingerprint_strength = v; _dirty()
func _s12(v): roughness = v; _dirty()
func _s13(v): fingerprint_normal = v; _dirty()

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

func generate() -> void:
	_wob.seed = 91
	_wob.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wob.frequency = 1.0
	_wob.fractal_octaves = 2

	_sag.seed = 137
	_sag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_sag.frequency = 1.0
	_sag.fractal_octaves = 2

	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var snow := SurfaceTool.new()
	snow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rb := 0
	var sb := 0
	for i in PEAKS.size():
		rb = _cone(rock, rb, PEAKS[i], i)
		sb = _snow(snow, sb, PEAKS[i], i)

	rock.generate_tangents()
	rock.set_material(_mat(rock_color))
	var am := ArrayMesh.new()
	rock.commit(am)
	snow.generate_tangents()
	snow.set_material(_mat(snow_color))
	snow.commit(am)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = am

# Blunt cone profile. `blunt` above 1 flattens the radius curve near the summit,
# so the tip rounds over instead of coming to a spike.
func _radius(m: Dictionary, t: float) -> float:
	var b: float = m.blunt
	return pow(maxf(1.0 - pow(clampf(t, 0.0, 1.0), b), 0.0), 1.0 / b)

func _point(m: Dictionary, t: float, seg: int, index: int) -> Vector3:
	var th := TAU * float(seg) / float(SEGS)
	var lobe: float = 1.0 + m.lobe * (0.62 * sin(2.0 * th + m.p) + 0.38 * sin(3.0 * th - m.p * 1.7 + index))
	var r := _radius(m, t) * lobe
	return Vector3(m.x + m.rx * r * cos(th), m.y + m.h * t, m.z + m.rz * r * sin(th))

func _normal(m: Dictionary, t: float, seg: int, index: int) -> Vector3:
	var dt := 0.01
	var a := _point(m, minf(t + dt, 1.0), seg, index) - _point(m, maxf(t - dt, -0.2), seg, index)
	var b := _point(m, t, (seg + 1) % SEGS, index) - _point(m, t, (seg - 1 + SEGS) % SEGS, index)
	var n := b.cross(a)
	if n.length() < 0.00001:
		return Vector3.UP
	n = n.normalized()
	var out := Vector3(_point(m, t, seg, index).x - m.x, 0.0, _point(m, t, seg, index).z - m.z)
	if out.length() > 0.0001 and n.dot(out.normalized()) < 0.0:
		n = -n
	return n

# Godot front faces are clockwise, so this vertex order shows the outward face
# for a lathe whose rows climb and whose columns run round the axis.
func _quad(st: SurfaceTool, base: int, a: int, b: int, c: int, d: int) -> void:
	st.add_index(base + a)
	st.add_index(base + b)
	st.add_index(base + c)
	st.add_index(base + b)
	st.add_index(base + d)
	st.add_index(base + c)

func _cone(st: SurfaceTool, base: int, m: Dictionary, index: int) -> int:
	# Starts below zero so the foot is buried behind the landform.
	for i in RINGS + 1:
		var t := lerpf(-0.12, 0.985, float(i) / float(RINGS))
		for s in SEGS:
			st.set_normal(_normal(m, t, s, index))
			st.set_uv(Vector2.ZERO)
			st.add_vertex(_point(m, t, s, index))
	var apex := RINGS + 1
	for s in SEGS:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(Vector3(m.x, m.y + m.h, m.z))
	for i in RINGS:
		for s in SEGS:
			var s2 := (s + 1) % SEGS
			_quad(st, base, i * SEGS + s, i * SEGS + s2, (i + 1) * SEGS + s, (i + 1) * SEGS + s2)
	for s in SEGS:
		var s2 := (s + 1) % SEGS
		_quad(st, base, RINGS * SEGS + s, RINGS * SEGS + s2, apex * SEGS + s, apex * SEGS + s2)
	return base + (apex + 1) * SEGS

# Where the snow stops, per bearing round the peak: a wandering line, then a
# tongue reaching further down some sides than others.
func _line(m: Dictionary, seg: int, index: int) -> float:
	var th := TAU * float(seg) / float(SEGS)
	var w := _wob.get_noise_3d(cos(th) * 1.6, sin(th) * 1.6, float(index) * 7.0)
	return clampf(snow_line + w * snow_wobble, 0.12, 0.94)

func _drip(m: Dictionary, seg: int, index: int) -> float:
	var th := TAU * float(seg) / float(SEGS)
	var n01: float = _sag.get_noise_3d(cos(th) * 1.15, sin(th) * 1.15, float(index) * 11.0) * 0.5 + 0.5
	var lobe: float = drip_min + (1.0 - drip_min) * smoothstep(0.0, 1.0, clampf(n01 + drip_bias, 0.0, 1.0))
	return drip_length * lobe

func _snow(st: SurfaceTool, base: int, m: Dictionary, index: int) -> int:
	var rows := DRIP_ROWS + CAP_ROWS
	for i in rows + 1:
		for s in SEGS:
			var line := _line(m, s, index)
			var drip := _drip(m, s, index)
			var t: float
			var off: float
			if i <= DRIP_ROWS:
				# Tongue: thins and closes onto the rock at its lower end.
				var frac := 1.0 - float(i) / float(DRIP_ROWS)
				t = line - drip * frac
				off = snow_thickness * (1.0 + drip_bulge * sin(frac * PI)) * (1.0 - pow(frac, 2.6))
			else:
				var f := float(i - DRIP_ROWS) / float(CAP_ROWS)
				t = lerpf(line, 0.985, f)
				off = snow_thickness * (1.0 + 0.12 * sin(f * 4.0 + float(index)))
			var n := _normal(m, t, s, index)
			st.set_normal(n)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(_point(m, t, s, index) + n * off)
	var apex := rows + 1
	for s in SEGS:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(Vector3(m.x, m.y + m.h + snow_thickness, m.z))
	for i in rows:
		for s in SEGS:
			var s2 := (s + 1) % SEGS
			_quad(st, base, i * SEGS + s, i * SEGS + s2, (i + 1) * SEGS + s, (i + 1) * SEGS + s2)
	for s in SEGS:
		var s2 := (s + 1) % SEGS
		_quad(st, base, rows * SEGS + s, rows * SEGS + s2, apex * SEGS + s, apex * SEGS + s2)
	return base + (apex + 1) * SEGS

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
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
