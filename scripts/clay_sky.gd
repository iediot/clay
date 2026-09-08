@tool
extends MeshInstance3D

# The sky is one sheet of clay held up in front of the camera, not a shell round
# the world. A dome was 7k vertices of sphere to show a single colour, and every
# part of it was seen at a different angle; a plane parallel to the image plane
# shows the same colour with none of that, and its thumbed lumps read the same
# everywhere because the whole sheet is square-on to the view.
#
# Its anchor parks it straight ahead of the camera each frame, so it never moves
# on screen and needs no parallax handling at all.

@export var distance: float = 600.0: set = _s1
@export var fov: float = 75.0: set = _s2
# How much wider than tall to build it, so it still covers an ultrawide frame.
@export var cover_aspect: float = 3.1: set = _s3
@export var margin: float = 1.15: set = _s4
@export var cols: int = 72: set = _s5
@export var rows: int = 44: set = _s6

# Depth of the thumbed lumps, in world units, and the distance one lump spans.
@export var lump: float = 27.0: set = _s7
@export var lump_span: float = 540.0: set = _s8
@export var sky_color: Color = Color(0.17, 0.56, 0.88): set = _s9
@export var grain: float = 300.0: set = _s10
@export_range(0.0, 0.6) var shade_contrast: float = 0.11: set = _s11
@export_range(0.0, 3.0) var grain_relief: float = 0.7: set = _s12
@export var fingerprint_normal: Texture2D = preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png"): set = _s13

@export_tool_button("Regenerate") var regen_button = generate

var _noise := FastNoiseLite.new()
var _queued := false

func _s1(v): distance = v; _dirty()
func _s2(v): fov = v; _dirty()
func _s3(v): cover_aspect = v; _dirty()
func _s4(v): margin = v; _dirty()
func _s5(v): cols = maxi(4, v); _dirty()
func _s6(v): rows = maxi(4, v); _dirty()
func _s7(v): lump = v; _dirty()
func _s8(v): lump_span = maxf(1.0, v); _dirty()
func _s9(v): sky_color = v; _dirty()
func _s10(v): grain = v; _dirty()
func _s11(v): shade_contrast = v; _dirty()
func _s12(v): grain_relief = v; _dirty()
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

func _half() -> Vector2:
	var h: float = distance * tan(deg_to_rad(fov * 0.5)) * margin
	return Vector2(h * cover_aspect, h)

# Lumps push the sheet toward the camera, along its own +Z.
func _depth(x: float, y: float) -> float:
	# Two rounds of the same broad noise rather than an octave stack: stacked
	# octaves gave the sheet a streaky, combed look instead of thumb marks.
	var w := _noise.get_noise_2d(x, y)
	w += _noise.get_noise_2d(x * 0.55 + 900.0, y * 0.55 - 400.0) * 0.55
	return w * lump

func generate() -> void:
	_noise.seed = 17
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / lump_span
	_noise.fractal_octaves = 2

	var half := _half()
	var v := PackedVector3Array()
	for r in rows + 1:
		var y: float = lerpf(-half.y, half.y, float(r) / float(rows))
		for c in cols + 1:
			var x: float = lerpf(-half.x, half.x, float(c) / float(cols))
			v.append(Vector3(x, y, _depth(x, y)))

	var idx := PackedInt32Array()
	var w := cols + 1
	for r in rows:
		for c in cols:
			var a := r * w + c
			var b := r * w + c + 1
			var d := (r + 1) * w + c
			var e := (r + 1) * w + c + 1
			# Front faces are clockwise, and the sheet's front is its +Z.
			idx.append_array([a, d, b, b, d, e])

	var n := PackedVector3Array()
	n.resize(v.size())
	for r in rows + 1:
		for c in cols + 1:
			var i := r * w + c
			var dx := v[r * w + mini(c + 1, cols)] - v[r * w + maxi(c - 1, 0)]
			var dy := v[mini(r + 1, rows) * w + c] - v[maxi(r - 1, 0) * w + c]
			var nn := dx.cross(dy)
			n[i] = nn.normalized() if nn.dot(Vector3.BACK) > 0.0 else -nn.normalized()

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, _mat())
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The sheet is parked in front of the camera every frame, so its own bounds
	# must not be used to cull it.
	custom_aabb = AABB(Vector3(-half.x, -half.y, -lump * 2.0) * 1.2,
		Vector3(half.x * 2.4, half.y * 2.4, lump * 4.8))
	mesh = am

func _mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/clay_sky.gdshader")
	m.set_shader_parameter("sky_color", sky_color)
	m.set_shader_parameter("fingerprint", fingerprint_normal)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("relief", grain_relief)
	m.set_shader_parameter("contrast", shade_contrast)
	return m
