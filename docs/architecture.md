# Architecture

`project.godot` — Godot 4.7 entry configuration; launches `scenes/world.tscn`.

`scenes/world.tscn` — composition root: player instance, player-child camera, directional light/environment, and `Terrain`.

`scenes/player.tscn` + `scripts/player.gd` — `CharacterBody3D` movement/jump and visual rolling. The imported `PlayerModel` is split at runtime: largest mesh is the body; remaining meshes are the face. Face motion follows body rotation, leads lateral input, then returns to rest.

`scripts/clay_deform.gd` + `shaders/clay_deform.gdshader` — plastic landing deformation for the player. The script replaces the imported player materials with one shared deformation shader, keeps facet state in the body's own frame, and drives the shader's world-space field. Visual only: collision and movement are untouched, so it also offsets the drawn ball to keep it on the ground.

`scripts/terrain_generator.gd` — `@tool` `MeshInstance3D` that builds the world slab from exported shape/noise/look parameters. It creates grass top/overhang and dirt underside; at runtime it builds matching trimesh collision. Generated mesh data is excluded from scene storage and rebuilt on load.

`tools/deform_probe.tscn` — dev harness that drives the real player in the real world scene and checks the deformation rules (idle holds, airborne travel does nothing, only contact passes remould). Run `godot --path . --headless --quit-after 12000 res://tools/deform_probe.tscn`; it prints PASS/FAIL lines and exits non-zero on failure.

`assets/` — imported player/grass/dirt models and fingerprint normal/roughness textures. `scenes/ground.tscn` and `scenes/grass_tile.tscn` are standalone asset compositions, not referenced by `world.tscn`.

Flow: Godot loads World -> Terrain generates render mesh (and runtime collision) -> Player physics uses it -> Player-child camera follows the character.
