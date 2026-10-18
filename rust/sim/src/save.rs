//! Versioned JSON saves. A Godot scene is not a save.
//!
//! The document carries `save_version`, the clock (the tick count), and the
//! RNG stream state (`rng.state`). Without the stream state a load cannot
//! reproduce the run.

use crate::state::{SimState, SAVE_VERSION};
use serde::Deserialize;
use std::fmt;

/// Why [`load_from_json`] refused a document.
#[derive(Debug)]
pub enum SaveError {
    /// The bytes are not JSON, or they are JSON that is not this save shape.
    Json(serde_json::Error),
    /// `save_version` is newer than [`SAVE_VERSION`]. We do not guess.
    VersionMismatch { found: u32, expected: u32 },
    /// `save_version` is older than [`SAVE_VERSION`]. A migration would have to
    /// run here; none is written yet.
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
///
/// `SimState` is owned data with no fallible fields. A serialize error is a bug.
pub fn save_to_json(state: &SimState) -> String {
    let mut json = serde_json::to_string_pretty(state).expect("SimState serializes");
    json.push('\n');
    json
}

#[derive(Deserialize)]
struct VersionHeader {
    save_version: u32,
}

/// Load a save written by this crate.
///
/// Version is checked before the rest of the document is accepted:
/// newer than [`SAVE_VERSION`] is [`SaveError::VersionMismatch`], older is
/// [`SaveError::MigrationNotImplemented`]. A body that is not JSON, or JSON
/// missing the fields this version requires, is [`SaveError::Json`].
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
    serde_json::from_str(text).map_err(SaveError::Json)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::SimState;

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
}
