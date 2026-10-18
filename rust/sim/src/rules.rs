//! Milestone 1a constants. Each threshold sits next to the test that names it.
//!
//! Needs fall at a rate measured in days, because that is how the play calendar
//! is described: a day is 12 minutes at 1x. An earlier revision said "hunger
//! falls 1/60 per tick", which empties a person in six seconds and refuses every
//! work order after four seconds of play — the blockout was unplayable and the
//! mistake was a contradiction between that rate and the "hungry in 1.7 days"
//! sentence in the same paragraph of the bridge contract.

use crate::clock::TICKS_PER_DAY;

/// Acre edge length, in meters. The path grid is this many 1 m cells.
pub const ACRE_METERS: f32 = 32.0;

/// Cells on one side of the acre.
pub const ACRE_CELLS: i32 = 32;

/// Survey peg, centre of the acre `[0, ACRE_METERS)`.
pub const PEG_X: f32 = 16.0;
pub const PEG_Y: f32 = 16.0;

/// 1.4 m/s at 10 Hz.
pub const WALK_METERS_PER_TICK: f32 = 0.14;

/// A waypoint is reached at this distance or closer.
pub const WAYPOINT_REACH_METERS: f32 = 0.1;

/// Gathering adds one unit after this many ticks stood at the node.
pub const GATHER_TICKS_PER_UNIT: u32 = 20;

/// A person carries at most this many units, across every item.
pub const CARRY_CAP: u32 = 20;

/// Ticks from a full person to an empty one. Two days at 1x, which is the
/// sentence the lore is written against ("hunger bites on day 2").
pub const HUNGER_FULL_TICKS: u64 = 2 * TICKS_PER_DAY;
/// Hunger lost each tick. A full person is empty after two days, clamped.
pub const HUNGER_PER_TICK: f32 = 1.0 / (HUNGER_FULL_TICKS as f32);

/// Ticks from full to empty for thirst. A little sooner than hunger, so water is
/// the first need that bites.
pub const THIRST_FULL_TICKS: u64 = TICKS_PER_DAY * 8 / 5;
/// Thirst lost each tick.
pub const THIRST_PER_TICK: f32 = 1.0 / (THIRST_FULL_TICKS as f32);

/// Ticks from full health to none, once a need has reached zero.
pub const HEALTH_FULL_TICKS: u64 = TICKS_PER_DAY;
/// Health lost each tick while hunger or thirst is exactly 0.
pub const HEALTH_PER_TICK: f32 = 1.0 / (HEALTH_FULL_TICKS as f32);

/// Grain each person of the starting cast carries: the Harth kit's ration, two
/// days of meals at two a day. Milestone 1a has no food in the world, so without
/// it `Eat` can never succeed and the hunger refusal is a dead end.
pub const STARTING_GRAIN: u32 = 4;

/// Work is refused when hunger is strictly below this.
pub const HUNGER_REFUSAL: f32 = 0.35;

/// Work is refused when health is strictly below this.
pub const HEALTH_REFUSAL: f32 = 0.30;

/// First tick of the day that is night. The last 20% of a 7200-tick day.
///
/// Night is `tick_of_day >= NIGHT_START_TICK` and `tick_of_day < TICKS_PER_DAY`.
/// Tick 7200 is the next morning, not night.
pub const NIGHT_START_TICK: u64 = 5_760;

/// Hunger restored by eating one grain, before the 0.0–1.0 clamp.
pub const EAT_HUNGER_RESTORE: f32 = 0.35;

/// Thirst restored by eating one grain, before the 0.0–1.0 clamp.
pub const EAT_THIRST_RESTORE: f32 = 0.15;

/// A node cell centre must be at least this far from the peg.
pub const NODE_MIN_FROM_PEG: f32 = 4.0;

/// Node positions must be at least this far apart.
pub const NODE_MIN_APART: f32 = 2.0;

/// Unapplied commands kept. The 257th submit is queue full.
pub const QUEUE_CAP: usize = 256;

/// Live owners. A further attach returns 0.
pub const OWNER_CAP: usize = 8;

pub const WOOD_REMAINING: u32 = 40;
pub const STONE_REMAINING: u32 = 30;
pub const FIBER_REMAINING: u32 = 50;
pub const WATER_REMAINING: u32 = 100;

/// Fixed points beside the peg, cardinal then diagonal, 1 m or √2 m away.
/// `new_game` draws three distinct indices from this list, in order.
pub const BESIDE_PEG: [[f32; 2]; 8] = [
    [15.0, 16.0],
    [17.0, 16.0],
    [16.0, 15.0],
    [16.0, 17.0],
    [15.0, 15.0],
    [17.0, 15.0],
    [15.0, 17.0],
    [17.0, 17.0],
];

/// BFS neighbour order: east, south, west, north. Fixed so the path is a function of the cells.
pub const NEIGHBOURS: [(i32, i32); 4] = [(1, 0), (0, 1), (-1, 0), (0, -1)];

pub fn night_at(tick: u64) -> bool {
    tick % TICKS_PER_DAY >= NIGHT_START_TICK
}

pub fn dist(a: [f32; 2], b: [f32; 2]) -> f32 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    (dx * dx + dy * dy).sqrt()
}
