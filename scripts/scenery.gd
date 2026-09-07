@tool
extends Node3D

# Planting for the landform behind the track. Generated nodes are deliberately
# left unowned: like the terrain mesh they are rebuilt on load and must never be
# serialised into the scene file.
# A few authored groups rather than
# an even scatter: clusters read as somebody put them there, and leave the route
# and its cutaway as the clear subject.
#
# Everything is placed off the landform's own surface, so a trunk stands in the
# grass with only its base buried, and every prop carries the shared clay
# material at one world grain size.

const TREE_A := preload("res://assets/Tree1.glb")
const TREE_B := preload("res://assets/Tree2.glb")
const FINGERPRINT := preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png")

const GRAIN := 3.6
const RELIEF := 13.0

# Composed clusters, not a scatter. Each entry mixes kinds so a group has a tall
# silhouette, a middle mass and a low fringe; counts and spreads are uneven on
# purpose. All of it sits well behind the track, so the route stays clear.
const GROUPS := [
	# Near framing groves: big enough to read as silhouettes, set well out to the
	# sides so the route and the cutaway keep the middle of the frame.
	{"mix": ["leafy", "leafy", "spruce"], "x": -103.0, "z": -27.0, "r": 12.0, "n": 5, "s": [0.62, 0.92]},
	{"mix": ["bush", "bush", "tuft", "flower"], "x": -95.0, "z": -19.0, "r": 9.0, "n": 12, "s": [1.0, 2.3]},
	{"mix": ["spruce", "spruce", "leafy"], "x": 84.0, "z": -30.0, "r": 13.0, "n": 5, "s": [0.58, 0.88]},
	{"mix": ["bush", "tuft", "rock", "flower"], "x": 92.0, "z": -20.0, "r": 10.0, "n": 12, "s": [0.9, 2.2]},

	# Middle distance: two loose groves either side of the stream, plus the
	# clumps that give the banks a shape.
	{"mix": ["leafy", "spruce"], "x": -47.0, "z": -56.0, "r": 11.0, "n": 4, "s": [0.50, 0.72]},
	{"mix": ["bush", "tuft"], "x": -55.0, "z": -46.0, "r": 8.0, "n": 8, "s": [1.1, 2.2]},
	{"mix": ["spruce", "leafy", "leafy"], "x": 34.0, "z": -62.0, "r": 12.0, "n": 5, "s": [0.48, 0.74]},
	{"mix": ["rock", "rock", "tuft"], "x": 12.0, "z": -50.0, "r": 8.0, "n": 6, "s": [0.9, 1.9]},
	{"mix": ["bush", "tuft", "flower"], "x": 128.0, "z": -48.0, "r": 11.0, "n": 10, "s": [0.9, 2.1]},
	{"mix": ["rock", "tuft"], "x": -134.0, "z": -44.0, "r": 10.0, "n": 7, "s": [0.9, 1.9]},

	# Hillside stands, small with distance, breaking the horizon into layers.
	{"mix": ["spruce", "spruce", "leafy"], "x": -152.0, "z": -86.0, "r": 22.0, "n": 8, "s": [0.40, 0.66]},
	{"mix": ["spruce"], "x": -86.0, "z": -104.0, "r": 16.0, "n": 5, "s": [0.36, 0.56]},
	{"mix": ["leafy", "spruce"], "x": -18.0, "z": -122.0, "r": 17.0, "n": 5, "s": [0.32, 0.50]},
	{"mix": ["spruce", "leafy"], "x": 72.0, "z": -98.0, "r": 20.0, "n": 7, "s": [0.36, 0.60]},
	{"mix": ["leafy"], "x": 158.0, "z": -92.0, "r": 18.0, "n": 5, "s": [0.38, 0.58]},

	# Outer flanks: the landform sweeps wide past the ends of the track, so those
	# slopes get their own planting instead of reading as bare ramps.
	{"mix": ["leafy", "spruce", "spruce"], "x": -196.0, "z": -40.0, "r": 18.0, "n": 6, "s": [0.52, 0.86]},
	{"mix": ["bush", "tuft", "rock", "flower"], "x": -182.0, "z": -26.0, "r": 14.0, "n": 13, "s": [0.9, 2.2]},
	{"mix": ["spruce", "leafy"], "x": -238.0, "z": -66.0, "r": 20.0, "n": 6, "s": [0.46, 0.74]},
	{"mix": ["leafy", "leafy", "spruce"], "x": 176.0, "z": -36.0, "r": 17.0, "n": 6, "s": [0.54, 0.90]},
	{"mix": ["bush", "tuft", "flower", "rock"], "x": 164.0, "z": -24.0, "r": 13.0, "n": 13, "s": [0.9, 2.2]},
	{"mix": ["spruce", "leafy"], "x": 224.0, "z": -60.0, "r": 20.0, "n": 6, "s": [0.46, 0.76]},
	{"mix": ["rock", "tuft"], "x": 208.0, "z": -96.0, "r": 16.0, "n": 8, "s": [1.0, 2.2]},
	{"mix": ["rock", "tuft", "bush"], "x": 104.0, "z": -16.0, "r": 15.0, "n": 11, "s": [0.9, 2.0]},
	{"mix": ["rock", "tuft", "bush"], "x": -110.0, "z": -16.0, "r": 15.0, "n": 11, "s": [0.9, 2.0]},
	{"mix": ["rock", "tuft"], "x": -216.0, "z": -104.0, "r": 16.0, "n": 8, "s": [1.0, 2.2]},

	# Lone trees, to keep the clumps from reading as a hedge.
	{"mix": ["leafy"], "x": -12.0, "z": -74.0, "r": 3.0, "n": 1, "s": [0.66, 0.72]},
	{"mix": ["spruce"], "x": 58.0, "z": -122.0, "r": 5.0, "n": 2, "s": [0.40, 0.52]},
	{"mix": ["leafy"], "x": -118.0, "z": -140.0, "r": 7.0, "n": 2, "s": [0.34, 0.44]},
]

# Clumps of low planting on the bank just behind the track. Deliberately gappy:
# a fringe with holes in it, not a border.
const VERGE := [
	{"x": -232.0, "n": 8}, {"x": -196.0, "n": 11}, {"x": -157.0, "n": 9},
	{"x": -121.0, "n": 12}, {"x": -95.0, "n": 11}, {"x": -73.0, "n": 8}, {"x": -30.0, "n": 13},
	{"x": 21.0, "n": 10}, {"x": 63.0, "n": 14}, {"x": 92.0, "n": 11}, {"x": 117.0, "n": 9},
	{"x": 154.0, "n": 12}, {"x": 196.0, "n": 10}, {"x": 232.0, "n": 8},
]

# Reeds and stones along the water, placed against the channel rather than in a
# circle, so the stream has a bank instead of an edge.
const BANKS := [-140.0, -96.0, -58.0, -20.0, 16.0, 58.0, 104.0, 146.0]

const BLOOMS := [
	Color(0.94, 0.31, 0.36),
	Color(0.98, 0.76, 0.22),
	Color(0.95, 0.95, 0.97),
	Color(0.72, 0.45, 0.90),
	Color(0.97, 0.55, 0.24),
	Color(0.36, 0.60, 0.94),
	Color(0.98, 0.62, 0.76),
]

const LEAF_TONES := [
	Color(0.38, 0.68, 0.22),
	Color(0.48, 0.76, 0.26),
	Color(0.31, 0.61, 0.23),
	Color(0.56, 0.79, 0.30),
]

@export var terrain_path: NodePath = ^"../Terrain": set = _s1
@export var scenery_seed: int = 7: set = _s2
@export var bush_color: Color = Color(0.29, 0.60, 0.17): set = _s3
@export var rock_color: Color = Color(0.62, 0.46, 0.35): set = _s4
@export var stem_color: Color = Color(0.39, 0.69, 0.24): set = _s5
@export var trunk_color: Color = Color(0.55, 0.35, 0.21): set = _s6
@export var needle_color: Color = Color(0.24, 0.55, 0.20): set = _s7
@export var leaf_color: Color = Color(0.42, 0.70, 0.22): set = _s8

@export_tool_button("Regenerate") var regen_button = build

var _queued := false

func _s1(v): terrain_path = v; _dirty()
func _s2(v): scenery_seed = v; _dirty()
func _s3(v): bush_color = v; _dirty()
func _s4(v): rock_color = v; _dirty()
func _s5(v): stem_color = v; _dirty()
func _s6(v): trunk_color = v; _dirty()
func _s7(v): needle_color = v; _dirty()
func _s8(v): leaf_color = v; _dirty()

func _ready() -> void:
	build()

func _dirty() -> void:
	if not is_node_ready() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_queued = false
	build()

func build() -> void:
	# queue_free, not free: the renderer still holds the old instances this frame,
	# and the material cache is kept so their materials outlive them.
	for c in get_children():
		c.queue_free()
	var terrain := get_node_or_null(terrain_path) as MeshInstance3D
	if terrain == null or not terrain.has_method("landform_height"):
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = scenery_seed
	var models := {"spruce": _parts(TREE_A), "leafy": _parts(TREE_B)}
	# A small library of shapes, reused across the placements. Building a fresh
	# mesh per plant is what made this scene slow to open; a dozen variants with
	# random size and spin read just as hand-made.
	var lib := {
		"tuft": _variants(12, func(r): return ClayShapes.tuft(r, 1.0, r.randi_range(5, 9), 0.55), rng),
		"flower": _variants(10, func(r): return ClayShapes.flower(r, 1.0), rng),
		"bush": _variants(8, func(r): return ClayShapes.bush(r, 1.0), rng),
		"rock": _variants(12, func(r): return ClayShapes.rock(r, 1.0), rng),
		"mound": _variants(6, func(r): return ClayShapes.mound(r, 1.0), rng),
	}


	for g in GROUPS:
		for i in g.n:
			var x: float = g.x
			var z: float = g.z
			var ok := false
			# Keep planting out of the stream bed; a few tries is plenty.
			for attempt in 8:
				var a := rng.randf() * TAU
				var rad: float = pow(rng.randf(), 0.65) * g.r
				x = g.x + cos(a) * rad
				z = g.z + sin(a) * rad * 0.7
				if terrain.stream_distance(x, z) > 1.25:
					ok = true
					break
			if not ok:
				continue
			var kind: String = g.mix[rng.randi() % g.mix.size()]
			var y: float = terrain.landform_height(x, z)
			var s: float = rng.randf_range(g.s[0], g.s[1])
			var yaw := rng.randf() * TAU
			match kind:
				"spruce", "leafy":
					_plant(models[kind], lib, rng, Vector3(x, y, z), s,
						yaw, _canopy(rng, kind))
				"bush":
					_prop(_pick(lib, "bush", rng), Vector3(x, y - s * 0.28, z), yaw, s,
						bush_color.lerp(LEAF_TONES[rng.randi() % LEAF_TONES.size()], 0.45))
				"rock":
					_prop(_pick(lib, "rock", rng), Vector3(x, y - s * 0.3, z), yaw, s,
						rock_color.lerp(rock_color.darkened(0.3), rng.randf()))
				"tuft":
					_prop(_pick(lib, "tuft", rng), Vector3(x, y - s * 0.12, z), yaw, s * 0.9,
						LEAF_TONES[rng.randi() % LEAF_TONES.size()])
				"flower":
					_prop(_pick(lib, "flower", rng), Vector3(x, y - s * 0.1, z), yaw, s, stem_color,
						BLOOMS[rng.randi() % BLOOMS.size()])

	# The verge: a low fringe on the bank immediately behind the track, so the
	# nearest ground is planted without anything tall entering the route.
	for band in VERGE:
		for i in band.n:
			var x: float = band.x + rng.randf_range(-9.0, 9.0)
			var z: float = -4.0 - rng.randf_range(3.5, 15.0)
			if terrain.stream_distance(x, z) < 1.25:
				continue
			var y: float = terrain.landform_height(x, z)
			var roll := rng.randf()
			if roll < 0.45:
				var s := rng.randf_range(0.9, 1.8)
				_prop(_pick(lib, "tuft", rng), Vector3(x, y - 0.15, z), rng.randf() * TAU, s,
					LEAF_TONES[rng.randi() % LEAF_TONES.size()])
			elif roll < 0.78:
				var s := rng.randf_range(0.9, 1.6)
				_prop(_pick(lib, "flower", rng), Vector3(x, y - s * 0.1, z), rng.randf() * TAU, s,
					stem_color, BLOOMS[rng.randi() % BLOOMS.size()])
			elif roll < 0.92:
				var s := rng.randf_range(0.7, 1.4)
				_prop(_pick(lib, "rock", rng), Vector3(x, y - s * 0.35, z), rng.randf() * TAU, s,
					rock_color.darkened(rng.randf() * 0.3))
			else:
				var s := rng.randf_range(0.9, 1.5)
				_prop(_pick(lib, "bush", rng), Vector3(x, y - s * 0.3, z), rng.randf() * TAU, s,
					bush_color.lerp(LEAF_TONES[rng.randi() % LEAF_TONES.size()], 0.4))

	# Bank dressing: reeds and wet stones sitting against the channel.
	for bx in BANKS:
		for side in [-1.0, 1.0]:
			var n := rng.randi_range(3, 6)
			for i in n:
				var x: float = bx + rng.randf_range(-11.0, 11.0)
				var z: float = terrain.stream_bank_z(x, side * rng.randf_range(1.05, 1.5))
				var y: float = terrain.landform_height(x, z)
				if rng.randf() < 0.55:
					var s := rng.randf_range(1.3, 2.4)
					_prop(_pick(lib, "tuft", rng), Vector3(x, y - 0.2, z), rng.randf() * TAU, s,
						LEAF_TONES[rng.randi() % LEAF_TONES.size()])
				else:
					var s := rng.randf_range(0.8, 1.7)
					_prop(_pick(lib, "rock", rng), Vector3(x, y - s * 0.35, z), rng.randf() * TAU, s,
						rock_color.darkened(rng.randf() * 0.25))

func _variants(count: int, make: Callable, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in count:
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		out.append(make.call(r))
	return out

func _pick(lib: Dictionary, kind: String, rng: RandomNumberGenerator) -> ArrayMesh:
	var set: Array = lib[kind]
	return set[rng.randi() % set.size()]

func _canopy(rng: RandomNumberGenerator, kind: String) -> Color:
	var base: Color = needle_color if kind == "spruce" else leaf_color
	return base.lerp(LEAF_TONES[rng.randi() % LEAF_TONES.size()], 0.35)

func _parts(scene: PackedScene) -> Array:
	var root := scene.instantiate()
	var out: Array = []
	_collect(root, out)
	root.queue_free()
	out.sort_custom(func(a, b): return a.mesh.get_faces().size() < b.mesh.get_faces().size())
	return out

func _collect(n: Node, out: Array) -> void:
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		out.append({"mesh": mi.mesh})
	for c in n.get_children():
		_collect(c, out)

# A tree is set into the ground with only its foot buried, and the clay it
# displaced is pushed up round the trunk so it reads as planted, not dropped.
func _plant(parts: Array, lib: Dictionary, rng: RandomNumberGenerator, at: Vector3, s: float, yaw: float, canopy: Color) -> void:
	var lean := Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05)) * Basis(Vector3.FORWARD, rng.randf_range(-0.05, 0.05))
	var base := Vector3(at.x, at.y - 0.22 * s, at.z)
	for i in parts.size():
		var mi := MeshInstance3D.new()
		mi.mesh = parts[i].mesh
		mi.transform = Transform3D(lean * Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), base)
		mi.set_surface_override_material(0, _clay(trunk_color if i == 0 else canopy, s))
		add_child(mi)
	_prop(_pick(lib, "mound", rng), Vector3(at.x, at.y - s * 0.25, at.z), rng.randf() * TAU,
		s * 2.1, _grass())

func _prop(mesh: ArrayMesh, at: Vector3, yaw: float, scale: float, col: Color, tip := Color(0, 0, 0, 0)) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), at)
	mi.set_surface_override_material(0, _clay(col, scale))
	if tip.a > 0.0 and mesh.get_surface_count() > 1:
		mi.set_surface_override_material(1, _clay(tip, scale))
	add_child(mi)

func _grass() -> Color:
	var terrain := get_node_or_null(terrain_path)
	return terrain.grass_color if terrain else Color(0.36, 0.72, 0.19)

var _mats: Dictionary = {}

func _clay(col: Color, node_scale: float) -> StandardMaterial3D:
	var key := "%s|%.3f" % [col.to_html(), node_scale]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.0
	m.metallic_specular = 0.12
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * node_scale / GRAIN
	m.normal_enabled = true
	m.normal_texture = FINGERPRINT
	m.normal_scale = RELIEF
	_mats[key] = m
	return m
