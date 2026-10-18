//! Milestone 1b rules. Headless. No Godot process.
//!
//! Each threshold is the sim constant, asserted beside the test that names it.

use latchsoil_sim::{
    load_from_json, save_to_json, BuildingKind, FailureReason, ItemId, JobKind, RecipeId,
    SaveError, SimState, BUILD_TICKS, CARRY_CAP, EAT_HUNGER_RESTORE, EAT_THIRST_RESTORE,
    HAUL_TICKS_PER_UNIT, HUNGER_PER_TICK, ITEM_BANDAGE, ITEM_FIBER, ITEM_GRAIN, ITEM_KNIFE,
    ITEM_MEAL, ITEM_STONE, ITEM_WATER, ITEM_WOOD, MALFORMED, MEAL_HUNGER_RESTORE,
    MEAL_THIRST_RESTORE, PEG_X, PEG_Y, QUEUED, RECIPE_BANDAGE, RECIPE_BANDAGE_TICKS, RECIPE_KNIFE,
    RECIPE_KNIFE_TICKS, RECIPE_MEAL, RECIPE_MEAL_TICKS, SAVE_VERSION, STALE, STARTING_GRAIN,
    STATION_RANGE_M, STOCKPILE_CAPACITY, TAKE_TICKS_PER_UNIT, THIRST_PER_TICK,
    WATER_HUNGER_RESTORE, WATER_THIRST_RESTORE,
};

fn started(seed: u64) -> SimState {
    let mut sim = SimState::new(seed);
    sim.new_game(seed);
    sim
}

fn carried_of(carried: &[[u32; 2]], item: u32) -> u32 {
    carried
        .iter()
        .filter(|pair| pair[0] == item)
        .map(|pair| pair[1])
        .sum()
}

fn view_person(sim: &SimState, index: u32) -> latchsoil_sim::PersonView {
    sim.view()
        .people
        .into_iter()
        .find(|person| person.index == index)
        .expect("person")
}

fn cell_of(point: [f32; 2]) -> (i32, i32) {
    (point[0].floor() as i32, point[1].floor() as i32)
}

fn edit(sim: &SimState, f: impl FnOnce(&mut serde_json::Value)) -> SimState {
    let mut value: serde_json::Value = serde_json::from_str(&save_to_json(sim)).unwrap();
    f(&mut value);
    load_from_json(&value.to_string()).expect("edited save")
}

fn slot_mut<'a>(value: &'a mut serde_json::Value, index: u64) -> &'a mut serde_json::Value {
    value["slots"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|slot| slot["index"] == index)
        .expect("slot")
}

fn set_carried(sim: &SimState, pairs: &[[u32; 2]]) -> SimState {
    edit(sim, |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!(pairs);
    })
}

/// A cell inside the acre, not the peg, not `avoid`.
fn open_cell(avoid: [f32; 2]) -> [f32; 2] {
    for y in 1..31 {
        for x in 1..31 {
            let at = [x as f32, y as f32];
            if cell_of(at) != cell_of(avoid) && cell_of(at) != (PEG_X as i32, PEG_Y as i32) {
                return at;
            }
        }
    }
    [1.0, 1.0]
}

/// A different cell within station range of `at`, inside the acre, not the peg.
fn adjacent_cell(at: [f32; 2]) -> [f32; 2] {
    for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0), (1.0, 1.0)] {
        let next = [at[0] + dx, at[1] + dy];
        if !(0.0..32.0).contains(&next[0]) || !(0.0..32.0).contains(&next[1]) {
            continue;
        }
        if cell_of(next) == cell_of(at) || cell_of(next) == (PEG_X as i32, PEG_Y as i32) {
            continue;
        }
        return next;
    }
    open_cell(at)
}

fn place_at(sim: &mut SimState, kind: BuildingKind, at: [f32; 2]) {
    let person = view_person(sim, 0);
    assert_eq!(
        sim.submit_place(0, person.generation, kind.discriminant(), at[0], at[1]),
        QUEUED
    );
}

fn finish_build(sim: &mut SimState) -> latchsoil_sim::BuildingView {
    for _ in 0..BUILD_TICKS + 400 {
        sim.step();
        if let Some(building) = sim.view().buildings.last() {
            if building.progress >= BUILD_TICKS && view_person(sim, 0).dest.is_empty() {
                return building.clone();
            }
        }
    }
    panic!("build did not finish");
}

fn order_done(sim: &SimState) -> bool {
    let person = view_person(sim, 0);
    person.dest.is_empty() && person.path.is_empty() && person.failure == -1
}

#[test]
fn catalog_names_knife_meal_and_bandage() {
    let sim = started(1);
    let catalog = sim.catalog();
    let items: Vec<_> = catalog
        .items
        .iter()
        .map(|row| (row.id, row.name.as_str()))
        .collect();
    assert_eq!(
        items,
        vec![
            (0, "grain"),
            (1, "wood"),
            (2, "stone"),
            (3, "fiber"),
            (4, "water"),
            (5, "knife"),
            (6, "meal"),
            (7, "bandage"),
        ]
    );
    let recipes: Vec<_> = catalog
        .recipes
        .iter()
        .map(|row| (row.id, row.name.as_str()))
        .collect();
    assert_eq!(recipes, vec![(0, "knife"), (1, "meal"), (2, "bandage")]);
    assert_eq!(ITEM_KNIFE, ItemId(5));
    assert_eq!(ITEM_MEAL, ItemId(6));
    assert_eq!(ITEM_BANDAGE, ItemId(7));
    assert_eq!(RECIPE_KNIFE, RecipeId(0));
    assert_eq!(RECIPE_MEAL, RecipeId(1));
    assert_eq!(RECIPE_BANDAGE, RecipeId(2));
}

#[test]
fn placement_inside_the_acre_succeeds_and_outside_it_is_no_path() {
    let mut inside = started(3);
    let person = view_person(&inside, 0);
    let at = open_cell([person.x, person.y]);
    place_at(&mut inside, BuildingKind::Campfire, at);
    inside.step();
    let buildings = inside.view().buildings;
    assert_eq!(buildings.len(), 1);
    assert_eq!(buildings[0].kind, BuildingKind::Campfire.discriminant());
    assert_eq!(buildings[0].x.to_bits(), at[0].to_bits());
    assert_eq!(buildings[0].y.to_bits(), at[1].to_bits());
    assert!(buildings[0].contents.is_empty(), "a campfire holds nothing");
    assert_eq!(view_person(&inside, 0).failure, -1);
    assert_eq!(view_person(&inside, 0).job, JobKind::Build.discriminant());

    let mut outside = started(3);
    let person = view_person(&outside, 0);
    assert_eq!(
        outside.submit_place(
            0,
            person.generation,
            BuildingKind::LeanTo.discriminant(),
            40.0,
            person.y,
        ),
        QUEUED
    );
    outside.step();
    assert!(outside.view().buildings.is_empty());
    let failed = view_person(&outside, 0);
    assert_eq!(failed.failure_text, "no path");
    assert_eq!(failed.failure, FailureReason::NoPath.discriminant());
    assert!(failed.path.is_empty());
    assert!(failed.dest.is_empty());
}

#[test]
fn two_buildings_are_refused_on_one_cell() {
    let mut sim = started(4);
    let person = view_person(&sim, 0);
    let at = open_cell([person.x, person.y]);
    place_at(&mut sim, BuildingKind::Campfire, at);
    sim.step();
    assert_eq!(sim.view().buildings.len(), 1);
    let same_cell = [at[0] + 0.4, at[1] + 0.6];
    assert_eq!(cell_of(same_cell), cell_of(at));
    place_at(&mut sim, BuildingKind::Stockpile, same_cell);
    sim.step();
    let buildings = sim.view().buildings;
    assert_eq!(
        buildings.len(),
        1,
        "a second building on the cell is refused"
    );
    assert_eq!(buildings[0].kind, BuildingKind::Campfire.discriminant());
    assert_eq!(buildings[0].x.to_bits(), at[0].to_bits());
}

#[test]
fn the_peg_cell_is_refused() {
    let mut sim = started(4);
    let person = view_person(&sim, 0);
    assert_eq!(
        sim.submit_place(
            0,
            person.generation,
            BuildingKind::Stockpile.discriminant(),
            PEG_X,
            PEG_Y
        ),
        QUEUED
    );
    sim.step();
    assert!(
        sim.view().buildings.is_empty(),
        "the peg cell is not a build site"
    );
    let failed = view_person(&sim, 0);
    assert_eq!(failed.failure, FailureReason::NoPath.discriminant());
    assert!(failed.path.is_empty());
    assert_ne!(cell_of([failed.x, failed.y]), (PEG_X as i32, PEG_Y as i32));
}

#[test]
fn build_progress_reaches_finished_and_only_a_finished_building_is_a_station() {
    assert_eq!(BUILD_TICKS, 60);
    assert_eq!(STATION_RANGE_M, 2.0);

    let mut sim = started(8);
    let person = view_person(&sim, 0);
    place_at(&mut sim, BuildingKind::Campfire, [person.x, person.y]);
    sim.step();
    assert_eq!(sim.view().buildings[0].progress, 1);
    assert_eq!(view_person(&sim, 0).job, JobKind::Build.discriminant());

    for expected in 2..BUILD_TICKS {
        sim.step();
        assert_eq!(sim.view().buildings[0].progress, expected);
        assert_eq!(view_person(&sim, 0).job, JobKind::Build.discriminant());
    }
    sim.step();
    let finished = &sim.view().buildings[0];
    assert_eq!(finished.progress, BUILD_TICKS);
    assert!(order_done(&sim), "a finished build clears the order");
    assert_eq!(view_person(&sim, 0).job, -1);

    let mut unfinished = started(8);
    let person = view_person(&unfinished, 0);
    place_at(
        &mut unfinished,
        BuildingKind::Campfire,
        [person.x, person.y],
    );
    unfinished.step();
    assert!(unfinished.view().buildings[0].progress < BUILD_TICKS);
    let with_inputs = set_carried(&unfinished, &[[ITEM_GRAIN.0, 1], [ITEM_WATER.0, 1]]);
    assert!(with_inputs.view().buildings[0].progress < BUILD_TICKS);
    let mut crafting = with_inputs;
    let person = view_person(&crafting, 0);
    assert_eq!(
        crafting.submit_craft(0, person.generation, RECIPE_MEAL.0),
        QUEUED
    );
    crafting.step();
    assert_eq!(view_person(&crafting, 0).failure_text, "no station");
    assert_eq!(
        view_person(&crafting, 0).failure,
        FailureReason::NoStation.discriminant()
    );
}

#[test]
fn a_recipe_with_no_station_unfinished_or_out_of_range_fails_no_station() {
    assert_eq!(STATION_RANGE_M, 2.0);
    assert_eq!(FailureReason::NoStation.as_str(), "no station");
    assert_eq!(FailureReason::NoStation.discriminant(), 7);
    assert_eq!(
        FailureReason::from_discriminant(7),
        Some(FailureReason::NoStation)
    );

    let mut none = set_carried(&started(2), &[[ITEM_GRAIN.0, 1], [ITEM_WATER.0, 1]]);
    let person = view_person(&none, 0);
    assert_eq!(
        none.submit_craft(0, person.generation, RECIPE_MEAL.0),
        QUEUED
    );
    none.step();
    assert_eq!(view_person(&none, 0).failure_text, "no station");
    assert!(none.view().buildings.is_empty());

    let mut site = started(2);
    let person = view_person(&site, 0);
    place_at(&mut site, BuildingKind::Campfire, [person.x, person.y]);
    for _ in 0..3 {
        site.step();
    }
    assert!(site.view().buildings[0].progress < BUILD_TICKS);
    let mut unfinished = set_carried(&site, &[[ITEM_GRAIN.0, 1], [ITEM_WATER.0, 1]]);
    let person = view_person(&unfinished, 0);
    assert_eq!(
        unfinished.submit_craft(0, person.generation, RECIPE_MEAL.0),
        QUEUED
    );
    unfinished.step();
    assert_eq!(view_person(&unfinished, 0).failure_text, "no station");

    let mut built = started(2);
    let person = view_person(&built, 0);
    place_at(&mut built, BuildingKind::Campfire, [person.x, person.y]);
    let fire = finish_build(&mut built);
    assert_eq!(fire.progress, BUILD_TICKS);
    let away = [person.x + 6.0, person.y];
    assert!(away[0] < 32.0);
    let person = view_person(&built, 0);
    assert_eq!(
        built.submit_move(0, person.generation, away[0], away[1]),
        QUEUED
    );
    for _ in 0..80 {
        built.step();
        if order_done(&built) {
            break;
        }
    }
    let stood = view_person(&built, 0);
    let dx = stood.x - fire.x;
    let dy = stood.y - fire.y;
    assert!(
        (dx * dx + dy * dy).sqrt() > STATION_RANGE_M,
        "the actor left station range"
    );
    let mut far = set_carried(&built, &[[ITEM_GRAIN.0, 1], [ITEM_WATER.0, 1]]);
    let person = view_person(&far, 0);
    assert_eq!(
        far.submit_craft(0, person.generation, RECIPE_MEAL.0),
        QUEUED
    );
    far.step();
    assert_eq!(view_person(&far, 0).failure_text, "no station");
    assert_eq!(far.view().buildings[0].progress, BUILD_TICKS);
}

#[test]
fn each_recipe_checks_inputs_tool_and_output_exactly() {
    assert_eq!(RECIPE_KNIFE_TICKS, 60);
    assert_eq!(RECIPE_MEAL_TICKS, 30);
    assert_eq!(RECIPE_BANDAGE_TICKS, 40);

    let mut knife = set_carried(&started(11), &[[ITEM_STONE.0, 1], [ITEM_WOOD.0, 2]]);
    let person = view_person(&knife, 0);
    assert_eq!(
        knife.submit_craft(0, person.generation, RECIPE_KNIFE.0),
        QUEUED
    );
    for _ in 0..RECIPE_KNIFE_TICKS - 1 {
        knife.step();
        assert_eq!(carried_of(&view_person(&knife, 0).carried, ITEM_KNIFE.0), 0);
        assert_eq!(view_person(&knife, 0).failure, -1);
    }
    knife.step();
    let made = view_person(&knife, 0);
    assert_eq!(made.failure, -1);
    assert!(
        knife.view().buildings.is_empty(),
        "a knife needs no station"
    );
    assert_eq!(carried_of(&made.carried, ITEM_KNIFE.0), 1);
    assert_eq!(carried_of(&made.carried, ITEM_STONE.0), 0);
    assert_eq!(carried_of(&made.carried, ITEM_WOOD.0), 1);

    let mut meal = started(11);
    let person = view_person(&meal, 0);
    place_at(&mut meal, BuildingKind::Campfire, [person.x, person.y]);
    finish_build(&mut meal);
    let meal = set_carried(&meal, &[[ITEM_GRAIN.0, 2], [ITEM_WATER.0, 1]]);
    let mut meal = meal;
    let person = view_person(&meal, 0);
    assert_eq!(
        meal.submit_craft(0, person.generation, RECIPE_MEAL.0),
        QUEUED
    );
    for _ in 0..RECIPE_MEAL_TICKS {
        meal.step();
    }
    let cooked = view_person(&meal, 0);
    assert_eq!(cooked.failure, -1);
    assert_eq!(carried_of(&cooked.carried, ITEM_MEAL.0), 1);
    assert_eq!(carried_of(&cooked.carried, ITEM_GRAIN.0), 1);
    assert_eq!(carried_of(&cooked.carried, ITEM_WATER.0), 0);

    let mut missing_fire = set_carried(&started(11), &[[ITEM_GRAIN.0, 1], [ITEM_WATER.0, 1]]);
    let person = view_person(&missing_fire, 0);
    assert_eq!(
        missing_fire.submit_craft(0, person.generation, RECIPE_MEAL.0),
        QUEUED
    );
    missing_fire.step();
    assert_eq!(view_person(&missing_fire, 0).failure_text, "no station");

    let mut shelter = started(11);
    let person = view_person(&shelter, 0);
    place_at(&mut shelter, BuildingKind::LeanTo, [person.x, person.y]);
    finish_build(&mut shelter);
    let ready = set_carried(
        &shelter,
        &[[ITEM_FIBER.0, 3], [ITEM_WATER.0, 1], [ITEM_KNIFE.0, 1]],
    );
    let mut bandage = ready;
    let person = view_person(&bandage, 0);
    assert_eq!(
        bandage.submit_craft(0, person.generation, RECIPE_BANDAGE.0),
        QUEUED
    );
    for _ in 0..RECIPE_BANDAGE_TICKS {
        bandage.step();
    }
    let wrapped = view_person(&bandage, 0);
    assert_eq!(wrapped.failure, -1);
    assert_eq!(carried_of(&wrapped.carried, ITEM_BANDAGE.0), 1);
    assert_eq!(carried_of(&wrapped.carried, ITEM_FIBER.0), 1);
    assert_eq!(carried_of(&wrapped.carried, ITEM_WATER.0), 0);
    assert_eq!(
        carried_of(&wrapped.carried, ITEM_KNIFE.0),
        1,
        "the knife is a tool"
    );

    let short = set_carried(
        &shelter,
        &[[ITEM_FIBER.0, 1], [ITEM_WATER.0, 1], [ITEM_KNIFE.0, 1]],
    );
    let mut short = short;
    let person = view_person(&short, 0);
    assert_eq!(
        short.submit_craft(0, person.generation, RECIPE_BANDAGE.0),
        QUEUED
    );
    short.step();
    assert_eq!(view_person(&short, 0).failure_text, "no material");

    let no_knife = set_carried(&shelter, &[[ITEM_FIBER.0, 2], [ITEM_WATER.0, 1]]);
    let mut no_knife = no_knife;
    let person = view_person(&no_knife, 0);
    assert_eq!(
        no_knife.submit_craft(0, person.generation, RECIPE_BANDAGE.0),
        QUEUED
    );
    no_knife.step();
    assert_eq!(view_person(&no_knife, 0).failure_text, "no material");

    let mut no_shelter = set_carried(
        &started(11),
        &[[ITEM_FIBER.0, 2], [ITEM_WATER.0, 1], [ITEM_KNIFE.0, 1]],
    );
    let person = view_person(&no_shelter, 0);
    assert_eq!(
        no_shelter.submit_craft(0, person.generation, RECIPE_BANDAGE.0),
        QUEUED
    );
    no_shelter.step();
    assert_eq!(view_person(&no_shelter, 0).failure_text, "no station");
}

#[test]
fn a_haul_that_fills_a_stockpile_leaves_a_part_load_without_failing() {
    assert_eq!(HAUL_TICKS_PER_UNIT, 5);
    assert_eq!(STOCKPILE_CAPACITY, 200);

    let mut sim = started(12);
    let person = view_person(&sim, 0);
    place_at(&mut sim, BuildingKind::Stockpile, [person.x, person.y]);
    let stock = finish_build(&mut sim);
    assert!(stock.contents.is_empty());
    let sim = edit(&sim, |value| {
        let slot = slot_mut(value, u64::from(stock.index));
        slot["contents"] = serde_json::json!([[ITEM_WOOD.0, 50], [ITEM_GRAIN.0, 149]]);
        slot["progress"] = serde_json::json!(BUILD_TICKS);
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_WOOD.0, 3]]);
    });
    let loaded = sim.view().buildings[0].clone();
    assert_eq!(
        loaded.contents,
        vec![[ITEM_GRAIN.0, 149], [ITEM_WOOD.0, 50]]
    );
    let mut sim = sim;
    let person = view_person(&sim, 0);
    assert_eq!(
        sim.submit_haul(
            0,
            person.generation,
            ITEM_WOOD.0,
            loaded.index,
            loaded.generation
        ),
        QUEUED
    );
    for _ in 0..4 {
        sim.step();
    }
    assert_eq!(
        sim.view().buildings[0].contents[1][1],
        50,
        "four ticks move nothing"
    );
    sim.step();
    let pile = &sim.view().buildings[0];
    assert_eq!(pile.contents, vec![[ITEM_GRAIN.0, 149], [ITEM_WOOD.0, 51]]);
    assert_eq!(
        pile.contents.iter().map(|pair| pair[1]).sum::<u32>(),
        STOCKPILE_CAPACITY
    );
    let holder = view_person(&sim, 0);
    assert_eq!(holder.failure, -1);
    assert_eq!(holder.failure_text, "");
    assert!(holder.dest.is_empty());
    assert_eq!(carried_of(&holder.carried, ITEM_WOOD.0), 2);
}

#[test]
fn a_haul_of_an_item_the_actor_does_not_carry_fails_no_material() {
    let mut sim = started(13);
    let person = view_person(&sim, 0);
    place_at(&mut sim, BuildingKind::Stockpile, [person.x, person.y]);
    let stock = finish_build(&mut sim);
    let person = view_person(&sim, 0);
    assert_eq!(carried_of(&person.carried, ITEM_STONE.0), 0);
    assert_eq!(
        sim.submit_haul(
            0,
            person.generation,
            ITEM_STONE.0,
            stock.index,
            stock.generation
        ),
        QUEUED
    );
    sim.step();
    let failed = view_person(&sim, 0);
    assert_eq!(failed.failure_text, "no material");
    assert_eq!(failed.failure, FailureReason::NoMaterial.discriminant());
    assert_eq!(carried_of(&failed.carried, ITEM_GRAIN.0), STARTING_GRAIN);
    assert!(sim.view().buildings[0].contents.is_empty());
}

#[test]
fn a_take_to_the_carry_cap_completes_and_a_take_of_none_fails_no_material() {
    assert_eq!(TAKE_TICKS_PER_UNIT, 3);
    assert_eq!(CARRY_CAP, 20);

    let mut sim = started(14);
    let person = view_person(&sim, 0);
    place_at(&mut sim, BuildingKind::Stockpile, [person.x, person.y]);
    let stock = finish_build(&mut sim);
    let sim = edit(&sim, |value| {
        slot_mut(value, u64::from(stock.index))["contents"] =
            serde_json::json!([[ITEM_WOOD.0, 10]]);
        slot_mut(value, u64::from(stock.index))["progress"] = serde_json::json!(BUILD_TICKS);
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_GRAIN.0, 19]]);
    });
    let mut sim = sim;
    let person = view_person(&sim, 0);
    assert_eq!(
        sim.submit_take(
            i64::from(person.index),
            i64::from(person.generation),
            i64::from(ITEM_WOOD.0),
            i64::from(stock.index),
            i64::from(stock.generation),
        ),
        i64::from(QUEUED)
    );
    for _ in 0..2 {
        sim.step();
    }
    assert_eq!(carried_of(&view_person(&sim, 0).carried, ITEM_WOOD.0), 0);
    sim.step();
    let capped = view_person(&sim, 0);
    assert_eq!(capped.failure, -1);
    assert!(capped.dest.is_empty());
    assert_eq!(carried_of(&capped.carried, ITEM_GRAIN.0), 19);
    assert_eq!(carried_of(&capped.carried, ITEM_WOOD.0), 1);
    assert_eq!(
        capped.carried.iter().map(|pair| pair[1]).sum::<u32>(),
        CARRY_CAP
    );
    assert_eq!(sim.view().buildings[0].contents, vec![[ITEM_WOOD.0, 9]]);

    let mut sim = started(14);
    let person = view_person(&sim, 0);
    place_at(&mut sim, BuildingKind::Stockpile, [person.x, person.y]);
    let stock = finish_build(&mut sim);
    let sim = edit(&sim, |value| {
        slot_mut(value, u64::from(stock.index))["contents"] =
            serde_json::json!([[ITEM_GRAIN.0, 4]]);
        slot_mut(value, u64::from(stock.index))["progress"] = serde_json::json!(BUILD_TICKS);
    });
    let mut sim = sim;
    let person = view_person(&sim, 0);
    assert_eq!(
        sim.submit_take(
            i64::from(person.index),
            i64::from(person.generation),
            i64::from(ITEM_WOOD.0),
            i64::from(stock.index),
            i64::from(stock.generation),
        ),
        0
    );
    sim.step();
    let failed = view_person(&sim, 0);
    assert_eq!(failed.failure_text, "no material");
    assert_eq!(sim.view().buildings[0].contents, vec![[ITEM_GRAIN.0, 4]]);
    assert_eq!(carried_of(&failed.carried, ITEM_WOOD.0), 0);

    assert_eq!(
        sim.submit_take(-1, 1, i64::from(ITEM_WOOD.0), i64::from(stock.index), 1),
        i64::from(STALE)
    );
    assert_eq!(
        sim.submit_take(
            i64::from(person.index),
            i64::from(person.generation),
            99,
            i64::from(stock.index),
            i64::from(stock.generation),
        ),
        i64::from(MALFORMED)
    );
}

#[test]
fn eating_a_meal_beats_raw_grain_and_water_restores_thirst_only() {
    assert_eq!(EAT_HUNGER_RESTORE, 0.35);
    assert_eq!(EAT_THIRST_RESTORE, 0.15);
    assert_eq!(MEAL_HUNGER_RESTORE, 0.75);
    assert_eq!(MEAL_THIRST_RESTORE, 0.30);
    assert_eq!(WATER_HUNGER_RESTORE, 0.0);
    assert_eq!(WATER_THIRST_RESTORE, 0.50);

    let grain = eat_from(0.20, 0.20, &[[ITEM_GRAIN.0, 1]], ITEM_GRAIN.0);
    let meal = eat_from(0.20, 0.20, &[[ITEM_MEAL.0, 1]], ITEM_MEAL.0);
    let water = eat_from(0.20, 0.20, &[[ITEM_WATER.0, 1]], ITEM_WATER.0);

    let grain_hunger = ((0.20 - HUNGER_PER_TICK).max(0.0) + EAT_HUNGER_RESTORE).min(1.0);
    let meal_hunger = ((0.20 - HUNGER_PER_TICK).max(0.0) + MEAL_HUNGER_RESTORE).min(1.0);
    let water_hunger = ((0.20 - HUNGER_PER_TICK).max(0.0) + WATER_HUNGER_RESTORE).min(1.0);
    let grain_thirst = ((0.20 - THIRST_PER_TICK).max(0.0) + EAT_THIRST_RESTORE).min(1.0);
    let meal_thirst = ((0.20 - THIRST_PER_TICK).max(0.0) + MEAL_THIRST_RESTORE).min(1.0);
    let water_thirst = ((0.20 - THIRST_PER_TICK).max(0.0) + WATER_THIRST_RESTORE).min(1.0);

    assert_eq!(grain.hunger.to_bits(), grain_hunger.to_bits());
    assert_eq!(meal.hunger.to_bits(), meal_hunger.to_bits());
    assert_eq!(water.hunger.to_bits(), water_hunger.to_bits());
    assert_eq!(grain.thirst.to_bits(), grain_thirst.to_bits());
    assert_eq!(meal.thirst.to_bits(), meal_thirst.to_bits());
    assert_eq!(water.thirst.to_bits(), water_thirst.to_bits());
    assert!(meal.hunger > grain.hunger);
    assert!(meal.thirst > grain.thirst);
    assert_eq!(water.hunger.to_bits(), water_hunger.to_bits());
    assert!(water.thirst > grain.thirst);
    assert!(grain.carried.is_empty());
    assert!(meal.carried.is_empty());
    assert!(water.carried.is_empty());
}

fn eat_from(
    hunger: f32,
    thirst: f32,
    carried: &[[u32; 2]],
    item: u32,
) -> latchsoil_sim::PersonView {
    let sim = edit(&started(5), |value| {
        let slot = slot_mut(value, 0);
        slot["hunger"] = serde_json::json!(hunger);
        slot["thirst"] = serde_json::json!(thirst);
        slot["carried"] = serde_json::json!(carried);
    });
    let mut sim = sim;
    let person = view_person(&sim, 0);
    assert_eq!(sim.submit_eat(0, person.generation, item), QUEUED);
    sim.step();
    let ate = view_person(&sim, 0);
    assert_eq!(ate.failure, -1, "{}", ate.failure_text);
    ate
}

#[test]
fn every_non_food_item_fails_no_material() {
    for item in [ITEM_WOOD, ITEM_STONE, ITEM_FIBER, ITEM_KNIFE, ITEM_BANDAGE] {
        let sim = set_carried(&started(6), &[[item.0, 1]]);
        let mut sim = sim;
        let person = view_person(&sim, 0);
        assert_eq!(sim.submit_eat(0, person.generation, item.0), QUEUED);
        sim.step();
        let failed = view_person(&sim, 0);
        assert_eq!(failed.failure_text, "no material", "{}", item.0);
        assert_eq!(failed.carried, vec![[item.0, 1]]);
        assert!(failed.hunger < 1.0);
    }
}

#[test]
fn a_version_1_save_is_migration_not_implemented() {
    assert_eq!(SAVE_VERSION, 2);
    let sim = started(1);
    let mut value: serde_json::Value = serde_json::from_str(&save_to_json(&sim)).unwrap();
    value["save_version"] = serde_json::json!(1);
    let err = load_from_json(&value.to_string()).unwrap_err();
    assert!(matches!(
        err,
        SaveError::MigrationNotImplemented { from: 1, to: 2 }
    ));
}

#[test]
fn a_version_2_save_round_trip_carries_buildings_progress_and_contents() {
    assert_eq!(SAVE_VERSION, 2);
    let first = scripted_holding(21);
    let second = scripted_holding(21);
    assert_eq!(first.state_hash(), second.state_hash());

    let stock = first
        .view()
        .buildings
        .iter()
        .find(|building| building.kind == BuildingKind::Stockpile.discriminant())
        .unwrap()
        .clone();
    let camp = first
        .view()
        .buildings
        .iter()
        .find(|building| building.kind == BuildingKind::Campfire.discriminant())
        .unwrap()
        .clone();
    assert_eq!(stock.progress, BUILD_TICKS);
    assert!(!stock.contents.is_empty());
    assert!(camp.progress > 0 && camp.progress < BUILD_TICKS);

    let json = save_to_json(&first);
    assert!(json.contains("\"progress\""));
    assert!(json.contains("\"contents\""));
    assert!(!json.contains("camera"));
    assert!(!json.contains("\"queue\""));
    let loaded = load_from_json(&json).unwrap();
    assert_eq!(loaded.state_hash(), first.state_hash());
    assert_eq!(loaded.view().buildings, first.view().buildings);
    assert_eq!(loaded.tick(), first.tick());
    assert_eq!(loaded.rng.state(), first.rng.state());

    let mut continued = loaded;
    let mut live = first;
    let person = view_person(&live, 0);
    live.submit_move(0, person.generation, person.x + 1.0, person.y);
    continued.submit_move(0, person.generation, person.x + 1.0, person.y);
    live.step();
    continued.step();
    assert_eq!(continued.state_hash(), live.state_hash());
}

fn scripted_holding(seed: u64) -> SimState {
    let mut sim = started(seed);
    let person = view_person(&sim, 0);
    let at = [person.x, person.y];
    place_at(&mut sim, BuildingKind::Stockpile, at);
    let stock = finish_build(&mut sim);
    let person = view_person(&sim, 0);
    assert_eq!(
        sim.submit_haul(
            0,
            person.generation,
            ITEM_GRAIN.0,
            stock.index,
            stock.generation
        ),
        QUEUED
    );
    for _ in 0..80 {
        sim.step();
        if order_done(&sim) {
            break;
        }
    }
    assert!(
        !sim.view().buildings[0].contents.is_empty(),
        "hauled grain is in the stockpile"
    );
    let person = view_person(&sim, 0);
    let camp = adjacent_cell([person.x, person.y]);
    place_at(&mut sim, BuildingKind::Campfire, camp);
    for _ in 0..8 {
        sim.step();
    }
    sim
}
