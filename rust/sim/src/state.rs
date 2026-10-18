//! Sim state: the acre, the queue, and the milestone 1b orders.
//!
//! A command submitted while `tick()` is N is queued. `step` and `frame` apply
//! that queue at the start of tick N+1, in submission order, then run one tick
//! of rules. One rejection does not stop the batch. The queue is not saved and
//! is not hashed. A successful `new_game` or load clears it.

use crate::catalog::{
    self, item_known, recipe_known, Catalog, ITEM_BANDAGE, ITEM_GRAIN, ITEM_KNIFE, ITEM_MEAL,
    ITEM_SALVE, ITEM_WATER,
};
use crate::clock::Clock;
use crate::command::{
    BuildingKind, Command, FailureReason, ItemId, JobKind, RecipeId, RegionKind, MALFORMED, QUEUED,
    QUEUE_FULL, STALE,
};
use crate::ids::{EntityAllocator, EntityId, EntityKind};
use crate::path::{self, advance_along};
use crate::rng::SplitMix64;
use crate::rules::{
    dist, night_at, scaled_work_ticks, AMBIENT_WARMTH_DAY, AMBIENT_WARMTH_NIGHT, BESIDE_PEG,
    BLEED_HEALTH_PER_TICK, BUILD_TICKS, CARRY_CAP, COLD_HEALTH_PER_TICK, EAT_HUNGER_RESTORE,
    EAT_THIRST_RESTORE, FATIGUE_PER_TICK, FATIGUE_REFUSAL, FATIGUE_WORK_MULTIPLIER,
    FIBER_REMAINING, GATHER_TICKS_PER_UNIT, GATHER_TOOL_RELIEF, HAUL_TICKS_PER_UNIT,
    HEALTH_PER_TICK, HEALTH_REFUSAL, HEAL_TICKS, HUNGER_PER_TICK, HUNGER_REFUSAL,
    INFECTION_HEALTH_PER_TICK, INFECTION_PER_TICK, INFECTION_SICK, LEANTO_WARMTH,
    MEAL_HUNGER_RESTORE, MEAL_THIRST_RESTORE, MEDICINE_SKILL_MIN, NODE_MIN_APART,
    NODE_MIN_FROM_PEG, OWNER_CAP, PEG_X, PEG_Y, QUEUE_CAP, SALVE_INFECTION_CUT, SKILL_BUILD,
    SKILL_COUNT, SKILL_CRAFT, SKILL_GATHER,
    SKILL_MEDICINE, SKILL_PER_UNIT, SLEEP_RECOVER_PER_TICK, STARTING_GRAIN, STATION_RANGE_M,
    STOCKPILE_CAPACITY, STONE_REMAINING, TAKE_TICKS_PER_UNIT, THIRST_PER_TICK,
    WALK_METERS_PER_TICK, WARMTH_DRIFT_PER_TICK, WARMTH_RANGE_M, WATER_HUNGER_RESTORE,
    WATER_REMAINING, WATER_THIRST_RESTORE, WAYPOINT_REACH_METERS, WOOD_REMAINING,
};
use crate::snapshot::{BuildingView, NodeView, PersonView, RegionView, Rejections, Snapshot};
use serde::{Deserialize, Serialize};

/// Save format this crate writes and will load without a migration.
///
/// Versions 1 and 2 are the earlier milestones. Nothing shipped, so they are
/// refused rather than migrated.
pub const SAVE_VERSION: u32 = 3;

/// One running simulation.
#[derive(Debug, Clone, PartialEq)]
pub struct SimState {
    pub save_version: u32,
    pub seed: u64,
    pub clock: Clock,
    pub rng: SplitMix64,
    alloc: EntityAllocator,
    people: Vec<Person>,
    buildings: Vec<Building>,
    nodes: Vec<Node>,
    queue: Vec<Command>,
    owners: Vec<Owner>,
    next_owner: u32,
    rejections: Rejections,
    paused: bool,
    speed: u8,
    accumulator: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Person {
    id: EntityId,
    x: f32,
    y: f32,
    hunger: f32,
    thirst: f32,
    health: f32,
    drafted: bool,
    carried: Vec<(ItemId, u32)>,
    failure: Option<FailureReason>,
    order: Option<Command>,
    path: Vec<[f32; 2]>,
    dest: Option<[f32; 2]>,
    target: Option<EntityId>,
    gather_ticks: u32,
    fatigue: f32,
    warmth: f32,
    skills: [f32; SKILL_COUNT],
    regions: [Region; 6],
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Building {
    id: EntityId,
    kind: BuildingKind,
    x: f32,
    y: f32,
    progress: u32,
    contents: Vec<(ItemId, u32)>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Node {
    id: EntityId,
    x: f32,
    y: f32,
    remaining: u32,
    yield_item: ItemId,
}

/// One body region. Kind is the index in [`RegionKind`] order, not stored.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Region {
    health: f32,
    bleeding: f32,
    infected: f32,
    bandaged: bool,
    treated: bool,
}

#[derive(Debug, Clone, PartialEq)]
struct Owner {
    id: u32,
    full_pending: bool,
}

impl SimState {
    /// Empty world: tick 0, no entities, RNG stream positioned at `seed`.
    ///
    /// The cast is placed by [`Self::new_game`], not here. A fresh process
    /// starts empty, matching the contract's tick-0 world.
    pub fn new(seed: u64) -> Self {
        Self {
            save_version: SAVE_VERSION,
            seed,
            clock: Clock::new(),
            rng: SplitMix64::new(seed),
            alloc: EntityAllocator::new(),
            people: Vec::new(),
            buildings: Vec::new(),
            nodes: Vec::new(),
            queue: Vec::new(),
            owners: Vec::new(),
            next_owner: 1,
            rejections: Rejections::default(),
            paused: false,
            speed: 1,
            accumulator: 0.0,
        }
    }

    /// Replace the world with the milestone 1a acre for `seed`.
    ///
    /// Clears the queue, keeps owners, and marks every owner for a full snapshot.
    /// Placement reads the sim RNG in a fixed order: three people beside the peg,
    /// then six nodes.
    pub fn new_game(&mut self, seed: u64) {
        let count = self.queue.len();
        eprintln!("queue cleared {count}");
        let owners = std::mem::take(&mut self.owners);
        let next_owner = self.next_owner;
        *self = Self::new(seed);
        self.owners = owners;
        self.next_owner = next_owner;
        self.place_cast();
        self.mark_owners_full();
    }

    pub fn tick(&self) -> u64 {
        self.clock.tick()
    }

    /// Advance exactly one tick. Applies the queue first, then rules. Ignores pause.
    pub fn step(&mut self) {
        self.tick_once();
    }

    /// Play entry. A negative or non-finite delta counts as 0. While paused, the
    /// accumulator does not grow. At most 5 ticks run; leftover above 0.1 after
    /// that cap is dropped.
    pub fn frame(&mut self, delta_seconds: f32) {
        if self.paused {
            return;
        }
        let delta = if delta_seconds.is_finite() && delta_seconds > 0.0 {
            delta_seconds
        } else {
            0.0
        };
        self.accumulator += delta * f32::from(self.speed);
        let mut ran = 0;
        while self.accumulator >= 0.1 && ran < 5 {
            self.tick_once();
            self.accumulator -= 0.1;
            ran += 1;
        }
        if ran == 5 && self.accumulator > 0.1 {
            self.accumulator = 0.1;
        }
    }

    /// Leftover accumulator / 0.1, clamped to 0.0..=1.0. 0 while paused.
    pub fn alpha(&self) -> f32 {
        if self.paused {
            0.0
        } else {
            (self.accumulator / 0.1).clamp(0.0, 1.0)
        }
    }

    pub fn set_paused(&mut self, paused: bool) {
        self.paused = paused;
    }

    pub fn paused(&self) -> bool {
        self.paused
    }

    pub fn speed(&self) -> u8 {
        self.speed
    }

    /// Speed is only 1, 2, or 3. Anything else returns 1, logs, and leaves the
    /// multiplier unchanged. Success returns 0.
    pub fn set_speed(&mut self, speed: i64) -> u8 {
        if matches!(speed, 1 | 2 | 3) {
            self.speed = speed as u8;
            QUEUED
        } else {
            eprintln!("reject malformed speed");
            MALFORMED
        }
    }

    pub fn rejections(&self) -> Rejections {
        self.rejections
    }

    pub fn catalog(&self) -> Catalog {
        catalog::catalog()
    }

    pub fn submit(&mut self, cmd: Command) -> u8 {
        if let Some(code) = self.validate(cmd) {
            self.reject(code, cmd);
            return code;
        }
        if self.queue.len() >= QUEUE_CAP {
            self.reject(QUEUE_FULL, cmd);
            return QUEUE_FULL;
        }
        if cmd.is_work_order() && !is_rest(cmd) {
            if let Some(reason) = self.work_refusal(cmd.actor()) {
                self.refuse_work(cmd.actor(), reason);
                return QUEUED;
            }
        }
        self.clear_failure(cmd.actor());
        self.queue.push(cmd);
        QUEUED
    }

    pub fn submit_move(&mut self, index: u32, generation: u32, x: f32, y: f32) -> u8 {
        self.submit(Command::Move {
            actor: EntityId { index, generation },
            to: [x, y],
        })
    }

    pub fn submit_gather(
        &mut self,
        actor_index: u32,
        actor_generation: u32,
        node_index: u32,
        node_generation: u32,
    ) -> u8 {
        self.submit(Command::Gather {
            actor: EntityId {
                index: actor_index,
                generation: actor_generation,
            },
            node: EntityId {
                index: node_index,
                generation: node_generation,
            },
        })
    }

    pub fn submit_eat(&mut self, index: u32, generation: u32, item: u32) -> u8 {
        self.submit(Command::Eat {
            actor: EntityId { index, generation },
            item: ItemId(item),
        })
    }

    pub fn submit_haul(
        &mut self,
        actor_index: u32,
        actor_generation: u32,
        item: u32,
        to_index: u32,
        to_generation: u32,
    ) -> u8 {
        self.submit(Command::Haul {
            actor: EntityId {
                index: actor_index,
                generation: actor_generation,
            },
            item: ItemId(item),
            to: EntityId {
                index: to_index,
                generation: to_generation,
            },
        })
    }

    pub fn submit_work(&mut self, index: u32, generation: u32, job: u32) -> u8 {
        let Some(job) = JobKind::from_discriminant(job) else {
            self.rejections.malformed += 1;
            eprintln!("reject malformed work");
            return MALFORMED;
        };
        self.submit(Command::Work {
            actor: EntityId { index, generation },
            job,
        })
    }

    pub fn submit_place(
        &mut self,
        index: u32,
        generation: u32,
        building: u32,
        x: f32,
        y: f32,
    ) -> u8 {
        let Some(building) = BuildingKind::from_discriminant(building) else {
            self.rejections.malformed += 1;
            eprintln!("reject malformed place");
            return MALFORMED;
        };
        self.submit(Command::Place {
            actor: EntityId { index, generation },
            building,
            at: [x, y],
        })
    }

    pub fn submit_craft(&mut self, index: u32, generation: u32, recipe: u32) -> u8 {
        self.submit(Command::Craft {
            actor: EntityId { index, generation },
            recipe: RecipeId(recipe),
        })
    }

    pub fn submit_draft(&mut self, index: u32, generation: u32, drafted: bool) -> u8 {
        self.submit(Command::Draft {
            actor: EntityId { index, generation },
            drafted,
        })
    }

    pub fn submit_attack(
        &mut self,
        actor_index: u32,
        actor_generation: u32,
        target_index: u32,
        target_generation: u32,
    ) -> u8 {
        self.submit(Command::Attack {
            actor: EntityId {
                index: actor_index,
                generation: actor_generation,
            },
            target: EntityId {
                index: target_index,
                generation: target_generation,
            },
        })
    }

    /// Queue a take. Same codes as the other submits: 0 queued, 1 malformed,
    /// 2 stale, 3 queue full. An id that does not fit in `u32` is `(0, 0)`,
    /// which is never live. An item id that does not fit is not in the table.
    pub fn submit_take(
        &mut self,
        actor_index: i64,
        actor_gen: i64,
        item_id: i64,
        from_index: i64,
        from_gen: i64,
    ) -> i64 {
        let (actor_index, actor_gen) = narrow_id(actor_index, actor_gen);
        let (from_index, from_gen) = narrow_id(from_index, from_gen);
        let item_id = u32::try_from(item_id).unwrap_or(u32::MAX);
        i64::from(self.submit(Command::Take {
            actor: EntityId {
                index: actor_index,
                generation: actor_gen,
            },
            item: ItemId(item_id),
            from: EntityId {
                index: from_index,
                generation: from_gen,
            },
        }))
    }

    /// Queue a heal. Same codes as the other submits: 0 queued, 1 malformed,
    /// 2 stale, 3 queue full. An id that does not fit in `u32` is `(0, 0)`,
    /// which is never live. An item id that does not fit is not in the table.
    pub fn submit_heal(
        &mut self,
        actor_index: i64,
        actor_gen: i64,
        target_index: i64,
        target_gen: i64,
        item_id: i64,
    ) -> i64 {
        let (actor_index, actor_gen) = narrow_id(actor_index, actor_gen);
        let (target_index, target_gen) = narrow_id(target_index, target_gen);
        let item_id = u32::try_from(item_id).unwrap_or(u32::MAX);
        i64::from(self.submit(Command::Heal {
            actor: EntityId {
                index: actor_index,
                generation: actor_gen,
            },
            target: EntityId {
                index: target_index,
                generation: target_gen,
            },
            item: ItemId(item_id),
        }))
    }

    /// Assign an owner id, starting at 1. The ninth live owner returns 0.
    pub fn attach(&mut self) -> u32 {
        if self.owners.len() >= OWNER_CAP {
            self.rejections.malformed += 1;
            eprintln!("reject malformed attach");
            return 0;
        }
        let id = self.next_owner;
        self.next_owner = self.next_owner.saturating_add(1);
        self.owners.push(Owner {
            id,
            full_pending: true,
        });
        id
    }

    pub fn detach(&mut self, owner: u32) {
        self.owners.retain(|slot| slot.id != owner);
    }

    pub fn detach_all(&mut self) {
        self.owners.clear();
    }

    /// Full copy for `owner`. Unknown owner: error 2, empty arrays, live tick and hash.
    pub fn snapshot(&mut self, owner: u32) -> Snapshot {
        self.pull(owner)
    }

    /// Milestone 1a: every pull is a full snapshot, `full` true, `removed` empty.
    pub fn poll(&mut self, owner: u32) -> Snapshot {
        self.pull(owner)
    }

    /// Full snapshot with no owner. Tests and `state_hash` callers use this.
    pub fn view(&self) -> Snapshot {
        self.full_snapshot()
    }

    pub fn state_hash(&self) -> u64 {
        let mut hash = Fnv64::new();
        hash.write_u32(self.save_version);
        hash.write_u64(self.seed);
        hash.write_u64(self.clock.tick());
        hash.write_u64(self.rng.state());
        hash.write_u64(self.people.len() as u64);
        for person in &self.people {
            hash_person(&mut hash, person);
        }
        hash.write_u64(self.buildings.len() as u64);
        for building in &self.buildings {
            hash_building(&mut hash, building);
        }
        hash.write_u64(self.nodes.len() as u64);
        for node in &self.nodes {
            hash_node(&mut hash, node);
        }
        hash.finish()
    }

    fn tick_once(&mut self) {
        let queued = std::mem::take(&mut self.queue);
        for cmd in queued {
            self.apply_command(cmd);
        }
        self.run_rules();
        self.clock.advance(1);
    }

    fn place_cast(&mut self) {
        let mut available: Vec<usize> = (0..BESIDE_PEG.len()).collect();
        for _ in 0..3 {
            let pick = self.rng.next_in_range(0, available.len() as u64) as usize;
            let idx = available.remove(pick);
            let at = BESIDE_PEG[idx];
            let id = self
                .alloc
                .allocate(EntityKind::Person)
                .expect("acre cast fits in the id space");
            let mut person = Person::new(id, at[0], at[1]);
            // The Harth kit's ration. Milestone 1a has no food in the world, so
            // this is what makes `Eat` reachable at all.
            add_carried(&mut person.carried, ITEM_GRAIN, STARTING_GRAIN);
            self.people.push(person);
        }
        let plan = [
            (ITEM_WOOD_YIELD, WOOD_REMAINING),
            (ITEM_WOOD_YIELD, WOOD_REMAINING),
            (ITEM_STONE_YIELD, STONE_REMAINING),
            (ITEM_STONE_YIELD, STONE_REMAINING),
            (ITEM_FIBER_YIELD, FIBER_REMAINING),
            (ITEM_WATER_YIELD, WATER_REMAINING),
        ];
        let mut placed: Vec<[f32; 2]> = Vec::new();
        for (yield_item, remaining) in plan {
            let (cx, cy) = self.pick_node_cell(&placed);
            let pos = [cx as f32 + 0.5, cy as f32 + 0.5];
            placed.push(pos);
            let id = self
                .alloc
                .allocate(EntityKind::Node)
                .expect("acre nodes fit in the id space");
            self.nodes.push(Node {
                id,
                x: pos[0],
                y: pos[1],
                remaining,
                yield_item,
            });
        }
    }

    fn pick_node_cell(&mut self, placed: &[[f32; 2]]) -> (i32, i32) {
        for _ in 0..2048 {
            let x = self.rng.next_in_range(0, 32) as i32;
            let y = self.rng.next_in_range(0, 32) as i32;
            if node_cell_ok(x, y, placed) {
                return (x, y);
            }
        }
        for y in 0..32 {
            for x in 0..32 {
                if node_cell_ok(x, y, placed) {
                    return (x, y);
                }
            }
        }
        (0, 0)
    }

    fn validate(&self, cmd: Command) -> Option<u8> {
        if !coords_finite(cmd) {
            return Some(MALFORMED);
        }
        if !items_known(cmd) {
            return Some(MALFORMED);
        }
        let ids = referenced_ids(cmd);
        if ids.iter().any(|id| !self.alloc.is_live(*id)) {
            return Some(STALE);
        }
        if !kinds_match(self, cmd) {
            return Some(MALFORMED);
        }
        None
    }

    fn reject(&mut self, code: u8, cmd: Command) {
        match code {
            MALFORMED => {
                self.rejections.malformed += 1;
                eprintln!("reject malformed {}", cmd.variant_name());
            }
            STALE => {
                self.rejections.stale += 1;
                eprintln!("reject stale {}", cmd.variant_name());
            }
            QUEUE_FULL => {
                self.rejections.queue_full += 1;
                eprintln!("reject queue_full {}", cmd.variant_name());
            }
            _ => {}
        }
    }

    fn work_refusal(&self, actor: EntityId) -> Option<FailureReason> {
        let person = self.people.iter().find(|p| p.id == actor)?;
        if person.hunger < HUNGER_REFUSAL {
            return Some(FailureReason::Hungry);
        }
        if night_at(self.clock.tick()) {
            return Some(FailureReason::Night);
        }
        if person.health < HEALTH_REFUSAL || person.sick() {
            return Some(FailureReason::Wounded);
        }
        if person.fatigue > FATIGUE_REFUSAL {
            return Some(FailureReason::Tired);
        }
        None
    }

    fn refuse_work(&mut self, actor: EntityId, reason: FailureReason) {
        let Some(person) = self.people.iter_mut().find(|p| p.id == actor) else {
            return;
        };
        person.order = None;
        person.path.clear();
        person.dest = None;
        person.target = None;
        person.gather_ticks = 0;
        person.failure = Some(reason);
    }

    fn clear_failure(&mut self, actor: EntityId) {
        if let Some(person) = self.people.iter_mut().find(|p| p.id == actor) {
            person.failure = None;
        }
    }

    fn apply_command(&mut self, cmd: Command) {
        if let Some(code) = self.validate(cmd) {
            self.reject(code, cmd);
            return;
        }
        let actor = cmd.actor();
        let Some(pi) = self.people.iter().position(|p| p.id == actor) else {
            self.reject(MALFORMED, cmd);
            return;
        };
        match cmd {
            Command::Move { to, .. } => {
                let from = [self.people[pi].x, self.people[pi].y];
                let path = path::path_to(from, to).unwrap_or_default();
                let person = &mut self.people[pi];
                person.order = Some(cmd);
                person.path = path;
                person.dest = Some(to);
                person.target = None;
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Gather { node, .. } => {
                let from = [self.people[pi].x, self.people[pi].y];
                let dest = self.nodes.iter().find(|n| n.id == node).map(|n| [n.x, n.y]);
                let path = dest
                    .and_then(|to| path::path_to(from, to))
                    .unwrap_or_default();
                let person = &mut self.people[pi];
                person.order = Some(cmd);
                person.path = path;
                person.dest = dest;
                person.target = Some(node);
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Eat { .. } => {
                let person = &mut self.people[pi];
                person.order = Some(cmd);
                person.path.clear();
                person.dest = None;
                person.target = None;
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Haul { to, .. } => self.begin_walk_order(pi, cmd, to),
            Command::Work { .. } => {
                let person = &mut self.people[pi];
                person.order = Some(cmd);
                person.path.clear();
                person.dest = None;
                person.target = None;
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Place { building, at, .. } => {
                if let Some(reason) = self.place_refusal(pi, at) {
                    fail(&mut self.people[pi], reason);
                    return;
                }
                let id = self
                    .alloc
                    .allocate(EntityKind::Building)
                    .expect("a place fits in the id space");
                self.buildings.push(Building {
                    id,
                    kind: building,
                    x: at[0],
                    y: at[1],
                    progress: 0,
                    contents: Vec::new(),
                });
                let from = [self.people[pi].x, self.people[pi].y];
                let path = path::path_to(from, at).unwrap_or_default();
                let person = &mut self.people[pi];
                person.order = Some(cmd);
                person.path = path;
                person.dest = Some(at);
                person.target = Some(id);
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Craft { .. } => {
                let person = &mut self.people[pi];
                person.order = Some(cmd);
                person.path.clear();
                person.dest = None;
                person.target = None;
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Draft { drafted, .. } => {
                let person = &mut self.people[pi];
                person.drafted = drafted;
                person.order = Some(cmd);
                person.path.clear();
                person.dest = None;
                person.target = None;
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Attack { target, .. } => {
                let person = &mut self.people[pi];
                person.order = Some(cmd);
                person.path.clear();
                person.dest = None;
                person.target = Some(target);
                person.gather_ticks = 0;
                person.failure = None;
            }
            Command::Take { from, .. } => self.begin_walk_order(pi, cmd, from),
            Command::Heal { target, .. } => self.begin_heal(pi, cmd, target),
        }
    }

    /// Walk to a building, then the rules move goods. Haul and Take share this.
    fn begin_walk_order(&mut self, pi: usize, cmd: Command, target: EntityId) {
        let from = [self.people[pi].x, self.people[pi].y];
        let dest = self
            .buildings
            .iter()
            .find(|b| b.id == target)
            .map(|b| [b.x, b.y]);
        let path = dest
            .and_then(|to| path::path_to(from, to))
            .unwrap_or_default();
        let person = &mut self.people[pi];
        person.order = Some(cmd);
        person.path = path;
        person.dest = dest;
        person.target = Some(target);
        person.gather_ticks = 0;
        person.failure = None;
    }

    /// Walk to the patient. A self-heal is already in range.
    fn begin_heal(&mut self, pi: usize, cmd: Command, target: EntityId) {
        let from = [self.people[pi].x, self.people[pi].y];
        let dest = self
            .people
            .iter()
            .find(|person| person.id == target)
            .map(|person| person.pos());
        let path = dest
            .and_then(|to| path::path_to(from, to))
            .unwrap_or_default();
        let person = &mut self.people[pi];
        person.order = Some(cmd);
        person.path = path;
        person.dest = dest;
        person.target = Some(target);
        person.gather_ticks = 0;
        person.failure = None;
    }

    /// A place that cannot become a building. Outside the acre is unreachable.
    /// The peg's cell and a cell that already holds a building are not build
    /// sites; the contract's only placement failure string is `no path`.
    fn place_refusal(&self, pi: usize, at: [f32; 2]) -> Option<FailureReason> {
        let Some(cell) = path::cell_of(at[0], at[1]) else {
            return Some(FailureReason::NoPath);
        };
        if cell == (PEG_X as i32, PEG_Y as i32) {
            return Some(FailureReason::NoPath);
        }
        if self
            .buildings
            .iter()
            .any(|building| path::cell_of(building.x, building.y) == Some(cell))
        {
            return Some(FailureReason::NoPath);
        }
        let from = [self.people[pi].x, self.people[pi].y];
        if path::path_to(from, at).is_none() {
            return Some(FailureReason::NoPath);
        }
        None
    }

    fn run_rules(&mut self) {
        let count = self.people.len();
        for i in 0..count {
            self.tick_body(i);
        }
        for i in 0..count {
            self.tick_order(i);
        }
    }

    fn tick_order(&mut self, index: usize) {
        let Some(order) = self.people[index].order else {
            return;
        };
        match order {
            Command::Move { to, .. } => self.tick_move(index, to),
            Command::Gather { node, .. } => self.tick_gather(index, node),
            Command::Eat { item, .. } => self.tick_eat(index, item),
            Command::Place { .. } => self.tick_place(index),
            Command::Haul { item, to, .. } => self.tick_haul(index, item, to),
            Command::Take { item, from, .. } => self.tick_take(index, item, from),
            Command::Craft { recipe, .. } => self.tick_craft(index, recipe),
            Command::Heal { target, item, .. } => self.tick_heal(index, target, item),
            Command::Work { job, .. } if job == JobKind::Rest => self.tick_rest(index),
            Command::Work { .. } | Command::Draft { .. } | Command::Attack { .. } => {}
        }
    }

    fn tick_move(&mut self, index: usize, to: [f32; 2]) {
        let person = &mut self.people[index];
        if person.path.is_empty() {
            if dist(person.pos(), to) <= WAYPOINT_REACH_METERS {
                complete(person);
            } else {
                fail(person, FailureReason::NoPath);
            }
            return;
        }
        let mut pos = person.pos();
        advance_along(&mut pos, &mut person.path, WALK_METERS_PER_TICK);
        person.x = pos[0];
        person.y = pos[1];
        if person.path.is_empty() && dist(person.pos(), to) <= WAYPOINT_REACH_METERS {
            complete(person);
        }
    }

    fn tick_gather(&mut self, index: usize, node_id: EntityId) {
        let Some(node_pos) = self
            .nodes
            .iter()
            .find(|n| n.id == node_id)
            .map(|n| [n.x, n.y])
        else {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        };
        if !self.people[index].path.is_empty() {
            let person = &mut self.people[index];
            let mut pos = person.pos();
            advance_along(&mut pos, &mut person.path, WALK_METERS_PER_TICK);
            person.x = pos[0];
            person.y = pos[1];
            return;
        }
        if dist(self.people[index].pos(), node_pos) > WAYPOINT_REACH_METERS {
            fail(&mut self.people[index], FailureReason::NoPath);
            return;
        }
        let needed = scaled_work_ticks(
            GATHER_TICKS_PER_UNIT,
            self.people[index].skills[SKILL_GATHER],
            self.gather_tool_relief(index),
        );
        self.people[index].gather_ticks += 1;
        if self.people[index].gather_ticks < needed {
            return;
        }
        self.people[index].gather_ticks = 0;
        let carried = total_carried(&self.people[index].carried);
        let Some(node_i) = self.nodes.iter().position(|n| n.id == node_id) else {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        };
        if self.nodes[node_i].remaining == 0 {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        }
        if carried >= CARRY_CAP {
            complete(&mut self.people[index]);
            return;
        }
        let yield_item = self.nodes[node_i].yield_item;
        self.nodes[node_i].remaining -= 1;
        let drained = self.nodes[node_i].remaining == 0;
        add_carried(&mut self.people[index].carried, yield_item, 1);
        raise_skill(&mut self.people[index], SKILL_GATHER);
        if drained {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        }
        if total_carried(&self.people[index].carried) >= CARRY_CAP {
            complete(&mut self.people[index]);
        }
    }

    fn tick_eat(&mut self, index: usize, item: ItemId) {
        let Some((hunger, thirst)) = eat_restore(item) else {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        };
        if count_of(&self.people[index].carried, item) == 0 {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        }
        let person = &mut self.people[index];
        take_carried(&mut person.carried, item, 1);
        person.hunger = (person.hunger + hunger).min(1.0);
        person.thirst = (person.thirst + thirst).min(1.0);
        complete(person);
    }

    fn tick_place(&mut self, index: usize) {
        let Some(target) = self.people[index].target else {
            fail(&mut self.people[index], FailureReason::NoPath);
            return;
        };
        let Some(bi) = self.buildings.iter().position(|b| b.id == target) else {
            fail(&mut self.people[index], FailureReason::NoPath);
            return;
        };
        if self.buildings[bi].progress >= BUILD_TICKS {
            complete(&mut self.people[index]);
            return;
        }
        let site = [self.buildings[bi].x, self.buildings[bi].y];
        if dist(self.people[index].pos(), site) > STATION_RANGE_M {
            if self.people[index].path.is_empty() {
                fail(&mut self.people[index], FailureReason::NoPath);
                return;
            }
            let person = &mut self.people[index];
            let mut pos = person.pos();
            advance_along(&mut pos, &mut person.path, WALK_METERS_PER_TICK);
            person.x = pos[0];
            person.y = pos[1];
            if dist(person.pos(), site) > STATION_RANGE_M {
                return;
            }
            person.path.clear();
        }
        let needed = scaled_work_ticks(BUILD_TICKS, self.people[index].skills[SKILL_BUILD], 0.0);
        self.people[index].gather_ticks += 1;
        let worked = self.people[index].gather_ticks;
        let progress = (worked.saturating_mul(BUILD_TICKS) / needed).min(BUILD_TICKS);
        self.buildings[bi].progress = progress;
        if worked >= needed {
            self.buildings[bi].progress = BUILD_TICKS;
            raise_skill(&mut self.people[index], SKILL_BUILD);
            complete(&mut self.people[index]);
        }
    }

    fn tick_haul(&mut self, index: usize, item: ItemId, to: EntityId) {
        if count_of(&self.people[index].carried, item) == 0 {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        }
        let Some(bi) = self.stockpile_index(to) else {
            fail(&mut self.people[index], FailureReason::NoStation);
            return;
        };
        if total_carried(&self.buildings[bi].contents) >= STOCKPILE_CAPACITY {
            complete(&mut self.people[index]);
            return;
        }
        if !self.arrived(index, bi) {
            return;
        }
        self.people[index].gather_ticks += 1;
        if self.people[index].gather_ticks < HAUL_TICKS_PER_UNIT {
            return;
        }
        self.people[index].gather_ticks = 0;
        take_carried(&mut self.people[index].carried, item, 1);
        add_carried(&mut self.buildings[bi].contents, item, 1);
        let emptied = count_of(&self.people[index].carried, item) == 0;
        let full = total_carried(&self.buildings[bi].contents) >= STOCKPILE_CAPACITY;
        if emptied || full {
            complete(&mut self.people[index]);
        }
    }

    fn tick_take(&mut self, index: usize, item: ItemId, from: EntityId) {
        let Some(bi) = self.stockpile_index(from) else {
            fail(&mut self.people[index], FailureReason::NoStation);
            return;
        };
        if count_of(&self.buildings[bi].contents, item) == 0 {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        }
        if total_carried(&self.people[index].carried) >= CARRY_CAP {
            complete(&mut self.people[index]);
            return;
        }
        if !self.arrived(index, bi) {
            return;
        }
        self.people[index].gather_ticks += 1;
        if self.people[index].gather_ticks < TAKE_TICKS_PER_UNIT {
            return;
        }
        self.people[index].gather_ticks = 0;
        take_carried(&mut self.buildings[bi].contents, item, 1);
        add_carried(&mut self.people[index].carried, item, 1);
        let emptied = count_of(&self.buildings[bi].contents, item) == 0;
        let capped = total_carried(&self.people[index].carried) >= CARRY_CAP;
        if emptied || capped {
            complete(&mut self.people[index]);
        }
    }

    fn tick_craft(&mut self, index: usize, recipe_id: RecipeId) {
        let Some(recipe) = catalog::recipe_def(recipe_id) else {
            fail(&mut self.people[index], FailureReason::NoMaterial);
            return;
        };
        if self.people[index].gather_ticks == 0 {
            if let Some(reason) = self.craft_block(index, recipe) {
                fail(&mut self.people[index], reason);
                return;
            }
        }
        let needed = scaled_work_ticks(recipe.ticks, self.people[index].skills[SKILL_CRAFT], 0.0);
        self.people[index].gather_ticks += 1;
        if self.people[index].gather_ticks < needed {
            return;
        }
        for (item, count) in recipe.inputs {
            take_carried(&mut self.people[index].carried, *item, *count);
        }
        add_carried(&mut self.people[index].carried, recipe.output, 1);
        raise_skill(&mut self.people[index], SKILL_CRAFT);
        complete(&mut self.people[index]);
    }

    /// Earliest failure wins: a missing input or tool is `no material`, and only
    /// then does a missing station report `no station`.
    fn craft_block(&self, index: usize, recipe: &catalog::RecipeDef) -> Option<FailureReason> {
        let carried = &self.people[index].carried;
        let missing_input = recipe
            .inputs
            .iter()
            .any(|(item, count)| count_of(carried, *item) < *count);
        let missing_tool = recipe.tool.is_some_and(|tool| count_of(carried, tool) == 0);
        if missing_input || missing_tool {
            return Some(FailureReason::NoMaterial);
        }
        if recipe
            .medicine_min
            .is_some_and(|min| self.people[index].skills[SKILL_MEDICINE] < min)
        {
            return Some(FailureReason::NoSkill);
        }
        if recipe
            .station
            .is_some_and(|kind| !self.station_ready(index, kind))
        {
            return Some(FailureReason::NoStation);
        }
        None
    }

    fn station_ready(&self, index: usize, kind: BuildingKind) -> bool {
        let pos = self.people[index].pos();
        self.buildings.iter().any(|building| {
            building.kind == kind
                && building.progress >= BUILD_TICKS
                && dist(pos, [building.x, building.y]) <= STATION_RANGE_M
        })
    }

    /// A finished stockpile. An unfinished one does not hold goods.
    fn stockpile_index(&self, id: EntityId) -> Option<usize> {
        self.buildings.iter().position(|building| {
            building.id == id
                && building.kind == BuildingKind::Stockpile
                && building.progress >= BUILD_TICKS
        })
    }

    fn tick_body(&mut self, index: usize) {
        decay_needs(&mut self.people[index]);
        tick_wounds(&mut self.people[index]);
        self.tick_warmth(index);
        self.tick_fatigue_gain(index);
    }

    fn tick_warmth(&mut self, index: usize) {
        let pos = self.people[index].pos();
        let by_fire = self.near_finished(pos, BuildingKind::Campfire, WARMTH_RANGE_M);
        let target = if by_fire {
            1.0
        } else if night_at(self.clock.tick()) {
            if self.near_finished(pos, BuildingKind::LeanTo, STATION_RANGE_M) {
                LEANTO_WARMTH
            } else {
                AMBIENT_WARMTH_NIGHT
            }
        } else {
            AMBIENT_WARMTH_DAY
        };
        let person = &mut self.people[index];
        if person.warmth <= 0.0 {
            person.health = (person.health - COLD_HEALTH_PER_TICK).max(0.0);
        }
        let delta = target - person.warmth;
        if delta.abs() <= WARMTH_DRIFT_PER_TICK {
            person.warmth = target;
        } else if delta > 0.0 {
            person.warmth += WARMTH_DRIFT_PER_TICK;
        } else {
            // Drifting down never passes the target, so an open night lands on 0.0.
            person.warmth = (person.warmth - WARMTH_DRIFT_PER_TICK).max(target);
        }
        person.warmth = person.warmth.clamp(0.0, 1.0);
    }

    fn tick_fatigue_gain(&mut self, index: usize) {
        let order = self.people[index].order;
        if matches!(
            order,
            Some(Command::Work {
                job: JobKind::Rest,
                ..
            })
        ) {
            return;
        }
        let gain = if fatigue_working(order) {
            FATIGUE_PER_TICK * FATIGUE_WORK_MULTIPLIER
        } else {
            FATIGUE_PER_TICK
        };
        self.people[index].fatigue = (self.people[index].fatigue + gain).min(1.0);
    }

    fn gather_tool_relief(&self, index: usize) -> f32 {
        if count_of(&self.people[index].carried, ITEM_KNIFE) > 0 {
            GATHER_TOOL_RELIEF
        } else {
            0.0
        }
    }

    fn near_finished(&self, pos: [f32; 2], kind: BuildingKind, range: f32) -> bool {
        self.buildings.iter().any(|building| {
            building.kind == kind
                && building.progress >= BUILD_TICKS
                && dist(pos, [building.x, building.y]) <= range
        })
    }

    fn tick_rest(&mut self, index: usize) {
        let pos = self.people[index].pos();
        let sheltered = self.near_finished(pos, BuildingKind::LeanTo, STATION_RANGE_M);
        let rate = if sheltered {
            SLEEP_RECOVER_PER_TICK * 2.0
        } else {
            SLEEP_RECOVER_PER_TICK
        };
        let person = &mut self.people[index];
        person.fatigue = (person.fatigue - rate).max(0.0);
        if person.fatigue == 0.0 {
            complete(person);
        }
    }

    /// Fail before walking when the item, the wound, or the skill cannot treat.
    /// NoMaterial is earlier than NoSkill, so a useless item wins over a missing skill.
    fn heal_block(&self, index: usize, target: EntityId, item: ItemId) -> Option<FailureReason> {
        if item != ITEM_BANDAGE && item != ITEM_SALVE {
            return Some(FailureReason::NoMaterial);
        }
        if count_of(&self.people[index].carried, item) == 0 {
            return Some(FailureReason::NoMaterial);
        }
        let medicine = self.people[index].skills[SKILL_MEDICINE];
        let Some(patient) = self.people.iter().find(|person| person.id == target) else {
            return Some(FailureReason::NoPath);
        };
        if item == ITEM_BANDAGE && worst_bleeding(&patient.regions).is_none() {
            return Some(FailureReason::NoMaterial);
        }
        if item == ITEM_SALVE && worst_infected(&patient.regions).is_none() {
            return Some(FailureReason::NoMaterial);
        }
        if item == ITEM_SALVE && medicine < MEDICINE_SKILL_MIN {
            return Some(FailureReason::NoSkill);
        }
        None
    }

    fn tick_heal(&mut self, index: usize, target: EntityId, item: ItemId) {
        if self.people[index].gather_ticks == 0 {
            if let Some(reason) = self.heal_block(index, target, item) {
                fail(&mut self.people[index], reason);
                return;
            }
        }
        let Some(target_pos) = self
            .people
            .iter()
            .find(|person| person.id == target)
            .map(|person| person.pos())
        else {
            fail(&mut self.people[index], FailureReason::NoPath);
            return;
        };
        if dist(self.people[index].pos(), target_pos) > STATION_RANGE_M {
            if self.people[index].path.is_empty() {
                fail(&mut self.people[index], FailureReason::NoPath);
                return;
            }
            let person = &mut self.people[index];
            let mut pos = person.pos();
            advance_along(&mut pos, &mut person.path, WALK_METERS_PER_TICK);
            person.x = pos[0];
            person.y = pos[1];
            if dist(person.pos(), target_pos) > STATION_RANGE_M {
                return;
            }
            person.path.clear();
        }
        let needed = scaled_work_ticks(HEAL_TICKS, self.people[index].skills[SKILL_MEDICINE], 0.0);
        self.people[index].gather_ticks += 1;
        if self.people[index].gather_ticks < needed {
            return;
        }
        if let Some(reason) = self.heal_block(index, target, item) {
            fail(&mut self.people[index], reason);
            return;
        }
        take_carried(&mut self.people[index].carried, item, 1);
        if let Some(patient) = self.people.iter_mut().find(|person| person.id == target) {
            apply_treatment(patient, item);
        }
        raise_skill(&mut self.people[index], SKILL_MEDICINE);
        complete(&mut self.people[index]);
    }

    /// Walk toward building `bi`. `true` once stood on it.
    fn arrived(&mut self, index: usize, bi: usize) -> bool {
        let dest = [self.buildings[bi].x, self.buildings[bi].y];
        if !self.people[index].path.is_empty() {
            let person = &mut self.people[index];
            let mut pos = person.pos();
            advance_along(&mut pos, &mut person.path, WALK_METERS_PER_TICK);
            person.x = pos[0];
            person.y = pos[1];
            return false;
        }
        if dist(self.people[index].pos(), dest) > WAYPOINT_REACH_METERS {
            fail(&mut self.people[index], FailureReason::NoPath);
            return false;
        }
        true
    }

    fn pull(&mut self, owner: u32) -> Snapshot {
        let Some(slot) = self.owners.iter_mut().find(|slot| slot.id == owner) else {
            return self.error_snapshot(2);
        };
        slot.full_pending = false;
        self.full_snapshot()
    }

    fn full_snapshot(&self) -> Snapshot {
        Snapshot {
            tick: self.tick(),
            people: self.people.iter().map(person_view).collect(),
            buildings: self.buildings.iter().map(building_view).collect(),
            nodes: self.nodes.iter().map(node_view).collect(),
            removed: Vec::new(),
            hash: self.state_hash(),
            full: true,
            error: 0,
        }
    }

    fn error_snapshot(&self, error: i32) -> Snapshot {
        Snapshot {
            tick: self.tick(),
            people: Vec::new(),
            buildings: Vec::new(),
            nodes: Vec::new(),
            removed: Vec::new(),
            hash: self.state_hash(),
            full: false,
            error,
        }
    }

    fn mark_owners_full(&mut self) {
        for owner in &mut self.owners {
            owner.full_pending = true;
        }
    }

    pub(crate) fn install_loaded(&mut self, loaded: LoadedWorld) {
        let count = self.queue.len();
        eprintln!("queue cleared {count}");
        self.save_version = loaded.save_version;
        self.seed = loaded.seed;
        self.clock = Clock::from_tick(loaded.tick);
        self.rng = SplitMix64::from_state(loaded.rng);
        self.alloc = loaded.alloc;
        self.people = loaded.people;
        self.buildings = loaded.buildings;
        self.nodes = loaded.nodes;
        self.queue.clear();
        self.mark_owners_full();
    }

    pub(crate) fn to_saved(&self) -> SavedWorld {
        let mut slots = Vec::new();
        for index in 0..self.alloc.slot_count() {
            let view = self.alloc.slot_at(index).expect("index is in range");
            slots.push(SavedSlot::from_world(view, self));
        }
        SavedWorld {
            save_version: self.save_version,
            seed: self.seed,
            tick: self.clock.tick(),
            rng: self.rng.state(),
            slots,
            free: self.alloc.free_list().to_vec(),
        }
    }
}

const ITEM_WOOD_YIELD: ItemId = catalog::ITEM_WOOD;
const ITEM_STONE_YIELD: ItemId = catalog::ITEM_STONE;
const ITEM_FIBER_YIELD: ItemId = catalog::ITEM_FIBER;
const ITEM_WATER_YIELD: ItemId = catalog::ITEM_WATER;

fn eat_restore(item: ItemId) -> Option<(f32, f32)> {
    if item == ITEM_GRAIN {
        Some((EAT_HUNGER_RESTORE, EAT_THIRST_RESTORE))
    } else if item == ITEM_MEAL {
        Some((MEAL_HUNGER_RESTORE, MEAL_THIRST_RESTORE))
    } else if item == ITEM_WATER {
        Some((WATER_HUNGER_RESTORE, WATER_THIRST_RESTORE))
    } else {
        None
    }
}

/// An id that does not fit in `u32` cannot be live. `(0, 0)` is always stale.
fn narrow_id(index: i64, generation: i64) -> (u32, u32) {
    match (u32::try_from(index), u32::try_from(generation)) {
        (Ok(index), Ok(generation)) => (index, generation),
        _ => (0, 0),
    }
}

fn node_cell_ok(x: i32, y: i32, placed: &[[f32; 2]]) -> bool {
    let pos = [x as f32 + 0.5, y as f32 + 0.5];
    if dist(pos, [PEG_X, PEG_Y]) < NODE_MIN_FROM_PEG {
        return false;
    }
    placed
        .iter()
        .all(|other| dist(pos, *other) >= NODE_MIN_APART)
}

fn coords_finite(cmd: Command) -> bool {
    match cmd {
        Command::Move { to, .. } => to[0].is_finite() && to[1].is_finite(),
        Command::Place { at, .. } => at[0].is_finite() && at[1].is_finite(),
        _ => true,
    }
}

fn items_known(cmd: Command) -> bool {
    match cmd {
        Command::Eat { item, .. }
        | Command::Haul { item, .. }
        | Command::Take { item, .. }
        | Command::Heal { item, .. } => item_known(item),
        Command::Craft { recipe, .. } => recipe_known(recipe),
        _ => true,
    }
}

fn referenced_ids(cmd: Command) -> Vec<EntityId> {
    match cmd {
        Command::Move { actor, .. }
        | Command::Eat { actor, .. }
        | Command::Work { actor, .. }
        | Command::Place { actor, .. }
        | Command::Craft { actor, .. }
        | Command::Draft { actor, .. } => vec![actor],
        Command::Gather { actor, node } => vec![actor, node],
        Command::Haul { actor, to, .. } => vec![actor, to],
        Command::Take { actor, from, .. } => vec![actor, from],
        Command::Attack { actor, target } | Command::Heal { actor, target, .. } => {
            vec![actor, target]
        }
    }
}

fn kinds_match(sim: &SimState, cmd: Command) -> bool {
    let actor_ok = sim.alloc.kind(cmd.actor()) == Some(EntityKind::Person);
    if !actor_ok {
        return false;
    }
    match cmd {
        Command::Gather { node, .. } => sim.alloc.kind(node) == Some(EntityKind::Node),
        Command::Haul { to, .. } => is_stockpile(sim, to),
        Command::Take { from, .. } => is_stockpile(sim, from),
        Command::Attack { target, .. } => sim.alloc.is_live(target),
        Command::Heal { target, .. } => sim.alloc.kind(target) == Some(EntityKind::Person),
        _ => true,
    }
}

fn is_stockpile(sim: &SimState, id: EntityId) -> bool {
    sim.buildings
        .iter()
        .any(|building| building.id == id && building.kind == BuildingKind::Stockpile)
}

fn decay_needs(person: &mut Person) {
    person.hunger = (person.hunger - HUNGER_PER_TICK).max(0.0);
    person.thirst = (person.thirst - THIRST_PER_TICK).max(0.0);
    if person.hunger == 0.0 || person.thirst == 0.0 {
        person.health = (person.health - HEALTH_PER_TICK).max(0.0);
    }
}

fn tick_wounds(person: &mut Person) {
    let bleed: f32 = person.regions.iter().map(|region| region.bleeding).sum();
    if bleed > 0.0 {
        person.health = (person.health - BLEED_HEALTH_PER_TICK * bleed).max(0.0);
    }
    for region in &mut person.regions {
        if !region.is_wound() {
            continue;
        }
        let mut rate = INFECTION_PER_TICK;
        if region.bandaged {
            rate *= 0.1;
        }
        if region.treated {
            rate *= 0.5;
        }
        region.infected = (region.infected + rate).min(1.0);
    }
    if person.sick() {
        person.health = (person.health - INFECTION_HEALTH_PER_TICK).max(0.0);
    }
}

fn is_rest(cmd: Command) -> bool {
    matches!(
        cmd,
        Command::Work {
            job: JobKind::Rest,
            ..
        }
    )
}

/// Walking or doing a job that has a rule. Rest recovers instead. Eat, Draft,
/// Attack, and an inert `Work` kind are idle: they are not the labour the
/// fatigue multiplier names.
fn fatigue_working(order: Option<Command>) -> bool {
    matches!(
        order,
        Some(
            Command::Move { .. }
                | Command::Gather { .. }
                | Command::Haul { .. }
                | Command::Place { .. }
                | Command::Craft { .. }
                | Command::Take { .. }
                | Command::Heal { .. }
        )
    )
}

fn raise_skill(person: &mut Person, skill: usize) {
    person.skills[skill] = (person.skills[skill] + SKILL_PER_UNIT).min(1.0);
}

/// Highest bleeding above zero. A tie keeps the earlier region.
fn worst_bleeding(regions: &[Region]) -> Option<usize> {
    let mut best: Option<(usize, f32)> = None;
    for (index, region) in regions.iter().enumerate() {
        if region.bleeding <= 0.0 {
            continue;
        }
        match best {
            Some((_, bleeding)) if region.bleeding <= bleeding => {}
            _ => best = Some((index, region.bleeding)),
        }
    }
    best.map(|(index, _)| index)
}

/// Highest infection above zero. A tie keeps the earlier region.
fn worst_infected(regions: &[Region]) -> Option<usize> {
    let mut best: Option<(usize, f32)> = None;
    for (index, region) in regions.iter().enumerate() {
        if region.infected <= 0.0 {
            continue;
        }
        match best {
            Some((_, infected)) if region.infected <= infected => {}
            _ => best = Some((index, region.infected)),
        }
    }
    best.map(|(index, _)| index)
}

fn apply_treatment(person: &mut Person, item: ItemId) {
    if item == ITEM_BANDAGE {
        if let Some(index) = worst_bleeding(&person.regions) {
            person.regions[index].bandaged = true;
            person.regions[index].bleeding = 0.0;
        }
    } else if item == ITEM_SALVE {
        if let Some(index) = worst_infected(&person.regions) {
            person.regions[index].infected =
                (person.regions[index].infected - SALVE_INFECTION_CUT).max(0.0);
            person.regions[index].treated = true;
        }
    }
}

fn complete(person: &mut Person) {
    person.order = None;
    person.path.clear();
    person.dest = None;
    person.target = None;
    person.gather_ticks = 0;
}

fn fail(person: &mut Person, reason: FailureReason) {
    person.failure = Some(reason);
    complete(person);
}

fn total_carried(carried: &[(ItemId, u32)]) -> u32 {
    carried.iter().map(|(_, count)| *count).sum()
}

fn count_of(carried: &[(ItemId, u32)], item: ItemId) -> u32 {
    carried
        .iter()
        .find(|(id, _)| *id == item)
        .map(|(_, count)| *count)
        .unwrap_or(0)
}

fn add_carried(carried: &mut Vec<(ItemId, u32)>, item: ItemId, n: u32) {
    if n == 0 {
        return;
    }
    if let Some((_, count)) = carried.iter_mut().find(|(id, _)| *id == item) {
        *count += n;
        return;
    }
    let pos = carried
        .iter()
        .position(|(id, _)| id.0 > item.0)
        .unwrap_or(carried.len());
    carried.insert(pos, (item, n));
}

fn take_carried(carried: &mut Vec<(ItemId, u32)>, item: ItemId, n: u32) -> bool {
    let Some(pos) = carried.iter().position(|(id, _)| *id == item) else {
        return false;
    };
    if carried[pos].1 < n {
        return false;
    }
    carried[pos].1 -= n;
    if carried[pos].1 == 0 {
        carried.remove(pos);
    }
    true
}

impl Person {
    fn new(id: EntityId, x: f32, y: f32) -> Self {
        Self {
            id,
            x,
            y,
            hunger: 1.0,
            thirst: 1.0,
            health: 1.0,
            drafted: false,
            carried: Vec::new(),
            failure: None,
            order: None,
            path: Vec::new(),
            dest: None,
            target: None,
            gather_ticks: 0,
            fatigue: 0.0,
            warmth: 1.0,
            skills: [0.0; SKILL_COUNT],
            regions: std::array::from_fn(|_| Region::healthy()),
        }
    }

    fn pos(&self) -> [f32; 2] {
        [self.x, self.y]
    }

    fn sick(&self) -> bool {
        self.regions
            .iter()
            .any(|region| region.infected >= INFECTION_SICK)
    }
}

impl Region {
    fn healthy() -> Self {
        Self {
            health: 1.0,
            bleeding: 0.0,
            infected: 0.0,
            bandaged: false,
            treated: false,
        }
    }

    /// A hurt region keeps accumulating infection. A fresh region does not.
    fn is_wound(&self) -> bool {
        self.bleeding > 0.0
            || self.infected > 0.0
            || self.bandaged
            || self.treated
            || self.health < 1.0
    }
}

fn person_view(person: &Person) -> PersonView {
    let job = match person.order {
        Some(Command::Work { job, .. }) => job.discriminant(),
        Some(Command::Place { .. }) => JobKind::Build.discriminant(),
        _ => -1,
    };
    let (failure, failure_text) = match person.failure {
        Some(reason) => (reason.discriminant(), reason.as_str().to_string()),
        None => (-1, String::new()),
    };
    let mut path = Vec::with_capacity(person.path.len() * 2);
    for point in &person.path {
        path.push(point[0]);
        path.push(point[1]);
    }
    let dest = match person.dest {
        Some(point) => vec![point[0], point[1]],
        None => Vec::new(),
    };
    let target = match person.target {
        Some(id) => vec![id.index, id.generation],
        None => Vec::new(),
    };
    PersonView {
        index: person.id.index,
        generation: person.id.generation,
        x: person.x,
        y: person.y,
        hunger: person.hunger,
        thirst: person.thirst,
        health: person.health,
        job,
        failure,
        failure_text,
        drafted: person.drafted,
        carried: person
            .carried
            .iter()
            .map(|(item, count)| [item.0, *count])
            .collect(),
        path,
        dest,
        target,
        fatigue: person.fatigue,
        warmth: person.warmth,
        skills: person.skills,
        regions: person
            .regions
            .iter()
            .enumerate()
            .map(|(index, region)| RegionView {
                kind: index as u32,
                health: region.health,
                bleeding: region.bleeding,
                infected: region.infected,
                bandaged: region.bandaged,
                treated: region.treated,
            })
            .collect(),
    }
}

fn building_view(building: &Building) -> BuildingView {
    let contents = if building.kind == BuildingKind::Stockpile {
        building
            .contents
            .iter()
            .map(|(item, count)| [item.0, *count])
            .collect()
    } else {
        Vec::new()
    };
    BuildingView {
        index: building.id.index,
        generation: building.id.generation,
        kind: building.kind.discriminant(),
        x: building.x,
        y: building.y,
        progress: building.progress,
        contents,
    }
}

fn node_view(node: &Node) -> NodeView {
    NodeView {
        index: node.id.index,
        generation: node.id.generation,
        x: node.x,
        y: node.y,
        remaining: node.remaining,
        yield_item: node.yield_item.0,
    }
}

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

    fn write_i32(&mut self, value: i32) {
        self.write_u32(value as u32);
    }

    fn write_f32(&mut self, value: f32) {
        self.write_u32(value.to_bits());
    }

    fn write_str(&mut self, value: &str) {
        self.write_u64(value.len() as u64);
        for byte in value.as_bytes() {
            self.write_u8(*byte);
        }
    }

    fn finish(self) -> u64 {
        self.0
    }
}

fn hash_person(hash: &mut Fnv64, person: &Person) {
    hash.write_u32(person.id.index);
    hash.write_u32(person.id.generation);
    hash.write_f32(person.x);
    hash.write_f32(person.y);
    hash.write_f32(person.hunger);
    hash.write_f32(person.thirst);
    hash.write_f32(person.health);
    let view = person_view(person);
    hash.write_i32(view.job);
    hash.write_i32(view.failure);
    hash.write_str(&view.failure_text);
    hash.write_u8(u8::from(person.drafted));
    hash.write_u64(person.carried.len() as u64);
    for (item, count) in &person.carried {
        hash.write_u32(item.0);
        hash.write_u32(*count);
    }
    hash.write_u64(person.path.len() as u64);
    for point in &person.path {
        hash.write_f32(point[0]);
        hash.write_f32(point[1]);
    }
    match person.dest {
        Some(point) => {
            hash.write_u8(1);
            hash.write_f32(point[0]);
            hash.write_f32(point[1]);
        }
        None => hash.write_u8(0),
    }
    match person.target {
        Some(id) => {
            hash.write_u8(1);
            hash.write_u32(id.index);
            hash.write_u32(id.generation);
        }
        None => hash.write_u8(0),
    }
    hash.write_u32(person.gather_ticks);
    hash_order(hash, person.order);
    hash.write_f32(person.fatigue);
    hash.write_f32(person.warmth);
    for skill in person.skills {
        hash.write_f32(skill);
    }
    for region in &person.regions {
        hash.write_f32(region.health);
        hash.write_f32(region.bleeding);
        hash.write_f32(region.infected);
        hash.write_u8(u8::from(region.bandaged));
        hash.write_u8(u8::from(region.treated));
    }
}

fn hash_order(hash: &mut Fnv64, order: Option<Command>) {
    match order {
        None => hash.write_u8(0),
        Some(Command::Move { to, .. }) => {
            hash.write_u8(1);
            hash.write_f32(to[0]);
            hash.write_f32(to[1]);
        }
        Some(Command::Gather { node, .. }) => {
            hash.write_u8(2);
            hash.write_u32(node.index);
            hash.write_u32(node.generation);
        }
        Some(Command::Eat { item, .. }) => {
            hash.write_u8(3);
            hash.write_u32(item.0);
        }
        Some(Command::Haul { item, to, .. }) => {
            hash.write_u8(4);
            hash.write_u32(item.0);
            hash.write_u32(to.index);
            hash.write_u32(to.generation);
        }
        Some(Command::Work { job, .. }) => {
            hash.write_u8(5);
            hash.write_u8(job.discriminant() as u8);
        }
        Some(Command::Place { building, at, .. }) => {
            hash.write_u8(6);
            hash.write_u8(building.discriminant() as u8);
            hash.write_f32(at[0]);
            hash.write_f32(at[1]);
        }
        Some(Command::Craft { recipe, .. }) => {
            hash.write_u8(7);
            hash.write_u32(recipe.0);
        }
        Some(Command::Draft { drafted, .. }) => {
            hash.write_u8(8);
            hash.write_u8(u8::from(drafted));
        }
        Some(Command::Attack { target, .. }) => {
            hash.write_u8(9);
            hash.write_u32(target.index);
            hash.write_u32(target.generation);
        }
        Some(Command::Take { item, from, .. }) => {
            hash.write_u8(10);
            hash.write_u32(item.0);
            hash.write_u32(from.index);
            hash.write_u32(from.generation);
        }
        Some(Command::Heal { item, target, .. }) => {
            hash.write_u8(11);
            hash.write_u32(item.0);
            hash.write_u32(target.index);
            hash.write_u32(target.generation);
        }
    }
}

fn hash_building(hash: &mut Fnv64, building: &Building) {
    hash.write_u32(building.id.index);
    hash.write_u32(building.id.generation);
    hash.write_u8(building.kind.discriminant() as u8);
    hash.write_f32(building.x);
    hash.write_f32(building.y);
    hash.write_u32(building.progress);
    hash.write_u64(building.contents.len() as u64);
    for (item, count) in &building.contents {
        hash.write_u32(item.0);
        hash.write_u32(*count);
    }
}

fn hash_node(hash: &mut Fnv64, node: &Node) {
    hash.write_u32(node.id.index);
    hash.write_u32(node.id.generation);
    hash.write_f32(node.x);
    hash.write_f32(node.y);
    hash.write_u32(node.remaining);
    hash.write_u32(node.yield_item.0);
}

/// World fields a save restores. Owners, the queue, pause, and speed stay.
pub(crate) struct LoadedWorld {
    pub save_version: u32,
    pub seed: u64,
    pub tick: u64,
    pub rng: u64,
    pub alloc: EntityAllocator,
    pub people: Vec<Person>,
    pub buildings: Vec<Building>,
    pub nodes: Vec<Node>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SavedWorld {
    pub save_version: u32,
    pub seed: u64,
    pub tick: u64,
    pub rng: u64,
    pub slots: Vec<SavedSlot>,
    pub free: Vec<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SavedSlot {
    pub index: u32,
    pub generation: u32,
    pub live: bool,
    #[serde(default)]
    pub retired: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
    #[serde(default)]
    pub hunger: f32,
    #[serde(default)]
    pub thirst: f32,
    #[serde(default)]
    pub health: f32,
    #[serde(default)]
    pub drafted: bool,
    #[serde(default)]
    pub carried: Vec<[u32; 2]>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub failure: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub order: Option<SavedOrder>,
    #[serde(default)]
    pub path: Vec<[f32; 2]>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dest: Option<[f32; 2]>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<[u32; 2]>,
    #[serde(default)]
    pub gather_ticks: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub building: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub remaining: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub yield_item: Option<u32>,
    /// Build ticks spent. Omitted when 0, which is also the load default.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub progress: u32,
    /// Stockpile contents, `[item_id, count]`, sorted by item id.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub contents: Vec<[u32; 2]>,
    /// Omitted on a non-person. Present, including 0, on a person.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fatigue: Option<f32>,
    /// Omitted on a non-person. A missing person value loads as 1.0.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub warmth: Option<f32>,
    /// Four skills, gather then build, craft, medicine.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub skills: Option<[f32; 4]>,
    /// Six regions in RegionKind order. Empty on a non-person.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub regions: Vec<SavedRegion>,
}

fn is_zero(value: &u32) -> bool {
    *value == 0
}

fn default_region_health() -> f32 {
    1.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SavedRegion {
    kind: u32,
    #[serde(default = "default_region_health")]
    health: f32,
    #[serde(default)]
    bleeding: f32,
    #[serde(default)]
    infected: f32,
    #[serde(default)]
    bandaged: bool,
    #[serde(default)]
    treated: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub(crate) enum SavedOrder {
    Move { to: [f32; 2] },
    Gather { node: [u32; 2] },
    Eat { item: u32 },
    Haul { item: u32, to: [u32; 2] },
    Work { job: u8 },
    Place { building: u8, at: [f32; 2] },
    Craft { recipe: u32 },
    Draft { drafted: bool },
    Attack { target: [u32; 2] },
    Take { item: u32, from: [u32; 2] },
    Heal { item: u32, target: [u32; 2] },
}

impl SavedSlot {
    fn from_world(view: crate::ids::SlotView, sim: &SimState) -> Self {
        let mut slot = Self {
            index: view.index,
            generation: view.generation,
            live: view.live,
            retired: view.retired,
            kind: view
                .kind
                .map(|kind| match kind {
                    EntityKind::Person => "person",
                    EntityKind::Building => "building",
                    EntityKind::Node => "node",
                })
                .map(str::to_string),
            x: 0.0,
            y: 0.0,
            hunger: 0.0,
            thirst: 0.0,
            health: 0.0,
            drafted: false,
            carried: Vec::new(),
            failure: None,
            order: None,
            path: Vec::new(),
            dest: None,
            target: None,
            gather_ticks: 0,
            building: None,
            remaining: None,
            yield_item: None,
            progress: 0,
            contents: Vec::new(),
            fatigue: None,
            warmth: None,
            skills: None,
            regions: Vec::new(),
        };
        let id = EntityId {
            index: view.index,
            generation: view.generation,
        };
        if let Some(person) = sim.people.iter().find(|p| p.id == id) {
            slot.x = person.x;
            slot.y = person.y;
            slot.hunger = person.hunger;
            slot.thirst = person.thirst;
            slot.health = person.health;
            slot.drafted = person.drafted;
            slot.carried = person
                .carried
                .iter()
                .map(|(item, count)| [item.0, *count])
                .collect();
            slot.failure = person.failure.map(|reason| reason.discriminant() as u32);
            slot.order = person.order.map(SavedOrder::from_command);
            slot.path = person.path.clone();
            slot.dest = person.dest;
            slot.target = person.target.map(|id| [id.index, id.generation]);
            slot.gather_ticks = person.gather_ticks;
            slot.fatigue = Some(person.fatigue);
            slot.warmth = Some(person.warmth);
            slot.skills = Some(person.skills);
            slot.regions = person
                .regions
                .iter()
                .enumerate()
                .map(|(index, region)| SavedRegion {
                    kind: index as u32,
                    health: region.health,
                    bleeding: region.bleeding,
                    infected: region.infected,
                    bandaged: region.bandaged,
                    treated: region.treated,
                })
                .collect();
        } else if let Some(building) = sim.buildings.iter().find(|b| b.id == id) {
            slot.x = building.x;
            slot.y = building.y;
            slot.building = Some(building.kind.discriminant() as u8);
            slot.progress = building.progress;
            slot.contents = building
                .contents
                .iter()
                .map(|(item, count)| [item.0, *count])
                .collect();
        } else if let Some(node) = sim.nodes.iter().find(|n| n.id == id) {
            slot.x = node.x;
            slot.y = node.y;
            slot.remaining = Some(node.remaining);
            slot.yield_item = Some(node.yield_item.0);
        }
        slot
    }
}

impl SavedOrder {
    fn from_command(cmd: Command) -> Self {
        match cmd {
            Command::Move { to, .. } => Self::Move { to },
            Command::Gather { node, .. } => Self::Gather {
                node: [node.index, node.generation],
            },
            Command::Eat { item, .. } => Self::Eat { item: item.0 },
            Command::Haul { item, to, .. } => Self::Haul {
                item: item.0,
                to: [to.index, to.generation],
            },
            Command::Work { job, .. } => Self::Work {
                job: job.discriminant() as u8,
            },
            Command::Place { building, at, .. } => Self::Place {
                building: building.discriminant() as u8,
                at,
            },
            Command::Craft { recipe, .. } => Self::Craft { recipe: recipe.0 },
            Command::Draft { drafted, .. } => Self::Draft { drafted },
            Command::Attack { target, .. } => Self::Attack {
                target: [target.index, target.generation],
            },
            Command::Take { item, from, .. } => Self::Take {
                item: item.0,
                from: [from.index, from.generation],
            },
            Command::Heal { item, target, .. } => Self::Heal {
                item: item.0,
                target: [target.index, target.generation],
            },
        }
    }

    fn into_command(self, actor: EntityId) -> Result<Command, &'static str> {
        Ok(match self {
            Self::Move { to } => Command::Move { actor, to },
            Self::Gather { node } => Command::Gather {
                actor,
                node: EntityId {
                    index: node[0],
                    generation: node[1],
                },
            },
            Self::Eat { item } => Command::Eat {
                actor,
                item: ItemId(item),
            },
            Self::Haul { item, to } => Command::Haul {
                actor,
                item: ItemId(item),
                to: EntityId {
                    index: to[0],
                    generation: to[1],
                },
            },
            Self::Work { job } => Command::Work {
                actor,
                job: JobKind::from_discriminant(u32::from(job)).ok_or("unknown job")?,
            },
            Self::Place { building, at } => Command::Place {
                actor,
                building: BuildingKind::from_discriminant(u32::from(building))
                    .ok_or("unknown building")?,
                at,
            },
            Self::Craft { recipe } => Command::Craft {
                actor,
                recipe: RecipeId(recipe),
            },
            Self::Draft { drafted } => Command::Draft { actor, drafted },
            Self::Attack { target } => Command::Attack {
                actor,
                target: EntityId {
                    index: target[0],
                    generation: target[1],
                },
            },
            Self::Take { item, from } => Command::Take {
                actor,
                item: ItemId(item),
                from: EntityId {
                    index: from[0],
                    generation: from[1],
                },
            },
            Self::Heal { item, target } => Command::Heal {
                actor,
                item: ItemId(item),
                target: EntityId {
                    index: target[0],
                    generation: target[1],
                },
            },
        })
    }
}

fn regions_from_saved(saved: &[SavedRegion]) -> Result<[Region; 6], &'static str> {
    if saved.is_empty() {
        return Ok(std::array::from_fn(|_| Region::healthy()));
    }
    if saved.len() != RegionKind::ALL.len() {
        return Err("a person does not have six regions");
    }
    let mut regions = std::array::from_fn(|_| Region::healthy());
    for (index, region) in saved.iter().enumerate() {
        if region.kind != index as u32 || RegionKind::from_discriminant(region.kind).is_none() {
            return Err("region kind is not in RegionKind order");
        }
        regions[index] = Region {
            health: region.health,
            bleeding: region.bleeding,
            infected: region.infected,
            bandaged: region.bandaged,
            treated: region.treated,
        };
    }
    Ok(regions)
}

pub(crate) fn world_from_saved(saved: SavedWorld) -> Result<LoadedWorld, &'static str> {
    use crate::ids::SlotView;
    let mut views = Vec::new();
    for slot in &saved.slots {
        let kind = match slot.kind.as_deref() {
            None => None,
            Some("person") => Some(EntityKind::Person),
            Some("building") => Some(EntityKind::Building),
            Some("node") => Some(EntityKind::Node),
            Some(_) => return Err("unknown entity kind"),
        };
        if slot.live != kind.is_some() {
            return Err("live flag does not match kind");
        }
        views.push(SlotView {
            index: slot.index,
            generation: slot.generation,
            live: slot.live,
            retired: slot.retired,
            kind,
        });
    }
    let alloc = EntityAllocator::from_saved(views, saved.free.clone())?;
    let mut people = Vec::new();
    let mut buildings = Vec::new();
    let mut nodes = Vec::new();
    for slot in saved.slots {
        if !slot.live {
            continue;
        }
        let id = EntityId {
            index: slot.index,
            generation: slot.generation,
        };
        match slot.kind.as_deref() {
            Some("person") => {
                let failure = match slot.failure {
                    None => None,
                    Some(disc) => {
                        Some(FailureReason::from_discriminant(disc).ok_or("unknown failure")?)
                    }
                };
                let order = match slot.order {
                    None => None,
                    Some(order) => Some(order.into_command(id)?),
                };
                let mut carried = Vec::new();
                for pair in slot.carried {
                    if pair[1] == 0 {
                        return Err("carried count is 0");
                    }
                    add_carried(&mut carried, ItemId(pair[0]), pair[1]);
                }
                let regions = regions_from_saved(&slot.regions)?;
                let skills = slot.skills.unwrap_or([0.0; SKILL_COUNT]);
                people.push(Person {
                    id,
                    x: slot.x,
                    y: slot.y,
                    hunger: slot.hunger,
                    thirst: slot.thirst,
                    health: slot.health,
                    drafted: slot.drafted,
                    carried,
                    failure,
                    order,
                    path: slot.path,
                    dest: slot.dest,
                    target: slot.target.map(|pair| EntityId {
                        index: pair[0],
                        generation: pair[1],
                    }),
                    gather_ticks: slot.gather_ticks,
                    fatigue: slot.fatigue.unwrap_or(0.0),
                    warmth: slot.warmth.unwrap_or(1.0),
                    skills,
                    regions,
                });
            }
            Some("building") => {
                let kind = BuildingKind::from_discriminant(u32::from(
                    slot.building.ok_or("building has no kind")?,
                ))
                .ok_or("unknown building")?;
                let mut contents = Vec::new();
                for pair in slot.contents {
                    if pair[1] == 0 {
                        return Err("stockpile count is 0");
                    }
                    add_carried(&mut contents, ItemId(pair[0]), pair[1]);
                }
                buildings.push(Building {
                    id,
                    kind,
                    x: slot.x,
                    y: slot.y,
                    progress: slot.progress,
                    contents,
                });
            }
            Some("node") => nodes.push(Node {
                id,
                x: slot.x,
                y: slot.y,
                remaining: slot.remaining.ok_or("node has no remaining")?,
                yield_item: ItemId(slot.yield_item.ok_or("node has no yield")?),
            }),
            _ => return Err("live slot has no kind"),
        }
    }
    people.sort_by_key(|person| person.id.index);
    buildings.sort_by_key(|building| building.id.index);
    nodes.sort_by_key(|node| node.id.index);
    Ok(LoadedWorld {
        save_version: saved.save_version,
        seed: saved.seed,
        tick: saved.tick,
        rng: saved.rng,
        alloc,
        people,
        buildings,
        nodes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_is_empty_tick_zero_and_the_seed_is_the_rng_state() {
        let sim = SimState::new(99);
        assert_eq!(sim.save_version, SAVE_VERSION);
        assert_eq!(sim.seed, 99);
        assert_eq!(sim.tick(), 0);
        assert_eq!(sim.rng.state(), 99);
        assert!(sim.view().people.is_empty());
        assert!(sim.queue.is_empty());
    }

    #[test]
    fn queue_cap_does_not_drop_the_queued_commands() {
        let mut sim = SimState::new(1);
        sim.new_game(1);
        let actor = sim.people[0].id;
        for _ in 0..QUEUE_CAP {
            assert_eq!(
                sim.submit(Command::Move {
                    actor,
                    to: [20.0, 16.0],
                }),
                QUEUED
            );
        }
        assert_eq!(sim.queue.len(), QUEUE_CAP);
        assert_eq!(
            sim.submit(Command::Move {
                actor,
                to: [20.0, 16.0],
            }),
            QUEUE_FULL
        );
        assert_eq!(sim.queue.len(), QUEUE_CAP);
        assert_eq!(sim.rejections().queue_full, 1);
    }

    #[test]
    fn save_keeps_a_freed_slot_stale() {
        use crate::command::{Command, STALE};
        use crate::save::{load_from_json, save_to_json};

        let mut sim = SimState::new(1);
        sim.new_game(1);
        let id = sim.people[0].id;
        let y = sim.people[0].y;
        sim.alloc.free(id);
        sim.people.retain(|person| person.id != id);
        let json = save_to_json(&sim);
        let mut loaded = load_from_json(&json).unwrap();
        assert_eq!(loaded.state_hash(), sim.state_hash());
        assert!(json.contains("\"free\""));
        assert_eq!(
            loaded.submit(Command::Move {
                actor: id,
                to: [20.0, y],
            }),
            STALE
        );
    }

    #[test]
    fn a_stale_command_in_the_batch_does_not_stop_the_next() {
        let mut sim = SimState::new(1);
        sim.new_game(1);
        let first = sim.people[0].id;
        let second = sim.people[1].id;
        assert_eq!(
            sim.submit(Command::Move {
                actor: first,
                to: [20.0, sim.people[0].y],
            }),
            QUEUED
        );
        assert_eq!(
            sim.submit(Command::Move {
                actor: second,
                to: [20.0, sim.people[1].y],
            }),
            QUEUED
        );
        sim.alloc.free(first);
        sim.people.retain(|person| person.id != first);
        let stale_before = sim.rejections().stale;
        sim.step();
        assert_eq!(sim.rejections().stale, stale_before + 1);
        let view = sim.view();
        let moved = view
            .people
            .iter()
            .find(|person| person.index == second.index)
            .unwrap();
        assert!(moved.x > 16.0 || moved.path.len() > 0 || moved.dest.len() == 2);
        assert!(view.people.iter().all(|person| person.index != first.index));
    }
}
