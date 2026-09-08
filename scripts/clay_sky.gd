@tool
extends MeshInstance3D

# The sky is a clay object, not a gradient: one flat bright colour on a large
# inward-facing dome that has been thumbed into broad soft lumps, with the same
# fingerprint relief as everything else, scaled up so it still reads from the
# gameplay camera.

@export var radius: float = 900.0: set = _s1
@export var segments: int = 128: set = _s2
@export var rings: int = 56: set = _s3
@export_range(0.0, 0.3) var lump: float = 0.055: set = _s4
@export_range(0.0, 0.6) var shade_contrast: float = 0.15: set = _s10
@export_range(0.0, 3.0) var grain_relief: float = 1.0: set = _s11
@export var lump_scale: float = 3.2: set = _s5
@export var sky_color: Color = Color(0.42, 0.79, 0.95): set = _s6
@export var grain: float = 240.0: set = _s7
@export var fingerprint_strength: float = 22.0: set = _s8
@export var fingerprint_normal: Texture2D = preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png"): set = _s9

@export_tool_button("Regenerate") var regen_button = generate

var _noise := FastNoiseLite.new()
var _queued := false

func _s1(v): radius = v; _dirty()
func _s2(v): segments = maxi(8, v); _dirty()
func _s3(v): rings = maxi(4, v); _dirty()
func _s4(v): lump = v; _dirty()
func _s5(v): lump_scale = v; _dirty()
func _s6(v): sky_color = v; _dirty()
func _s7(v): grain = v; _dirty()
func _s8(v): fingerprint_strength = v; _dirty()
func _s9(v): fingerprint_normal = v; _dirty()
func _s10(v): shade_contrast = v; _dirty()
func _s11(v): grain_relief = v; _dirty()

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

func _dir(ring: int, seg: int) -> Vector3:
	# Down to 30 degrees below the horizon; the land covers everything under it.
	var phi := PI * 0.667 * float(ring) / float(rings)
	var theta := TAU * float(seg) / float(segments)
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))

func _point(ring: int, seg: int) -> Vector3:
	var d := _dir(ring, seg)
	var w := _noise.get_noise_3d(d.x * 100.0, d.y * 100.0, d.z * 100.0)
	w += _noise.get_noise_3d(d.x * 213.0, d.y * 213.0 + 91.0, d.z * 213.0) * 0.45
	return d * radius * (1.0 + lump * w)

func generate() -> void:
	_noise.seed = 17
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = lump_scale * 0.01
	_noise.fractal_octaves = 2

	var v := PackedVector3Array()
	for r in rings + 1:
		for s in segments:
			v.append(_point(r, s))

	var idx := PackedInt32Array()
	for r in rings:
		for s in segments:
			var s2 := (s + 1) % segments
			var a := r * segments + s
			var b := r * segments + s2
			var c := (r + 1) * segments + s
			var d := (r + 1) * segments + s2
			# Seen from inside, so the winding is the mirror of an outward sphere.
			idx.append_array([a, b, c, b, d, c])

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
		n[i] = (-n[i]).normalized() if n[i].length() > 0.0 else -v[i].normalized()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in v.size():
		st.set_normal(n[i])
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v[i])
	for i in idx:
		st.add_index(i)
	st.generate_tangents()
	st.set_material(_mat())
	var am := ArrayMesh.new()
	st.commit(am)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = am
	custom_aabb = AABB(Vector3.ONE * -radius * 1.2, Vector3.ONE * radius * 2.4)

func _mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/clay_sky.gdshader")
	m.set_shader_parameter("sky_color", sky_color)
	m.set_shader_parameter("fingerprint", fingerprint_normal)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("relief", grain_relief)
	m.set_shader_parameter("contrast", shade_contrast)
	return m
