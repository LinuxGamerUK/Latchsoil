//! Built-in item and recipe rows.
//!
//! No data files are loaded yet. The nodes still have to name a yield item, so
//! this table is the loaded set: fixed order, no `HashMap`. A later milestone
//! that reads `data/` replaces these numbers; it must not renumber them silently.

use crate::command::{BuildingKind, ItemId, RecipeId};
use crate::rules::{RECIPE_BANDAGE_TICKS, RECIPE_KNIFE_TICKS, RECIPE_MEAL_TICKS};

pub const ITEM_GRAIN: ItemId = ItemId(0);
pub const ITEM_WOOD: ItemId = ItemId(1);
pub const ITEM_STONE: ItemId = ItemId(2);
pub const ITEM_FIBER: ItemId = ItemId(3);
pub const ITEM_WATER: ItemId = ItemId(4);
pub const ITEM_KNIFE: ItemId = ItemId(5);
pub const ITEM_MEAL: ItemId = ItemId(6);
pub const ITEM_BANDAGE: ItemId = ItemId(7);

pub const RECIPE_KNIFE: RecipeId = RecipeId(0);
pub const RECIPE_MEAL: RecipeId = RecipeId(1);
pub const RECIPE_BANDAGE: RecipeId = RecipeId(2);

const ITEMS: [(ItemId, &str); 8] = [
    (ITEM_GRAIN, "grain"),
    (ITEM_WOOD, "wood"),
    (ITEM_STONE, "stone"),
    (ITEM_FIBER, "fiber"),
    (ITEM_WATER, "water"),
    (ITEM_KNIFE, "knife"),
    (ITEM_MEAL, "meal"),
    (ITEM_BANDAGE, "bandage"),
];

/// One recipe. Inputs are consumed. A tool is carried and kept. A station must
/// be a finished building of that kind within station range.
pub(crate) struct RecipeDef {
    pub id: RecipeId,
    pub inputs: &'static [(ItemId, u32)],
    pub tool: Option<ItemId>,
    pub station: Option<BuildingKind>,
    pub ticks: u32,
    pub output: ItemId,
}

const KNIFE_INPUTS: [(ItemId, u32); 2] = [(ITEM_STONE, 1), (ITEM_WOOD, 1)];
const MEAL_INPUTS: [(ItemId, u32); 2] = [(ITEM_GRAIN, 1), (ITEM_WATER, 1)];
const BANDAGE_INPUTS: [(ItemId, u32); 2] = [(ITEM_FIBER, 2), (ITEM_WATER, 1)];

const RECIPES: [RecipeDef; 3] = [
    RecipeDef {
        id: RECIPE_KNIFE,
        inputs: &KNIFE_INPUTS,
        tool: None,
        station: None,
        ticks: RECIPE_KNIFE_TICKS,
        output: ITEM_KNIFE,
    },
    RecipeDef {
        id: RECIPE_MEAL,
        inputs: &MEAL_INPUTS,
        tool: None,
        station: Some(BuildingKind::Campfire),
        ticks: RECIPE_MEAL_TICKS,
        output: ITEM_MEAL,
    },
    RecipeDef {
        id: RECIPE_BANDAGE,
        inputs: &BANDAGE_INPUTS,
        tool: Some(ITEM_KNIFE),
        station: Some(BuildingKind::LeanTo),
        ticks: RECIPE_BANDAGE_TICKS,
        output: ITEM_BANDAGE,
    },
];

const RECIPE_ROWS: [(RecipeId, &str); 3] = [
    (RECIPE_KNIFE, "knife"),
    (RECIPE_MEAL, "meal"),
    (RECIPE_BANDAGE, "bandage"),
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
        recipes: RECIPE_ROWS
            .iter()
            .map(|(id, name)| CatalogRow {
                id: id.0,
                name: (*name).to_string(),
            })
            .collect(),
    }
}

pub fn item_known(id: ItemId) -> bool {
    ITEMS.iter().any(|(item, _)| *item == id)
}

pub fn recipe_known(id: RecipeId) -> bool {
    recipe_def(id).is_some()
}

pub(crate) fn recipe_def(id: RecipeId) -> Option<&'static RecipeDef> {
    RECIPES.iter().find(|recipe| recipe.id == id)
}
