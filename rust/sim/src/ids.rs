//! Entity ids. One slot table holds people, buildings, and resource nodes.
//!
//! `EntityId` is the pair Godot stores: index, then generation. A new slot
//! starts at generation 1. Generation 0 is never live, so `(0, 0)` is always
//! stale and is the empty value. Freeing a slot increments its generation; the
//! next occupant of that index gets the new generation. If the increment would
//! overflow `u32`, the index is retired and not reused.
//!
//! The free list is a `Vec`, reused LIFO. Nothing here walks a `HashMap`.

use serde::{Deserialize, Serialize};

/// Occupant of a slot. People, buildings, and nodes share the table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EntityKind {
    Person,
    Building,
    Node,
}

/// Generational id. `(0, 0)` is never live.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct EntityId {
    pub index: u32,
    pub generation: u32,
}

/// Old name for [`EntityId`]. The pair is the id.
pub type GenerationalIndex = EntityId;

impl EntityId {
    /// Godot's empty value. Never live.
    pub const EMPTY: Self = Self {
        index: 0,
        generation: 0,
    };
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
struct Slot {
    generation: u32,
    live: bool,
    retired: bool,
    kind: Option<EntityKind>,
}

/// Hands out [`EntityId`]s and reuses freed ones. Saved with the sim so a pair
/// that was stale before the save is still stale after it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntityAllocator {
    slots: Vec<Slot>,
    /// Freed indices, reused LIFO via `pop`. Order is part of the save.
    free: Vec<u32>,
}

impl EntityAllocator {
    pub fn new() -> Self {
        Self {
            slots: Vec::new(),
            free: Vec::new(),
        }
    }

    /// Next id of `kind`. `None` only when the index space is exhausted, which
    /// a player command cannot cause.
    pub fn allocate(&mut self, kind: EntityKind) -> Option<EntityId> {
        if let Some(index) = self.free.pop() {
            let slot = self
                .slots
                .get_mut(index as usize)
                .expect("free list entry has a slot");
            debug_assert!(!slot.live, "free list handed out a live slot");
            debug_assert!(!slot.retired, "free list handed out a retired slot");
            slot.live = true;
            slot.kind = Some(kind);
            return Some(EntityId {
                index,
                generation: slot.generation,
            });
        }
        let index = u32::try_from(self.slots.len()).ok()?;
        self.slots.push(Slot {
            generation: 1,
            live: true,
            retired: false,
            kind: Some(kind),
        });
        Some(EntityId {
            index,
            generation: 1,
        })
    }

    /// Retire `id` if it is the current occupant. The index can be reused at
    /// the incremented generation. A generation that would overflow `u32` retires
    /// the index instead. Unknown, stale, or already-freed ids are ignored.
    pub fn free(&mut self, id: EntityId) {
        let Some(slot) = self.slots.get_mut(id.index as usize) else {
            return;
        };
        if !slot.live || slot.retired || slot.generation != id.generation {
            return;
        }
        slot.live = false;
        slot.kind = None;
        if slot.generation == u32::MAX {
            slot.retired = true;
            return;
        }
        slot.generation += 1;
        self.free.push(id.index);
    }

    /// True only when this exact occupant of the slot is still allocated.
    pub fn is_live(&self, id: EntityId) -> bool {
        self.slots
            .get(id.index as usize)
            .is_some_and(|slot| slot.live && !slot.retired && slot.generation == id.generation)
    }

    pub fn kind(&self, id: EntityId) -> Option<EntityKind> {
        let slot = self.slots.get(id.index as usize)?;
        if slot.live && slot.generation == id.generation {
            slot.kind
        } else {
            None
        }
    }

    pub fn generation(&self, id: EntityId) -> Option<u32> {
        self.slots
            .get(id.index as usize)
            .map(|slot| slot.generation)
    }

    pub(crate) fn slot_count(&self) -> usize {
        self.slots.len()
    }

    pub(crate) fn slot_at(&self, index: usize) -> Option<SlotView> {
        self.slots.get(index).map(|slot| SlotView {
            index: index as u32,
            generation: slot.generation,
            live: slot.live,
            retired: slot.retired,
            kind: slot.kind,
        })
    }

    pub(crate) fn free_list(&self) -> &[u32] {
        &self.free
    }

    /// Rebuild from a save. `Err` if the free list or a live generation is impossible.
    pub(crate) fn from_saved(slots: Vec<SlotView>, free: Vec<u32>) -> Result<Self, &'static str> {
        let mut built = Vec::with_capacity(slots.len());
        for (expected, slot) in slots.iter().enumerate() {
            if slot.index != expected as u32 {
                return Err("slot index is not dense from 0");
            }
            if slot.live && slot.generation == 0 {
                return Err("generation 0 is live");
            }
            if slot.live && slot.retired {
                return Err("a live slot is retired");
            }
            if slot.live && slot.kind.is_none() {
                return Err("a live slot has no kind");
            }
            if !slot.live && slot.kind.is_some() {
                return Err("a free slot has a kind");
            }
            built.push(Slot {
                generation: slot.generation,
                live: slot.live,
                retired: slot.retired,
                kind: slot.kind,
            });
        }
        for index in &free {
            let Some(slot) = built.get(*index as usize) else {
                return Err("free list names an unknown index");
            };
            if slot.live || slot.retired {
                return Err("free list names a live or retired slot");
            }
        }
        let mut seen = vec![false; built.len()];
        for index in &free {
            let i = *index as usize;
            if seen[i] {
                return Err("free list repeats an index");
            }
            seen[i] = true;
        }
        for (i, slot) in built.iter().enumerate() {
            if !slot.live && !slot.retired && !seen[i] {
                return Err("a reusable slot is missing from the free list");
            }
        }
        Ok(Self { slots: built, free })
    }
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct SlotView {
    pub index: u32,
    pub generation: u32,
    pub live: bool,
    pub retired: bool,
    pub kind: Option<EntityKind>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_slots_start_at_generation_1_and_zero_zero_is_never_live() {
        let mut alloc = EntityAllocator::new();
        let e0 = alloc.allocate(EntityKind::Person).unwrap();
        let e1 = alloc.allocate(EntityKind::Node).unwrap();
        let e2 = alloc.allocate(EntityKind::Building).unwrap();
        assert_eq!(
            e0,
            EntityId {
                index: 0,
                generation: 1
            }
        );
        assert_eq!(e1.index, 1);
        assert_eq!(e2.index, 2);
        assert!(alloc.is_live(e0));
        assert!(!alloc.is_live(EntityId::EMPTY));
        assert!(!alloc.is_live(EntityId {
            index: 0,
            generation: 0
        }));
        assert_eq!(alloc.kind(e0), Some(EntityKind::Person));
        assert_eq!(alloc.kind(e1), Some(EntityKind::Node));
    }

    #[test]
    fn free_increments_generation_and_reuses_lifo() {
        let mut alloc = EntityAllocator::new();
        let e0 = alloc.allocate(EntityKind::Person).unwrap();
        let e1 = alloc.allocate(EntityKind::Person).unwrap();
        let _e2 = alloc.allocate(EntityKind::Person).unwrap();

        alloc.free(e1);
        alloc.free(e0);
        assert!(!alloc.is_live(e0));
        assert_eq!(alloc.generation(e0), Some(2));

        let again0 = alloc.allocate(EntityKind::Node).unwrap();
        assert_eq!(
            again0,
            EntityId {
                index: 0,
                generation: 2
            }
        );
        assert!(alloc.is_live(again0));
        assert!(!alloc.is_live(e0));
        assert_eq!(alloc.kind(again0), Some(EntityKind::Node));

        let again1 = alloc.allocate(EntityKind::Person).unwrap();
        assert_eq!(again1.index, 1);
        assert_eq!(again1.generation, 2);

        let fresh = alloc.allocate(EntityKind::Person).unwrap();
        assert_eq!(fresh.index, 3);
        assert_eq!(fresh.generation, 1);
    }

    #[test]
    fn stale_free_does_not_corrupt_the_free_list() {
        let mut alloc = EntityAllocator::new();
        alloc.free(EntityId {
            index: 9,
            generation: 1,
        });
        let e = alloc.allocate(EntityKind::Person).unwrap();
        alloc.free(e);
        alloc.free(e);
        assert_eq!(alloc.generation(e), Some(2));
        assert_eq!(alloc.allocate(EntityKind::Person).unwrap().index, e.index);
        assert_eq!(alloc.allocate(EntityKind::Person).unwrap().index, 1);
    }

    #[test]
    fn overflowing_generation_retires_the_index() {
        let mut alloc = EntityAllocator::new();
        let e = alloc.allocate(EntityKind::Person).unwrap();
        alloc.slots[0].generation = u32::MAX;
        let maxed = EntityId {
            index: e.index,
            generation: u32::MAX,
        };
        assert!(alloc.is_live(maxed));
        alloc.free(maxed);
        assert!(!alloc.is_live(maxed));
        assert!(alloc.free_list().is_empty());
        assert!(alloc.slots[0].retired);
        let next = alloc.allocate(EntityKind::Person).unwrap();
        assert_eq!(next.index, 1);
        assert_ne!(next.index, e.index);
    }

    #[test]
    fn allocator_round_trip_keeps_the_next_id_stable() {
        let mut alloc = EntityAllocator::new();
        let e0 = alloc.allocate(EntityKind::Person).unwrap();
        let _e1 = alloc.allocate(EntityKind::Node).unwrap();
        alloc.free(e0);
        let json = serde_json::to_string(&alloc).unwrap();
        let mut loaded: EntityAllocator = serde_json::from_str(&json).unwrap();
        assert_eq!(loaded, alloc);
        assert_eq!(
            loaded.allocate(EntityKind::Building).unwrap(),
            alloc.allocate(EntityKind::Building).unwrap()
        );
    }
}
