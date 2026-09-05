# Decisions

## Procedural diorama terrain

Decision:
Terrain is a generated narrow grass-over-dirt slab, not the former tile/GridMap world.

Reason:
`terrain_generator.gd` intentionally excludes its mesh from scene storage and rebuilds it on load.

Implication:
Keep scene-level terrain configuration parameter-driven; preserve runtime collision generation when changing terrain creation.

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
