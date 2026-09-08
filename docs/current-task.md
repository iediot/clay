# Current Task

## Goal
Build the world around the playable track: one connected clay landform behind it, a finite
mountain backdrop, sky and sun, and scenery — without changing the track, the player, the
deformation, the camera or the automated check.

## Current State
Verified from the gameplay camera at x = -36, 0 and +36 (`tools/shot.tscn`).

- **Everything scales with `size_x`.** The landform's half-width is the track's
  half-length plus `backland_margin` — the margin is how much ground the camera needs beside the
  route, so it is added rather than multiplied, and lengthening the track grows the world by exactly
  its own extra length. The stream's reach and drift, the mountain range's span and count, and the
  scenery's cluster counts are all expressed per unit of length, so density and framing are the same
  at any size_x. Verified identical framing at 60, 200 and 800.
- **One landform.** `scripts/backland.gd` continues the terrain slab behind the track. Its first
  row of vertices *is* the track's rear top edge — same `_outline` call, same height noise — so the
  weld is exact by construction, and both sides of it take the height field's analytic normal so it
  does not shade as a crease. From there the surface fans out to ±210, banks up into grass knolls
  and closes on a low ridge. Grass only: the dirt cutaway remains unique to the track, whose own
  overhang, drips and end caps are untouched.
- **Every falloff is grass over dirt.** Where the landform's grass runs out it is built like the
  track's edge and never as a cut sheet: the mat rolls over into drips hung off the same shared
  `drip_profile`, closes back underneath at its own thickness, and stands on a real mass of dirt in
  the track's own dirt clay. The seam row is left open because it is welded to the track.
- **The fan carries the track's column density only where it is needed.** Fine columns out to
  12 units behind the seam — the weld has to match the track vertex for vertex — then a thinned set
  joined by one stitched strip that uses every fine vertex, so the two densities share an edge and
  cannot crack. Without it an 800-long track put 330k vertices into background fan.
- **Collision is the track only.** `terrain_generator.gd` snapshots the two track surfaces before
  the backland is appended and builds the trimesh from that, so physics is unchanged.
- **Mountains** (`scripts/clay_mountains.gd`, `scenes/mountains.tscn`) are one height field behind
  the landform, not terrain and not a row of cones. Each is described by a crest line — a short
  polyline of points carrying a height and a flank width — so the large forms are the ones real
  mountains have: a summit, ridges running off it, saddles between tops, and flanks that run out
  further on one side than the other. Six named silhouettes (horn, crest, shoulder, twin, saddle,
  dome) are drawn from in an alternating major/minor rhythm. A separable blur over the field is what
  makes them plasticine — broad blunt surfaces, rounded crests, no small detail anywhere.
- **Snow** is a second sheet over the same field, clipped to a wandering contour by marching squares
  so its edge is a smooth curve rather than a grid staircase, lifted along the surface normal, and
  closed by a lip that bulges out and comes back down onto the rock a little way downhill. Because
  the foot is sampled from the rock height it cannot float, and because the field carries each
  summit's own height the snow line follows that mountain rather than one flat altitude.
- **Sky and sun** (`scenes/backdrop.tscn`). The sky is one flat cyan-blue inward dome thumbed into
  broad lumps, with the fingerprint scaled up (330 units per tile) to still read at 900 units away.
  It is locked to the camera, so it never parallaxes. `Sun.glb` sits upright at x -236, y 112,
  z -430 on a 0.94 follow, which holds it within ~20 px of the same screen position across the whole
  track.
- **Stream.** The bed is pressed into the same clay: a rounded groove with a raised lip and a
  lifted far bank so the camera looks into it rather than skimming it. The water is a ribbon on
  `shaders/clay_water.gdshader` — matte, opaque, its fingerprint creeping downstream with a small
  cross swell. Planting is kept out of the bed.
- **Scenery** (`scripts/scenery.gd`, `scripts/clay_shapes.gd`). Five depth bands, each with its own
  cluster rate per 100 units of length, planted biggest-first: tree stands claim their room, then
  shrubs and stones, then ground cover between them, then a sweep that seeds whatever came out bare.
  Every candidate is tested against a coarse occupancy hash using a per-kind footprint, so a flower
  cannot grow up through a stone and a trunk cannot stand in a boulder; against the landform's own
  extent, so nothing is planted in the air off the rim; and against a low-frequency mask that keeps
  a few deliberate clearings. Nothing is placed within 8 units of the track's rear edge.
- **Clusters are mixed communities, not patches of one kind.** A cluster draws its whole list from
  one character — grove, thicket, rocky, meadow, clearing — so stones, stumps and fallen logs stand
  among a grove's trees and a rocky patch has a tree or two in it. Placement still runs biggest-first
  globally: trees and logs go down across the whole world before anything small does, so they keep
  their room without the kinds separating into patches.
- **Woody props are remeshed reference models.** `Log1/2`, `Stump1/2/3`, `Tree3` (broadleaf) and
  `Tree4` (small conifer) come from the reference forest set through
  `tools/blender/export_clay_props.py`, which repeats the Tree1/Tree2 recipe: split, join the canopy,
  voxel remesh, swell, relax. `ClayShapes` now only makes the small ground cover. Loose stone comes
  in five tones, two of them the grey the mountains are made of. `Tree1.glb`/`Tree2.glb` are used as-is with
  trunk and canopy recoloured and the shared clay material applied; each is set into the ground with
  a mound of clay pushed up round the foot. Everything else is generated: rocks and bush lobes are
  lumpy balls; grass blades, flower stems and leaves are swept tapered strands laid along a bend, so
  each one arcs and droops as a single continuous piece.

### Performance
Launch is dominated by mesh generation, not by rendering: uncapped the scene runs at about 310 fps
(3.2 ms/frame, ~1400 draw calls). Start-up at `size_x` 800 went 2.38 s -> 1.30 s through, in order of
what each was worth: handing surfaces over as arrays with analytic tangents instead of `SurfaceTool`,
caching the built terrain mesh on disk, reading neighbouring rows by index rather than searching them
by x when the landform's two column densities agree, and skipping snow cells whose corners are all
outside the sheet.

### Measured
- `tools/deform_probe.tscn`: all seven checks pass, with the same numbers as the pre-change
  baseline (facet 0.2058 deep, 7 contact passes, 40.02 units rolled, rounding 0.198).
- Startup 1.4 s; 1080p runs vsync-capped at 8.3 ms/frame, 190 draw calls, 47.6 MB video memory.
- `scenes/backdrop.tscn` and `scenes/mountains.tscn` carry their own UIDs and are referenced from
  `world.tscn` by UID; both survive a Godot re-save.

### Track length
`size_x` is safe to change. Two things scaled with it and had to be cut loose.

- **Grain.** `resolution` was a division count spread over the whole length, so the world cell grew
  with `size_x` — 0.67 at 200, 1.33 at 400 — against a drip lobe about 7 units across and a grass
  mat 0.8 thick. It is now `GRAIN_SPAN / resolution`, a fixed 0.2667 units.
- **Footprint.** One superellipse over the whole slab tapers over a fixed *fraction* of the length,
  so at size_x 800 each end was a 44-unit spike sampled in 11-unit steps: low-poly overhang at the
  ends, and cells near the long edges stretched into marks along the top grass. The footprint is now
  a straight run closed by caps a fixed `size_z / 2` deep, walked at equal arc, and `_outline` maps
  the grid square's end edges onto them. Rows come from the cap's arc, columns from the length.
- **Winding.** The dirt wall and floor took their winding from a per-quad normal test, which failed
  on the sliver quads those long ends produced (18 flipped triangles at size_x 400). It now comes
  from the footprint loop's turn.

Verified with `tools/scale_probe.tscn` at size_x 20, 30, 80, 200, 400 and 800: every step — along the
grid, across it, and round the outline — sits between 0.295 and 0.384 units at every length, where
across-the-grid used to run from 1.13 at 80 to 11.2 at 800. No degenerate triangles, no bad normals,
no gaps, no flipped faces beyond the one pre-existing ring under the overhang, in-tree (editor)
regeneration equal to a fresh build, collision equal to the two track surfaces. Triangle count is
linear in length: 41 k at 80, 214 k at 400.

## Next
1. Clouds — the sky was left with room for them and nothing was authored.
2. Judge whether the landform's rolled rim should ever be visible at the extreme sides, or whether
   the fan should open faster still.
3. The near flank beside each end of the track is the emptiest part of the frame.

## Relevant Files
- `scripts/backland.gd`, `scripts/terrain_generator.gd`
- `scripts/clay_mountains.gd`, `scripts/clay_sky.gd`, `scripts/backdrop_anchor.gd`
- `scripts/scenery.gd`, `scripts/clay_shapes.gd`, `scripts/clay_prop.gd`
- `shaders/clay_water.gdshader`
- `scenes/world.tscn`, `scenes/backdrop.tscn`, `scenes/mountains.tscn`
- `tools/shot.tscn`, `tools/scale_probe.tscn`
