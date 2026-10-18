//! The command surface. A command is the only write into a live entity.
//!
//! Failure strings are part of the bridge. Godot prints `failure_text`; it does
//! not invent a wording and it does not map the discriminant itself.

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
        item: ItemId,
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
    Take {
        actor: EntityId,
        item: ItemId,
        from: EntityId,
    },
}

impl Command {
    pub fn actor(self) -> EntityId {
        match self {
            Self::Move { actor, .. }
            | Self::Gather { actor, .. }
            | Self::Eat { actor, .. }
            | Self::Haul { actor, .. }
            | Self::Work { actor, .. }
            | Self::Place { actor, .. }
            | Self::Craft { actor, .. }
            | Self::Draft { actor, .. }
            | Self::Attack { actor, .. }
            | Self::Take { actor, .. } => actor,
        }
    }

    /// Lowercase variant name used on the reject line.
    pub fn variant_name(self) -> &'static str {
        match self {
            Self::Move { .. } => "move",
            Self::Gather { .. } => "gather",
            Self::Eat { .. } => "eat",
            Self::Haul { .. } => "haul",
            Self::Work { .. } => "work",
            Self::Place { .. } => "place",
            Self::Craft { .. } => "craft",
            Self::Draft { .. } => "draft",
            Self::Attack { .. } => "attack",
            Self::Take { .. } => "take",
        }
    }

    /// Labour. Refused at submit when hungry, wounded, or night.
    ///
    /// Eat is not labour: a hungry person must still be able to eat. Draft stores
    /// a posture and Attack stores a target; neither is refused at submit.
    pub fn is_work_order(self) -> bool {
        matches!(
            self,
            Self::Move { .. }
                | Self::Gather { .. }
                | Self::Haul { .. }
                | Self::Work { .. }
                | Self::Place { .. }
                | Self::Craft { .. }
                | Self::Take { .. }
        )
    }
}

/// Submit result. 0 queued, 1 malformed, 2 stale, 3 queue full.
pub const QUEUED: u8 = 0;
pub const MALFORMED: u8 = 1;
pub const STALE: u8 = 2;
pub const QUEUE_FULL: u8 = 3;

/// Item type id. Not generational. Names a row in the loaded item table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemId(pub u32);

/// Recipe id from the loaded tables.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecipeId(pub u32);

/// From 0: Haul, Build, Farm, Craft, Heal, Cook, Guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum JobKind {
    Haul = 0,
    Build = 1,
    Farm = 2,
    Craft = 3,
    Heal = 4,
    Cook = 5,
    Guard = 6,
}

impl JobKind {
    pub fn discriminant(self) -> i32 {
        self as i32
    }

    pub fn from_discriminant(value: u32) -> Option<Self> {
        Some(match value {
            0 => Self::Haul,
            1 => Self::Build,
            2 => Self::Farm,
            3 => Self::Craft,
            4 => Self::Heal,
            5 => Self::Cook,
            6 => Self::Guard,
            _ => return None,
        })
    }
}

/// From 0: Campfire, LeanTo, Stockpile, House, FarmPlot, Well, Workshop, Store, Palisade.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum BuildingKind {
    Campfire = 0,
    LeanTo = 1,
    Stockpile = 2,
    House = 3,
    FarmPlot = 4,
    Well = 5,
    Workshop = 6,
    Store = 7,
    Palisade = 8,
}

impl BuildingKind {
    pub fn discriminant(self) -> u32 {
        self as u32
    }

    pub fn from_discriminant(value: u32) -> Option<Self> {
        Some(match value {
            0 => Self::Campfire,
            1 => Self::LeanTo,
            2 => Self::Stockpile,
            3 => Self::House,
            4 => Self::FarmPlot,
            5 => Self::Well,
            6 => Self::Workshop,
            7 => Self::Store,
            8 => Self::Palisade,
            _ => return None,
        })
    }
}

/// Why a job failed. The string is the interface; the variant is the sim's.
///
/// Discriminants, from 0, are the snapshot `failure` field. If more than one
/// reason applies, the earliest variant wins.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum FailureReason {
    Hungry = 0,
    NoPath = 1,
    NoMaterial = 2,
    NoSkill = 3,
    Afraid = 4,
    Night = 5,
    Wounded = 6,
    NoStation = 7,
}

impl FailureReason {
    pub fn discriminant(self) -> i32 {
        self as i32
    }

    pub fn from_discriminant(value: u32) -> Option<Self> {
        Some(match value {
            0 => Self::Hungry,
            1 => Self::NoPath,
            2 => Self::NoMaterial,
            3 => Self::NoSkill,
            4 => Self::Afraid,
            5 => Self::Night,
            6 => Self::Wounded,
            7 => Self::NoStation,
            _ => return None,
        })
    }

    /// Bridge string. Godot prints this and does not keep a second wording.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Hungry => "hungry",
            Self::NoPath => "no path",
            Self::NoMaterial => "no material",
            Self::NoSkill => "no skill",
            Self::Afraid => "afraid",
            Self::Night => "night",
            Self::Wounded => "wounded",
            Self::NoStation => "no station",
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
            (FailureReason::Hungry, "hungry", 0),
            (FailureReason::NoPath, "no path", 1),
            (FailureReason::NoMaterial, "no material", 2),
            (FailureReason::NoSkill, "no skill", 3),
            (FailureReason::Afraid, "afraid", 4),
            (FailureReason::Night, "night", 5),
            (FailureReason::Wounded, "wounded", 6),
            (FailureReason::NoStation, "no station", 7),
        ];
        for (reason, word, disc) in cases {
            assert_eq!(reason.as_str(), word);
            assert_eq!(reason.to_string(), word);
            assert_eq!(reason.discriminant(), disc);
            assert_eq!(FailureReason::from_discriminant(disc as u32), Some(reason));
        }
        assert_eq!(FailureReason::from_discriminant(8), None);
    }

    #[test]
    fn unknown_job_and_building_discriminants_are_rejected() {
        assert_eq!(JobKind::from_discriminant(7), None);
        assert_eq!(BuildingKind::from_discriminant(9), None);
        assert_eq!(JobKind::Haul.discriminant(), 0);
        assert_eq!(BuildingKind::Campfire.discriminant(), 0);
        assert_eq!(JobKind::Guard.discriminant(), 6);
        assert_eq!(BuildingKind::Palisade.discriminant(), 8);
    }
}
