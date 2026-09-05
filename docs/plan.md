# Development Plan

Current baseline: an implemented scene with a generated terrain slab, player movement/jump/rolling presentation, and a following camera. There is no objective, interaction, UI, audio, or automated validation configuration in the tracked project.

## BLOCKERS — prove the vertical-slice baseline

### Prototype natural clay landing deformation
Objective: make a landing visibly compress and spread the ball, then retain that plastic shape while idle. Only rolling movement gradually remolds it, never into a generic scale squash or perfect sphere.

Systems: `scripts/player.gd`, `scenes/player.tscn`, body/face mesh materials; likely a new player deformation shader.

Dependencies: baseline jump/landing playtest.

Approach:
1. Detect the air-to-floor transition and capture pre-collision downward speed; add its deformation to persistent visual shape state. Do not trigger from jump input.
2. Prototype a body-only vertex deformation in the impact/contact direction: localized bottom flattening and lateral bulge. Hold this state while idle; keep collision and movement unchanged.
3. Use actual rolling distance/speed, not elapsed idle time, to slowly remold that state toward a capped average radius. Retain the mesh's existing radial variation so the result never becomes spherical.
4. Feed the same surface displacement into face placement/lift (or deform face meshes consistently). The face must not sink into or float above the body.

Done: light and heavy landings read differently; landing shape remains visibly changed while idle; only rolling remolds it; deformation is localized/organic rather than uniform scaling; silhouette stays lumpy; face attachment and ground contact remain convincing; no movement or collision regression.

Experiment first: shader deformation versus authored blend shapes. Prefer a shader spike initially: it keeps this visual-only, preserves the imported irregular model, and avoids committing to Blender work before the motion is proven. Use blend shapes only if the shader cannot make the face/body relationship credible.

### Playtest and stabilize traversal
Objective: verify the current scene is controllable and visually readable before adding systems.

Systems: `scenes/world.tscn`, `scripts/player.gd`, `scripts/terrain_generator.gd`.

Dependencies: none.

Done: player lands/runs/jumps reliably on generated collision; camera keeps player and terrain cutaway readable; no visible terrain/face regression in a normal play session.

### Define the first player objective
Objective: select a concrete, finishable traversal loop (destination, obstacle, or collection) and success/failure feedback.

Systems: new gameplay/world content, player/world integration.

Dependencies: stable baseline.

Done: a player can understand, attempt, complete, and restart one short challenge.

Experiment first: objective type, challenge length, camera framing, and whether momentum/precision is central to the roll.

## IMPORTANT — turn the slice into a coherent game

### Build level-ready terrain/world composition
Objective: make the procedural slab support the selected challenge without losing the exposed-dirt diorama read.

Systems: terrain generator, world scene, future obstacle/content scenes.

Dependencies: first objective.

Done: world parameters/content create a readable route, safe start, clear finish, and intentional boundaries.

### Tune player and camera as one system
Objective: tune movement, jump, roll/face response, and camera for readable clay-character control.

Systems: `scripts/player.gd`, `scenes/player.tscn`, `scenes/world.tscn`.

Dependencies: representative challenge.

Done: traversal feels responsive, the face stays convincing over motion, and framing supports anticipation and landing.

### Add essential feedback
Objective: communicate state, objective progress, completion, and restart with minimal UI/audio/visual feedback.

Systems: new UI/audio/feedback assets.

Dependencies: defined loop and states.

Done: players can act without external explanation and receive clear responses to success/failure.

## NICE TO HAVE — polish after the loop works

### Claymation presentation pass
Objective: improve lighting, material consistency, terrain silhouette, and environmental dressing within the established visual language.

Dependencies: stable framing and level composition.

Done: the scene consistently reads as a deliberately hand-sculpted diorama in motion.

### Performance and release validation
Objective: measure the representative scene, reduce avoidable generation/render cost, and test packaged play.

Dependencies: representative content.

Done: target-platform playtest passes; performance decisions are measured rather than assumed.

## DEFERRED

- Multiple levels, progression, broad content libraries, and elaborate UI: defer until one polished challenge proves the loop.
- New rendering technology or broad architectural rewrites: defer unless measurement or a visual requirement justifies them.
