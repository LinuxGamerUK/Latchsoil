//! Entity ids. The index is stable across save/load; the generation says whether
//! a holder of that index is still talking about the same occupant.
//!
//! The free list is a `Vec`, reused LIFO. A `HashMap` would make "who comes back
//! next" depend on iteration order, and a load could not reproduce the run.

use serde::{Deserialize, Serialize};

/// Stable index of a person, building, stockpile, or resource node.
///
/// Godot holds this. It does not change when the sim saves and loads. Reuse of
/// a freed index is detected with [`GenerationalIndex`], not by renumbering.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntityId(pub u32);

/// Generational index: the slot, and which occupant of that slot is current.
///
/// `generation` starts at 0 and bumps on every free. A stale holder fails
/// [`EntityAllocator::is_live`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct GenerationalIndex {
    pub index: u32,
    pub generation: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
struct Slot {
    generation: u32,
    live: bool,
}

/// Hands out [`EntityId`]s and reuses freed ones. Saved with the sim so the
/// next id after a load is the same id it would have been without the load.
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

    /// Next id. A freed index comes back before a fresh one, with the generation
    /// bumped at free time already stored on the slot.
    pub fn allocate(&mut self) -> EntityId {
        if let Some(index) = self.free.pop() {
            let slot = self
                .slots
                .get_mut(index as usize)
                .expect("free list entry has a slot");
            debug_assert!(!slot.live, "free list handed out a live slot");
            slot.live = true;
            EntityId(index)
        } else {
            let index = self.slots.len() as u32;
            self.slots.push(Slot {
                generation: 0,
                live: true,
            });
            EntityId(index)
        }
    }

    /// Retire `id`. The index can be reused; its generation bumps so the old
    /// generational index is no longer live. Unknown or already-freed ids are
    /// ignored, so a double free cannot push the same index twice.
    pub fn free(&mut self, id: EntityId) {
        let Some(slot) = self.slots.get_mut(id.0 as usize) else {
            return;
        };
        if !slot.live {
            return;
        }
        slot.live = false;
        slot.generation = slot.generation.wrapping_add(1);
        self.free.push(id.0);
    }

    /// Generation currently stored for `id`, live or not. `None` if the index
    /// was never allocated.
    pub fn generation(&self, id: EntityId) -> Option<u32> {
        self.slots.get(id.0 as usize).map(|slot| slot.generation)
    }

    /// The generational index a holder should store alongside [`EntityId`].
    pub fn generational_index(&self, id: EntityId) -> Option<GenerationalIndex> {
        self.generation(id).map(|generation| GenerationalIndex {
            index: id.0,
            generation,
        })
    }

    /// True only when this exact occupant of the slot is still allocated.
    pub fn is_live(&self, id: GenerationalIndex) -> bool {
        self.slots
            .get(id.index as usize)
            .is_some_and(|slot| slot.live && slot.generation == id.generation)
    }

    pub(crate) fn slot_views(&self) -> impl Iterator<Item = (u32, bool)> + '_ {
        self.slots.iter().map(|slot| (slot.generation, slot.live))
    }

    pub(crate) fn free_list(&self) -> &[u32] {
        &self.free
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allocate_reuses_freed_ids_lifo_with_a_bumped_generation() {
        let mut alloc = EntityAllocator::new();
        let e0 = alloc.allocate();
        let e1 = alloc.allocate();
        let e2 = alloc.allocate();
        assert_eq!((e0, e1, e2), (EntityId(0), EntityId(1), EntityId(2)));

        let born = alloc.generational_index(e0).unwrap();
        assert_eq!(
            born,
            GenerationalIndex {
                index: 0,
                generation: 0
            }
        );
        assert!(alloc.is_live(born));
        assert_eq!(alloc.generation(e0), Some(0));

        alloc.free(e1);
        alloc.free(e0);
        assert!(!alloc.is_live(born));
        assert_eq!(alloc.generation(e0), Some(1));
        assert_eq!(
            alloc.generational_index(e0).unwrap(),
            GenerationalIndex {
                index: 0,
                generation: 1
            }
        );

        // LIFO: 0 was freed last, so it comes back first. The index is stable.
        let again0 = alloc.allocate();
        assert_eq!(again0, EntityId(0));
        assert_eq!(alloc.generation(again0), Some(1));
        assert!(alloc.is_live(GenerationalIndex {
            index: 0,
            generation: 1
        }));
        assert!(!alloc.is_live(born));

        let again1 = alloc.allocate();
        assert_eq!(again1, EntityId(1));
        assert_eq!(alloc.generation(again1), Some(1));

        // High-water mark did not move while freed slots remained.
        assert_eq!(alloc.allocate(), EntityId(3));
        assert_eq!(alloc.generation(EntityId(3)), Some(0));
    }

    #[test]
    fn unknown_and_double_free_do_not_corrupt_the_free_list() {
        let mut alloc = EntityAllocator::new();
        alloc.free(EntityId(9));
        let e = alloc.allocate();
        alloc.free(e);
        alloc.free(e);
        assert_eq!(alloc.generation(e), Some(1));
        assert_eq!(alloc.allocate(), e);
        assert_eq!(alloc.allocate(), EntityId(1));
        assert_eq!(alloc.generation(EntityId(99)), None);
        assert!(!alloc.is_live(GenerationalIndex {
            index: 99,
            generation: 0
        }));
    }

    #[test]
    fn allocator_round_trip_keeps_the_next_id_stable() {
        let mut alloc = EntityAllocator::new();
        let e0 = alloc.allocate();
        let _e1 = alloc.allocate();
        alloc.free(e0);
        let json = serde_json::to_string(&alloc).unwrap();
        let mut loaded: EntityAllocator = serde_json::from_str(&json).unwrap();
        assert_eq!(loaded, alloc);

        let from_loaded = loaded.allocate();
        let from_original = alloc.allocate();
        assert_eq!(from_loaded, from_original);
        assert_eq!(from_loaded, EntityId(0));
        assert_eq!(loaded.generation(from_loaded), Some(1));
        assert_eq!(
            loaded.generation(from_loaded),
            alloc.generation(from_original)
        );
    }
}
