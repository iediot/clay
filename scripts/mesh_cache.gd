class_name ClayMeshCache
extends RefCounted

# Generated meshes are kept on disk between runs. The scene files stay clean —
# nothing is serialised into them — but rebuilding half a million vertices of
# terrain in GDScript on every launch is most of the project's start-up time,
# and none of it changes unless a parameter or the code that reads it does.
#
# The key covers both: every stored parameter of the node, plus a digest of the
# scripts that do the building. That means editing generation code invalidates
# every cached mesh on its own — there is no version number to forget to bump.

const DIR := "user://mesh_cache"

static func key(params: Array, sources: Array) -> String:
	var s := ""
	for path in sources:
		s += FileAccess.get_md5(path) + ";"
	for p in params:
		s += str(p) + ";"
	return s.md5_text()

# Every stored, script-declared property of a node, in a stable textual form.
# Resources are reduced to their path so two loads of the same texture agree.
static func params_of(node: Object) -> Array:
	var out: Array = []
	for p in node.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE) or not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v = node.get(p.name)
		if v is Callable or v is Signal:
			continue
		if v is Resource:
			v = (v as Resource).resource_path
		elif v is Object:
			continue
		out.append("%s=%s" % [p.name, v])
	out.sort()
	return out

static func fetch(name: String, key: String) -> Resource:
	var path := _path(name, key)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

static func store(name: String, key: String, res: Resource) -> void:
	if res == null:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	_drop_others(name, key)
	ResourceSaver.save(res, _path(name, key))

static func _path(name: String, key: String) -> String:
	return "%s/%s_%s.res" % [DIR, name, key]

# Only the current key is worth keeping; otherwise sweeping a parameter would
# leave a directory full of dead meshes.
static func _drop_others(name: String, keep: String) -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with(name + "_") and f != "%s_%s.res" % [name, keep]:
			d.remove(f)
