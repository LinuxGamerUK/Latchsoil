# Charter decisions

A running log of decisions that change this charter. Newest last. Each entry names the decision and the reason, so a later reader does not have to guess why the numbers moved.

## 2026-10-18 — review pass, before milestone 0

1. **Engine and bindings pinned to Godot 4.7.2.** Both ends of the toolchain are verified on 4.7.2 and the `godot` crate publishes an `api-4-7` feature target, so the fallback is contingency only. If a gdext load actually fails under 4.7.2, the pin drops to 4.6.3 at both ends and this file records it. No other version is supported.
2. **Milestone 1 is split into 1a and 1b.** As written it was camera, selection, orders, four resources, three buildings, three craft items and save/load in one commit — too much to accept honestly in one step.
3. **Crops grow about five days, two crops to a season.** A season is ten days, so a plot planted on day 1 pays inside the season. Four worked plots must leave surplus after spoilage and seed, not break exactly even.
4. **The camera is view state, not save state.** The sim save holds needs, positions, jobs, inventory, the tick count and the RNG stream. Where the player was looking is a local preference and does not travel with a save.
5. **The project is called Latchsoil** everywhere: directory, Forgejo repository, GitHub repository.
6. **This repository is public.** No host names, addresses, paths, network names, operator details or build-machine specifics belong in it. Headless checks are described as running in the devshell, never on a named machine.

## Rules added during the same review, reversible if unwanted

- `rust/` is a two-crate workspace: `latchsoil-sim` (no Godot types, no gdext dependency, plain `cargo test`) and `latchsoil-godot` (the gdext cdylib and the bridge). "Rules stay out of GDScript" is enforced by the dependency graph, not by intent.
- The save carries `save_version` and the RNG stream state, and a migration test guards the version. Without the RNG state, load cannot reproduce a run.
- Nothing in `sim/` iterates a `HashMap`. Fixed iteration order only.
- `docs/09-bridge.md` — the command list, entity ids, per-tick state transfer and failure strings — is a milestone 0 deliverable, because milestone 1 cannot be written without it.
