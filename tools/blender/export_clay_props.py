# Turns objects from the reference forest set into clay props, the same way
# Tree1/Tree2 were made:
#
#   split into loose parts -> join the canopy parts -> voxel remesh
#   -> swell the crown a little -> relax with a Smooth pass -> shade smooth
#
# The remesh welds the source's separate low-poly pieces into one shell and
# gives it a uniform quad grid; the relax is what actually removes the facets
# and rounds every edge into clay. Remesh alone keeps every flat face.
#
#   blender -b ../BlenderProjects/clay/forest_nature_set_all_in.blend \
#           -P tools/blender/export_clay_props.py
#
# Writes GLBs straight into assets/. Nothing here runs at game time.

import bpy, os, sys

OUT = "/Users/iediot/clay/assets"

# name in the reference set -> (exported name, voxel divisor, split trunk from canopy)
# reference object -> (exported name, voxel divisor, smoothing iterations, split trunk)
JOBS = [
    ("Log_big_regular",      "Log1",   70,  22, False),
    ("Log_big_knotty",       "Log2",   70,  22, False),
    ("Stump_average_high",   "Stump1", 60,  20, False),
    ("Stump_average_low",    "Stump2", 55,  18, False),
    ("Stump_average_hollow", "Stump3", 55,  18, False),
    ("Tree_average_regular", "Tree3",  115, 30, True),
    ("Tree_Spruce_tiny_01",  "Tree4",  110, 30, True),
]

BARK = (0.09, 0.043, 0.0002, 1.0)
LEAF = (0.045, 0.088, 0.0002, 1.0)

def clear_sel():
    for o in bpy.data.objects:
        o.select_set(False)

def split(ob):
    clear_sel(); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='LOOSE'); bpy.ops.object.mode_set(mode='OBJECT')
    return list(bpy.context.selected_objects)

def join(objs):
    clear_sel()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    return objs[0]

def remesh(o, vs, relax, swell = 0.0):
    # Voxel remesh welds the source's separate low-poly pieces into one shell and
    # gives it a uniform quad grid; the smooth pass afterwards is what actually
    # turns the facets into clay, swelling and rounding every edge. Remesh alone
    # keeps every flat face of the original.
    clear_sel(); o.select_set(True); bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("r", 'REMESH')
    m.mode = 'VOXEL'; m.voxel_size = vs; m.adaptivity = 0.0; m.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier="r")
    if swell > 0.0:
        # Swell the crown a little before relaxing it, so the branch tips end
        # inside the mass instead of poking through it.
        d = o.modifiers.new("d", 'DISPLACE')
        d.strength = swell; d.mid_level = 0.0; d.direction = 'NORMAL'
        bpy.ops.object.modifier_apply(modifier="d")
    if relax > 0:
        sm = o.modifiers.new("s", 'SMOOTH')
        sm.factor = 1.0; sm.iterations = relax
        bpy.ops.object.modifier_apply(modifier="s")
    bpy.ops.object.shade_smooth()

def clay_mat(name, rgba):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = rgba
    b.inputs["Roughness"].default_value = 0.91
    b.inputs["Metallic"].default_value = 0.0
    return m

for src_name, out_name, div, relax, do_split in JOBS:
    src = bpy.data.objects.get(src_name)
    if src is None:
        print("MISSING", src_name); continue
    dup = src.copy(); dup.data = src.data.copy()
    bpy.context.collection.objects.link(dup)
    dup.location = (0, 0, 0)
    size = max(dup.dimensions)
    vs = size / float(div)

    if do_split:
        parts = split(dup)
        parts.sort(key=lambda o: min(v.co.z for v in o.data.vertices))
        trunk = parts[0]
        canopy = join(parts[1:]) if len(parts) > 1 else None
        groups = [(trunk, BARK, out_name + "_trunk"), (canopy, LEAF, out_name + "_canopy")]
    else:
        groups = [(dup, BARK, out_name + "_wood")]

    made = []
    for ob, col, nm in groups:
        if ob is None:
            continue
        remesh(ob, vs, relax, 0.30 if nm.endswith("_canopy") else 0.0)
        ob.name = nm
        ob.data.materials.clear()
        ob.data.materials.append(clay_mat(nm + "_clay", col))
        made.append(ob)

    clear_sel()
    for o in made:
        o.select_set(True)
    bpy.context.view_layer.objects.active = made[0]
    path = os.path.join(OUT, out_name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
        export_apply=True, export_yup=True, export_materials='EXPORT')
    print("EXPORT %-8s voxel=%.4f  %s" % (out_name, vs,
        " ".join("%s=%d" % (o.name, len(o.data.vertices)) for o in made)))
    for o in made:
        bpy.data.objects.remove(o)
