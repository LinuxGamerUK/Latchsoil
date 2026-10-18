//! Milestone 1a constants. Each threshold sits next to the test that names it.
//!
//! Hunger falls by [`HUNGER_PER_TICK`] every tick. The bridge's "about 1.7 days"
//! remark does not match that rate (60 ticks is 6 seconds at 1x); the rate in
//! the 1a section is what the rules use.

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

/// Hunger lost each tick. A full person is empty after 60 ticks, clamped.
pub const HUNGER_PER_TICK: f32 = 1.0 / 60.0;

/// Thirst lost each tick.
pub const THIRST_PER_TICK: f32 = 1.0 / 90.0;

/// Health lost each tick while hunger or thirst is exactly 0.
pub const HEALTH_PER_TICK: f32 = 1.0 / 1200.0;

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
