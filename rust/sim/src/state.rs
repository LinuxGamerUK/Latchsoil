//! Sim state: the seed, the clock, the RNG stream, the id allocator, and the
//! command log. Hunger, skills, factions, combat, worldgen, and job execution
//! are later milestones and are not fields here.

use crate::clock::Clock;
use crate::command::{BuildingKind, Command, FailureReason, JobKind};
use crate::ids::EntityAllocator;
use crate::rng::SplitMix64;
use serde::{Deserialize, Serialize};

/// Save format this crate writes and will load without a migration.
pub const SAVE_VERSION: u32 = 1;

/// FNV-1a 64-bit. Offset basis and prime from the public-domain FNV note.
/// Little-endian so the fingerprint does not depend on host endianness.
struct Fnv64(u64);

impl Fnv64 {
    fn new() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }

    fn write_u8(&mut self, byte: u8) {
        self.0 ^= u64::from(byte);
        self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
    }

    fn write_u32(&mut self, value: u32) {
        for byte in value.to_le_bytes() {
            self.write_u8(byte);
        }
    }

    fn write_u64(&mut self, value: u64) {
        for byte in value.to_le_bytes() {
            self.write_u8(byte);
        }
    }

    fn finish(self) -> u64 {
        self.0
    }
}

/// One running simulation.
///
/// `commands` is the log [`SimState::apply`] records. It is part of the save so
/// a round trip preserves the hash; later milestones read it instead of growing
/// a second history.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SimState {
    pub save_version: u32,
    pub seed: u64,
    pub clock: Clock,
    pub rng: SplitMix64,
    pub next_entity: EntityAllocator,
    commands: Vec<Command>,
}

impl SimState {
    /// Version [`SAVE_VERSION`], tick 0, RNG stream positioned at `seed`, no ids, no commands.
    pub fn new(seed: u64) -> Self {
        Self {
            save_version: SAVE_VERSION,
            seed,
            clock: Clock::new(),
            rng: SplitMix64::new(seed),
            next_entity: EntityAllocator::new(),
            commands: Vec::new(),
        }
    }

    /// Accept `cmd` onto the log.
    ///
    /// The skeleton does not execute jobs, so every command is `Ok`. Returning
    /// [`FailureReason`] is the later milestone's job; the type is in the
    /// signature so the command list already reaches the sim.
    pub fn apply(&mut self, cmd: &Command) -> Result<(), FailureReason> {
        self.commands.push(*cmd);
        Ok(())
    }

    /// Commands recorded by [`Self::apply`], in apply order.
    pub fn commands(&self) -> &[Command] {
        &self.commands
    }

    /// Fingerprint for determinism checks.
    ///
    /// Hand-rolled FNV-1a over fields in a fixed order: save version, seed,
    /// tick, RNG stream state, allocator slots, free list, then the command log.
    /// `std`'s `DefaultHasher` is not used — it is not stable across Rust
    /// releases, and it is keyed per process. No `HashMap` is walked; there
    /// isn't one. Two runs with the same seed and the same command list therefore
    /// compare equal without depending on hash-table iteration.
    pub fn state_hash(&self) -> u64 {
        let mut hash = Fnv64::new();
        hash.write_u8(1);
        hash.write_u32(self.save_version);
        hash.write_u8(2);
        hash.write_u64(self.seed);
        hash.write_u8(3);
        hash.write_u64(self.clock.tick());
        hash.write_u8(4);
        hash.write_u64(self.rng.state());
        hash.write_u8(5);
        hash_allocator(&mut hash, &self.next_entity);
        hash.write_u8(6);
        hash.write_u64(self.commands.len() as u64);
        for cmd in &self.commands {
            hash_command(&mut hash, cmd);
        }
        hash.finish()
    }
}

fn hash_allocator(hash: &mut Fnv64, alloc: &EntityAllocator) {
    let mut count = 0u64;
    for (generation, live) in alloc.slot_views() {
        hash.write_u32(generation);
        hash.write_u8(u8::from(live));
        count += 1;
    }
    hash.write_u64(count);
    hash.write_u64(alloc.free_list().len() as u64);
    for index in alloc.free_list() {
        hash.write_u32(*index);
    }
}

fn hash_command(hash: &mut Fnv64, cmd: &Command) {
    match cmd {
        Command::Move { actor, to } => {
            hash.write_u8(1);
            hash.write_u32(actor.0);
            hash.write_u32(to[0].to_bits());
            hash.write_u32(to[1].to_bits());
        }
        Command::Gather { actor, node } => {
            hash.write_u8(2);
            hash.write_u32(actor.0);
            hash.write_u32(node.0);
        }
        Command::Eat { actor, item } => {
            hash.write_u8(3);
            hash.write_u32(actor.0);
            hash.write_u32(item.0);
        }
        Command::Haul { actor, item, to } => {
            hash.write_u8(4);
            hash.write_u32(actor.0);
            hash.write_u32(item.0);
            hash.write_u32(to.0);
        }
        Command::Work { actor, job } => {
            hash.write_u8(5);
            hash.write_u32(actor.0);
            hash.write_u8(job_tag(*job));
        }
        Command::Place {
            actor,
            building,
            at,
        } => {
            hash.write_u8(6);
            hash.write_u32(actor.0);
            hash.write_u8(building_tag(*building));
            hash.write_u32(at[0].to_bits());
            hash.write_u32(at[1].to_bits());
        }
        Command::Craft { actor, recipe } => {
            hash.write_u8(7);
            hash.write_u32(actor.0);
            hash.write_u32(recipe.0);
        }
        Command::Draft { actor, drafted } => {
            hash.write_u8(8);
            hash.write_u32(actor.0);
            hash.write_u8(u8::from(*drafted));
        }
        Command::Attack { actor, target } => {
            hash.write_u8(9);
            hash.write_u32(actor.0);
            hash.write_u32(target.0);
        }
    }
}

fn job_tag(job: JobKind) -> u8 {
    match job {
        JobKind::Haul => 1,
        JobKind::Build => 2,
        JobKind::Farm => 3,
        JobKind::Craft => 4,
        JobKind::Heal => 5,
        JobKind::Cook => 6,
        JobKind::Guard => 7,
    }
}

fn building_tag(building: BuildingKind) -> u8 {
    match building {
        BuildingKind::Campfire => 1,
        BuildingKind::LeanTo => 2,
        BuildingKind::Stockpile => 3,
        BuildingKind::House => 4,
        BuildingKind::FarmPlot => 5,
        BuildingKind::Well => 6,
        BuildingKind::Workshop => 7,
        BuildingKind::Store => 8,
        BuildingKind::Palisade => 9,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::{BuildingKind, ItemId, JobKind, RecipeId};
    use crate::ids::EntityId;

    #[test]
    fn new_carries_version_tick_zero_and_the_seed_as_rng_state() {
        let sim = SimState::new(99);
        assert_eq!(sim.save_version, SAVE_VERSION);
        assert_eq!(sim.save_version, 1);
        assert_eq!(sim.seed, 99);
        assert_eq!(sim.clock.tick(), 0);
        assert_eq!(sim.rng.state(), 99);
        assert!(sim.commands().is_empty());
    }

    #[test]
    fn apply_records_every_command_variant_and_the_hash_follows() {
        let commands = [
            Command::Move {
                actor: EntityId(1),
                to: [1.5, 2.25],
            },
            Command::Gather {
                actor: EntityId(1),
                node: EntityId(2),
            },
            Command::Eat {
                actor: EntityId(1),
                item: ItemId(7),
            },
            Command::Haul {
                actor: EntityId(1),
                item: EntityId(3),
                to: EntityId(4),
            },
            Command::Work {
                actor: EntityId(1),
                job: JobKind::Farm,
            },
            Command::Place {
                actor: EntityId(1),
                building: BuildingKind::Well,
                at: [0.5, 8.0],
            },
            Command::Craft {
                actor: EntityId(1),
                recipe: RecipeId(9),
            },
            Command::Draft {
                actor: EntityId(1),
                drafted: false,
            },
            Command::Attack {
                actor: EntityId(1),
                target: EntityId(5),
            },
        ];
        let mut sim = SimState::new(3);
        let before = sim.state_hash();
        for cmd in &commands {
            assert!(sim.apply(cmd).is_ok());
        }
        assert_eq!(sim.commands(), &commands);
        assert_ne!(sim.state_hash(), before);

        let mut again = SimState::new(3);
        for cmd in &commands {
            again.apply(cmd).unwrap();
        }
        assert_eq!(again.state_hash(), sim.state_hash());
    }
}
