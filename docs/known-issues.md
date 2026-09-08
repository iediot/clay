# Known Issues

## One-time GLES3 "Parameter \"material\" is null" on startup

Four of these print once as the first frame is set up, from
`material_casts_shadows` / `material_is_animated` / `material_get_instance_shader_parameters` /
`material_update_dependency`. Nothing in the tree has a null material — a scan of every
`MeshInstance3D` surface finds none — and rendering, the deformation probe and frame timing are all
unaffected. It only appears with several of the generated meshes present at once; neither the
mountains nor the backdrop reproduces it alone, and reordering `cast_shadow` against the `mesh`
assignment does not clear it. Treated as backend noise.

## The grass mat's underside cap is wound against the drip skirt

The last drip row folds back up to the dirt footprint, and that closing cap is wound the same way
round the tip ring as the skirt above it — one full ring of back-facing triangles (660 at the
approved default, one per ring step at any length). It is hidden under the overhang and it is part
of what the approved look was signed off on, because the flipped faces also feed the smoothed vertex
normals at the drip tips. Length-independent, so it is not part of the resizing fix; correcting it
would change the drip-tip shading at the default. `tools/scale_probe.tscn` expects exactly one ring
of them and fails if the count moves.

## The side walls' texture projection jumps at the four corners

`_axis_of` gives each side vertex a planar projection — x on the long faces, z on the ends — and the
two disagree at the corners, so one sliver triangle at each corner carries a jump of half the slab's
length in UV. The number of affected triangles is fixed (about 180) and it is a hairline at any
length, but the jump inside those slivers grows with `size_x` (48x the correct rate at 80, 3386x at
800). Taking the horizontal coordinate from distance travelled round the outline would remove it,
at the cost of shifting the fingerprint's phase on the default's side walls.

## Backland width does not follow a long track

`backland.gd` fans from `size_x * 0.5` at the seam out to `backland_width` (210). Past about
size_x 300 the track is wider than the landform behind it, so the landform stops fanning and its
rolled rim comes into frame beside the track's ends. The stream is likewise pinned to |x| < 168.
Both are scenery, not the track, and neither shows at the approved default.

## Marching-squares winding, for anything hung off a contour

The snow's contour cells do not all come out wound the same way, so a quad hung below the contour
cannot trust the order its endpoints arrive in — `_face_quad` turns each one to face out and down
the slope instead. Two related traps, both of which produced visible artefacts before being fixed:
a drip whose foot sits exactly on the rock z-fights it into stripes along the snowline, so the foot
is held a fraction above; and anything derived from the *cell* (its centre, its edge midpoint)
differs between the two cells sharing a contour segment, which breaks the skirt into a comb of loose
ribbons — every property of the lip has to be a function of the contour point alone.

## A weld can still be see-through even when it is welded

The landform shares the track's rear edge vertex for vertex, yet the world was see-through along a
hairline there: a ray that grazes the shared edge passes just under the landform and then out
through the track's rear drips, which face away from the camera and are culled. Nothing is torn — the
wedge beneath the join simply had no front face. `ClayBackland._collar` gives it one.

Worth knowing because the usual checks all pass: a top-down render shows a solid slab, and an
open-edge count finds no holes. What finds it is rendering the gameplay camera against a magenta
background and counting magenta pixels below the horizon, which is cheap enough to keep doing after
any change to the seam.
