//! The Latchsoil bridge. Godot talks only to `SimHost`.
//!
//! Rules, the world, the owner table, the command queue, pause, speed, the tick
//! accumulator and the rejection counters live in `latchsoil-sim`. This crate
//! copies the sim's plain records into Godot values and never hands Godot a
//! pointer into sim memory. Reject lines are written by the sim; this crate
//! does not write a second one. The method names are the ones in `docs/09-bridge.md`.

mod convert;

use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};

use godot::classes::{ClassDb, Engine};
use godot::obj::Singleton;
use godot::prelude::*;
use latchsoil_sim::{SimState, SAVE_VERSION};

/// API this crate was compiled for. A pin change is a charter decision.
const ENGINE_API: &str = "4.7";
const ENGINE_MAJOR: i64 = 4;
const ENGINE_MINOR: i64 = 7;

/// One host has been constructed in this process. A second is a startup failure.
static HOST_LIVE: AtomicBool = AtomicBool::new(false);

struct LatchsoilExtension;

#[gdextension]
unsafe impl ExtensionLibrary for LatchsoilExtension {
    fn on_stage_init(stage: InitStage) {
        if stage == InitStage::MainLoop {
            // Main loop init runs before the main scene, so a mismatch never
            // reaches play and never prints the smoke line.
            guard_startup();
        }
    }
}

fn guard_startup() {
    if !ClassDb::singleton().class_exists("SimHost") {
        fail_startup("SimHost is not registered");
    }
    let info = Engine::singleton().get_version_info();
    let major = info.get("major").and_then(|value| value.try_to::<i64>().ok());
    let minor = info.get("minor").and_then(|value| value.try_to::<i64>().ok());
    if major != Some(ENGINE_MAJOR) || minor != Some(ENGINE_MINOR) {
        fail_startup("engine_api 4.7 does not match the running engine");
    }
}

fn fail_startup(reason: &str) -> ! {
    eprintln!("latchsoil: {reason}");
    let _ = io::stderr().flush();
    let _ = io::stdout().flush();
    std::process::exit(1);
}

/// One running sim, owned by Godot as a node. One per process.
#[derive(GodotClass)]
#[class(base=Node)]
struct SimHost {
    base: Base<Node>,
    sim: SimState,
}

#[godot_api]
impl INode for SimHost {
    fn init(base: Base<Node>) -> Self {
        if HOST_LIVE.swap(true, Ordering::SeqCst) {
            fail_startup("a second SimHost is a startup failure");
        }
        Self {
            base,
            sim: SimState::new(0),
        }
    }

    fn ready(&mut self) {
        godot_print!("latchsoil: SimHost ready (save v{SAVE_VERSION})");
    }

    fn exit_tree(&mut self) {
        self.sim.detach_all();
    }
}

#[godot_api]
impl SimHost {
    /// Replace the world. Same call as [`Self::new_game`]; the smoke scene
    /// still uses this name.
    #[func]
    fn start(&mut self, seed: i64) {
        self.new_game(seed);
    }

    /// Reset tick, seed, and entities, and lay the cast. The sim clears the
    /// queue and marks every owner for a full snapshot.
    #[func]
    fn new_game(&mut self, seed: i64) {
        self.sim.new_game(seed as u64);
    }

    /// Attach a consumer. Owner ids start at 1. The ninth live owner returns 0.
    #[func]
    fn attach(&mut self) -> i64 {
        i64::from(self.sim.attach())
    }

    /// Drop that owner's pending copies. An unknown owner is a no-op.
    #[func]
    fn detach(&mut self, owner: i64) {
        if let Ok(owner) = u32::try_from(owner) {
            self.sim.detach(owner);
        }
    }

    /// Advance exactly one tick. Applies the queue first. Ignores pause.
    #[func]
    fn step(&mut self) -> i64 {
        self.sim.step();
        self.tick()
    }

    /// Add `delta * speed` to the accumulator and run at most five ticks.
    /// A negative or non-finite delta counts as 0. While paused, nothing moves.
    #[func]
    fn frame(&mut self, delta: f64) {
        self.sim.frame(delta as f32);
    }

    #[func]
    fn set_paused(&mut self, paused: bool) {
        self.sim.set_paused(paused);
    }

    /// Speed is only 1, 2, or 3. Anything else returns 1 and leaves the
    /// multiplier alone. The sim writes the reject line.
    #[func]
    fn set_speed(&mut self, speed: i64) -> i64 {
        i64::from(self.sim.set_speed(speed))
    }

    #[func]
    fn submit_move(&mut self, actor_index: i64, actor_generation: i64, x: f64, y: f64) -> i64 {
        let (index, generation) = id_pair(actor_index, actor_generation);
        i64::from(self.sim.submit_move(index, generation, as_f32(x), as_f32(y)))
    }

    #[func]
    fn submit_gather(
        &mut self,
        actor_index: i64,
        actor_generation: i64,
        node_index: i64,
        node_generation: i64,
    ) -> i64 {
        let (actor, actor_gen) = id_pair(actor_index, actor_generation);
        let (node, node_gen) = id_pair(node_index, node_generation);
        i64::from(self.sim.submit_gather(actor, actor_gen, node, node_gen))
    }

    #[func]
    fn submit_eat(&mut self, actor_index: i64, actor_generation: i64, item: i64) -> i64 {
        let (index, generation) = id_pair(actor_index, actor_generation);
        i64::from(self.sim.submit_eat(index, generation, as_u32(item)))
    }

    #[func]
    fn submit_haul(
        &mut self,
        actor_index: i64,
        actor_generation: i64,
        item: i64,
        to_index: i64,
        to_generation: i64,
    ) -> i64 {
        let (actor, actor_gen) = id_pair(actor_index, actor_generation);
        let (to, to_gen) = id_pair(to_index, to_generation);
        i64::from(
            self.sim
                .submit_haul(actor, actor_gen, as_u32(item), to, to_gen),
        )
    }

    #[func]
    fn submit_work(&mut self, actor_index: i64, actor_generation: i64, job: i64) -> i64 {
        let (index, generation) = id_pair(actor_index, actor_generation);
        i64::from(self.sim.submit_work(index, generation, as_u32(job)))
    }

    #[func]
    fn submit_place(
        &mut self,
        actor_index: i64,
        actor_generation: i64,
        building: i64,
        x: f64,
        y: f64,
    ) -> i64 {
        let (index, generation) = id_pair(actor_index, actor_generation);
        i64::from(self.sim.submit_place(
            index,
            generation,
            as_u32(building),
            as_f32(x),
            as_f32(y),
        ))
    }

    #[func]
    fn submit_craft(&mut self, actor_index: i64, actor_generation: i64, recipe: i64) -> i64 {
        let (index, generation) = id_pair(actor_index, actor_generation);
        i64::from(self.sim.submit_craft(index, generation, as_u32(recipe)))
    }

    #[func]
    fn submit_draft(&mut self, actor_index: i64, actor_generation: i64, drafted: bool) -> i64 {
        let (index, generation) = id_pair(actor_index, actor_generation);
        i64::from(self.sim.submit_draft(index, generation, drafted))
    }

    #[func]
    fn submit_attack(
        &mut self,
        actor_index: i64,
        actor_generation: i64,
        target_index: i64,
        target_generation: i64,
    ) -> i64 {
        let (actor, actor_gen) = id_pair(actor_index, actor_generation);
        let (target, target_gen) = id_pair(target_index, target_generation);
        i64::from(self.sim.submit_attack(actor, actor_gen, target, target_gen))
    }

    /// Queue a take from a stockpile. Same codes as the other submits.
    /// The sim writes the reject line; this method does not.
    #[func]
    fn submit_take(
        &mut self,
        actor_index: i64,
        actor_gen: i64,
        item_id: i64,
        from_index: i64,
        from_gen: i64,
    ) -> i64 {
        self.sim
            .submit_take(actor_index, actor_gen, item_id, from_index, from_gen)
    }

    /// Force a full copy. An unknown owner gets error 2 and empty arrays.
    #[func]
    fn snapshot(&mut self, owner: i64) -> VarDictionary {
        convert::snapshot(&self.sim.snapshot(owner_id(owner)))
    }

    /// Milestone 1a: every pull is a full snapshot. `removed` is empty.
    #[func]
    fn poll(&mut self, owner: i64) -> VarDictionary {
        convert::snapshot(&self.sim.poll(owner_id(owner)))
    }

    #[func]
    fn catalog(&self) -> VarDictionary {
        convert::catalog(&self.sim.catalog())
    }

    #[func]
    fn tick(&self) -> i64 {
        i64::try_from(self.sim.tick()).unwrap_or(i64::MAX)
    }

    /// 16 lowercase hex digits. Godot's int is narrower than the sim hash.
    #[func]
    fn state_hash(&self) -> GString {
        GString::from(convert::hash_hex(self.sim.state_hash()).as_str())
    }

    #[func]
    fn rejections(&self) -> VarDictionary {
        convert::rejections(&self.sim.rejections())
    }

    #[func]
    fn save_json(&self) -> GString {
        GString::from(self.sim.save_json().as_str())
    }

    /// 0 on success, 1 if the text is not a save this build can load.
    /// The sim writes `reject malformed save` and keeps the current world.
    #[func]
    fn load_json(&mut self, text: GString) -> i64 {
        i64::from(self.sim.load_json(&text.to_string()))
    }

    /// The API this crate was compiled for, `major.minor`.
    #[func]
    fn engine_api(&self) -> GString {
        GString::from(ENGINE_API)
    }

    /// Leftover accumulator over one tick, in 0.0..=1.0. Zero while paused.
    #[func]
    fn alpha(&self) -> f64 {
        f64::from(self.sim.alpha())
    }
}

/// An id that does not fit in `u32` cannot be live. `(0, 0)` is always stale,
/// so the sim rejects, logs, and counts it without this crate writing a line.
fn id_pair(index: i64, generation: i64) -> (u32, u32) {
    match (u32::try_from(index), u32::try_from(generation)) {
        (Ok(index), Ok(generation)) => (index, generation),
        _ => (0, 0),
    }
}

/// A table id or discriminant outside `u32` is not in the loaded tables.
/// `u32::MAX` is not a known item, recipe, job, or building, so the sim
/// rejects it as malformed and writes the one reject line.
fn as_u32(value: i64) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

/// A coordinate that does not fit in `f32` becomes non-finite. The sim rejects
/// a non-finite point as malformed and does not write it.
fn as_f32(value: f64) -> f32 {
    let narrowed = value as f32;
    if value.is_finite() && !narrowed.is_finite() {
        f32::NAN
    } else {
        narrowed
    }
}

/// 0 is never a live owner. A negative or oversized id is an unknown owner.
fn owner_id(owner: i64) -> u32 {
    u32::try_from(owner).unwrap_or(0)
}
