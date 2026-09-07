# Architecture

`project.godot` — Godot 4.7 entry configuration; launches `scenes/world.tscn`.

`scenes/world.tscn` — composition root: player instance, player-child camera, directional light/environment, `Backdrop`, `Mountains`, `Terrain` and `Scenery`. The two new sub-scenes are referenced by UID.

`scenes/player.tscn` + `scripts/player.gd` — `CharacterBody3D` movement/jump and visual rolling. The imported `PlayerModel` is split at runtime: largest mesh is the body; remaining meshes are the face. Face motion follows body rotation, leads lateral input, then returns to rest.

`scripts/clay_deform.gd` + `shaders/clay_deform.gdshader` — plastic landing deformation for the player. The script replaces the imported player materials with one shared deformation shader, keeps facet state in the body's own frame, and drives the shader's world-space field. Visual only: collision and movement are untouched, so it also offsets the drawn ball to keep it on the ground.

`scripts/terrain_generator.gd` — `@tool` `MeshInstance3D` that builds the world slab from exported shape/noise/look parameters. `resolution` is a grain, not a division count: it is the number of cells laid across `GRAIN_SPAN` world units, so the cell stays the same size whatever `size_x` is. The footprint is a straight run closed by fixed-size superellipse caps, and `_outline` maps the grid square's edges onto it — end edges to the caps, long edges to the sides — so the ends keep both their shape and their share of the grid at any length. It creates grass top/overhang and dirt underside; at runtime it builds matching trimesh collision from the track surfaces only. Generated mesh data is excluded from scene storage and rebuilt on load. When `backland_enabled` it also hands the same `ArrayMesh` to `ClayBackland`, and exposes the seam (`rear_edge_point`, `surface_height`, `seam_normal`), the shared material recipe (`clay_material`, `commit_surface`, `water_material`) and surface queries for planting (`landform_height`, `stream_distance`, `stream_bank_z`).

`scripts/backland.gd` — `ClayBackland`, the landform behind the track, appended as extra surfaces of the terrain's own mesh. Its first vertex row is the track's rear top edge, so the two are welded by construction; behind that it fans out, banks into grass hills, closes on a ridge, rolls its free sides into a lipped edge with a hidden skirt, and presses in the stream bed. Winding comes from grid topology, never a world-up hint.

`scripts/clay_mountains.gd` + `scenes/mountains.tscn` — the backdrop range: blunt grey clay cones standing behind the landform, each with a white snow layer built by the track's overhang logic (a wandering stop line, then tongues that bulge and thin to close against the rock).

`scenes/backdrop.tscn` — sky and sun, held near-fixed on screen by `scripts/backdrop_anchor.gd` (follow 1.0 locks the sky, 0.94 lets the sun drift slowly). `scripts/clay_sky.gd` generates the lumpy inward dome; `scripts/clay_prop.gd` puts `Sun.glb` into the world's material language.

`scripts/scenery.gd` + `scripts/clay_shapes.gd` — authored planting clusters on the landform. `ClayShapes` builds props from two primitives: a lumpy ball for masses and a swept tapered strand for anything long (blades, stems, leaves). A small library of variants is generated once and reused across placements.

`shaders/clay_water.gdshader` — the stream ribbon: matte, opaque, its fingerprint creeping downstream with a small cross swell.

`tools/shot.tscn` — dev harness that parks the player at given X positions in the real world scene and writes a PNG of the gameplay camera for each. Run `godot --path . --resolution 1920x1080 res://tools/shot.tscn -- --out=<dir> 0 -36 36`.

`tools/scale_probe.tscn` — dev harness that builds the track at a sweep of `size_x` values and checks grain, gaps, winding, normals, editor-vs-runtime regeneration and collision coverage. Run `godot --headless --path . res://tools/scale_probe.tscn -- 20 80 200 400`; it prints PASS/FAIL lines.

`tools/deform_probe.tscn` — dev harness that drives the real player in the real world scene and checks the deformation rules (idle holds, airborne travel does nothing, only contact passes remould). Run `godot --path . --headless --quit-after 12000 res://tools/deform_probe.tscn`; it prints PASS/FAIL lines and exits non-zero on failure.

`assets/` — imported player/grass/dirt/tree/sun models and fingerprint normal/roughness textures. Every generated material shares the one `GrassBlock_..._normal` texture, and the tree/sun GLBs import with their embedded copies discarded. `scenes/ground.tscn` and `scenes/grass_tile.tscn` are standalone asset compositions, not referenced by `world.tscn`.

Flow: Godot loads World -> Terrain generates the track, then the backland continuation, then runtime collision from the track alone -> Scenery plants itself off the landform's built grid -> Player physics uses the track -> Player-child camera follows the character, with the backdrop anchors trailing it.
