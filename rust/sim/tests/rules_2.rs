//! Milestone 2 rules. Headless. No Godot process.
//!
//! Each threshold is the sim constant, asserted beside the test that names it.
//! Wounds are written into the save: nothing in this milestone wounds a person.

use latchsoil_sim::{
    load_from_json, night_at, save_to_json, scaled_work_ticks, BuildingKind, Command, EntityId,
    FailureReason, ItemId, JobKind, RecipeId, RegionKind, SaveError, SimState, AMBIENT_WARMTH_DAY,
    AMBIENT_WARMTH_NIGHT, BLEED_HEALTH_PER_TICK, BUILD_TICKS, COLD_HEALTH_PER_TICK,
    FATIGUE_PER_TICK, FATIGUE_REFUSAL, FATIGUE_WORK_MULTIPLIER, GATHER_TICKS_PER_UNIT,
    GATHER_TOOL_RELIEF, HEAL_TICKS, INFECTION_HEALTH_PER_TICK, INFECTION_PER_TICK, INFECTION_SICK,
    ITEM_BANDAGE, ITEM_FIBER, ITEM_KNIFE, ITEM_SALVE, ITEM_STONE, ITEM_WATER, ITEM_WOOD,
    LEANTO_WARMTH, MALFORMED, MEDICINE_SKILL_MIN, NIGHT_START_TICK, PEG_X, PEG_Y, QUEUED,
    RECIPE_SALVE, RECIPE_SALVE_TICKS, SALVE_INFECTION_CUT, SAVE_VERSION, SKILL_BUILD, SKILL_CRAFT,
    SKILL_GATHER, SKILL_MEDICINE, SKILL_PER_UNIT, SKILL_TIME_RELIEF, SLEEP_RECOVER_PER_TICK, STALE,
    STATION_RANGE_M, TICKS_PER_DAY, WARMTH_DRIFT_PER_TICK, WARMTH_RANGE_M,
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

fn actor(sim: &SimState, index: u32) -> EntityId {
    let person = view_person(sim, index);
    EntityId {
        index: person.index,
        generation: person.generation,
    }
}

fn dist(a: [f32; 2], b: [f32; 2]) -> f32 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    (dx * dx + dy * dy).sqrt()
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

fn set_region(
    sim: &SimState,
    person: u64,
    region: usize,
    bleeding: f32,
    infected: f32,
    bandaged: bool,
    treated: bool,
) -> SimState {
    edit(sim, |value| {
        let region = &mut slot_mut(value, person)["regions"][region];
        region["bleeding"] = serde_json::json!(bleeding);
        region["infected"] = serde_json::json!(infected);
        region["bandaged"] = serde_json::json!(bandaged);
        region["treated"] = serde_json::json!(treated);
    })
}

fn close(a: f32, b: f32) -> bool {
    (a - b).abs() < 1e-3
}

fn at_night(sim: &SimState, warmth: f32) -> SimState {
    edit(sim, |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        let slot = slot_mut(value, 0);
        slot["warmth"] = serde_json::json!(warmth);
        slot["health"] = serde_json::json!(1.0);
        slot["hunger"] = serde_json::json!(1.0);
        slot["thirst"] = serde_json::json!(1.0);
    })
}

fn place_finished(sim: &mut SimState, kind: BuildingKind, at: [f32; 2]) -> u32 {
    let person = view_person(sim, 0);
    assert_eq!(
        sim.submit_place(0, person.generation, kind.discriminant(), at[0], at[1]),
        QUEUED
    );
    for _ in 0..BUILD_TICKS + 80 {
        sim.step();
        let done = sim.view().buildings.iter().any(|building| {
            building.kind == kind.discriminant() && building.progress >= BUILD_TICKS
        });
        if done && view_person(sim, 0).dest.is_empty() {
            break;
        }
    }
    sim.view()
        .buildings
        .into_iter()
        .find(|building| building.kind == kind.discriminant() && building.progress >= BUILD_TICKS)
        .expect("finished building")
        .index
}

/// One metre further from the peg, so the cell is free and not the peg itself.
fn step_away(at: [f32; 2]) -> [f32; 2] {
    if at[0] != PEG_X {
        let dx = if at[0] >= PEG_X { 1.0 } else { -1.0 };
        [at[0] + dx, at[1]]
    } else {
        let dy = if at[1] >= PEG_Y { 1.0 } else { -1.0 };
        [at[0], at[1] + dy]
    }
}

fn reaches_during_night(sim: &mut SimState, warmth: f32) -> bool {
    while night_at(sim.tick()) {
        sim.step();
        if view_person(sim, 0).warmth.to_bits() == warmth.to_bits() {
            return true;
        }
    }
    false
}

#[test]
fn a_bleeding_wound_empties_health_in_one_day_and_a_bandage_stops_it() {
    assert_eq!(BLEED_HEALTH_PER_TICK, 1.0 / 7_200.0);
    assert_eq!(TICKS_PER_DAY, 7_200);

    let mut open = set_region(
        &started(2),
        0,
        RegionKind::Torso.discriminant() as usize,
        1.0,
        0.0,
        false,
        false,
    );
    let half = {
        let mut mid = open.clone();
        for _ in 0..TICKS_PER_DAY / 2 {
            mid.step();
        }
        view_person(&mid, 0).health
    };
    assert!(
        half > 0.4,
        "halfway through the day the wound has not emptied health, got {half}"
    );
    for _ in 0..TICKS_PER_DAY {
        open.step();
    }
    let emptied = view_person(&open, 0);
    assert!(
        emptied.health < 1e-3,
        "a wound at bleeding 1.0 empties health in one day, got {}",
        emptied.health
    );

    let stacked = set_region(
        &set_region(&started(2), 0, 0, 1.0, 0.0, false, false),
        0,
        1,
        1.0,
        0.0,
        false,
        false,
    );
    let mut stacked = stacked;
    stacked.step();
    let dropped = view_person(&stacked, 0).health;
    assert!(
        close(dropped, 1.0 - 2.0 * BLEED_HEALTH_PER_TICK),
        "two bleeding regions add, got {dropped}"
    );

    let mut bandaged = set_region(&started(3), 0, 1, 1.0, 0.0, false, false);
    bandaged = edit(&bandaged, |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_BANDAGE.0, 1]]);
    });
    let person = view_person(&bandaged, 0);
    assert_eq!(
        bandaged.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_BANDAGE.0)
        ),
        i64::from(QUEUED)
    );
    for _ in 0..HEAL_TICKS {
        bandaged.step();
    }
    let stopped = view_person(&bandaged, 0);
    assert_eq!(stopped.failure, -1, "{}", stopped.failure_text);
    assert!(stopped.regions[1].bandaged);
    assert_eq!(stopped.regions[1].bleeding, 0.0);
    assert_eq!(carried_of(&stopped.carried, ITEM_BANDAGE.0), 0);
    let held = stopped.health;
    assert!(
        held > 0.9,
        "the bandage landed before the day emptied them, got {held}"
    );
    for _ in 0..500 {
        bandaged.step();
    }
    let later = view_person(&bandaged, 0).health;
    assert!(
        close(later, held),
        "bleeding stopped, so health holds, {held} then {later}"
    );
}

#[test]
fn bandaging_needs_no_skill_but_a_salve_below_medicine_min_fails_no_skill() {
    assert_eq!(MEDICINE_SKILL_MIN, 0.25);
    assert_eq!(SALVE_INFECTION_CUT, 0.5);
    assert_eq!(ITEM_SALVE, ItemId(8));
    assert_eq!(RECIPE_SALVE, RecipeId(3));
    assert_eq!(RECIPE_SALVE_TICKS, 40);
    let catalog = started(1).catalog();
    assert_eq!(catalog.items[8].name, "salve");
    assert_eq!(catalog.recipes[3].name, "salve");

    let mut bandage = set_region(&started(4), 0, 2, 0.4, 0.0, false, false);
    bandage = edit(&bandage, |value| {
        let slot = slot_mut(value, 0);
        slot["carried"] = serde_json::json!([[ITEM_BANDAGE.0, 1]]);
        slot["skills"] = serde_json::json!([0.0, 0.0, 0.0, 0.0]);
    });
    let person = view_person(&bandage, 0);
    assert_eq!(person.skills[SKILL_MEDICINE], 0.0);
    assert_eq!(
        bandage.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_BANDAGE.0)
        ),
        i64::from(QUEUED)
    );
    for _ in 0..HEAL_TICKS {
        bandage.step();
    }
    let tied = view_person(&bandage, 0);
    assert_eq!(tied.failure, -1, "{}", tied.failure_text);
    assert!(
        tied.regions[2].bandaged,
        "bandaging needs no medicine skill"
    );
    assert_eq!(tied.regions[2].bleeding, 0.0);

    let mut unskilled = set_region(&started(4), 0, 2, 0.0, 0.4, false, false);
    unskilled = edit(&unskilled, |value| {
        let slot = slot_mut(value, 0);
        slot["carried"] = serde_json::json!([[ITEM_SALVE.0, 1]]);
        slot["skills"] = serde_json::json!([0.0, 0.0, 0.0, 0.0]);
    });
    let person = view_person(&unskilled, 0);
    assert_eq!(
        unskilled.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_SALVE.0)
        ),
        i64::from(QUEUED)
    );
    unskilled.step();
    let refused = view_person(&unskilled, 0);
    assert_eq!(refused.failure_text, "no skill");
    assert_eq!(refused.failure, FailureReason::NoSkill.discriminant());
    assert_eq!(carried_of(&refused.carried, ITEM_SALVE.0), 1);
    assert!(close(refused.regions[2].infected, 0.4));

    let mut skilled = set_region(&started(4), 0, 2, 0.0, 0.4, false, false);
    skilled = edit(&skilled, |value| {
        let slot = slot_mut(value, 0);
        slot["carried"] = serde_json::json!([[ITEM_SALVE.0, 1]]);
        slot["skills"] = serde_json::json!([0.0, 0.0, 0.0, MEDICINE_SKILL_MIN]);
    });
    let person = view_person(&skilled, 0);
    assert!(person.skills[SKILL_MEDICINE] >= MEDICINE_SKILL_MIN);
    assert_eq!(
        skilled.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_SALVE.0)
        ),
        i64::from(QUEUED)
    );
    for _ in 0..HEAL_TICKS {
        skilled.step();
        if carried_of(&view_person(&skilled, 0).carried, ITEM_SALVE.0) == 0 {
            break;
        }
    }
    let treated = view_person(&skilled, 0);
    assert_eq!(treated.failure, -1, "{}", treated.failure_text);
    assert!(treated.regions[2].treated);
    assert!(
        treated.regions[2].infected < 1e-4,
        "the cut is clamped at 0, got {}",
        treated.regions[2].infected
    );
    assert_eq!(carried_of(&treated.carried, ITEM_SALVE.0), 0);

    let mut above = set_region(&started(4), 0, 0, 0.0, 0.8, false, false);
    above = edit(&above, |value| {
        let healer = slot_mut(value, 1);
        healer["carried"] = serde_json::json!([[ITEM_SALVE.0, 1]]);
        healer["skills"] = serde_json::json!([0.0, 0.0, 0.0, 0.5]);
    });
    let healer = view_person(&above, 1);
    let patient = view_person(&above, 0);
    assert_eq!(
        above.submit_heal(
            i64::from(healer.index),
            i64::from(healer.generation),
            i64::from(patient.index),
            i64::from(patient.generation),
            i64::from(ITEM_SALVE.0)
        ),
        i64::from(QUEUED)
    );
    for _ in 0..HEAL_TICKS + 200 {
        above.step();
        if carried_of(&view_person(&above, 1).carried, ITEM_SALVE.0) == 0 {
            break;
        }
    }
    let cut = view_person(&above, 0).regions[0].infected;
    assert!(
        (cut - (0.8 - SALVE_INFECTION_CUT)).abs() < 0.02,
        "a salve at or above medicine min cuts infection, got {cut}"
    );
    assert!(view_person(&above, 0).regions[0].treated);

    let mut camp = started(9);
    let person = view_person(&camp, 0);
    assert_eq!(
        camp.submit_place(
            0,
            person.generation,
            BuildingKind::Campfire.discriminant(),
            person.x,
            person.y
        ),
        QUEUED
    );
    for _ in 0..BUILD_TICKS + 5 {
        camp.step();
        if camp
            .view()
            .buildings
            .first()
            .is_some_and(|building| building.progress >= BUILD_TICKS)
        {
            break;
        }
    }
    let low = edit(&camp, |value| {
        let slot = slot_mut(value, 0);
        slot["carried"] = serde_json::json!([[ITEM_FIBER.0, 1], [ITEM_WATER.0, 1]]);
        slot["skills"] = serde_json::json!([0.0, 0.0, 0.0, 0.0]);
    });
    let mut low = low;
    let person = view_person(&low, 0);
    assert_eq!(
        low.submit_craft(0, person.generation, RECIPE_SALVE.0),
        QUEUED
    );
    low.step();
    assert_eq!(view_person(&low, 0).failure_text, "no skill");
    assert_eq!(carried_of(&view_person(&low, 0).carried, ITEM_FIBER.0), 1);

    let ready = edit(&camp, |value| {
        let slot = slot_mut(value, 0);
        slot["carried"] = serde_json::json!([[ITEM_FIBER.0, 1], [ITEM_WATER.0, 1]]);
        slot["skills"] = serde_json::json!([0.0, 0.0, 0.0, MEDICINE_SKILL_MIN]);
    });
    let mut ready = ready;
    let person = view_person(&ready, 0);
    assert_eq!(
        ready.submit_craft(0, person.generation, RECIPE_SALVE.0),
        QUEUED
    );
    for _ in 0..RECIPE_SALVE_TICKS {
        ready.step();
    }
    let made = view_person(&ready, 0);
    assert_eq!(made.failure, -1, "{}", made.failure_text);
    assert_eq!(carried_of(&made.carried, ITEM_SALVE.0), 1);
    assert_eq!(carried_of(&made.carried, ITEM_FIBER.0), 0);
    assert_eq!(carried_of(&made.carried, ITEM_WATER.0), 0);
}

#[test]
fn a_neglected_wound_reaches_infection_sick_and_a_bandaged_one_takes_ten_times_as_long() {
    assert_eq!(INFECTION_PER_TICK, 1.0 / 28_800.0);
    assert_eq!(INFECTION_SICK, 0.5);
    assert_eq!(INFECTION_HEALTH_PER_TICK, 1.0 / 14_400.0);
    // 1/28800 reaches 0.5 in two days and 1.0 in four. The sentence "0.5 in four
    // days" does not match the listed constant; the test follows the constant.
    let ticks_to_sick = (INFECTION_SICK / INFECTION_PER_TICK).round() as u64;
    assert_eq!(ticks_to_sick, 14_400);
    assert_eq!(ticks_to_sick, 2 * TICKS_PER_DAY);

    let mut neglected = set_region(&started(6), 0, 0, 0.0, 0.0, false, false);
    neglected = edit(&neglected, |value| {
        slot_mut(value, 0)["regions"][0]["health"] = serde_json::json!(0.5);
    });
    for _ in 0..ticks_to_sick {
        neglected.step();
    }
    let sick = view_person(&neglected, 0);
    assert!(
        sick.regions[0].infected + 1e-3 >= INFECTION_SICK,
        "neglected infected {} after {} ticks",
        sick.regions[0].infected,
        ticks_to_sick
    );

    let mut draining = set_region(&started(6), 0, 1, 0.0, INFECTION_SICK, false, false);
    let before = view_person(&draining, 0).health;
    draining.step();
    let after = view_person(&draining, 0).health;
    assert!(
        close(before - after, INFECTION_HEALTH_PER_TICK),
        "at infection sick, health drains by the infection rate, {before} to {after}"
    );

    let mut refuse = set_region(&started(6), 0, 1, 0.0, INFECTION_SICK, false, false);
    let patient = view_person(&refuse, 0);
    assert_eq!(
        refuse.submit(Command::Move {
            actor: actor(&refuse, 0),
            to: [patient.x + 1.0, patient.y],
        }),
        QUEUED
    );
    let refused = view_person(&refuse, 0);
    assert_eq!(refused.failure_text, "wounded");
    assert_eq!(refused.failure, FailureReason::Wounded.discriminant());
    assert!(refused.path.is_empty(), "the refused order does not start");

    let mut bandaged = set_region(&started(6), 0, 0, 0.0, 0.0, true, false);
    let sample = 2_000u64;
    let mut neglected_rate = set_region(&started(6), 0, 0, 1.0, 0.0, false, false);
    for _ in 0..sample {
        neglected_rate.step();
        bandaged.step();
    }
    let open = view_person(&neglected_rate, 0).regions[0].infected;
    let wrapped = view_person(&bandaged, 0).regions[0].infected;
    assert!(
        close(open, wrapped * 10.0) || (open / wrapped - 10.0).abs() < 0.05,
        "bandaged infection {wrapped} should be a tenth of neglected {open}"
    );

    let mut slow = set_region(&started(7), 0, 3, 0.0, 0.0, true, false);
    for _ in 0..ticks_to_sick * 10 {
        slow.step();
    }
    let late = view_person(&slow, 0).regions[3].infected;
    assert!(
        late + 1e-2 >= INFECTION_SICK,
        "a bandaged wound reaches infection sick in ten times as many ticks, got {late}"
    );
}

#[test]
fn warmth_drifts_to_ambient_a_campfire_holds_it_and_zero_warmth_drains_health() {
    assert_eq!(AMBIENT_WARMTH_DAY, 0.9);
    assert_eq!(AMBIENT_WARMTH_NIGHT, 0.0);
    assert_eq!(WARMTH_DRIFT_PER_TICK, 1.0 / 1_200.0);
    assert_eq!(WARMTH_RANGE_M, 3.0);
    assert_eq!(COLD_HEALTH_PER_TICK, 1.0 / 3_600.0);

    let mut day = started(8);
    assert_eq!(view_person(&day, 0).warmth.to_bits(), 1.0f32.to_bits());
    for _ in 0..300 {
        day.step();
    }
    let day_warmth = view_person(&day, 0).warmth;
    assert!(
        close(day_warmth, AMBIENT_WARMTH_DAY),
        "day warmth drifts to {AMBIENT_WARMTH_DAY}, got {day_warmth}"
    );
    day.step();
    assert!(close(view_person(&day, 0).warmth, AMBIENT_WARMTH_DAY));

    let night = edit(&started(8), |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
    });
    assert!(night_at(night.tick()));
    let mut night = night;
    for _ in 0..300 {
        night.step();
    }
    let night_warmth = view_person(&night, 0).warmth;
    assert!(
        night_warmth < AMBIENT_WARMTH_DAY - 0.01,
        "night keeps drifting past the day target, got {night_warmth}"
    );
    assert!(night_warmth > AMBIENT_WARMTH_NIGHT);

    let mut fire = started(8);
    let person = view_person(&fire, 0);
    assert_eq!(
        fire.submit_place(
            0,
            person.generation,
            BuildingKind::Campfire.discriminant(),
            person.x,
            person.y
        ),
        QUEUED
    );
    for _ in 0..BUILD_TICKS + 5 {
        fire.step();
        if fire
            .view()
            .buildings
            .first()
            .is_some_and(|building| building.progress >= BUILD_TICKS)
        {
            break;
        }
    }
    let fire_id = fire.view().buildings[0].index;
    let held = edit(&fire, |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        slot_mut(value, 0)["warmth"] = serde_json::json!(1.0);
    });
    let mut held = held;
    for _ in 0..200 {
        held.step();
    }
    assert_eq!(
        view_person(&held, 0).warmth.to_bits(),
        1.0f32.to_bits(),
        "a finished campfire holds warmth at 1.0"
    );

    let cold_fire = edit(&fire, |value| {
        slot_mut(value, u64::from(fire_id))["progress"] = serde_json::json!(0);
        slot_mut(value, 0)["warmth"] = serde_json::json!(1.0);
    });
    let mut cold_fire = cold_fire;
    cold_fire.step();
    assert!(
        view_person(&cold_fire, 0).warmth < 1.0,
        "an unfinished campfire is not a fire"
    );

    let person = view_person(&fire, 0);
    let in_range = edit(&fire, |value| {
        value["tick"] = serde_json::json!(0);
        let slot = slot_mut(value, 0);
        slot["x"] = serde_json::json!(10.0);
        slot["y"] = serde_json::json!(16.0);
        slot["warmth"] = serde_json::json!(1.0);
        let site = slot_mut(value, u64::from(fire_id));
        site["x"] = serde_json::json!(10.0 + WARMTH_RANGE_M);
        site["y"] = serde_json::json!(16.0);
        site["progress"] = serde_json::json!(BUILD_TICKS);
    });
    let mut in_range = in_range;
    in_range.step();
    assert_eq!(view_person(&in_range, 0).warmth.to_bits(), 1.0f32.to_bits());
    let _ = person;

    let out_of_range = edit(&fire, |value| {
        let slot = slot_mut(value, 0);
        slot["x"] = serde_json::json!(10.0);
        slot["y"] = serde_json::json!(16.0);
        slot["warmth"] = serde_json::json!(1.0);
        let site = slot_mut(value, u64::from(fire_id));
        site["x"] = serde_json::json!(10.0 + WARMTH_RANGE_M + 0.5);
        site["y"] = serde_json::json!(16.0);
    });
    let mut out_of_range = out_of_range;
    out_of_range.step();
    assert!(view_person(&out_of_range, 0).warmth < 1.0);

    let freezing = edit(&started(8), |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        let slot = slot_mut(value, 0);
        slot["warmth"] = serde_json::json!(0.0);
        slot["health"] = serde_json::json!(1.0);
        slot["hunger"] = serde_json::json!(1.0);
        slot["thirst"] = serde_json::json!(1.0);
    });
    let mut freezing = freezing;
    freezing.step();
    let chilled = view_person(&freezing, 0);
    assert!(
        close(chilled.health, 1.0 - COLD_HEALTH_PER_TICK),
        "zero warmth drains health at the cold rate, got {}",
        chilled.health
    );
    assert_eq!(
        chilled.warmth.to_bits(),
        0.0f32.to_bits(),
        "at night in the open, zero warmth stays on the night target"
    );

    let mut day_freeze = edit(&started(8), |value| {
        value["tick"] = serde_json::json!(0);
        let slot = slot_mut(value, 0);
        slot["warmth"] = serde_json::json!(0.0);
        slot["health"] = serde_json::json!(1.0);
        slot["hunger"] = serde_json::json!(1.0);
        slot["thirst"] = serde_json::json!(1.0);
    });
    day_freeze.step();
    let thawed = view_person(&day_freeze, 0);
    assert!(
        close(thawed.health, 1.0 - COLD_HEALTH_PER_TICK),
        "zero warmth still pays the cold cost when the day target is higher, got {}",
        thawed.health
    );
    assert!(
        thawed.warmth > 0.0,
        "the tick pays the cost and then leaves zero toward the day target"
    );
}

#[test]
fn in_ordinary_play_an_open_night_reaches_zero_warmth_and_health_falls() {
    let mut sim = started(20);
    assert_eq!(sim.tick(), 0);
    assert!(!night_at(sim.tick()));
    assert_eq!(view_person(&sim, 0).warmth.to_bits(), 1.0f32.to_bits());
    assert_eq!(view_person(&sim, 0).health.to_bits(), 1.0f32.to_bits());

    while !night_at(sim.tick()) {
        sim.step();
    }
    let night_began = sim.tick();
    let at_dusk = view_person(&sim, 0);
    let health_before = at_dusk.health;
    assert_eq!(night_began, NIGHT_START_TICK);
    assert!(
        close(at_dusk.warmth, AMBIENT_WARMTH_DAY),
        "ordinary play enters the night at day ambient, got {}",
        at_dusk.warmth
    );
    assert!(at_dusk.warmth > 0.0);

    let mut zero_at = None;
    let mut ticks_at_zero = 0u64;
    while night_at(sim.tick()) {
        if view_person(&sim, 0).warmth <= 0.0 {
            ticks_at_zero += 1;
        }
        sim.step();
        if zero_at.is_none() && view_person(&sim, 0).warmth <= 0.0 {
            zero_at = Some(sim.tick());
        }
    }
    let health_after = view_person(&sim, 0).health;
    let warmth_after = view_person(&sim, 0).warmth;
    let zero_at = zero_at.unwrap_or(u64::MAX);
    let drop = health_before - health_after;
    let expected = COLD_HEALTH_PER_TICK * (ticks_at_zero as f32);
    let arithmetic = format!(
        "night began at {night_began}, warmth reached 0.0 at {zero_at}, health {health_before} -> {health_after}, drop {drop} against {ticks_at_zero} ticks at zero * {COLD_HEALTH_PER_TICK} = {expected}"
    );
    assert!(
        zero_at > night_began && zero_at <= night_began + (TICKS_PER_DAY - NIGHT_START_TICK),
        "warmth did not reach 0.0 during the night (ended at {warmth_after}); {arithmetic}"
    );
    assert_eq!(
        warmth_after.to_bits(),
        0.0f32.to_bits(),
        "open night did not stay on 0.0; {arithmetic}"
    );
    assert!(
        ticks_at_zero > 0,
        "warmth reached 0.0 with no night tick left to pay the cold cost; {arithmetic}"
    );
    assert!(
        (drop - expected).abs() < 1e-4,
        "health did not fall by the cold rate times the ticks spent at zero; {arithmetic}"
    );
    eprintln!("{arithmetic}");
}

#[test]
fn beside_a_finished_lean_to_warmth_settles_at_lean_to_warmth_and_takes_no_cold_damage() {
    assert_eq!(LEANTO_WARMTH, 0.6);

    let mut shelter = started(21);
    let person = view_person(&shelter, 0);
    let lean_id = place_finished(&mut shelter, BuildingKind::LeanTo, [person.x, person.y]);

    let mut night = at_night(&shelter, 1.0);
    assert!(
        reaches_during_night(&mut night, LEANTO_WARMTH),
        "lean-to night warmth settled at {}, not {LEANTO_WARMTH}",
        view_person(&night, 0).warmth
    );
    assert_eq!(view_person(&night, 0).health.to_bits(), 1.0f32.to_bits());
    while night_at(night.tick()) {
        night.step();
    }
    let stayed = view_person(&night, 0);
    assert_eq!(stayed.warmth.to_bits(), LEANTO_WARMTH.to_bits());
    assert_eq!(
        stayed.health.to_bits(),
        1.0f32.to_bits(),
        "shelter at {LEANTO_WARMTH} is above freezing, so the night costs no health"
    );

    let unfinished = edit(&shelter, |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        slot_mut(value, u64::from(lean_id))["progress"] = serde_json::json!(0);
        slot_mut(value, 0)["warmth"] = serde_json::json!(0.5);
    });
    let mut unfinished = unfinished;
    unfinished.step();
    assert!(
        view_person(&unfinished, 0).warmth < 0.5,
        "an unfinished lean-to is not shelter"
    );

    let outside = edit(&shelter, |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        let slot = slot_mut(value, 0);
        slot["x"] = serde_json::json!(10.0);
        slot["y"] = serde_json::json!(16.0);
        slot["warmth"] = serde_json::json!(0.5);
        let site = slot_mut(value, u64::from(lean_id));
        site["x"] = serde_json::json!(10.0 + STATION_RANGE_M + 0.5);
        site["y"] = serde_json::json!(16.0);
        site["progress"] = serde_json::json!(BUILD_TICKS);
    });
    let mut outside = outside;
    outside.step();
    assert!(
        view_person(&outside, 0).warmth < 0.5,
        "a lean-to outside station range does not raise the night target"
    );

    let edge = edit(&shelter, |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        let slot = slot_mut(value, 0);
        slot["x"] = serde_json::json!(10.0);
        slot["y"] = serde_json::json!(16.0);
        slot["warmth"] = serde_json::json!(0.5);
        let site = slot_mut(value, u64::from(lean_id));
        site["x"] = serde_json::json!(10.0 + STATION_RANGE_M);
        site["y"] = serde_json::json!(16.0);
        site["progress"] = serde_json::json!(BUILD_TICKS);
    });
    let mut edge = edge;
    edge.step();
    assert!(
        view_person(&edge, 0).warmth > 0.5,
        "a finished lean-to at station range raises the night target"
    );

    let day = edit(&shelter, |value| {
        value["tick"] = serde_json::json!(0);
        slot_mut(value, 0)["warmth"] = serde_json::json!(LEANTO_WARMTH);
    });
    let mut day = day;
    let before = view_person(&day, 0).warmth;
    day.step();
    let after = view_person(&day, 0).warmth;
    assert!(
        (after - (before + WARMTH_DRIFT_PER_TICK)).abs() < 1e-4,
        "day target stays ambient day even beside a lean-to, {before} -> {after}"
    );
}

#[test]
fn beside_a_finished_campfire_the_warmth_target_is_one() {
    let mut fire = started(22);
    let person = view_person(&fire, 0);
    place_finished(&mut fire, BuildingKind::Campfire, [person.x, person.y]);
    let mut night = at_night(&fire, 0.5);
    assert!(
        reaches_during_night(&mut night, 1.0),
        "campfire night warmth settled at {}, not 1.0",
        view_person(&night, 0).warmth
    );
    assert!(night_at(night.tick()));
    night.step();
    let held = view_person(&night, 0);
    assert_eq!(held.warmth.to_bits(), 1.0f32.to_bits());
    assert_eq!(held.health.to_bits(), 1.0f32.to_bits());
}

#[test]
fn with_a_lean_to_and_a_campfire_in_range_the_campfire_wins() {
    let mut sim = started(23);
    let person = view_person(&sim, 0);
    let lean_at = [person.x, person.y];
    let lean_id = place_finished(&mut sim, BuildingKind::LeanTo, lean_at);
    let fire_at = step_away(lean_at);
    let fire_id = place_finished(&mut sim, BuildingKind::Campfire, fire_at);
    let stood = view_person(&sim, 0);
    assert!(
        dist([stood.x, stood.y], lean_at) <= STATION_RANGE_M,
        "person left the lean-to"
    );
    assert!(
        dist([stood.x, stood.y], fire_at) <= WARMTH_RANGE_M,
        "person left the campfire"
    );
    assert!(sim
        .view()
        .buildings
        .iter()
        .any(|building| building.index == lean_id && building.progress >= BUILD_TICKS));

    let mut night = at_night(&sim, 0.5);
    assert!(
        reaches_during_night(&mut night, 1.0),
        "with both in range warmth settled at {}, campfire should win at 1.0",
        view_person(&night, 0).warmth
    );
    assert!(view_person(&night, 0).warmth > LEANTO_WARMTH);

    let shelter_only = edit(&sim, |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        slot_mut(value, 0)["warmth"] = serde_json::json!(0.75);
        let site = slot_mut(value, u64::from(fire_id));
        site["x"] = serde_json::json!(stood.x + WARMTH_RANGE_M + 1.0);
        site["y"] = serde_json::json!(stood.y);
    });
    let mut shelter_only = shelter_only;
    let before = view_person(&shelter_only, 0).warmth;
    shelter_only.step();
    assert!(
        view_person(&shelter_only, 0).warmth < before,
        "a campfire outside warmth range does not beat the lean-to"
    );
}

#[test]
fn fatigue_rises_faster_while_working_refuses_above_the_threshold_and_rest_clears_it() {
    assert_eq!(FATIGUE_PER_TICK, 1.0 / 28_800.0);
    assert_eq!(FATIGUE_WORK_MULTIPLIER, 3.0);
    assert_eq!(FATIGUE_REFUSAL, 0.85);
    assert_eq!(SLEEP_RECOVER_PER_TICK, 1.0 / 2_400.0);
    assert_eq!(JobKind::Rest.discriminant(), 7);
    assert_eq!(FailureReason::Tired.as_str(), "tired");
    assert_eq!(FailureReason::Tired.discriminant(), 8);
    assert_eq!(
        FailureReason::from_discriminant(8),
        Some(FailureReason::Tired)
    );

    let mut working = started(10);
    let idle = working.clone();
    let person = view_person(&working, 0);
    assert_eq!(
        working.submit_move(0, person.generation, 30.0, 30.0),
        QUEUED
    );
    let mut idle = idle;
    for _ in 0..40 {
        working.step();
        idle.step();
    }
    let worked = view_person(&working, 0).fatigue;
    let rested = view_person(&idle, 1).fatigue;
    let walker = view_person(&working, 0).fatigue;
    let stood = view_person(&idle, 0).fatigue;
    assert!(
        walker > stood * 2.5,
        "working {walker} should outpace idle {stood}"
    );
    assert!(
        (walker / stood - FATIGUE_WORK_MULTIPLIER).abs() < 0.05,
        "working fatigue {walker} vs idle {stood}"
    );
    let _ = (worked, rested);

    let tired = edit(&started(10), |value| {
        slot_mut(value, 0)["fatigue"] = serde_json::json!(0.9);
    });
    let mut tired = tired;
    let person = view_person(&tired, 0);
    assert!(person.fatigue > FATIGUE_REFUSAL);
    assert_eq!(
        tired.submit_move(0, person.generation, person.x + 2.0, person.y),
        QUEUED
    );
    let refused = view_person(&tired, 0);
    assert_eq!(refused.failure_text, "tired");
    assert_eq!(refused.failure, FailureReason::Tired.discriminant());
    assert!(refused.path.is_empty());

    let fresh = edit(&started(10), |value| {
        slot_mut(value, 0)["fatigue"] = serde_json::json!(FATIGUE_REFUSAL);
    });
    let mut fresh = fresh;
    let person = view_person(&fresh, 0);
    assert_eq!(
        fresh.submit_move(0, person.generation, person.x + 2.0, person.y),
        QUEUED
    );
    fresh.step();
    let accepted = view_person(&fresh, 0);
    assert_eq!(
        accepted.failure, -1,
        "fatigue at the threshold is not above it"
    );
    assert!(!accepted.path.is_empty() || accepted.x != person.x);

    let mut shelter = started(11);
    let person = view_person(&shelter, 0);
    assert_eq!(
        shelter.submit_place(
            0,
            person.generation,
            BuildingKind::LeanTo.discriminant(),
            person.x,
            person.y
        ),
        QUEUED
    );
    for _ in 0..BUILD_TICKS + 20 {
        shelter.step();
        if shelter
            .view()
            .buildings
            .first()
            .is_some_and(|building| building.progress >= BUILD_TICKS)
            && view_person(&shelter, 0).dest.is_empty()
        {
            break;
        }
    }
    assert!(shelter.view().buildings[0].progress >= BUILD_TICKS);
    let sheltered = edit(&shelter, |value| {
        slot_mut(value, 0)["fatigue"] = serde_json::json!(0.5);
    });
    let open = edit(&started(11), |value| {
        slot_mut(value, 0)["fatigue"] = serde_json::json!(0.5);
    });
    let mut sheltered = sheltered;
    let mut open = open;
    let sleeper = view_person(&sheltered, 0);
    let outsider = view_person(&open, 0);
    assert_eq!(
        sheltered.submit(Command::Work {
            actor: EntityId {
                index: sleeper.index,
                generation: sleeper.generation,
            },
            job: JobKind::Rest,
        }),
        QUEUED
    );
    assert_eq!(
        open.submit(Command::Work {
            actor: EntityId {
                index: outsider.index,
                generation: outsider.generation,
            },
            job: JobKind::Rest,
        }),
        QUEUED
    );
    sheltered.step();
    assert_eq!(view_person(&sheltered, 0).job, JobKind::Rest.discriminant());
    for _ in 0..239 {
        sheltered.step();
        open.step();
    }
    open.step();
    let by_shelter = 0.5 - view_person(&sheltered, 0).fatigue;
    let in_open = 0.5 - view_person(&open, 0).fatigue;
    assert!(
        (by_shelter / in_open - 2.0).abs() < 0.05,
        "lean-to recovery {by_shelter} should be twice the open {in_open}"
    );

    let mut until_clear = edit(&started(12), |value| {
        slot_mut(value, 0)["fatigue"] = serde_json::json!(0.05);
    });
    let person = view_person(&until_clear, 0);
    assert_eq!(
        until_clear.submit_work(0, person.generation, JobKind::Rest.discriminant() as u32),
        QUEUED
    );
    let mut steps = 0;
    for _ in 0..400 {
        until_clear.step();
        steps += 1;
        if view_person(&until_clear, 0).job != JobKind::Rest.discriminant() {
            break;
        }
    }
    assert_eq!(view_person(&until_clear, 0).fatigue, 0.0);
    assert_eq!(view_person(&until_clear, 0).job, -1);
    assert!(steps < 400, "rest completes");

    let exhausted = edit(&started(12), |value| {
        value["tick"] = serde_json::json!(NIGHT_START_TICK);
        slot_mut(value, 0)["fatigue"] = serde_json::json!(0.95);
    });
    let mut exhausted = exhausted;
    let person = view_person(&exhausted, 0);
    assert_eq!(
        exhausted.submit_work(0, person.generation, JobKind::Rest.discriminant() as u32),
        QUEUED
    );
    exhausted.step();
    let sleeping = view_person(&exhausted, 0);
    assert_eq!(sleeping.failure, -1, "{}", sleeping.failure_text);
    assert_eq!(sleeping.job, JobKind::Rest.discriminant());
}

#[test]
fn work_raises_its_skill_and_shortens_its_time_and_a_knife_cuts_gathering_further() {
    assert_eq!(SKILL_PER_UNIT, 0.01);
    assert_eq!(SKILL_TIME_RELIEF, 0.4);
    assert_eq!(GATHER_TOOL_RELIEF, 0.25);
    assert_eq!(scaled_work_ticks(100, 1.0, 0.0), 60);
    assert_eq!(
        scaled_work_ticks(GATHER_TICKS_PER_UNIT, 0.0, 0.0),
        GATHER_TICKS_PER_UNIT
    );
    assert_eq!(scaled_work_ticks(GATHER_TICKS_PER_UNIT, 1.0, 0.0), 12);
    assert_eq!(
        scaled_work_ticks(GATHER_TICKS_PER_UNIT, 0.0, GATHER_TOOL_RELIEF),
        15
    );
    assert_eq!(
        scaled_work_ticks(GATHER_TICKS_PER_UNIT, 1.0, GATHER_TOOL_RELIEF),
        9
    );
    assert_eq!(scaled_work_ticks(BUILD_TICKS, 1.0, 0.0), 36);

    let fresh = started(13);
    let person = view_person(&fresh, 0);
    assert_eq!(person.skills, [0.0, 0.0, 0.0, 0.0]);

    let wood = fresh
        .view()
        .nodes
        .into_iter()
        .find(|node| node.yield_item == ITEM_WOOD.0)
        .unwrap();
    let stood = edit(&fresh, |value| {
        let slot = slot_mut(value, 0);
        slot["x"] = serde_json::json!(wood.x);
        slot["y"] = serde_json::json!(wood.y);
    });
    let mut stood = stood;
    let person = view_person(&stood, 0);
    assert_eq!(
        stood.submit_gather(0, person.generation, wood.index, wood.generation),
        QUEUED
    );
    let ticks = steps_until_wood(&mut stood, 0);
    assert_eq!(ticks, GATHER_TICKS_PER_UNIT);
    assert_eq!(
        view_person(&stood, 0).skills[SKILL_GATHER].to_bits(),
        SKILL_PER_UNIT.to_bits()
    );

    let skilled = edit(&fresh, |value| {
        let slot = slot_mut(value, 0);
        slot["x"] = serde_json::json!(wood.x);
        slot["y"] = serde_json::json!(wood.y);
        slot["skills"] = serde_json::json!([1.0, 0.0, 0.0, 0.0]);
    });
    let mut skilled = skilled;
    let person = view_person(&skilled, 0);
    assert_eq!(
        skilled.submit_gather(0, person.generation, wood.index, wood.generation),
        QUEUED
    );
    assert_eq!(
        steps_until_wood(&mut skilled, 0),
        scaled_work_ticks(GATHER_TICKS_PER_UNIT, 1.0, 0.0)
    );
    assert_eq!(
        view_person(&skilled, 0).skills[SKILL_GATHER].to_bits(),
        1.0f32.to_bits()
    );

    let knifed = edit(&fresh, |value| {
        let slot = slot_mut(value, 0);
        slot["x"] = serde_json::json!(wood.x);
        slot["y"] = serde_json::json!(wood.y);
        slot["carried"] = serde_json::json!([[ITEM_KNIFE.0, 1]]);
        slot["skills"] = serde_json::json!([0.0, 0.0, 0.0, 0.0]);
    });
    let mut knifed = knifed;
    let person = view_person(&knifed, 0);
    assert_eq!(
        knifed.submit_gather(0, person.generation, wood.index, wood.generation),
        QUEUED
    );
    assert_eq!(
        steps_until_wood(&mut knifed, 0),
        scaled_work_ticks(GATHER_TICKS_PER_UNIT, 0.0, GATHER_TOOL_RELIEF)
    );
    assert_eq!(
        carried_of(&view_person(&knifed, 0).carried, ITEM_KNIFE.0),
        1
    );

    let mut builder = started(14);
    let person = view_person(&builder, 0);
    assert_eq!(
        builder.submit_place(
            0,
            person.generation,
            BuildingKind::Stockpile.discriminant(),
            person.x,
            person.y
        ),
        QUEUED
    );
    for _ in 0..BUILD_TICKS {
        builder.step();
    }
    assert_eq!(builder.view().buildings[0].progress, BUILD_TICKS);
    assert_eq!(
        view_person(&builder, 0).skills[SKILL_BUILD].to_bits(),
        SKILL_PER_UNIT.to_bits()
    );

    let fast = edit(&started(14), |value| {
        slot_mut(value, 0)["skills"] = serde_json::json!([0.0, 1.0, 0.0, 0.0]);
    });
    let mut fast = fast;
    let person = view_person(&fast, 0);
    assert_eq!(
        fast.submit_place(
            0,
            person.generation,
            BuildingKind::Campfire.discriminant(),
            person.x,
            person.y
        ),
        QUEUED
    );
    let needed = scaled_work_ticks(BUILD_TICKS, 1.0, 0.0);
    for _ in 0..needed {
        fast.step();
    }
    assert_eq!(fast.view().buildings[0].progress, BUILD_TICKS);
    assert!(view_person(&fast, 0).dest.is_empty());

    let mut crafter = edit(&started(15), |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_STONE.0, 1], [ITEM_WOOD.0, 1]]);
    });
    let person = view_person(&crafter, 0);
    assert_eq!(crafter.submit_craft(0, person.generation, 0), QUEUED);
    for _ in 0..60 {
        crafter.step();
    }
    assert_eq!(
        carried_of(&view_person(&crafter, 0).carried, ITEM_KNIFE.0),
        1
    );
    assert_eq!(
        view_person(&crafter, 0).skills[SKILL_CRAFT].to_bits(),
        SKILL_PER_UNIT.to_bits()
    );
}

fn steps_until_wood(sim: &mut SimState, already: u32) -> u32 {
    let mut ticks = 0;
    for _ in 0..80 {
        sim.step();
        ticks += 1;
        let person = view_person(sim, 0);
        assert_eq!(person.failure, -1, "{}", person.failure_text);
        if carried_of(&person.carried, ITEM_WOOD.0) > already {
            return ticks;
        }
    }
    panic!("gather did not yield");
}

#[test]
fn heal_walks_spends_heal_ticks_consumes_the_item_and_treats_the_worst_region() {
    assert_eq!(HEAL_TICKS, 60);
    assert_eq!(STATION_RANGE_M, 2.0);

    let mut self_heal = set_region(
        &set_region(&started(16), 0, 0, 0.2, 0.0, false, false),
        0,
        1,
        0.9,
        0.0,
        false,
        false,
    );
    self_heal = edit(&self_heal, |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_BANDAGE.0, 1]]);
    });
    let person = view_person(&self_heal, 0);
    assert_eq!(
        self_heal.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_BANDAGE.0)
        ),
        i64::from(QUEUED)
    );
    self_heal.step();
    assert!(
        view_person(&self_heal, 0).path.is_empty(),
        "self-heal does not walk"
    );
    for _ in 1..HEAL_TICKS {
        self_heal.step();
    }
    let treated = view_person(&self_heal, 0);
    assert_eq!(treated.failure, -1, "{}", treated.failure_text);
    assert_eq!(carried_of(&treated.carried, ITEM_BANDAGE.0), 0);
    assert!(
        treated.regions[1].bandaged,
        "the worst bleeding region is the torso"
    );
    assert_eq!(treated.regions[1].bleeding, 0.0);
    assert!(!treated.regions[0].bandaged);
    assert!(close(treated.regions[0].bleeding, 0.2));
    assert_eq!(
        treated.skills[SKILL_MEDICINE].to_bits(),
        SKILL_PER_UNIT.to_bits()
    );

    let tied = set_region(
        &set_region(&started(16), 0, 0, 0.5, 0.0, false, false),
        0,
        4,
        0.5,
        0.0,
        false,
        false,
    );
    let mut tied = edit(&tied, |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_BANDAGE.0, 1]]);
    });
    let person = view_person(&tied, 0);
    assert_eq!(
        tied.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_BANDAGE.0)
        ),
        i64::from(QUEUED)
    );
    for _ in 0..HEAL_TICKS {
        tied.step();
    }
    let tied = view_person(&tied, 0);
    assert!(tied.regions[0].bandaged, "a tie keeps the earlier region");
    assert!(!tied.regions[4].bandaged);

    let mut useless = set_region(&started(16), 0, 1, 1.0, 0.0, false, false);
    useless = edit(&useless, |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_WOOD.0, 1]]);
    });
    let person = view_person(&useless, 0);
    assert_eq!(
        useless.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_WOOD.0)
        ),
        i64::from(QUEUED)
    );
    useless.step();
    let failed = view_person(&useless, 0);
    assert_eq!(failed.failure_text, "no material");
    assert_eq!(carried_of(&failed.carried, ITEM_WOOD.0), 1);

    let mut healthy = edit(&started(16), |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_BANDAGE.0, 1]]);
    });
    let person = view_person(&healthy, 0);
    assert_eq!(
        healthy.submit_heal(
            0,
            i64::from(person.generation),
            0,
            i64::from(person.generation),
            i64::from(ITEM_BANDAGE.0)
        ),
        i64::from(QUEUED)
    );
    healthy.step();
    let failed = view_person(&healthy, 0);
    assert_eq!(failed.failure_text, "no material");
    assert_eq!(
        carried_of(&failed.carried, ITEM_BANDAGE.0),
        1,
        "nothing to treat does not consume the bandage"
    );

    assert_eq!(
        started(16).submit_heal(0, 1, 0, 1, 99),
        i64::from(MALFORMED)
    );
    assert_eq!(
        started(16).submit_heal(0, 1, 9, 1, i64::from(ITEM_BANDAGE.0)),
        i64::from(STALE)
    );

    let walker = edit(
        &set_region(&started(17), 1, 3, 1.0, 0.0, false, false),
        |value| {
            let actor = view_xy(&started(17), 0);
            slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_BANDAGE.0, 1]]);
            let patient = slot_mut(value, 1);
            let x = (actor[0] + 8.0).clamp(1.0, 30.0);
            patient["x"] = serde_json::json!(x);
            patient["y"] = serde_json::json!(actor[1]);
        },
    );
    let mut walker = walker;
    let healer = view_person(&walker, 0);
    let patient = view_person(&walker, 1);
    assert!(dist([healer.x, healer.y], [patient.x, patient.y]) > STATION_RANGE_M);
    assert_eq!(
        walker.submit_heal(
            i64::from(healer.index),
            i64::from(healer.generation),
            i64::from(patient.index),
            i64::from(patient.generation),
            i64::from(ITEM_BANDAGE.0)
        ),
        i64::from(QUEUED)
    );
    let mut saw_path = false;
    let mut in_range_ticks = 0u32;
    let mut done = false;
    for _ in 0..400 {
        walker.step();
        let healer = view_person(&walker, 0);
        if !healer.path.is_empty() {
            saw_path = true;
        }
        let patient = view_person(&walker, 1);
        let arrived = healer.path.is_empty()
            && dist([healer.x, healer.y], [patient.x, patient.y]) <= STATION_RANGE_M
            && healer.failure == -1;
        if arrived {
            in_range_ticks += 1;
        }
        if carried_of(&healer.carried, ITEM_BANDAGE.0) == 0 {
            done = true;
            break;
        }
        assert_eq!(healer.failure, -1, "{}", healer.failure_text);
    }
    assert!(saw_path, "heal walks to the patient");
    assert!(done, "the bandage is consumed");
    assert_eq!(in_range_ticks, HEAL_TICKS);
    let patient = view_person(&walker, 1);
    assert!(patient.regions[3].bandaged);
    assert_eq!(patient.regions[3].bleeding, 0.0);
}

fn view_xy(sim: &SimState, index: u32) -> [f32; 2] {
    let person = view_person(sim, index);
    [person.x, person.y]
}

#[test]
fn a_version_3_save_round_trips_regions_wounds_fatigue_warmth_and_skills() {
    assert_eq!(SAVE_VERSION, 3);
    let fresh = started(18);
    let person = view_person(&fresh, 0);
    assert_eq!(person.fatigue, 0.0);
    assert_eq!(person.warmth.to_bits(), 1.0f32.to_bits());
    assert_eq!(person.skills, [0.0, 0.0, 0.0, 0.0]);
    assert_eq!(person.regions.len(), 6);
    for (index, region) in person.regions.iter().enumerate() {
        assert_eq!(region.kind, index as u32);
        assert_eq!(region.kind, RegionKind::ALL[index].discriminant());
        assert_eq!(region.health, 1.0);
        assert_eq!(region.bleeding, 0.0);
        assert_eq!(region.infected, 0.0);
        assert!(!region.bandaged);
        assert!(!region.treated);
    }

    let wounded = edit(&fresh, |value| {
        let slot = slot_mut(value, 0);
        slot["fatigue"] = serde_json::json!(0.4);
        slot["warmth"] = serde_json::json!(0.55);
        slot["skills"] = serde_json::json!([0.2, 0.1, 0.0, 0.3]);
        let head = &mut slot["regions"][0];
        head["health"] = serde_json::json!(0.7);
        head["bleeding"] = serde_json::json!(0.4);
        head["infected"] = serde_json::json!(0.2);
        head["bandaged"] = serde_json::json!(true);
        head["treated"] = serde_json::json!(true);
    });
    let json = save_to_json(&wounded);
    assert!(json.contains("\"regions\""));
    assert!(json.contains("\"fatigue\""));
    assert!(json.contains("\"warmth\""));
    assert!(json.contains("\"skills\""));
    assert!(!json.contains("camera"));
    assert!(!json.contains("\"queue\""));
    let loaded = load_from_json(&json).unwrap();
    assert_eq!(loaded.state_hash(), wounded.state_hash());
    assert_eq!(loaded.view().people, wounded.view().people);
    let restored = view_person(&loaded, 0);
    assert_eq!(restored.fatigue.to_bits(), 0.4f32.to_bits());
    assert!(close(restored.warmth, 0.55));
    assert_eq!(restored.skills[SKILL_GATHER].to_bits(), 0.2f32.to_bits());
    assert_eq!(restored.skills[SKILL_BUILD].to_bits(), 0.1f32.to_bits());
    assert_eq!(restored.skills[SKILL_MEDICINE].to_bits(), 0.3f32.to_bits());
    assert!(restored.regions[0].bandaged && restored.regions[0].treated);
    assert!(close(restored.regions[0].bleeding, 0.4));
    assert!(close(restored.regions[0].infected, 0.2));
    assert!(close(restored.regions[0].health, 0.7));

    let mut value: serde_json::Value = serde_json::from_str(&json).unwrap();
    value["save_version"] = serde_json::json!(2);
    let err = load_from_json(&value.to_string()).unwrap_err();
    assert!(matches!(
        err,
        SaveError::MigrationNotImplemented { from: 2, to: 3 }
    ));
}
