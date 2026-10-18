# Latchsoil

Latchsoil is a single-player holding sim on a heavy world called the Latch. A habitat ring once paid this world to grow its food. The ring shed itself across the sky, and the people who stayed were edited into different folk. You plant a new charter peg in a procedural wilderness, then build, eat, bleed, negotiate, and become the kind of neighbor the other holdings already fear or need.

The sentence on the peg: build the holding, survive the year, thrive in a way the map will remember.

## Locked choices

- Title: Latchsoil
- View: stylized 3D isometric
- Control: colony camera. WASD moves the view. You never walk a single body. You select people and give orders.
- Moral range: systemic and consequential. Raids, forced labor, corpse-ration, and plague or fire used on fields are real acts with records and endings. They are shown as outcomes, without graphic spectacle.
- Stack: Godot presents. Rust decides. This machine builds and runs headless sims. Playtest on the Legion.
- Scope of this commit: design only. Milestone 0 has not started.

## Read in this order

1. [docs/01-vision.md](docs/01-vision.md) — what the game is
2. [docs/02-names.md](docs/02-names.md) — title, spare titles, proper nouns
3. [docs/03-lore.md](docs/03-lore.md) — the Latch, the Shedding, the two tracks
4. [docs/04-races.md](docs/04-races.md) — twelve peoples, art, stats, kits, relations
5. [docs/05-systems.md](docs/05-systems.md) — camera, survival, skills, craft, politics, combat, map
6. [docs/06-architecture.md](docs/06-architecture.md) — Godot, Rust, data, saves, ticks
7. [docs/07-milestones.md](docs/07-milestones.md) — what to build, in order, and how to know it worked
8. [docs/08-art.md](docs/08-art.md) — shared art direction

## For the implementing agent

Read the docs above before writing code.

The current milestone is none. When asked to start, implement milestone 0 only, from `docs/07-milestones.md`. Do not start milestone N+1 while that milestone's acceptance check is failing. Gameplay rules belong in Rust. Godot shows them and takes input. Do not message anyone about this repo unless Gavin asks.

## Machine

Canonical working copy:

`/home/gav/Projects/Project-Game-Dev` on `192.168.1.150` (`nixos-prod-aiserver`)

Checked when this charter was written:

- Nixpkgs here provides Godot 4.7.2 and Rust 1.98.1
- About 62 GB RAM and a large free disk
- A GPU node exists at PCI `01:00.0`. Its model was not identified. Do not block a milestone on editor screenshots from this host.
