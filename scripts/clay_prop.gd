@tool
extends Node3D

# Puts an imported model into the world's material language: flat matte colour
# with the shared fingerprint relief, projected in world space so one prop's
# grain is the same size as the terrain's however the prop is scaled.

@export var grain: float = 6.0: set = _s1
@export var relief: float = 14.0: set = _s2
@export_range(0.0, 1.0) var roughness: float = 0.92: set = _s3
@export var lighten: float = 0.0: set = _s4
@export var albedo_override: Color = Color(0, 0, 0, 0): set = _s5
@export var fingerprint_normal: Texture2D = preload("res://assets/GrassBlock_imperfection_0002_normal_opengl_2k.png"): set = _s6

func _s1(v): grain = v; _apply()
func _s2(v): relief = v; _apply()
func _s3(v): roughness = v; _apply()
func _s4(v): lighten = v; _apply()
func _s5(v): albedo_override = v; _apply()
func _s6(v): fingerprint_normal = v; _apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_node_ready():
		return
	for mi in _meshes(self):
		var s: float = maxf(mi.global_transform.basis.get_scale().length() / sqrt(3.0), 0.0001)
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _mat(mi.mesh.surface_get_material(i), s))

func _meshes(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		out.append(mi)
	for c in n.get_children():
		_meshes(c, out)
	return out

func _mat(src: Material, node_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := Color(0.6, 0.6, 0.6)
	var std := src as StandardMaterial3D
	if std:
		base = std.albedo_color
	if albedo_override.a > 0.0:
		base = albedo_override
	m.albedo_color = base.lightened(clampf(lighten, 0.0, 1.0)) if lighten > 0.0 else base
	m.metallic = 0.0
	m.metallic_specular = 0.12
	m.roughness = roughness
	# Triplanar over local positions: the mesh has no usable unwrap, and dividing
	# by the node's scale keeps the grain a fixed size in the world.
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * node_scale / maxf(grain, 0.001)
	if fingerprint_normal:
		m.normal_enabled = true
		m.normal_texture = fingerprint_normal
		m.normal_scale = relief
	return m
