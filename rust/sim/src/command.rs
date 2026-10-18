//! The command surface. Commands are the only way the world changes, so a
//! command list plus a seed is a reproduction of a run.
//!
//! Failure strings are part of the bridge. Godot formats them; it does not invent them.

use crate::ids::EntityId;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Player order. One variant per verb the bridge accepts.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum Command {
    Move {
        actor: EntityId,
        to: [f32; 2],
    },
    Gather {
        actor: EntityId,
        node: EntityId,
    },
    Eat {
        actor: EntityId,
        item: ItemId,
    },
    Haul {
        actor: EntityId,
        item: EntityId,
        to: EntityId,
    },
    Work {
        actor: EntityId,
        job: JobKind,
    },
    Place {
        actor: EntityId,
        building: BuildingKind,
        at: [f32; 2],
    },
    Craft {
        actor: EntityId,
        recipe: RecipeId,
    },
    Draft {
        actor: EntityId,
        drafted: bool,
    },
    Attack {
        actor: EntityId,
        target: EntityId,
    },
}

/// Item type id. Not an entity: eating names a kind, hauling names a thing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemId(pub u32);

/// Recipe id from the data files. The sim does not execute it in this skeleton.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecipeId(pub u32);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobKind {
    Haul,
    Build,
    Farm,
    Craft,
    Heal,
    Cook,
    Guard,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BuildingKind {
    Campfire,
    LeanTo,
    Stockpile,
    House,
    FarmPlot,
    Well,
    Workshop,
    Store,
    Palisade,
}

/// Why a job failed. The string is the interface; the variant is the sim's.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FailureReason {
    Hungry,
    NoPath,
    NoMaterial,
    NoSkill,
    Afraid,
    Night,
    Wounded,
}

impl FailureReason {
    /// Bridge string. Lowercase, spaces where the variant is two words.
    /// These are the words Godot is allowed to show.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Hungry => "hungry",
            Self::NoPath => "no path",
            Self::NoMaterial => "no material",
            Self::NoSkill => "no skill",
            Self::Afraid => "afraid",
            Self::Night => "night",
            Self::Wounded => "wounded",
        }
    }
}

impl fmt::Display for FailureReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failure_strings_are_the_bridge_words() {
        let cases = [
            (FailureReason::Hungry, "hungry"),
            (FailureReason::NoPath, "no path"),
            (FailureReason::NoMaterial, "no material"),
            (FailureReason::NoSkill, "no skill"),
            (FailureReason::Afraid, "afraid"),
            (FailureReason::Night, "night"),
            (FailureReason::Wounded, "wounded"),
        ];
        for (reason, word) in cases {
            assert_eq!(reason.as_str(), word);
            assert_eq!(reason.to_string(), word);
        }
    }
}
