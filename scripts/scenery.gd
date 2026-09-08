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

# Every woody prop is a reference-set model put through the same clay treatment
# as Tree1/Tree2: split into loose parts, canopy parts joined, voxel remeshed,
# swelled a little and relaxed until the low-poly facets are gone. See
# docs/decisions.md — nothing here is a stack of primitives any more.
const MODELS := {
	"spruce": [preload("res://assets/Tree1.glb")],
	"leafy": [preload("res://assets/Tree2.glb")],
	"broad": [preload("res://assets/Tree3.glb")],
	"conifer": [preload("res://assets/Tree4.glb")],
	"stump": [preload("res://assets/Stump1.glb"), preload("res://assets/Stump2.glb"),
		preload("res://assets/Stump3.glb")],
	"log": [preload("res://assets/Log1.glb"), preload("res://assets/Log2.glb")],
}
const CANOPIES := ["spruce", "leafy", "broad", "conifer"]
const FINGERPRINT := preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png")

const GRAIN := 3.6
const RELIEF := 13.0

# Composed clusters, not a scatter. Each entry mixes kinds so a group has a tall
# silhouette, a middle mass and a low fringe; counts and spreads are uneven on
# purpose. All of it sits well behind the track, so the route stays clear.
# Cluster characters. A cluster draws its props from one of these bags, so a
# grove has stones and stumps standing among its trees and a rocky patch has a
# tree or two in it — rather than the world being patches of one kind each.
const COMMUNITIES := {
	"grove": ["spruce", "leafy", "broad", "conifer", "spruce", "broad", "stump", "log",
		"bush", "bush", "rock", "tuft", "tuft", "flower"],
	"thicket": ["conifer", "broad", "bush", "bush", "bush", "tuft", "tuft", "flower", "rock", "stump", "leafy"],
	"rocky": ["rock", "rock", "rock", "bush", "tuft", "tuft", "flower", "log", "spruce", "conifer"],
	"meadow": ["flower", "flower", "tuft", "tuft", "tuft", "bush", "rock", "conifer", "stump"],
	"clearing": ["tuft", "tuft", "flower", "stump", "rock", "log", "conifer"],
}

# Planting bands, measured back from the track's rear edge: the depth range, how
# many clusters to try per 100 units of length, how many props each holds, and
# which characters that band draws from. Counts are per unit of length, so a
# longer track gets more planting at the same density rather than the same
# planting spread thinner.
const BANDS := [
	{"z": [-13.0, -28.0], "clusters": 3.8, "n": [5, 12], "tree": [0.42, 0.72], "prop": [0.8, 1.6],
		"mix": ["grove", "thicket", "grove", "meadow", "thicket"]},
	{"z": [-28.0, -56.0], "clusters": 3.4, "n": [6, 14], "tree": [0.50, 0.86], "prop": [0.9, 2.2],
		"mix": ["grove", "thicket", "meadow", "rocky", "grove"]},
	{"z": [-56.0, -102.0], "clusters": 3.6, "n": [7, 16], "tree": [0.44, 0.76], "prop": [0.9, 2.3],
		"mix": ["grove", "grove", "rocky", "thicket", "clearing"]},
	{"z": [-102.0, -162.0], "clusters": 3.8, "n": [8, 18], "tree": [0.34, 0.60], "prop": [0.9, 2.1],
		"mix": ["grove", "grove", "thicket", "rocky", "meadow"]},
	{"z": [-162.0, -238.0], "clusters": 3.4, "n": [8, 18], "tree": [0.26, 0.46], "prop": [0.85, 1.9],
		"mix": ["grove", "grove", "grove", "thicket", "rocky"]},
]

# Room each kind needs around it, as a multiple of its own scale. Placement is
# ordered biggest-first and every candidate is tested against what is already
# down, so a flower cannot grow up through a stone and a trunk cannot stand in
# a boulder.
# Room each kind needs, as a multiple of its own scale — these are model units,
# so a log's is half its length rather than a guess.
const FOOTPRINT := {"spruce": 4.4, "leafy": 5.6, "broad": 5.2, "conifer": 3.2,
	"log": 4.4, "stump": 1.9, "bush": 1.15, "rock": 1.25, "tuft": 0.7, "flower": 0.55}
# Stumps and logs are modelled at reference-set size, so they get their own range.
const WOOD_SIZE := [0.42, 0.85]
# Flowers are single blooms on a stem, not bushes; they need their own range or
# they come out the size of the shrubs beside them.
const FLOWER_SIZE := [0.42, 0.78]
const TREES := ["spruce", "leafy", "broad", "conifer"]

# Stone is not all one colour: some of it is the grey the mountains are made of.
const STONE_TONES := [
	Color(0.62, 0.46, 0.35),
	Color(0.54, 0.40, 0.31),
	Color(0.56, 0.56, 0.58),
	Color(0.48, 0.48, 0.52),
	Color(0.66, 0.63, 0.58),
]

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
	_occ.clear()
	_clear_mask.seed = scenery_seed + 61
	_clear_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clear_mask.frequency = 0.006

	var models := {}
	for kind in MODELS:
		var set: Array = []
		for scene in MODELS[kind]:
			set.append(_parts(scene))
		models[kind] = set
	# A small library of shapes, reused across the placements. Building a fresh
	# mesh per plant is what made this scene slow to open; a dozen variants with
	# random size and spin read just as hand-made.
	var lib := {
		"tuft": _variants(14, func(r): return ClayShapes.tuft(r, 1.0, r.randi_range(5, 9), 0.55), rng),
		"flower": _variants(12, func(r): return ClayShapes.flower(r, 1.0), rng),
		"bush": _variants(10, func(r): return ClayShapes.bush(r, 1.0), rng),
		"rock": _variants(14, func(r): return ClayShapes.rock(r, 1.0), rng),
	}

	var reach: float = terrain.landform_half_width() * 0.97
	var run: float = reach * 2.0

	# Lay out the clusters first, then plant them in two sweeps. Everything with
	# a big footprint goes down across the whole world before anything small
	# does, so trees still claim their room — but each cluster's own list is
	# mixed, which is what interleaves the kinds instead of making patches.
	var clusters: Array = []
	for band in BANDS:
		for i in int(run / 100.0 * band.clusters):
			var kinds: Array = []
			var bag: Array = COMMUNITIES[band.mix[rng.randi() % band.mix.size()]]
			for j in rng.randi_range(band.n[0], band.n[1]):
				kinds.append(bag[rng.randi() % bag.size()])
			clusters.append({
				"x": rng.randf_range(-reach, reach),
				"z": rng.randf_range(band.z[0], band.z[1]),
				"spread": rng.randf_range(7.0, 22.0),
				"kinds": kinds, "band": band,
			})

	for big in [true, false]:
		for c in clusters:
			for kind in c.kinds:
				if (kind in TREES or kind == "log" or kind == "stump") != big:
					continue
				var band: Dictionary = c.band
				var s: float
				if kind in TREES:
					s = rng.randf_range(band.tree[0], band.tree[1])
				elif kind in MODELS:
					s = rng.randf_range(WOOD_SIZE[0], WOOD_SIZE[1])
				elif kind == "flower":
					s = rng.randf_range(FLOWER_SIZE[0], FLOWER_SIZE[1])
				else:
					s = rng.randf_range(band.prop[0], band.prop[1])
				_scatter(terrain, lib, models, rng, c.x, c.z, c.spread, kind, s)

	_fill_gaps(terrain, lib, models, rng, reach)

	# Bank dressing: reeds and wet stones sitting against the channel.
	var bx := -reach
	while bx < reach:
		var at := bx
		bx += rng.randf_range(24.0, 44.0)
		for side in [-1.0, 1.0]:
			for i in rng.randi_range(3, 7):
				var x: float = at + rng.randf_range(-12.0, 12.0)
				var z: float = terrain.stream_bank_z(x, side * rng.randf_range(1.05, 1.55))
				var kind: String = ["tuft", "tuft", "rock", "log"][rng.randi() % 4]
				var s: float = rng.randf_range(WOOD_SIZE[0], WOOD_SIZE[1]) if kind == "log" \
					else rng.randf_range(0.9, 2.1)
				_scatter(terrain, lib, models, rng, x, z, 3.0, kind, s)

# Nothing may be planted where the ground has run out, in the water, inside a
# deliberate clearing, or on top of something already there.
func _spot(terrain: MeshInstance3D, rng: RandomNumberGenerator, cx: float, cz: float,
		spread: float, kind: String, s: float, tries: int = 4) -> Vector3:
	var need: float = FOOTPRINT[kind] * s
	for attempt in tries:
		var a := rng.randf() * TAU
		var rad: float = pow(rng.randf(), 0.6) * spread
		var x: float = cx + cos(a) * rad
		var z: float = cz + sin(a) * rad * 0.6
		if z > -8.0 or terrain.stream_distance(x, z) < 1.02:
			continue
		if _clear_mask.get_noise_2d(x, z * 2.2) > 0.36:
			continue
		if not _ground(terrain, x, z, need):
			continue
		if not _free(x, z, need):
			continue
		_claim(x, z, need)
		return Vector3(x, terrain.landform_height(x, z), z)
	return Vector3(0.0, INF, 0.0)

func _scatter(terrain: MeshInstance3D, lib: Dictionary, models: Dictionary, rng: RandomNumberGenerator,
		cx: float, cz: float, spread: float, kind: String, s: float, tries: int = 4) -> void:
	var at := _spot(terrain, rng, cx, cz, spread, kind, s, tries)
	if at.y == INF:
		return
	var yaw := rng.randf() * TAU
	if kind in MODELS:
		var set: Array = models[kind]
		var parts: Array = set[rng.randi() % set.size()]
		var wood: Color = trunk_color.darkened(snappedf(rng.randf(), 0.34) * 0.22)
		var sink: float = 0.22 if kind in TREES else 0.5
		_plant(parts, lib, rng, at, s, yaw, wood, _canopy(rng, kind) if kind in TREES else wood, sink)
		return
	match kind:
		"bush":
			_prop(_pick(lib, "bush", rng), at - Vector3(0.0, s * 0.28, 0.0), yaw, s,
				bush_color.lerp(LEAF_TONES[rng.randi() % LEAF_TONES.size()], 0.45))
		"rock":
			_prop(_pick(lib, "rock", rng), at - Vector3(0.0, s * 0.3, 0.0), yaw, s,
				STONE_TONES[rng.randi() % STONE_TONES.size()])
		"tuft":
			_prop(_pick(lib, "tuft", rng), at - Vector3(0.0, s * 0.12, 0.0), yaw, s * 0.9,
				LEAF_TONES[rng.randi() % LEAF_TONES.size()])
		"flower":
			_prop(_pick(lib, "flower", rng), at - Vector3(0.0, s * 0.1, 0.0), yaw, s, stem_color,
				BLOOMS[rng.randi() % BLOOMS.size()])

# Sweep the whole planted region and seed anything that came out bare, so there
# are no dead patches — except where the clearing mask deliberately opens one.
func _fill_gaps(terrain: MeshInstance3D, lib: Dictionary, models: Dictionary,
		rng: RandomNumberGenerator, reach: float) -> void:
	var step := 16.0
	var z := -9.0
	while z > -238.0:
		var x := -reach
		while x < reach:
			var px: float = x + rng.randf_range(-4.0, 4.0)
			var pz: float = z + rng.randf_range(-4.0, 4.0)
			x += step
			if not _free(px, pz, step * 0.42):
				continue
			for i in rng.randi_range(2, 4):
				var roll := rng.randf()
				var kind := "tuft"
				if roll > 0.90:
					kind = "conifer"
				elif roll > 0.80:
					kind = "rock"
				elif roll > 0.56:
					kind = "flower"
				var s: float = rng.randf_range(0.8, 1.7)
				if kind == "conifer":
					s = rng.randf_range(0.24, 0.38)
				elif kind == "flower":
					s = rng.randf_range(FLOWER_SIZE[0], FLOWER_SIZE[1])
				_scatter(terrain, lib, models, rng, px, pz, 5.0, kind, s, 1)
		z -= step

# --- occupancy ---------------------------------------------------------------
# A coarse hash of what is already planted. Cheap enough to ask before every
# placement, which is what keeps props out of each other.
const OCC_CELL := 9.0

var _occ: Dictionary = {}
var _clear_mask := FastNoiseLite.new()

func _key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / OCC_CELL)), int(floor(z / OCC_CELL)))

func _free(x: float, z: float, r: float) -> bool:
	var k := _key(x, z)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cell: Array = _occ.get(Vector2i(k.x + dx, k.y + dz), [])
			for e in cell:
				var dxx: float = x - e.x
				var dzz: float = z - e.y
				var reach: float = r + e.z
				if dxx * dxx + dzz * dzz < reach * reach:
					return false
	return true

func _claim(x: float, z: float, r: float) -> void:
	var k := _key(x, z)
	if not _occ.has(k):
		_occ[k] = []
	_occ[k].append(Vector3(x, z, r))

# There has to be generated surface under a prop and all round its footprint, so
# nothing is planted in the air off the rim where the land has fallen away.
func _ground(terrain: MeshInstance3D, x: float, z: float, r: float) -> bool:
	if not terrain.landform_ground(x, z):
		return false
	var m: float = maxf(r, 2.5)
	for o in [Vector2(m, 0.0), Vector2(-m, 0.0), Vector2(0.0, m), Vector2(0.0, -m)]:
		if not terrain.landform_ground(x + o.x, z + o.y):
			return false
	return true

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
	var base: Color = needle_color if kind == "spruce" or kind == "conifer" else leaf_color
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
# Trunks are simply set into the ground. They used to get a pad of clay pushed
# up round the foot; it read as a platform the tree was standing on rather than
# as ground, so the sink alone does the work now.
func _plant(parts: Array, lib: Dictionary, rng: RandomNumberGenerator, at: Vector3, s: float,
		yaw: float, wood: Color, canopy: Color, sink: float) -> void:
	var lean := Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05)) * Basis(Vector3.FORWARD, rng.randf_range(-0.05, 0.05))
	var base := Vector3(at.x, at.y - sink * s, at.z)
	for i in parts.size():
		var mi := MeshInstance3D.new()
		mi.mesh = parts[i].mesh
		mi.transform = Transform3D(lean * Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), base)
		mi.set_surface_override_material(0, _clay(wood if i == 0 else canopy, s))
		add_child(mi)

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

# Scale and tint are snapped before they become a cache key. Left continuous,
# every prop got its own material — thousands of them, one draw call each, and
# most of the build time went into making them. The grain difference between
# neighbouring buckets is invisible.
func _clay(col: Color, node_scale: float) -> StandardMaterial3D:
	node_scale = snappedf(node_scale, 0.35)
	var key := "%s|%.2f" % [col.to_html(), node_scale]
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
