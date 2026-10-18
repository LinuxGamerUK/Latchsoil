//! Latchsoil simulation.
//!
//! Gameplay rules live here. This crate names no Godot type and does not depend
//! on gdext, so `cargo test` runs with no engine at all.
//!
//! A `u64` seed plus the same command list reproduces a run. Saves carry
//! `save_version`, the tick count, and the RNG stream state. Nothing in this
//! crate iterates a `HashMap` — fixed order only, or a run stops being
//! reproducible.

mod catalog;
mod clock;
mod command;
mod ids;
mod path;
mod rng;
mod rules;
mod save;
mod snapshot;
mod state;

pub use catalog::{
    Catalog, CatalogRow, ITEM_BANDAGE, ITEM_FIBER, ITEM_GRAIN, ITEM_KNIFE, ITEM_MEAL, ITEM_SALVE,
    ITEM_STONE, ITEM_WATER, ITEM_WOOD, RECIPE_BANDAGE, RECIPE_KNIFE, RECIPE_MEAL, RECIPE_SALVE,
};
pub use clock::{Clock, Season, DAYS_PER_SEASON, DAYS_PER_YEAR, TICKS_PER_DAY, TICKS_PER_SECOND};
pub use command::{
    BuildingKind, Command, FailureReason, ItemId, JobKind, RecipeId, RegionKind, MALFORMED, QUEUED,
    QUEUE_FULL, STALE,
};
pub use ids::{EntityAllocator, EntityId, EntityKind, GenerationalIndex};
pub use rng::SplitMix64;
pub use rules::{
    night_at, scaled_work_ticks, ACRE_METERS, AMBIENT_WARMTH_DAY, AMBIENT_WARMTH_NIGHT,
    BLEED_HEALTH_PER_TICK, BUILD_TICKS, CARRY_CAP, COLD_HEALTH_PER_TICK, EAT_HUNGER_RESTORE,
    EAT_THIRST_RESTORE, FATIGUE_PER_TICK, FATIGUE_REFUSAL, FATIGUE_WORK_MULTIPLIER,
    GATHER_TICKS_PER_UNIT, GATHER_TOOL_RELIEF, HAUL_TICKS_PER_UNIT, HEALTH_FULL_TICKS,
    HEALTH_PER_TICK, HEALTH_REFUSAL, HEAL_TICKS, HUNGER_FULL_TICKS, HUNGER_PER_TICK,
    HUNGER_REFUSAL, INFECTION_HEALTH_PER_TICK, INFECTION_PER_TICK, INFECTION_SICK, LEANTO_WARMTH,
    MEAL_HUNGER_RESTORE, MEAL_THIRST_RESTORE, MEDICINE_SKILL_MIN, NIGHT_START_TICK, PEG_X, PEG_Y,
    QUEUE_CAP, RECIPE_BANDAGE_TICKS, RECIPE_KNIFE_TICKS, RECIPE_MEAL_TICKS, RECIPE_SALVE_TICKS,
    SALVE_INFECTION_CUT, SKILL_BUILD, SKILL_COUNT, SKILL_CRAFT, SKILL_GATHER, SKILL_MEDICINE,
    SKILL_PER_UNIT, SKILL_TIME_RELIEF, SLEEP_RECOVER_PER_TICK, STARTING_GRAIN, STATION_RANGE_M,
    STOCKPILE_CAPACITY, TAKE_TICKS_PER_UNIT, THIRST_FULL_TICKS, THIRST_PER_TICK,
    WALK_METERS_PER_TICK, WARMTH_DRIFT_PER_TICK, WARMTH_RANGE_M, WATER_HUNGER_RESTORE,
    WATER_REMAINING, WATER_THIRST_RESTORE, WAYPOINT_REACH_METERS,
};
pub use save::{load_from_json, save_to_json, SaveError};
pub use snapshot::{BuildingView, NodeView, PersonView, RegionView, Rejections, Snapshot};
pub use state::{SimState, SAVE_VERSION};
