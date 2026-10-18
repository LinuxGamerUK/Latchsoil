# Milestones

Implement these in order. Each one ends in a commit. Do not start the next while the current acceptance check is failing. Placeholder art is part of finishing a milestone, not a later art pass that blocks the sim.

The current milestone, as of the design commit, is **none**. Milestone 0 and milestone 1a are complete; milestone 1b is next, and starts when Gavin asks for it.

## Agent rules

- Read `README.md` and the rest of `docs/` before editing.
- Gameplay rules go in Rust. Godot presents them.
- Add a headless check for every sim behavior you claim works.
- Keep the change inside the milestone. A good idea for milestone 5 gets a line in this file, not a surprise system in milestone 1.
- Do not import concept art as a runtime texture.
- Camera feel is playtested by hand and written up in `docs/playtests/`. This side of the project owes headless proof.

## 0 — Toolchain truth

Create the flake, the Godot project, and the Rust extension described in [06-architecture.md](06-architecture.md).

Acceptance:

- The flake shell provides Godot and Cargo, and `flake.lock` is committed.
- `cargo test` advances a clock with no Godot process.
- Headless Godot loads the extension, prints a sim tick, and quits cleanly.
- `docs/09-bridge.md` exists and names the command list, entity ids, state transfer and failure strings.
- `.gitignore` exists; the repository has its licence and both remotes.
- If Godot 4.7.2 will not load the extension, the flake pins Godot 4.6.3 and the choice is recorded in [00-decisions.md](00-decisions.md).

## 1a — One field, one camera

A temperate blockout. An isometric camera: WASD pan, wheel zoom, Q and E rotate by 90 degrees, Space pauses. Three Harth stand under the peg.

The player can select people, and order the selection to move, gather, or eat. Job state ticks in Rust; Godot draws a ground ring, an order path, a destination marker, and one line of failure reason.

Acceptance:

- A headless scenario issues move, gather and eat orders and asserts the sim state changed as ordered (position, carried goods, hunger).
- A headless order that cannot be satisfied writes the reason string, and the test names each reason it covers.
- On a real machine, selection, the order path, and the failure line are readable at holding zoom. Write the note in `docs/playtests/`.

**Done, 2026-10-18 (`9cd8a04`).** The gate is `nix run .#test`: 38 sim tests, the milestone 0 smoke line, then `scripts/check-1a.sh`, which proves the first two acceptance lines through the bridge — cast placed, a move in flight, a gather that adds to carried goods and drains the node, eat refused as `no material` with and without goods, `no path` for an order outside the acre, a stale id rejected without disturbing the world, and the same seed and command list giving the same hash from both `step` and `frame`. The third line owes a human's eyes: `scripts/render.sh` produces review frames from a display-less host, and a playtest note records what a person saw.

## 1b — One holding, one save

Hunger, thirst and health tick in Rust. People gather fiber, wood, stone and water, and gathering depletes a node. The player can place a campfire, a lean-to and a stockpile. A colonist's job can craft a bandage, a meal, and a stone knife. Save and load.

Acceptance:

- A headless scenario applies hunger and asserts health falls only after the hunger threshold.
- Gathering depletes a node.
- Save, load, and compare: needs, positions, jobs, inventory, tick count, and RNG stream state survive the round trip with an equal state hash. A second run from the same seed and command list matches it.
- The camera is not in the save.

## 2 — The body keeps score

Add body regions, bleeding, infection, temperature, fatigue, and sleep. Use-based skills rise on the actions a person actually performs. Tools change speed and failure.

Acceptance:

- A headless wound bleeds out without a bandage and stabilizes with one.
- Infection advances on a neglected wound and slows when medicine is applied.
- Doing the same job repeatedly raises that skill and changes the time the job takes.

## 3 — A holding

Colonist records, work priorities, and persistent orders. Buildings: house, farm plot, well, workshop, store, palisade.

Acceptance, headless, same seed and same starting Harth:

- Four people, four worked plots, and a well survive 10 days, with grain left over after spoilage and seed.
- The same run with no well fails.
- The same run with plots and forage disabled fails from hunger before the harvest pays.
- Adjust yields in data until those three outcomes hold, and record the constants next to the test. A crop takes about five days, so a plot pays twice in a Sprout; four plots must beat four people's eighty grain with margin, not break even.

## 4 — A seed

A 512 m map from a `u64` seed. Seven biome stamps, ruins, and resource nodes. New game chooses seed, people, and season.

Acceptance:

- The same seed places the same peg, the same ruins, and the same resource nodes.
- A different seed differs.
- The Harth start still meets the milestone 3 food test on a temperate site.

## 5 — Neighbors

Three sites on the map: one kin, one trader, one danger. A relation number, a place to talk, and a trade screen. One incident, either a raid or refugees. Drafting, melee, one ranged weapon, and death.

Acceptance:

- A headless raid can kill an undrafted person and can be beaten by drafted ones.
- Trade moves goods and changes the relation number.
- Pause freezes combat resolution.

## 6 — Word and appetite

Treaties, war goals, and guest-right. The two tracks are derived from acts. The law-loom can publish Open Gate, Closed Ditch, and one appetite law (Flesh Is Ration or Implant Tithe). Two incidents play out differently because of what the holding did.

Acceptance:

- Publishing a law spends the cost, changes colonist behavior, and moves at least one neighbor.
- Breaking guest-right writes an appetite record the neighbor can read.
- Sheltering a refugee line writes a kept-word record.
- The two incident variants are covered by tests, not by a manual-only branch.

## 7 — The rest of the peoples

The remaining peoples arrive as data, start packages, and stand-in silhouettes. Add the event deck, weapon familiarity, and stubs for the six endings in the lore doc. Grow the map past 512 m only after the 512 m loop is fun.

Acceptance:

- Each people loads from RON, spawns with their kit, and shows their accent in the blockout.
- A familiarity test shows a skilled farmer missing with an unfamiliar weapon.
- Each ending stub can be forced from sim state in a test, and the UI can name it.

## Explicitly later

Other planets, flight, multiplayer, voice acting, a scripted campaign, mods beyond data files, vehicles, a cover system, and unique animation sets for all twelve peoples.

## Kickoff, when Gavin asks for milestone 0

Work in the repository root. Read the docs in the order the README gives. Implement milestone 0 only. Prove the headless load. Commit that milestone. Stop.
