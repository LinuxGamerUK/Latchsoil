//! Sim constants. Each threshold sits next to the test that names it.
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

/// Hunger restored by eating one meal. Cooking pays about twice over grain.
pub const MEAL_HUNGER_RESTORE: f32 = 0.75;

/// Thirst restored by eating one meal.
pub const MEAL_THIRST_RESTORE: f32 = 0.30;

/// Hunger restored by drinking one water. Water is thirst only.
pub const WATER_HUNGER_RESTORE: f32 = 0.0;

/// Thirst restored by drinking one water.
pub const WATER_THIRST_RESTORE: f32 = 0.50;

/// Ticks of work, standing within [`STATION_RANGE_M`], until a building is finished.
pub const BUILD_TICKS: u32 = 60;

/// Ticks stood at a stockpile per unit hauled in.
pub const HAUL_TICKS_PER_UNIT: u32 = 5;

/// Ticks stood at a stockpile per unit taken out.
pub const TAKE_TICKS_PER_UNIT: u32 = 3;

/// A finished building is a station for an actor within this distance.
pub const STATION_RANGE_M: f32 = 2.0;

/// Units a stockpile holds, across every item.
pub const STOCKPILE_CAPACITY: u32 = 200;

/// Ticks to craft a knife. No station.
pub const RECIPE_KNIFE_TICKS: u32 = 60;

/// Ticks to craft a meal. Needs a finished campfire.
pub const RECIPE_MEAL_TICKS: u32 = 30;

/// Ticks to craft a bandage. Needs a finished lean-to and a carried knife.
pub const RECIPE_BANDAGE_TICKS: u32 = 40;

/// Health lost each tick per unit of bleeding, summed across regions. A wound at
/// 1.0 empties a healthy person in one day. Bleeding does not fade on its own.
pub const BLEED_HEALTH_PER_TICK: f32 = 1.0 / (TICKS_PER_DAY as f32);

/// Ticks stood within station range before a heal consumes its item.
pub const HEAL_TICKS: u32 = 60;

/// Infection gained each tick by a wound nobody bandaged.
///
/// The checklist names 1/28800. That reaches [`INFECTION_SICK`] in two days and
/// 1.0 in four. The sentence "at 0.5 in four days" does not match this constant;
/// the constant is what the rules use.
pub const INFECTION_PER_TICK: f32 = 1.0 / 28_800.0;

/// Infected at or above this makes the person sick: health drains, and work is
/// refused with `wounded`.
pub const INFECTION_SICK: f32 = 0.5;

/// Health lost each tick while any region is at or above [`INFECTION_SICK`].
/// Once per person, not once per region.
pub const INFECTION_HEALTH_PER_TICK: f32 = 1.0 / 14_400.0;

/// Infection removed by one salve, before the 0.0 clamp.
pub const SALVE_INFECTION_CUT: f32 = 0.5;

/// Medicine skill a salve needs, at Heal and at the salve recipe. Below this the
/// order fails with `no skill`. Bandaging needs none.
pub const MEDICINE_SKILL_MIN: f32 = 0.25;

/// Warmth the world pulls a person toward outside the night range.
pub const AMBIENT_WARMTH_DAY: f32 = 0.9;

/// Warmth the world pulls a person toward inside the night range, in the open.
pub const AMBIENT_WARMTH_NIGHT: f32 = 0.0;

/// Night target within [`STATION_RANGE_M`] of a finished lean-to. Shelter, not a fire.
pub const LEANTO_WARMTH: f32 = 0.6;

/// Warmth moved toward the ambient target each tick, without overshooting it.
/// From day ambient, an open night reaches 0 in about three quarters of the night.
pub const WARMTH_DRIFT_PER_TICK: f32 = 1.0 / 1_200.0;

/// A finished campfire within this distance raises the warmth target to 1.0.
pub const WARMTH_RANGE_M: f32 = 3.0;

/// Health lost each tick while warmth is at or below 0. Drift runs after this check,
/// so a tick that starts at 0 pays the cost and then leaves 0 if the target is higher.
/// The ticks an open night spends at 0 cost about a tenth of health.
pub const COLD_HEALTH_PER_TICK: f32 = 1.0 / 3_600.0;

/// Fatigue gained each tick while idle. Walking or working multiplies it.
pub const FATIGUE_PER_TICK: f32 = 1.0 / 28_800.0;

/// Idle fatigue, times this, while walking or working. A full day of work is 0.75.
pub const FATIGUE_WORK_MULTIPLIER: f32 = 3.0;

/// Work is refused when fatigue is strictly above this, with `tired`.
pub const FATIGUE_REFUSAL: f32 = 0.85;

/// Fatigue cleared each tick of `Work { job: Rest }`. Twice this beside a finished lean-to.
pub const SLEEP_RECOVER_PER_TICK: f32 = 1.0 / 2_400.0;

/// Skill gained per gathered unit, finished building, crafted item, or completed heal.
/// Capped at 1.0.
pub const SKILL_PER_UNIT: f32 = 0.01;

/// Fraction of listed ticks a skill at 1.0 removes. The job then takes 60 percent.
pub const SKILL_TIME_RELIEF: f32 = 0.4;

/// Further fraction removed from gathering time when a knife is carried.
/// Applied to the skill-adjusted time, not added to the skill fraction.
pub const GATHER_TOOL_RELIEF: f32 = 0.25;

/// Ticks to craft a salve. Needs a finished campfire and medicine skill.
pub const RECIPE_SALVE_TICKS: u32 = 40;

/// `skills` array order on a person: gather, build, craft, medicine.
pub const SKILL_GATHER: usize = 0;
pub const SKILL_BUILD: usize = 1;
pub const SKILL_CRAFT: usize = 2;
pub const SKILL_MEDICINE: usize = 3;
pub const SKILL_COUNT: usize = 4;

/// Listed work ticks after skill and tool relief.
///
/// `skill` (0.0 to 1.0) keeps `1 - skill * SKILL_TIME_RELIEF` of `listed`.
/// `extra_relief` cuts that result again by the same kind of fraction: a carried
/// knife passes [`GATHER_TOOL_RELIEF`], and other jobs pass 0. Rounded to the
/// nearest tick, and at least 1 so a job cannot finish before it has been worked.
pub fn scaled_work_ticks(listed: u32, skill: f32, extra_relief: f32) -> u32 {
    let skill_keep = 1.0 - skill.clamp(0.0, 1.0) * SKILL_TIME_RELIEF;
    let tool_keep = 1.0 - extra_relief.clamp(0.0, 0.99);
    let ticks = (listed as f32 * skill_keep * tool_keep).round() as u32;
    ticks.max(1)
}

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
