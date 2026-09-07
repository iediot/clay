# Current Task

## Goal
Build the world around the playable track: one connected clay landform behind it, a finite
mountain backdrop, sky and sun, and scenery — without changing the track, the player, the
deformation, the camera or the automated check.

## Current State
Verified from the gameplay camera at x = -36, 0 and +36 (`tools/shot.tscn`).

- **One landform.** `scripts/backland.gd` continues the terrain slab behind the track. Its first
  row of vertices *is* the track's rear top edge — same `_outline` call, same height noise — so the
  weld is exact by construction, and both sides of it take the height field's analytic normal so it
  does not shade as a crease. From there the surface fans out to ±210, banks up into grass knolls
  and closes on a low ridge. Grass only: the dirt cutaway remains unique to the track, whose own
  overhang, drips and end caps are untouched.
- **The landform's free sides** roll over into a lipped grass edge and a skirt down to y = -150,
  so the landmass reads as a finite sculpted object rather than an open landscape. The seam row is
  left open because it is welded to the track.
- **Collision is the track only.** `terrain_generator.gd` snapshots the two track surfaces before
  the backland is appended and builds the trimesh from that, so physics is unchanged.
- **Mountains** (`scripts/clay_mountains.gd`, `scenes/mountains.tscn`) are separate background
  objects standing behind the landform, not terrain: eight blunt grey clay cones with a couple of
  gentle lobes each, varied in height, width and bluntness. Their feet sit below the landform's
  ridge, so only their upper bodies are seen.
- **Snow** is a second clay layer over each cone, built with the track's overhang logic: the line it
  stops at wanders with the bearing, and below it tongues sag down selected sides, bulging and then
  thinning to close against the rock. It has visible thickness, not a painted stripe.
- **Sky and sun** (`scenes/backdrop.tscn`). The sky is one flat cyan-blue inward dome thumbed into
  broad lumps, with the fingerprint scaled up (330 units per tile) to still read at 900 units away.
  It is locked to the camera, so it never parallaxes. `Sun.glb` sits upright at x -236, y 112,
  z -430 on a 0.94 follow, which holds it within ~20 px of the same screen position across the whole
  track.
- **Stream.** The bed is pressed into the same clay: a rounded groove with a raised lip and a
  lifted far bank so the camera looks into it rather than skimming it. The water is a ribbon on
  `shaders/clay_water.gdshader` — matte, opaque, its fingerprint creeping downstream with a small
  cross swell. Planting is kept out of the bed.
- **Scenery** (`scripts/scenery.gd`, `scripts/clay_shapes.gd`). Authored clusters, each mixing a
  tall silhouette, a middle mass and a low fringe, plus a gappy verge on the bank behind the track,
  bank dressing along the water, and a few lone trees. `Tree1.glb`/`Tree2.glb` are used as-is with
  trunk and canopy recoloured and the shared clay material applied; each is set into the ground with
  a mound of clay pushed up round the foot. Everything else is generated: rocks and bush lobes are
  lumpy balls; grass blades, flower stems and leaves are swept tapered strands laid along a bend, so
  each one arcs and droops as a single continuous piece.

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
