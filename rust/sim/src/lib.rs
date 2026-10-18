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

pub use catalog::{Catalog, CatalogRow, ITEM_FIBER, ITEM_GRAIN, ITEM_STONE, ITEM_WATER, ITEM_WOOD};
pub use clock::{Clock, Season, DAYS_PER_SEASON, DAYS_PER_YEAR, TICKS_PER_DAY, TICKS_PER_SECOND};
pub use command::{
    BuildingKind, Command, FailureReason, ItemId, JobKind, RecipeId, MALFORMED, QUEUED, QUEUE_FULL,
    STALE,
};
pub use ids::{EntityAllocator, EntityId, EntityKind, GenerationalIndex};
pub use rng::SplitMix64;
pub use rules::{
    night_at, ACRE_METERS, CARRY_CAP, EAT_HUNGER_RESTORE, EAT_THIRST_RESTORE, GATHER_TICKS_PER_UNIT,
    HEALTH_PER_TICK, HEALTH_REFUSAL, HUNGER_PER_TICK, HUNGER_REFUSAL, NIGHT_START_TICK, PEG_X,
    PEG_Y, QUEUE_CAP, THIRST_PER_TICK, WALK_METERS_PER_TICK, WAYPOINT_REACH_METERS,
};
pub use save::{load_from_json, save_to_json, SaveError};
pub use snapshot::{BuildingView, NodeView, PersonView, Rejections, Snapshot};
pub use state::{SimState, SAVE_VERSION};
