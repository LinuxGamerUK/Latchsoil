# Architecture

Godot presents. Rust decides. Gameplay rules do not live in GDScript.

This repository is the charter until milestone 0. Do not add `flake.nix`, `godot/`, or `rust/` until that milestone is the assigned task.

## Target tree

```
Latchsoil/
  flake.nix
  docs/
  data/
    races/
    items/
    buildings/
    laws/
    events/
  godot/
    project.godot
    latchsoil.gdextension
    scenes/
    assets/
    ui/
  rust/
    Cargo.toml            workspace
    sim/                  latchsoil-sim — no Godot types, plain cargo test
      src/
        clock.rs
        needs.rs
        skills.rs
        inventory.rs
        crafting.rs
        building.rs
        factions.rs
        combat.rs
        save.rs
        worldgen/
    godot-ext/            latchsoil-godot — the gdext cdylib and the bridge
      src/
        lib.rs
        bridge/
```

Two crates, one workspace. `latchsoil-sim` must not depend on gdext and must not name a Godot type — that is what makes "the rules are not in GDScript" true in the dependency graph instead of in a promise. `latchsoil-godot` holds the gdext entry point and a thin `bridge/`: Godot nodes that own entity ids and push input into the sim.

## Rules that keep the sim honest

- The sim ticks at 10 Hz. Render runs at whatever the machine holds. Input applies on the next tick.
- 1 unit is 1 meter. The build grid is 1 meter.
- Nothing in `sim/` iterates a `HashMap`. Fixed iteration order only, or a run stops being reproducible.
- Saves are versioned JSON through the early milestones, so a failing run can be opened in an editor. The save carries `save_version`, the tick count, and the RNG stream state; without the stream state a load cannot reproduce the run. A migration test guards the version. A Godot scene is not a save.
- The camera is Godot-owned view state and is not part of a save. Where the player was looking is a local preference.
- Pathfinding lives on the Rust grid, so a headless test and the running game agree.
- Races, items, buildings, laws, and events are RON files under `data/`. Comments are part of the format. A new people is numbers, text, an art key, and a starting kit — not a branch in the simulation.
- Headless checks run in the devshell (and in CI). Camera feel is a playtest written up in a short note under `docs/playtests/`. Do not treat a missing screenshot as a failed milestone.

## The bridge

[`docs/09-bridge.md`](09-bridge.md) defines the whole Godot↔Rust surface: the command list, entity id allocation, how sim state reaches a frame (snapshot or delta), how a tick aligns to a frame, and which side computes the one-line failure reason (`hungry`, `no path`, `no material`, `no skill`, `afraid`, `night`, `wounded`). It is a milestone 0 deliverable, because milestone 1 cannot be written without it.

## Godot and Rust versions

The flake pins **Godot 4.7.2** for the editor and the export templates, and a released `godot` crate (gdext) with its `api-4-7` feature target. Both ends of the toolchain are verified on 4.7.2, so there is no version split. `flake.lock` and `Cargo.lock` are committed, and the devshell reports `4.7.2.stable.nixpkgs.ed1daf0bf`.

The binding builds from prebuilt 4.7 bindings: no editor binary is needed to compile the extension. Only export templates ever need the engine installed alongside cargo.

If a gdext load ever fails under 4.7.2, the pin drops to **4.6.3** at both ends — editor, export templates and the crate's API feature — and the change is recorded in [`00-decisions.md`](00-decisions.md). No other version is supported.

## What Rust owns

Clock, needs, skills, inventory, crafting, building occupancy, faction relations, combat resolution, save and load, and world generation. If a rule can change a number the player cares about, it is Rust.

## What Godot owns

Camera, selection drawing, meshes, animation, light, UI layout, audio, and the translation of clicks into sim commands. If it can be wrong in a screenshot and right in the save file, it is still Godot's bug to fix, and the sim test should stay green.

## Determinism

A `u64` seed plus the same command list produces the same sim state. Render interpolation is allowed to differ. Tests compare sim state, not pixels.

## Milestone 0 shape, when it is asked for

The flake provides Godot and Cargo from one devshell, so the whole toolchain comes from a single pinned nixpkgs. `cargo test` runs the sim with no Godot process. `nix run .#test` then builds the extension, writes the one line Godot needs to find it, loads it headless, ticks the sim once and quits. The repository also carries its `.gitignore`, its licence, `docs/09-bridge.md`, and a CI workflow that runs the same checks on every push. Acceptance text lives in [07-milestones.md](07-milestones.md); what the build settled is in [00-decisions.md](00-decisions.md).
