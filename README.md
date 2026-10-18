# Latchsoil

Latchsoil is a single-player holding sim on a heavy world called the Latch. A habitat ring once paid this world to grow its food. The ring shed itself across the sky, and the people who stayed were edited into different folk. You plant a new charter peg in a procedural wilderness, then build, eat, bleed, negotiate, and become the kind of neighbor the other holdings already fear or need.

**Build the holding. Survive the year. Thrive in a way the map will remember.**

## The world in short

- **Cinderwell** is the star: swollen, orange, long dusks.
- **Latch 11** — the Latch in local speech — is a heavy world. A habitat ring called the **Gramarye** hung above it and bought the grain this world grew.
- The ring's inner rail failed 311 years ago. Elevendays of falling districts are called the **Shedding**; the pale debris arc still hanging at dusk is the **Stitch**.
- The ring is still broken and does not get repaired. Thriving means a holding that feeds itself, defends its ditch, and chooses which promises it keeps.
- **Glass chits** are coin cut from ring-glass, and also machine fuel. Spending cash melts the sky; hoarding it hoards power.

## How it plays

- **A colony camera, not a body.** WASD moves the view across a stylized 3D isometric world. You select people and give orders. The founder can die like anyone else, and the run continues.
- **One play year is 40 days** in four seasons of ten: Sprout, High Sun, Stitchfall, Deep Bell.
- **Bodies keep score.** Hunger, thirst, wounds, infection, temperature, fatigue, sleep, and skills that rise because a person did the work.
- **Territory is dirt and paper.** The survey peg stays where it was granted. The ditch around it is the lived border, and moving that ditch past the paper is how a farm becomes a war.
- **Good and evil are records of acts, not a meter you spend.** *Kept word* is guest-right, refuge, fair trade, shared water and pacts honored when they cost grain. *Open appetite* is raids, forced labor, implant-stripping, plague or fire on fields, and flesh taken as ration. A holding can carry both records.

## The twelve peoples

Twelve peoples live on the Latch, edited for the work their charters demanded. Baseline is 50; a people is a set of biases, a material language, and a way of reading the world.

| People | Who they are | Lean |
| --- | --- | --- |
| Harth | Unedited charter farmers | Kept word |
| Cindervault | Glass-waste smiths | Appetite |
| Brinelung | Canal traders with gill-slits | Kept word |
| Marrowquiet | Underground archivists | Neutral |
| Kiteborn | Mesa gliders | Neutral |
| Thornlattice | Photosynthetic syndicate | Kept word |
| Rust Cantors | Machine-yard singers | Neither |
| Sable Choir | Nocturnal ridge harmonists | Appetite |
| Glass Shepherds | Nomad herders of mineral beasts | Trade |
| Lumenbrood | Clones from a medical hull | Unaligned |
| Keelwights | Crew of landed ships | Lawful |
| Mire Saints | Fungal healers | Kept word |

Full kits, palettes, stats and the opening relation matrix are in [`docs/04-races.md`](docs/04-races.md).

## Endings

Six late outcomes exist as stubs, and each one is earned by a record rather than selected: **Open House**, **Quiet Ditch**, **Red Granary**, **Stitch Throne**, **Second Charter**, **Ash Orchard**.

## How it is built

- **Godot presents, Rust decides.** Presentation is Godot 4.7 (stylized 3D isometric). Needs, skills, crafting, factions, combat, saves, world generation and the map seed are Rust. Gameplay rules do not live in GDScript.
- **The sim is the game.** A headless test can starve a holding, save it, and load it back. One `u64` seed plus the same command list produces the same sim state; tests compare sim state, not pixels.
- **A new people is data, not a code branch.** Races, items, buildings, laws and events are RON files under `data/`.
- **A milestone finishes with placeholder art.** A tinted blockout with the right silhouette beats a stall for a finished mesh.

## Build and test

The toolchain is one pinned devshell — Godot 4.7.2, Rust and Cargo — so nothing else has to be installed:

```bash
nix develop          # engine, cargo, rustc on PATH
nix run .#test       # workspace tests, then the headless engine load
```

`nix run .#test` is the acceptance gate: it runs the sim's tests with no engine in the process, then builds the GDExtension, loads it in a headless Godot, ticks the sim once, checks the determinism fingerprint, and quits. The same command runs in CI on every push.

## Status

Milestone 0 (toolchain truth) is done: the devshell, the two-crate workspace, the headless engine load and the sim's own tests all run from one command. Milestone 1a is next — the camera, selection and the order path on a blockout field. [`docs/07-milestones.md`](docs/07-milestones.md) is the build order, and [`docs/00-decisions.md`](docs/00-decisions.md) records what has been decided since.

## The documents

1. [`docs/01-vision.md`](docs/01-vision.md) — what the game is
2. [`docs/02-names.md`](docs/02-names.md) — title, spare titles, proper nouns
3. [`docs/03-lore.md`](docs/03-lore.md) — the Latch, the Shedding, the two tracks
4. [`docs/04-races.md`](docs/04-races.md) — twelve peoples, art, stats, kits, relations
5. [`docs/05-systems.md`](docs/05-systems.md) — camera, survival, skills, craft, politics, combat, map
6. [`docs/06-architecture.md`](docs/06-architecture.md) — Godot, Rust, data, saves, ticks
7. [`docs/07-milestones.md`](docs/07-milestones.md) — what to build, in order, and how to know it worked
8. [`docs/08-art.md`](docs/08-art.md) — shared art direction

## Licence

MIT. See [`LICENSE`](LICENSE).
