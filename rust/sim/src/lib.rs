//! Latchsoil simulation.
//!
//! Gameplay rules live here. This crate names no Godot type and does not depend
//! on gdext, so `cargo test` runs with no engine at all.
//!
//! A `u64` seed plus the same command list reproduces a run. Saves carry
//! `save_version`, the tick count, and the RNG stream state. Nothing in this
//! crate iterates a `HashMap` — fixed order only, or a run stops being
//! reproducible.

mod clock;
mod command;
mod ids;
mod rng;
mod save;
mod state;

pub use clock::{Clock, Season, DAYS_PER_SEASON, DAYS_PER_YEAR, TICKS_PER_DAY, TICKS_PER_SECOND};
pub use command::{BuildingKind, Command, FailureReason, ItemId, JobKind, RecipeId};
pub use ids::{EntityAllocator, EntityId, GenerationalIndex};
pub use rng::SplitMix64;
pub use save::{load_from_json, save_to_json, SaveError};
pub use state::{SimState, SAVE_VERSION};
