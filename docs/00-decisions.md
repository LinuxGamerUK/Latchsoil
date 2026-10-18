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

## 2026-10-18 — milestone 0, as built

What the build settled, so nobody rediscovers it:

1. **The toolchain comes from `github:NixOS/nixpkgs/nixos-unstable`, frozen in `flake.lock`** (currently the 2026-10-15 revision, `fe1324228`). There is no `nixos-26.11` branch on GitHub to pin, and `nixos-unstable` is the branch that actually ships Godot 4.7.2. The devshell gives Godot `4.7.2.stable.nixpkgs.ed1daf0bf` — the same build the editor reports.
2. **The binding needs no editor to compile.** `godot` 0.5.5 with `api-4-7` compiles against prebuilt bindings shipped in `gdextension-api` 0.5.1 (API 4.7.0) and never invokes Godot. `GODOT4_BIN` stays exported in the devshell for the `api-custom` path only.
3. **`extension_list.cfg` is not optional.** A game run does not scan for `.gdextension` files: Godot loads only what `<project>/.godot/extension_list.cfg` names, and only the editor writes that file during import. A fresh checkout has no extension at all until `scripts/smoke.sh` writes the one line. The headless editor's own `--import` pass writes it and then aborts, so its exit code cannot be used as a gate.
4. **The library stays inside the project.** `scripts/build-extension.sh` links the cdylib into `godot/bin/`, and `latchsoil.gdextension` names `res://bin/liblatchsoil_godot.so`. A path outside the project (`res://../rust/target/...`) also loads under the editor, but it is unproven for export, so the tree does not use it.
5. **The smoke scene fails closed.** If `SimHost` is not registered the harness exits 3; a save with no `save_version` exits 4. Godot itself only continues with an error line when the library is missing, so a check that trusted the engine's exit code alone would pass a broken build.
6. **`./` is the only entry point for checks**: `nix run .#test` runs the workspace tests and then the headless load from the repository root. A bare `cargo test` fails there — the workspace lives in `rust/`.
