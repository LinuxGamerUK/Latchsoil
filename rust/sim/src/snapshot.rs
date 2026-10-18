//! Plain snapshot records. No Godot type. `latchsoil-godot` turns these into
//! dictionaries; the field names are the contract's keys.

/// One person, as last copied out of the sim.
#[derive(Debug, Clone, PartialEq)]
pub struct PersonView {
    pub index: u32,
    pub generation: u32,
    pub x: f32,
    pub y: f32,
    pub hunger: f32,
    pub thirst: f32,
    pub health: f32,
    /// `JobKind` discriminant, or -1 when the order is not a job.
    pub job: i32,
    /// `FailureReason` discriminant, or -1 when there is no failure.
    pub failure: i32,
    pub failure_text: String,
    pub drafted: bool,
    /// `[item_id, count]` pairs, count at least 1, ascending item id.
    pub carried: Vec<[u32; 2]>,
    /// Packed x, y. Empty when the order has nowhere to walk.
    pub path: Vec<f32>,
    /// `[x, y]`, or empty.
    pub dest: Vec<f32>,
    /// `[index, generation]` when the order names another entity, otherwise empty.
    pub target: Vec<u32>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BuildingView {
    pub index: u32,
    pub generation: u32,
    /// `BuildingKind` discriminant, from 0.
    pub kind: u32,
    pub x: f32,
    pub y: f32,
    /// Work ticks spent. Finished at `BUILD_TICKS`.
    pub progress: u32,
    /// `[item_id, count]` pairs, sorted by item id. Empty for a non-stockpile.
    pub contents: Vec<[u32; 2]>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NodeView {
    pub index: u32,
    pub generation: u32,
    pub x: f32,
    pub y: f32,
    pub remaining: u32,
    pub yield_item: u32,
}

/// A full snapshot, or an error pull.
///
/// Milestone 1a: `poll` and `snapshot` both return this with `full` true and
/// `removed` empty for a live owner. An unknown owner gets `error` 2, empty
/// arrays, and the live tick and hash.
#[derive(Debug, Clone, PartialEq)]
pub struct Snapshot {
    pub tick: u64,
    pub people: Vec<PersonView>,
    pub buildings: Vec<BuildingView>,
    pub nodes: Vec<NodeView>,
    /// `[index, generation]` pairs. Empty on a full snapshot.
    pub removed: Vec<[u32; 2]>,
    pub hash: u64,
    pub full: bool,
    /// 0 on a good pull. 2 for an unknown owner.
    pub error: i32,
}

/// Counters behind `rejections`. Code 0 (queued) is not a rejection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Rejections {
    pub malformed: u64,
    pub stale: u64,
    pub queue_full: u64,
}
