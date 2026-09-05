# clay

Godot 4.7 / GDScript claymation game. The target is an expressive rolling clay ball crossing a narrow, visible grass-over-dirt diorama.

- Preserve hand-sculpted plasticine: matte, bright, soft, irregular; avoid machine-perfect forms and shiny materials.
- Use the shared fingerprint normals with flat albedo/no albedo texture for new clay assets where applicable.
- The procedural terrain slab and player face-on-rolling-body relationship are intentional; see `docs/architecture.md`.
- GL Compatibility renderer and Jolt Physics are project constraints.
- Prefer surgical edits and minimal comments. Explain Godot/Blender concepts without assuming user expertise.

Read `AGENTS.md` first. Load docs selectively: architecture for structure, design before creative changes, current task for active state, decisions/plan/issues only when relevant. Search focused files; do not repeatedly load unchanged context. Update `docs/current-task.md` at meaningful milestones; persistent docs are compressed memory, not a transcript.
