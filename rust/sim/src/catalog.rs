//! Built-in item rows for milestone 1a.
//!
//! No data files are loaded yet. The 1a nodes still have to name a yield item,
//! so this table is the loaded set: fixed order, no `HashMap`. A later milestone
//! that reads `data/` replaces these numbers; it must not renumber them silently.
//! Recipes are empty. A `RecipeId` is therefore missing from the loaded tables.

use crate::command::{ItemId, RecipeId};

pub const ITEM_GRAIN: ItemId = ItemId(0);
pub const ITEM_WOOD: ItemId = ItemId(1);
pub const ITEM_STONE: ItemId = ItemId(2);
pub const ITEM_FIBER: ItemId = ItemId(3);
pub const ITEM_WATER: ItemId = ItemId(4);

const ITEMS: [(ItemId, &str); 5] = [
    (ITEM_GRAIN, "grain"),
    (ITEM_WOOD, "wood"),
    (ITEM_STONE, "stone"),
    (ITEM_FIBER, "fiber"),
    (ITEM_WATER, "water"),
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CatalogRow {
    pub id: u32,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Catalog {
    pub items: Vec<CatalogRow>,
    pub recipes: Vec<CatalogRow>,
}

pub fn catalog() -> Catalog {
    Catalog {
        items: ITEMS
            .iter()
            .map(|(id, name)| CatalogRow {
                id: id.0,
                name: (*name).to_string(),
            })
            .collect(),
        recipes: Vec::new(),
    }
}

pub fn item_known(id: ItemId) -> bool {
    ITEMS.iter().any(|(item, _)| *item == id)
}

pub fn recipe_known(_id: RecipeId) -> bool {
    false
}
