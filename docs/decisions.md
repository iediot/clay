# Decisions

## Procedural diorama terrain

Decision:
Terrain is a generated narrow grass-over-dirt slab, not the former tile/GridMap world.

Reason:
`terrain_generator.gd` intentionally excludes its mesh from scene storage and rebuilds it on load.

Implication:
Keep scene-level terrain configuration parameter-driven; preserve runtime collision generation when changing terrain creation.

## The track's grain and its footprint are both length-independent

Decision:
Three things in `terrain_generator.gd` are cut loose from `size_x`:
- The cell is `GRAIN_SPAN / resolution`, a fixed number of world units, not `size_x / resolution`.
- The footprint is a straight run closed by superellipse end caps a fixed `size_z / 2` deep, not one
  superellipse stretched over the whole slab. `_outline` now takes a point on the unit square's
  edge — the square's end edges are the caps, its long edges the sides — and the caps are walked at
  equal arc (`_build_cap`, `_cap_point`).
- `_grid_divs` takes columns from the length and rows from the cap's arc, so the row count depends
  on `size_z` and `corner_sharpness` and never on `size_x`.
Ring and wall winding comes from the footprint loop's own turn (`_loop_ccw`), not a per-quad normal
test.

Reason:
Everything the slab has to resolve — drip lobes, the overhang, the height noise, the fingerprint
tile — is fixed in world units, so the mesh's grain has to be too. Two separate things scaled with
the length and made a long track fall apart. A fixed division count spread over the whole length
made every cell coarser. Worse, a single superellipse tapers over a fixed *fraction* of the length,
so at size_x 800 each end was a 44-unit spike that a fixed row count sampled in 11-unit steps: the
overhang went low-poly at the ends and the cells near the long edges stretched into visible marks
along the top grass. The per-quad normal test also failed on the sliver quads those ends produced,
flipping the dirt corners.

Implication:
`resolution` no longer bounds the triangle count; `size_x` does, linearly (about 500 triangles per
world unit of length). Every measured step — along the grid, across it, and round the outline the
overhang hangs from — is about 0.3 units at any length. `GRAIN_SPAN` is 80.0, the length the look
was authored at. The cap arc is retabulated whenever `size_x`, `size_z` or `corner_sharpness`
changes; `corner_sharpness` now shapes the cap alone, so it no longer trades against the aspect
ratio. Any new ring-hung wall should take its winding from the loop, not from a hint vector.

## Claymation material language

Decision:
Clay surfaces use matte flat colour with fingerprint normal detail.

Reason:
Documented project direction and supplied normal-map assets.

Implication:
New visible assets should support the same hand-sculpted read unless intentionally contrasted.
The grain must also be the same size everywhere: the imported player unwrap is
far finer than the terrain's, so `clay_deform.gd` rescales each surface's UVs at
load onto one world-space `fingerprint_size` and applies the terrain's own relief
depth. Keep that in step with `terrain_generator.gd`'s `texture_scale` (the tile
spans 1/texture_scale^2 units, as it is applied to both the mesh UVs and
`uv1_scale`) and `fingerprint_strength`.

## Plastic deformation by shader, not blend shapes

Decision:
Landing deformation is a runtime vertex shader over the imported model, and the
player's clay surfaces are `ShaderMaterial`s built at load from the imported
`StandardMaterial3D` settings.

Reason:
The shader spike proved the shape and the face/body relationship without Blender
work, and it keeps the hand-sculpted irregular mesh authoritative. A shared
material was needed because `StandardMaterial3D` cannot carry a vertex program.

Implication:
Changes to the imported player materials must stay expressible by
`shaders/clay_deform.gdshader`. Deformation state lives in the body's own frame
and is remolded only while that facet is passing through the ground-contact
patch; never reintroduce a time-based decay, an elastic rebound, or a fade
driven by generic player travel. `scripts/clay_deform.gd` mirrors the shader's facet maths
so ground contact matches what is drawn — the two must change together.

## The world behind the track is the same mesh, not a backdrop

Decision:
`terrain_generator.gd` hands its `ArrayMesh` to `ClayBackland`, whose first vertex row is produced
by the same `rear_edge_point`/`surface_height` calls the track's rear boundary uses.

Reason:
The landform has to grow out of the track rather than sit behind it. Sharing the functions makes the
weld exact by construction instead of by tuning, and both sides of the seam are given the height
field's analytic normal so the drips hanging under the rear edge cannot darken it into a line.

Implication:
Never let the backland's terms be non-zero at depth 0 — every one of them is gated so the first row
reduces to the track's own edge. Collision is taken from the track surfaces before the backland is
appended; keep that snapshot if `generate()` is reordered. The landform is grass only: the dirt
cutaway is the track's alone.

## Mountains are objects, the landform is terrain

Decision:
The range is a separate `MeshInstance3D` of blunt clay cones (`clay_mountains.gd`), not a heightfield
feature, and its snow is a second surface laid over each cone.

Reason:
The style is pressed-out plasticine, and simple cones read as handmade where sculpted terrain reads
as landscape. Keeping them separate also keeps the grass landform one flat colour.

Implication:
Snow reuses the track's overhang idea — a wandering stop line, then tongues that bulge and thin to
close against the rock. It must keep visible thickness; a thin offset reads as paint. Mountain feet
sit below the landform's ridge and are meant to stay hidden.

## Props are a variant library, not one mesh each

Decision:
`scenery.gd` generates about a dozen variants per prop kind and instances them with random spin and
scale; long parts (blades, stems, leaves) are swept tapered strands, not stacks of spheres.

Reason:
A fresh lumpy-ball mesh per plant took 56 s to open the scene, and beads on a curve read as beads.
Sweeping one tube along a bend is both far cheaper and the only way a blade looks like one piece of
clay.

Implication:
Keep the library small and the sweeps low-segment. The material cache is keyed by colour and scale
and deliberately outlives a rebuild, and children are released with `queue_free` so the renderer
still holds them for the frame.
