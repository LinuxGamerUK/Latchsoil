# Systems

The camera is the player. The people are the bodies. Rust owns every number in this file. Godot shows them.

## Camera and orders

WASD pans across the holding. The mouse wheel zooms between a close isometric and a wide holding view. Q and E rotate in 90 degree steps so walls stay readable. Space pauses and steps the speed. Edge-scroll stays off, so WASD remains the way the view moves.

Left click and drag select people, buildings, and stockpiles. Right click orders the selection: move, haul, work, attack. Priorities run the holding while the camera is elsewhere.

Drafting is the RTS posture. A drafted person holds, follows a move order, and fights until released. An undrafted person who is attacked defends at a penalty and then runs.

Every person can die, including the founder. There is no body to inhabit.

A selected person shows a ground ring and their current job. An order shows a path and a destination until it finishes or fails. A failure says why in one line: hungry, no path, no material, no skill, afraid, night, wounded.

## Time

- Sim tick: 10 Hz
- Default day: 12 real minutes at 1x speed
- Play year: 40 days. Seasons are Sprout, High Sun, Stitchfall, Deep Bell, 10 days each.
- Lore year, a turning, is 428 days. Flavor text can mention it. The sim uses the 40-day year.

## Survival

Each person tracks hunger, thirst, fatigue, temperature, pain, blood, infection, and mood.

Body regions are head, torso, arms, and legs. A ruined leg limps. A ruined arm drops carry and craft speed. Bleeding is a clock. Infection is a second clock that medicine can interrupt.

Sleep needs shelter and a sense of safety. Without it, fatigue and mood get worse.

Target pressure for the first balancing pass:

- A person eats 2 meals a day.
- A meal is 1 grain plus fuel, or 2 forage units.
- A worked 4×4 plot yields about 20 grain in a Sprout.
- Four people want four plots and a well.
- With no food effort, hunger is serious on day 2.
- Forage can bridge a careful group to the first harvest, and it is capped so it cannot replace fields.
- Spoilage makes a storehouse part of the food chain.

Milestone 3's headless test is allowed to change the exact constants until those sentences are true. The sentences stay.

## Skills

Use-based, from 0 to 20, with diminishing returns. No experience items.

Cutting, Hauling, Building, Farming, Cooking, Medicine, Shooting, Melee, Social, Machines, Stealth, Husbandry.

Tools and weapons keep a separate familiarity. A master cook holding a stranger's rifle is still a bad shot.

## Craft and building

The grid is 1 meter. Chains stay short enough to test.

Gather: fiber, wood, stone, water, ore, salvage, glass, spore, brine, herd goods.

Make: boards, bricks, glaze, meals, cloth, tools, arms, medicine, recut parts.

Raise: camp, house, farm plot, well, store, workshop, palisade, gate, kiln, law-loom.

The first player-facing craft list is smaller. Milestone 1 only needs a bandage, a meal, and a stone knife.

## The law-loom

The political craft bench. Publishing a law costs materials, Social skill, and a public day. People in the holding change their behavior. Neighbors judge the paper.

First laws, in milestone 6's first slice of three and then the rest:

- Open Gate
- Closed Ditch
- Shared Grain
- Quarantine
- No Flesh
- Flesh Is Ration
- Implant Tithe
- Canticle Hour
- Night Market

Flesh Is Ration, Implant Tithe, and a weaponized quarantine are appetite acts. The UI records them as laws you published, not as staged cruelty.

## Politics

Each faction leans five axes from −2 to +2: Word, Appetite, Gate, Machine, Soil.

Relations run from −100 to 100. States, in order of contact: unknown, contact, trade, passage, defense, tribute, war, vendetta.

War goals stay small: a field, a wreck, revenge, or humiliation. Humiliation means seize their glass and leave the houses. Annihilation is rare and expensive.

Acts that move relations include trade, gifts, raids, border kills, guest-right kept or broken, plague, refuge, and a ditch pushed past the peg's paper.

## Combat

Real time while unpaused. Pause to issue orders. Draft, then right click a destination or a target. Melee and one ranged category come first. Friendly fire is on. Line of sight and range decide a shot. Cover and vehicles wait.

## Map

One planet. Finite, seeded, streamed in chunks. The design target is a 4 km square. The first generated playable map is 512 m, then 2 km, then 4 km. The same seed makes the same peg.

First biomes: temperate valley, glass basin, coast, karst, mesa, marsh, hull crater.

Generation order: elevation, temperature, moisture, glass-sheen, fertility, ruin density, then stamped hulls and charter ruins, then faction sites.

## Starting grant

Default new game, once a start exists:

- People: Harth
- Season: Sprout
- Three people in milestone 1, four in the milestone 3 survival test
- A survey peg, a cart of the Harth kit, and the granted acre marked on the ground
- Seed shown in the UI and stored in the save
