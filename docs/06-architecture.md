# Architecture

Godot presents. Rust decides. Gameplay rules do not live in GDScript.

This repository is the charter until milestone 0. Do not add `flake.nix`, `godot/`, or `rust/` until that milestone is the assigned task.

## Target tree

```
Project-Game-Dev/
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
    Cargo.toml
    src/
      lib.rs
      bridge/
      sim/
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
  tests/
```

`lib.rs` is the gdext entry. `bridge/` is thin Godot nodes that hold entity ids and push input into the sim. `sim/` has no Godot types if a split can keep them out. `tests/` runs scenarios with no window.

## Rules that keep the sim honest

- The sim ticks at 10 Hz. Render runs at whatever the machine holds. Input applies on the next tick.
- 1 unit is 1 meter. The build grid is 1 meter.
- Saves are versioned JSON through the early milestones, so a failing run can be opened in an editor. A Godot scene is not a save.
- Pathfinding lives on the Rust grid, so a headless test and the running game agree.
- Races, items, buildings, laws, and events are RON files under `data/`. Comments are part of the format. A new people is numbers, text, a mesh, and a starting kit.
- Headless checks run on this NixOS host. Camera feel is a Legion playtest written up in a short note under `docs/playtests/`. Do not treat a missing screenshot on this host as a failed milestone.

## Godot and Rust versions

Nixpkgs on this machine provides Godot 4.7.2 and Rust 1.98.1. godot-rust's stable API target at the time of this charter is 4.6.

Milestone 0 must prove a gdext library loads under Godot 4.7.2. If it does not, pin Godot 4.6 in the flake and stay there. Record the choice in `docs/06-architecture.md` rather than leaving it as a guess in a commit message.

Prefer a released godot crate. A git pin of gdext is allowed only when the 4.7 load requires it, and the commit should name the reason.

## What Rust owns

Clock, needs, skills, inventory, crafting, building occupancy, faction relations, combat resolution, save and load, and world generation. If a rule can change a number the player cares about, it is Rust.

## What Godot owns

Camera, selection drawing, meshes, animation, light, UI layout, audio, and the translation of clicks into sim commands. If it can be wrong in a screenshot and right in the save file, it is still Godot's bug to fix, and the sim test should stay green.

## Determinism

A `u64` seed plus the same command list produces the same sim state. Render interpolation is allowed to differ. Tests compare sim state, not pixels.

## Milestone 0 shape, when it is asked for

The flake provides `godot` and `cargo`. `cargo test` runs the clock with no Godot process. Headless Godot loads the extension, prints one sim tick, and quits. Details and acceptance text live in [07-milestones.md](07-milestones.md).
