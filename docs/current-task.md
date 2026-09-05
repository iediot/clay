# Current Task

## Goal
Plan and prototype plastic landing deformation: impact shape persists at rest and is remolded only by rolling that shape through ground contact.

## Current State
Prototype working in the running scene: `shaders/clay_deform.gdshader` plus `scripts/clay_deform.gd`, driven from `player.gd`.

- An air-to-floor transition presses a flat facet, with a swell around its rim, into the ball along the contact normal; depth scales with the speed lost. Jump input cannot trigger it.
- Up to four facets are held in the body's own frame, so they ride along as the ball rolls. A landing on ground the ball is already flattened against deepens that facet instead of taking a slot.
- Remolding is gated on contact, not on travel or time. Each facet's axis is compared against the ground-contact direction every step, and it only accumulates wear inside a narrow patch (`contact_edge`/`contact_core`). A facet on the side or top of the ball, one held while idle, and one carried through the air are all left exactly as they were.
- Global rounding accrues only from ground-contact travel, capped at `round_max` and approached slowly (`round_length`), so the ball ends subtly smoother but keeps its sculpted lumps. Checked visually at the cap: still clearly hand-made, not spherical.
- Body and face meshes share the shader and the same world-space field, so the face deforms with the surface it rides on. The imported `StandardMaterial3D` settings are copied onto the shader at runtime.
- Collision and movement are untouched. Because collision stays a sphere, each frame the visual ball is shifted along the contact normal by the difference between the sculpted and deformed silhouette reach, so it neither floats nor sinks.

`tools/deform_probe.tscn` proves the rules against the real scene and passes: idle drift 0 over 1 s; 5.0 units of airborne travel and 5.0 rad of airborne spin change nothing; 34 units rolled with the facet clear of the ground change nothing; the facet needs 7 contact passes and 40 units of total rolling to work out. Landing height and impact speed still match the pre-change baseline.

## Next
1. Playtest for feel: facet depth, `knead_contact`, and whether a facet rolling under the ball reads as a clay bump or as a glitch.
2. Decide whether the spawn drop should mark the ball before the player has done anything.
3. The face still swings edge-on while rolling (pre-existing); judge that against the deformed body.

## Relevant Files
- `scripts/clay_deform.gd`
- `shaders/clay_deform.gdshader`
- `scripts/player.gd`
- `tools/deform_probe.tscn`
- `scenes/world.tscn`
