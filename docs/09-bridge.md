# The bridge

This file defines the entire surface between Godot and the sim. It is written in milestone 0, before any gameplay node exists, because milestone 1 cannot be built without it. Until then, it is a list of questions the milestone must answer.

## What it must specify

1. **Commands.** One enum of player orders (move, gather, eat, haul, work, place, craft, draft, attack), with the id of the issuer and the target. Commands are the only way the world changes, so a command list plus a seed is a full reproduction of a run.
2. **Entity ids.** How a person, a building, a stockpile or a resource node is named, who allocates the id, and how Godot holds one. Ids are stable across a save and a load.
3. **State transfer.** What crosses the boundary each tick: a full snapshot, a dirty set, or a delta, and who owns the buffer. The sim must not hand out references into its own storage.
4. **Tick alignment.** The sim ticks at 10 Hz; frames arrive at whatever rate the machine holds. The rule for interpolating between the last two sim states, and the rule for input that arrives mid-tick.
5. **Failure strings.** The sim owns the reason a job failed — `hungry`, `no path`, `no material`, `no skill`, `afraid`, `night`, `wounded` — and Godot only formats it. The strings are part of the interface, so they are tested headlessly.
6. **Time and speed.** Who owns pause and speed multipliers, and what happens to an order issued while paused.
7. **Errors.** What Godot does when the extension is missing or a version mismatch is detected, and what the sim does with a malformed command.

## Rules that carry over from [06-architecture.md](06-architecture.md)

- Nothing in this interface names a Godot type on the sim side. The sim crate stays free of gdext.
- No zero-copy sharing between the two: the boundary copies, deliberately, so a test can drive the sim with no engine at all.
- Every command and every failure string gets a headless test the day it is added.
