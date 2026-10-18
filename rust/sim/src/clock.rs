//! Sim clock. Render rate is not this clock's problem.
//!
//! Arithmetic, at 1x speed:
//! - the sim ticks at 10 Hz ([`TICKS_PER_SECOND`]);
//! - a day is 12 real minutes = `12 * 60 * 10` = [`TICKS_PER_DAY`] (7_200) ticks;
//! - a season is [`DAYS_PER_SEASON`] (10) days;
//! - a year is four seasons = [`DAYS_PER_YEAR`] (40) days = 288_000 ticks.
//!
//! The lore turning (428 days) is flavor text and is not used here.

use serde::{Deserialize, Serialize};

/// Sim ticks per real second at 1x. The sim runs at 10 Hz.
pub const TICKS_PER_SECOND: u64 = 10;

/// Ticks in one sim day.
///
/// A day is 12 real minutes at 1x: `12 * 60 * TICKS_PER_SECOND = 7_200`.
pub const TICKS_PER_DAY: u64 = 7_200;

/// Days in one season. The four seasons are Sprout, High Sun, Stitchfall, Deep Bell.
pub const DAYS_PER_SEASON: u64 = 10;

/// Days in one sim year: four seasons of [`DAYS_PER_SEASON`].
///
/// A year is 40 days = `40 * 7_200` = 288_000 ticks.
pub const DAYS_PER_YEAR: u64 = 40;

/// The four sim seasons, in year order. A season is [`DAYS_PER_SEASON`] days.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Season {
    Sprout,
    HighSun,
    Stitchfall,
    DeepBell,
}

/// Tick counter. Day, season, and year are derived; they are not stored,
/// so a save cannot disagree with the tick it carries.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Clock {
    tick: u64,
}

impl Clock {
    /// Tick 0: day 0 of Sprout, year 0.
    pub fn new() -> Self {
        Self { tick: 0 }
    }

    /// A clock already at `tick`. Used when a save is loaded.
    pub fn from_tick(tick: u64) -> Self {
        Self { tick }
    }

    /// Tick within the current day, in `0..TICKS_PER_DAY`.
    pub fn tick_of_day(self) -> u64 {
        self.tick % TICKS_PER_DAY
    }

    /// Move the clock forward by `n` ticks.
    ///
    /// Panics if the tick counter would overflow `u64`. That is a bug, not a
    /// season boundary.
    pub fn advance(&mut self, n: u64) {
        self.tick = self.tick.checked_add(n).expect("clock tick overflow");
    }

    /// Ticks elapsed since [`Clock::new`].
    pub fn tick(&self) -> u64 {
        self.tick
    }

    /// 0-based day index. Day `d` is ticks `[d * TICKS_PER_DAY, (d + 1) * TICKS_PER_DAY)`.
    pub fn day(&self) -> u64 {
        self.tick / TICKS_PER_DAY
    }

    /// Season containing [`Self::day`]. Sprout, High Sun, Stitchfall, Deep Bell, then the next year.
    pub fn season(&self) -> Season {
        match (self.day() / DAYS_PER_SEASON) % 4 {
            0 => Season::Sprout,
            1 => Season::HighSun,
            2 => Season::Stitchfall,
            _ => Season::DeepBell,
        }
    }

    /// 0-based day within the current season, in `0..DAYS_PER_SEASON`.
    pub fn day_of_season(&self) -> u64 {
        self.day() % DAYS_PER_SEASON
    }

    /// 0-based sim year. A year is [`DAYS_PER_YEAR`] days (288_000 ticks).
    pub fn year(&self) -> u64 {
        self.day() / DAYS_PER_YEAR
    }
}
