# The bridge

This file is the whole surface between Godot and the sim. It is a milestone 0 deliverable. Milestone 1 cannot be written without it. Names here are fixed.

Two crates. `latchsoil-sim` holds the rules and the state. It names no Godot type and does not depend on gdext. `latchsoil-godot` is the GDExtension cdylib. It registers one node class, `SimHost`. Godot talks only to `SimHost`. Tests may drive `latchsoil-sim` with no engine running. The split is the one in [06-architecture.md](06-architecture.md).

## What crosses the boundary

The sim owns the rules and the world state: clock, needs, jobs, inventory, pathfinding, save bytes, and the RNG stream. Godot owns the camera, selection, meshes, animation, light, audio, and layout. A value that can be wrong on screen and right in the save is still Godot's. It does not enter the sim.

What crosses in: commands, pause, the speed multiplier, the frame delta, attach and detach, a new-game seed, and a save or load request. What crosses out: a snapshot or a dirty set, a failure reason, a command error, the tick, the state hash, and the interpolation fraction. Save bytes cross out as text the sim built. Godot writes the file. A Godot scene is not a save. The camera is not in the save.

What does not cross: any Godot type into `latchsoil-sim`. No `Node`, no `Vector2`, no `Object`, no RID, no scene path. The sim never names one. No zero-copy reference into sim storage crosses either way. The sim copies into plain arrays and hands those arrays out. When the call returns, the caller owns the copy, and the sim may reuse its scratch buffers. Godot must not keep a pointer, a guard, or a view into sim memory. `latchsoil-godot` turns those arrays into Godot values. That second copy is deliberate, so a test can run the sim with no engine at all.

Selection stays in Godot. A click on many people becomes one command per person, in selection order. The sim does not know what is selected. `catalog()` copies item and recipe rows out as plain data, two arrays, `items` and `recipes`, each `{id, name}` in id order. If no data is loaded, both arrays are empty. Reading it is not a command.

One `SimHost` per process. A second instance is a startup failure, same as a missing class. There is one world.

## Commands

A command is the only write Godot can make to a live entity. Load and `new_game` replace the world. Pause and speed do not change entity state. Inside a tick, the sim's own rules then run. Those rules are not commands. A `u64` seed plus the ordered list of `(tick, command)` pairs that applied reproduces a run. Rejected commands are not in that list. Replay does not call `frame`. It submits each command while `tick()` is one below the stamped tick, in list order, then calls `step`.

The enum lives in `latchsoil-sim`. One variant per order.

```rust
enum Command {
    Move { actor: EntityId, to: [f32; 2] },
    Gather { actor: EntityId, node: EntityId },
    Eat { actor: EntityId, item: ItemId },
    Haul { actor: EntityId, item: ItemId, to: EntityId },
    Work { actor: EntityId, job: JobKind },
    Place { actor: EntityId, building: BuildingKind, at: [f32; 2] },
    Craft { actor: EntityId, recipe: RecipeId },
    Draft { actor: EntityId, drafted: bool },
    Attack { actor: EntityId, target: EntityId },
}
```

`actor` is a person. `node` is a resource node. Attack's `target` is an entity. Haul's `to` is a building entity, the place that receives the goods. `item` is an `ItemId`. `recipe` is a `RecipeId`. `job` is a `JobKind`. `building` is a `BuildingKind`. Coordinates are meters. 1 unit is 1 meter. The build grid and the path grid are 1 meter, cell origin at the floor of each axis. Godot rounds each axis to the nearest integer meter before `submit_place`, half away from zero, so 1.5 becomes 2 and -1.5 becomes -2. The sim stores a finite point as given and paths to the cell that contains it. Godot does not pathfind.

`SimHost` has one submit method per variant: `submit_move`, `submit_gather`, `submit_eat`, `submit_haul`, `submit_work`, `submit_place`, `submit_craft`, `submit_draft`, `submit_attack`. An `EntityId` passes as two ints, index then generation. An `ItemId` or `RecipeId` passes as one int. `JobKind` and `BuildingKind` pass as the discriminant below, from 0. Each method returns 0 when the command is queued. It does not apply it.

Who may submit: the player, through Godot, and a test, through the same methods or the sim crate. The sim does not submit commands to itself.

A command submitted when `tick()` is N applies at the start of tick N+1, before that tick's rules. A submit during the apply of a tick waits for the tick after. Queued commands apply in submission order. One rejection does not stop the batch. Accepting a command stores it as that actor's current order. The job may still fail during rules. That is a `FailureReason`, not a command error. Eat and Haul draw from the actor's carried goods. Craft draws from the recipe's inputs. A missing good does not reject the submit. Rules report `NoMaterial`.

Apply checks every `EntityId` again. If any is stale, the command is stale, counted, logged, and skipped, and nothing in it is written. A live id of the wrong kind is malformed: `actor` must be a person, `node` a resource node, haul's `to` a building. Attack's `target` may be any live entity. Place, when accepted, allocates the building id during apply. `submit_place` does not return that id. Godot reads it from the dirty set. The queue lives in the sim, so a headless test hits the same cap with no engine.

`JobKind`, from 0: Haul, Build, Farm, Craft, Heal, Cook, Guard.

`BuildingKind`, from 0: Campfire, LeanTo, Stockpile, House, FarmPlot, Well, Workshop, Store, Palisade.

Both enums are closed. An unknown discriminant is malformed. A new variant is a charter change, recorded in [00-decisions.md](00-decisions.md), not a silent add. Every command gets a headless test the day it is added.

The world starts at tick 0, seed 0, with no entities. `new_game(seed)` resets tick, seed, and entities, clears the queue, and marks every owner for a full snapshot. Placing the starting cast is sim setup inside that call, not a command. Until milestone 1 names the cast, `new_game` leaves the world empty.

## Entity ids

`EntityId` is `{ index: u32, generation: u32 }`. One slot table holds people, buildings, and resource nodes. The sim allocates every id. Godot never mints one. Godot holds the pair as two ints on the node that draws that entity. It does not hold a pointer.

A new slot starts at generation 1. Generation 0 is never live, so `(0, 0)` is always stale and is Godot's empty value. When the sim frees a slot it increments generation. The next occupant of that index gets the new generation. A command still carrying the old pair must not affect the new occupant. If generation would overflow `u32`, that index is retired and not reused.

`ItemId` and `RecipeId` are `u32` newtypes, not generational. They name rows in the loaded data tables. The sim assigns them in fixed file order. Nothing in the sim walks a `HashMap` to do it. The same data set produces the same numbers. All three id kinds are stable across save and load. The save stores index and generation for live entities and for free slots, so a pair that was stale before the save is still stale after it.

A stale id means the index is out of range, the slot is free, or the generation does not match. The sim rejects the command. It does not apply it to whoever sits in that slot now.

## State transfer

A full snapshot when a Godot node attaches, and again after a successful load or `new_game`. Otherwise `poll` returns that owner's dirty set: entities whose fields differ from the copy last sent to that owner, plus ids freed since that pull. A revert to the last sent copy is not dirty. The record is the latest state, not a per-field patch.

`attach` returns an `OwnerId`, a `u32` the sim assigns, starting at 1, not saved. The cap is 8 owners. A ninth attach returns 0, logs `reject malformed attach`, counts a malformed rejection, and does not attach. 0 is never a live owner. `detach` drops that owner's pending copies. When `SimHost` leaves the tree it detaches every owner. Detach does not free entity ids. `snapshot(owner)` forces a full copy and clears that owner's dirty set. `poll(owner)` returns the dirty set, or the full snapshot if one is pending. A pull clears only that owner.

At milestone 1 a snapshot has the tick, the people, the buildings, and the resource nodes. Later milestones append fields. They do not reorder or renumber these. `latchsoil-godot` builds the dictionary. The sim returns structs with the same fields. Keys: `tick`, `people`, `buildings`, `nodes`, `removed`, `hash`, `full`, `error`. `full` is true on a snapshot and false on a dirty pull. `error` is 0 on a good pull. An unknown owner gets `error` 2, empty arrays, and the live `tick` and `hash`. `hash` is always the sim hash on a good pull. `removed` is empty on a full snapshot, and otherwise `[index, generation]` pairs. Godot deletes its node for a removed id. Detach of an unknown owner is a no-op.

A person: `index`, `generation`, `x`, `y`, `hunger`, `thirst`, `health`, `job`, `failure`, `failure_text`, `drafted`, `carried`, `path`, `dest`, `target`. Hunger, thirst, and health are `f32` in 0.0 to 1.0, where 1.0 is full or unhurt and 0.0 is empty or dead. Thresholds live in the sim, beside the test that names them. `job` and `failure` are discriminants, or -1 when none. `failure_text` is the display string, or empty. Godot prints `failure_text` and does not map the discriminant itself. `carried` is `[item_id, count]` pairs, count at least 1, in ascending `ItemId` order. `path` is packed floats, x then y, empty when the order has nowhere to walk. The sim writes `path`. `dest` is `[x, y]` or empty. `target` is `[index, generation]` when the order names another entity, otherwise empty.

A building: `index`, `generation`, `kind`, `x`, `y`. A resource node: `index`, `generation`, `x`, `y`, `remaining`, `yield_item`. `remaining` is a `u32`. `yield_item` is the `ItemId` gathering adds to carried goods.

The state hash is a `u64` from `latchsoil-sim`, over applied state, live entities, ascending index. It covers the tick, the RNG stream, and the person, building, and node fields above. It does not cover the camera, selection, the unapplied queue, pause, speed, owners, or the interpolation fraction. `state_hash` returns it. Godot does not recompute it. Positions are hashed as the stored `f32` bits.

## Tick alignment and input

The sim tick is the unit of truth. The step is fixed at 10 Hz, 100 ms of sim time. A day is 12 minutes at 1x, which is 7200 ticks. Frames arrive at whatever rate the host manages. Frame rate is not saved and is not hashed.

Each drawn frame, Godot calls `frame(delta_seconds)` from `_process`, not from `_physics_process`. A negative delta counts as 0. When the sim is not paused it adds `delta * speed` to an accumulator. While the accumulator holds at least 0.1, the sim applies the commands queued before this boundary, runs one tick of rules, subtracts 0.1, and repeats. At most 5 ticks run in one call. Leftover above 0.1 after that cap is dropped, so a hitch slows the sim instead of skipping ahead.

Input that arrives mid-tick is queued and applied at the next tick boundary. It does not land in the middle of rules.

`alpha` is the leftover accumulator divided by 0.1, clamped to 0.0 through 1.0. Godot may lerp a drawn position between the last two sim positions by that fraction. The fraction may differ between machines and must not be written back. Skipping the lerp does not change the sim. The path polyline is the latest sim path, not a blend. While paused, `alpha` is 0 and Godot draws the last sim state.

The sim starts at tick 0. `step` advances exactly one tick, applies the queue first, and ignores pause. `tick`, `state_hash`, `step`, and `frame` do not require an owner. Play uses `frame`. The smoke scene uses `step`.

## Pause and speed

Godot owns pause and the speed multiplier. The sim owns whether a tick advances. The sim starts unpaused at speed 1. Pause is a bool, set with `set_paused`. Speed is a separate int, set with `set_speed`, and is only 1, 2, or 3. Pause does not zero the multiplier, so resume keeps the previous speed. Any other multiplier returns error 1, writes `reject malformed speed` to stderr, and leaves the multiplier unchanged.

While paused, `frame` does not grow the accumulator, and no tick runs. Commands submitted while paused are queued, not dropped, and not applied until the next tick that advances. On resume they apply together, in order, at the start of that tick, then rules run once.

The queue cap is 256 unapplied commands. At 256, submit returns error 3, the new command is not stored, and the queued ones stay. The sim does not drop the oldest to make room.

A successful load or `new_game` clears the queue, logs `queue cleared <count>` with a decimal count, and does not apply those commands. They named the world that was just replaced.

## Failure strings

The sim owns the reason a job failed. It returns a `FailureReason` and the display string. Godot prints that string as the whole line. It does not keep a second wording, does not add a name or a prefix, and never invents a reason. No failure means no line. A command error never appears on that line.

`FailureReason`, from 0, with the display string: Hungry `hungry`, NoPath `no path`, NoMaterial `no material`, NoSkill `no skill`, Afraid `afraid`, Night `night`, Wounded `wounded`.

`Hungry`: too hungry to carry out the order. `NoPath`: the grid has no path to the point or the entity. `NoMaterial`: a required item or recipe input is absent. `NoSkill`: the actor cannot perform that job. `Afraid`: the actor refuses out of fear. `Night`: the order is refused because the clock is in the night range. That range is a sim constant next to its test, not a bridge field. `Wounded`: too hurt to carry out the order. If more than one applies, the sim returns the earliest in this list. Godot does not choose. A headless test asserts each string the day that reason can be produced.

A new command clears the actor's previous failure. On failure, rules clear `path`, `dest`, and `target`, and set `failure`.

## Errors

If the extension library is missing, `SimHost` is not registered, or the cdylib was built against a different engine API than the binary now loading it, Godot fails at startup. It quits with exit code 1. It does not enter play, and it does not stand up a GDScript substitute. A half-registered class is the same failure. If `engine_api` cannot be called, or its `major.minor` does not match the running engine, quit. The success line below must not be printed. `engine_api` returns the API the crate was compiled for. That is `4.7` until a pin change is recorded in [00-decisions.md](00-decisions.md).

A bad command returns a typed error and does not panic. Codes: 0 queued, 1 malformed, 2 stale, 3 queue full. The sim increments a counter per code. `rejections` returns them under `malformed`, `stale`, and `queue_full`. It also writes one stderr line, `reject <malformed|stale|queue_full> <variant>`, and leaves the world unchanged. Variant names are lowercase: move, gather, eat, haul, work, place, craft, draft, attack.

Malformed means a non-finite coordinate, an unknown discriminant, or an `ItemId` or `RecipeId` missing from the loaded tables. Stale is a bad `EntityId`, as defined above. The sim never panics on player input. That includes a bad id, a bad float, a full queue, a submit while paused, and a poll from a dead owner.

`save_json` returns the versioned JSON text. `load_json` returns 0 or 1. Missing JSON, a missing `save_version`, or an unknown `save_version` returns 1, logs `reject malformed save`, and keeps the current world. There is no migration. The save does not include the command list or the camera. The test holds the command list. On success, load replaces state, restores ids, clears the queue, and marks every owner for a full snapshot.

## How a headless run proves the contract

The smoke scene loads the extension, instances the one `SimHost`, calls `step` once, prints one stdout line, and quits with code 0. The line is the tick number and the state hash, and nothing else:

```
latchsoil: tick 1 hash 0123456789abcdef
```

The `latchsoil: ` prefix is part of the line: the check scripts grep for it, so the sim's line cannot be confused with engine chatter. The tick is decimal. The hash is 16 lowercase hex digits, zero-padded. A fresh sim is tick 0. One `step` makes it tick 1. The scene prints what `tick` and `state_hash` return. It does not format its own hash.

A load failure exits non-zero and does not print that line. Loader text on stderr is allowed. The exit code is the check. `cargo test` in `latchsoil-sim` never needs this scene. It calls the same command enum, the same id rules, and the same hash.

## What is deliberately absent

World generation is not on this contract. No biome stamp, no ruin, no seeded map. Milestone 1 is a blockout. Godot owns that layout. The sim does not grow a map here.

Factions are not on this contract. No relation number, no war goal, and no treaty crosses yet.

Combat resolution is not on this contract. `Draft` stores the bool. `Attack` stores the target when both ids are live, and does not write a path. Neither applies a hit, a wound, or a death. Those rules arrive with the milestone that names them.

Save migration, past the version check, is not on this contract. An unknown `save_version` fails the load. It does not rewrite fields. The snapshot grows when a later milestone adds state. New fields are appended. Existing discriminants stay where they are.

## Milestone 1a — what the rules implement

This section says what the rules do in milestone 1a, so the tests and the scene agree on one world. It narrows the contract above; it does not extend it.

**The acre.** A new game lays a 32 m by 32 m acre with the survey peg at its centre, three Harth standing beside the peg, and six resource nodes. The acre is the whole path grid: 1 m cells, 32 by 32, cell origin at the floor of each axis. The same seed puts the same cast and the same nodes in the same places, because they come from the sim's own RNG stream in a fixed order. There are no obstacles yet: a point inside the acre is reachable and a point outside it is `no path`. Obstacles, terrain and the wider map arrive with the milestone that names them.

**The cast.** Three people, all Harth, all starting at 1.0 hunger, 1.0 thirst, 1.0 health, carrying nothing. Ids are allocated in order: index 0, 1, 2, generation 1.

**The nodes.** Two wood, two stone, one fiber, one water, at seed-chosen cells at least 4 m from the peg and 2 m apart. `remaining`: wood 40, stone 30, fiber 50, water 100. `yield_item` is the item gathering adds to carried goods, so a wood node yields the wood item.

**Needs.** Hunger, thirst and health are `f32` in 0.0 to 1.0, where 1.0 is full. Hunger falls by 1/60 per tick, so a full person is hungry in about 1.7 days at 1x. Thirst falls by 1/90 per tick. Health is untouched while both are above 0.0, and falls by 1/1200 per tick while either is at 0.0. Eating restores 0.35 hunger and 0.15 thirst and consumes one carried grain.

**Refusal thresholds**, each beside the test that names it: work is refused below 0.35 hunger with `hungry`, below 0.30 health with `wounded`, and between tick 5760 and 7200 of a day with `night` (the last 20 percent of the day is the night range). If more than one applies, the earliest in the `FailureReason` order wins.

**Movement and work.** A person walks 1.4 m per second, which is 0.14 m per tick, along the path the sim computed, and reaches a waypoint when it is within 0.1 m. Gathering takes one unit per 20 ticks and adds it to carried goods; a person carries at most 20 units. A node that runs out while gathering fails the order with `no material`. An `eat` order with no carried grain fails with `no material`. Work orders are the only ones refused at submit time; the rest are accepted and then fail in rules if they cannot finish.

**The five reasons 1a can produce:** `hungry`, `no path`, `night`, `wounded`, `no material`. `no skill` and `afraid` have no rule yet, so no 1a test can produce them and nothing returns them.

**Rules implemented:** `Move`, `Gather`, `Eat`. The other six commands are accepted, stored as the actor's current order, and carry out nothing yet; their rules arrive with the milestone that names them. `Place` therefore allocates nothing in 1a.

**One owner is enough.** `attach`, `detach`, `snapshot` and the owner cap behave as described above, but `poll` returns a full snapshot every time, with `full` true and `removed` empty. Per-owner dirty sets arrive with the second consumer of the world state, and this file records the change when they do.
