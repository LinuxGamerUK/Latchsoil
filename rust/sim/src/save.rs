//! Versioned JSON saves. A Godot scene is not a save.
//!
//! The document carries `save_version`, the seed, the tick, the RNG stream
//! state, every slot (live entities and free or retired slots), and the free
//! list. It does not carry the command queue, owners, pause, speed, or the camera.
//! There is no migration: any `save_version` other than [`SAVE_VERSION`] is refused.

use crate::state::{world_from_saved, SavedWorld, SimState, SAVE_VERSION};
use serde::Deserialize;
use std::fmt;

/// Why [`load_from_json`] refused a document.
#[derive(Debug)]
pub enum SaveError {
    /// The bytes are not JSON, or they are JSON that is not this save shape.
    Json(serde_json::Error),
    /// `save_version` is newer than [`SAVE_VERSION`]. We do not guess.
    VersionMismatch { found: u32, expected: u32 },
    /// `save_version` is older than [`SAVE_VERSION`]. No migration is written.
    MigrationNotImplemented { from: u32, to: u32 },
}

impl fmt::Display for SaveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(err) => write!(f, "save json: {err}"),
            Self::VersionMismatch { found, expected } => {
                write!(f, "save version {found} does not match {expected}")
            }
            Self::MigrationNotImplemented { from, to } => {
                write!(
                    f,
                    "migration from save version {from} to {to} is not implemented"
                )
            }
        }
    }
}

impl std::error::Error for SaveError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Json(err) => Some(err),
            Self::VersionMismatch { .. } | Self::MigrationNotImplemented { .. } => None,
        }
    }
}

/// Pretty JSON, so a failing run can be opened in an editor.
pub fn save_to_json(state: &SimState) -> String {
    let doc = state.to_saved();
    let mut json = serde_json::to_string_pretty(&doc).expect("save document serializes");
    json.push('\n');
    json
}

/// `save_json` on the sim. Same text as [`save_to_json`].
impl SimState {
    pub fn save_json(&self) -> String {
        save_to_json(self)
    }
}

#[derive(Deserialize)]
struct VersionHeader {
    save_version: u32,
}

/// Load a save written by this crate into a fresh sim with no owners.
///
/// Version is checked before the rest of the document is accepted.
/// Newer than [`SAVE_VERSION`] is [`SaveError::VersionMismatch`], older is
/// [`SaveError::MigrationNotImplemented`]. A body that is not this shape is
/// [`SaveError::Json`].
pub fn load_from_json(text: &str) -> Result<SimState, SaveError> {
    let header: VersionHeader = serde_json::from_str(text).map_err(SaveError::Json)?;
    if header.save_version > SAVE_VERSION {
        return Err(SaveError::VersionMismatch {
            found: header.save_version,
            expected: SAVE_VERSION,
        });
    }
    if header.save_version < SAVE_VERSION {
        return Err(SaveError::MigrationNotImplemented {
            from: header.save_version,
            to: SAVE_VERSION,
        });
    }
    let doc: SavedWorld = serde_json::from_str(text).map_err(SaveError::Json)?;
    let loaded = world_from_saved(doc).map_err(|msg| {
        SaveError::Json(serde::de::Error::custom(msg))
    })?;
    let mut sim = SimState::new(loaded.seed);
    // install_loaded logs a queue clear. A fresh sim's queue is empty.
    sim.install_loaded(loaded);
    Ok(sim)
}

impl SimState {
    /// Replace this world's entities from `text`. Returns 0 on success, 1 on
    /// refusal. A refusal logs `reject malformed save` and keeps the current world.
    /// Success clears the queue and marks every owner for a full snapshot.
    /// Owners themselves are not in the save and are not dropped.
    pub fn load_json(&mut self, text: &str) -> u8 {
        match load_into(text) {
            Ok(loaded) => {
                self.install_loaded(loaded);
                0
            }
            Err(_) => {
                eprintln!("reject malformed save");
                1
            }
        }
    }
}

fn load_into(text: &str) -> Result<crate::state::LoadedWorld, SaveError> {
    let header: VersionHeader = serde_json::from_str(text).map_err(SaveError::Json)?;
    if header.save_version != SAVE_VERSION {
        return Err(SaveError::VersionMismatch {
            found: header.save_version,
            expected: SAVE_VERSION,
        });
    }
    let doc: SavedWorld = serde_json::from_str(text).map_err(SaveError::Json)?;
    world_from_saved(doc).map_err(|msg| SaveError::Json(serde::de::Error::custom(msg)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_json_is_a_json_error() {
        let err = load_from_json("not json").unwrap_err();
        assert!(matches!(err, SaveError::Json(_)));
    }

    #[test]
    fn missing_save_version_is_a_json_error() {
        let err = load_from_json("{}").unwrap_err();
        assert!(matches!(err, SaveError::Json(_)));
    }

    #[test]
    fn older_save_version_is_migration_not_implemented() {
        let sim = SimState::new(1);
        let mut value: serde_json::Value = serde_json::from_str(&save_to_json(&sim)).unwrap();
        value["save_version"] = serde_json::json!(0);
        let err = load_from_json(&value.to_string()).unwrap_err();
        assert!(matches!(
            err,
            SaveError::MigrationNotImplemented {
                from: 0,
                to: SAVE_VERSION
            }
        ));
    }

    #[test]
    fn load_json_refuses_an_unknown_version_and_keeps_the_world() {
        let mut sim = SimState::new(3);
        sim.new_game(3);
        let hash = sim.state_hash();
        let tick = sim.tick();
        let mut value: serde_json::Value = serde_json::from_str(&save_to_json(&sim)).unwrap();
        value["save_version"] = serde_json::json!(SAVE_VERSION + 9);
        assert_eq!(sim.load_json(&value.to_string()), 1);
        assert_eq!(sim.state_hash(), hash);
        assert_eq!(sim.tick(), tick);
        assert_eq!(sim.load_json("not json"), 1);
        assert_eq!(sim.state_hash(), hash);
        assert_eq!(sim.load_json("{}"), 1);
        assert_eq!(sim.state_hash(), hash);
    }
}
