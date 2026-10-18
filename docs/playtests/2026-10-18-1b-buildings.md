# 2026-10-18 — milestone 1b, buildings, a store and three recipes

Played: milestone 1b. The interface was frozen first (contract `a7f2464`), then built; the code and this note landed together.

Where: **review frames rendered on the build host**, software Vulkan under Xvfb, and this time every picture was produced by driving the real sim with the sim's own rows printed beside it. **Nobody has played 1b with their hands yet.** The four frames are kept beside the project note in the vault; the repository carries the driver that reproduces them.

## What the frames establish

**A building is built, not conjured.** `1b-half.png` was captured at tick 30 with the campfire's own snapshot row printed as `{"index": 9, "generation": 1, "kind": 0, "progress": 30, "contents": []}` — the frame shows a half-height stone ring with no flame, and the HUD reads `campfire 30/60`. `1b-finished.png` at tick 60 shows the same campfire complete with a flame and reads `60/60`, while the two other sites are still bare four-post frames, matching their printed `progress: 0`. Two people are walking toward those sites, which is what their printed `job 1` with a non-empty `dest` and `path` says.

**A store holds what it was actually given.** `1b-stockpile.png` is tick 807, hash `62e10392b8beef6c`. Wood and fiber were gathered from real nodes and hauled in, and the stockpile's printed row is `contents: [[1, 2], [3, 2]]`. The HUD reads `holds wood 2, fiber 2`. `_fill_crates` draws one crate per unit, capped at three per item and eight in total, so those contents draw four crates.

**A recipe ran.** Recipe 1 (meal) was crafted at the finished campfire. The same frame prints person 0 carrying `[[0, 3], [6, 1]]`: three grain and one meal, from four grain and a water.

**The camera is still not in the save**, and the harness asserts it rather than asserting the absence of a feature: the save text is grepped for `camera` and its keys are walked case-insensitively.

## What a person still has to judge

- **A store's contents are readable by label, not by eye.** Reading these frames myself I counted three crates where the code draws four; the two independent readings of the HUD text agreed (`holds wood 2, fiber 2`), because the HUD carries the snapshot's own numbers and the props are decoration. If a store should be countable at a glance, that is a drawing decision and not a sim one.
- **A build site reads as a site, not as the building it will become.** At progress 0 all three kinds draw the same four-post frame. Worth confirming that is enough of a promise.
- **A person at holding zoom is still a handful of pixels.** The sim places three people in the wide frame and I could find one of them.
- **Nothing here has been felt.** Placing a building and waiting 60 ticks — six seconds — is the first time the game asks for time as a cost. Whether that reads as work or as a stall is a judgement only play answers.

## Owed

A human session: place a campfire and cook a meal, haul into a store and take back out, and say whether the build wait reads as work or as a stall. What a person already has to judge from 1a — camera feel, the destination marker, the label over a neighbour — is still outstanding too.
