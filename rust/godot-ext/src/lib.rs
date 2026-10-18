//! The Latchsoil bridge: a GDExtension cdylib that exposes the engine-free sim
//! to Godot. Rules live in `latchsoil-sim`; this crate only carries them across.
//!
//! Milestone 0 exposes one node, `SimHost`: start a run from a seed, advance it,
//! read the tick, read the determinism fingerprint, and ask for a save string.
//! Commands, snapshots and dirty sets arrive in milestone 1 (see `docs/09-bridge.md`).

use godot::prelude::*;
use latchsoil_sim::{save_to_json, SimState, SAVE_VERSION};

/// Version of this bridge's surface, bumped when a `#[func]` changes shape.
const BRIDGE_VERSION: i64 = 0;

struct LatchsoilExtension;

#[gdextension]
unsafe impl ExtensionLibrary for LatchsoilExtension {}

/// One running sim, owned by Godot as a node.
#[derive(GodotClass)]
#[class(base=Node)]
struct SimHost {
    base: Base<Node>,
    sim: SimState,
}

#[godot_api]
impl INode for SimHost {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            // A seed of 0 is a placeholder: the new-game flow calls `start`.
            sim: SimState::new(0),
        }
    }

    fn ready(&mut self) {
        godot_print!(
            "latchsoil: SimHost ready (bridge v{}, save v{})",
            BRIDGE_VERSION,
            SAVE_VERSION
        );
    }
}

#[godot_api]
impl SimHost {
    /// Begin a run from `seed`, discarding any state already here.
    /// The sim owns the seed; Godot only carries the number.
    #[func]
    fn start(&mut self, seed: i64) {
        self.sim = SimState::new(seed as u64);
    }

    /// Advance the sim by one tick and return the new tick count.
    #[func]
    fn tick_once(&mut self) -> i64 {
        self.sim.clock.advance(1);
        self.sim.clock.tick() as i64
    }

    /// Advance the sim by `ticks` and return the new tick count. A negative
    /// count advances nothing: the sim never runs backwards.
    #[func]
    fn advance(&mut self, ticks: i64) -> i64 {
        if ticks > 0 {
            self.sim.clock.advance(ticks as u64);
        }
        self.sim.clock.tick() as i64
    }

    /// The determinism fingerprint of the whole sim state, as 16 hex digits.
    /// Two runs with the same seed and the same command list share this value.
    #[func]
    fn state_hash(&self) -> GString {
        GString::from(format!("{:016x}", self.sim.state_hash()).as_str())
    }

    /// The sim state as versioned JSON. Godot is never the owner of a save.
    #[func]
    fn save_json(&self) -> GString {
        GString::from(save_to_json(&self.sim).as_str())
    }

    /// The save format version this build reads and writes.
    #[func]
    fn save_version(&self) -> i64 {
        SAVE_VERSION as i64
    }
}
