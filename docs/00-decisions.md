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

## 2026-10-18 — milestone 1a, as built

- **The sim grew a world, and the bridge shrank.** `latchsoil-sim` now owns the acre, the cast, the nodes, the command queue, the owner table, pause, speed, the tick accumulator and the rejection counters (`rules.rs`, `path.rs`, `catalog.rs`, `snapshot.rs`, and a rewritten `state.rs`). `latchsoil-godot` is a thin adapter: it converts the sim's plain snapshot records into Godot dictionaries and never keeps a second copy of anything the sim owns.
- **Two workstreams built those halves in parallel and the bridge was written against the older sim API.** It did not compile — and the milestone's own harness caught it, not a human. **Lesson: when two workstreams share an interface, freeze the interface and the file ownership first, and budget the integration step as real work.**
- **`nix run .#test` is the gate and it is green:** 38 sim tests, the milestone 0 smoke line, and `scripts/check-1a.sh` reaching `1a: ok`. The harness proves move, gather, eat (both paths), `no path`, stale-id rejection and cross-entry-point determinism **through the bridge**, not only in Rust.
- **A headless host can produce real frames.** `scripts/render.sh` renders any scene through software Vulkan (lavapipe) under Xvfb, about 1.3 s a frame warm at 640x360, verified by decoding the PNG and by eye. Visual checks no longer need a human's machine; camera *feel* still does.
- **Scene defects the first cut shipped, all found by a static review and all fixed:** the selection ring was wider than the spacing between the starting three people; the order path was drawn only while its owner stayed selected, though the sim keeps it until the job ends; the fibre node was a two-pixel tuft; the drafted yoke was three pixels thick in a near-identical colour; and a failure string could be attributed to the wrong person.

## 2026-10-18 — needs rates are defined in days, not per-tick fractions

1. **Needs rates are defined in days, not per-tick fractions.** A per-tick constant in the contract let a rule empty a person in six seconds while the same paragraph said 1.7 days, and the blockout was unplayable after four seconds as a result. Two guards: a person must be able to accept work for at least ten minutes of play at 1x before hunger refuses it, and the acre cast starts with four grain (`STARTING_GRAIN = 4`), because the acre yields no food.

## 2026-10-18 — milestone 1b interface

1. **`Command::Take` joins the enum.** A stockpile that can only receive goods is a hole, not a store: without a way out, hauling into it destroys the goods for every purpose the player has. The enum is closed, so this is a charter change and it is recorded here.
2. **`FailureReason::NoStation` joins the enum.** A recipe that needs a fire or a shelter must say so in the one line the HUD prints. Reporting `no material` while the inputs are in hand would be a lie.
3. **A building is built, not conjured.** `Place` allocates the building immediately, but it counts as a building only once `progress` reaches `BUILD_TICKS`, so `JobKind::Build` has a rule and the player watches a work site become a building. A half-built campfire is not a station.
4. **`save_version` becomes 2, with no migration.** Nothing has shipped, so a version 1 save is refused rather than half-read. The save gains buildings, their progress and the contents of every stockpile.
5. **The bandage heals nothing in 1b.** Wounds are milestone 2. The item exists so the lean-to has a reason and the fiber has a use; its rule does not exist yet, and no test may claim otherwise.
6. **A recipe's station is a distance, not a room.** `STATION_RANGE_M = 2.0` keeps 1b free of interior spaces while still making placement matter. Interiors, if they ever exist, are a later milestone.

## 2026-10-18 — milestone 2 interface

1. **`Command::Heal { actor, target, item }` joins the enum.** Healing names who is being treated, and `Work { actor, job }` has nowhere to put a target. Self-treatment is allowed — one person alone on a holding has to be able to bandage their own arm, and forbidding it would make a wound unsurvivable rather than interesting.
2. **`JobKind::Rest` joins the closed job list.** `Work { actor, job: Rest }` is how a person sleeps, and sleeping has to report as something; reusing an existing kind would put a lie in the HUD's job line.
3. **`FailureReason::Tired = 8`.** An exhausted worker stops, and the one line the HUD prints has to say why. The alternative is a player watching a person slow down and guessing at the cause.
4. **`no skill` finally has a rule, and it guards medicine only.** A salve needs `medicine` skill at 0.25; bandaging needs nothing, because a bandage is cloth and a wound anyone can tie. Gating the cheap treatment behind a skill would make the acceptance line ('a wound stabilises with one') a lottery.
5. **Nothing wounds anybody in this milestone.** Attacks are milestone 5, so wounds arrive in tests and saves; milestone 2 is the set of rules that bleed, infect, treat and heal them. Any test that wounds a person sets the wound explicitly and says so.
6. **Warmth drifts toward an ambient target rather than tracking a temperature in degrees.** The sim has no thermometer and the fiction does not need one: what matters is that night is a cost, a campfire is an answer, and both are readable from one number. **Amended the same hour, before anything was built:** the first freeze set the night target to 0.35, which makes the cold rule unreachable — a person in the open at night settles *just above* the drain threshold and never takes the damage the rule exists to model. The night target is now 0.0, a finished lean-to raises it to 0.6 and a finished campfire to 1.0, so shelter is an answer and a fire is a better one. A rule that can never fire is not a rule, and shipping one that only looks like it fires is worse.
7. **`save_version` becomes 3, still with no migration.** Second milestone in a row with nothing shipped; the refusal stays honest rather than offering a half-read.
