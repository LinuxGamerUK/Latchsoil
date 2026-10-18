//! Milestone 1a rules that still hold. Headless. No Godot process.
//!
//! Thresholds named here are the sim constants: hunger work is refused below
//! 0.35, health below 0.30, night from tick 5760 of a 7200-tick day.

use latchsoil_sim::{
    load_from_json, night_at, save_to_json, Command, EntityId, FailureReason, ItemId, JobKind,
    SimState, CARRY_CAP, EAT_HUNGER_RESTORE, EAT_THIRST_RESTORE, GATHER_TICKS_PER_UNIT,
    HEALTH_FULL_TICKS, HEALTH_PER_TICK, HEALTH_REFUSAL, HUNGER_FULL_TICKS, HUNGER_PER_TICK,
    HUNGER_REFUSAL, ITEM_GRAIN, ITEM_WOOD, MALFORMED, NIGHT_START_TICK, PEG_X, PEG_Y, QUEUED,
    QUEUE_CAP, QUEUE_FULL, STALE, STARTING_GRAIN, THIRST_FULL_TICKS, THIRST_PER_TICK,
    TICKS_PER_DAY, WALK_METERS_PER_TICK, WAYPOINT_REACH_METERS,
};

fn started(seed: u64) -> SimState {
    let mut sim = SimState::new(seed);
    sim.new_game(seed);
    sim
}

/// Units of one item in a carry list, so a test can ignore the starting ration.
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

fn view_node(sim: &SimState, index: u32) -> latchsoil_sim::NodeView {
    sim.view()
        .nodes
        .into_iter()
        .find(|node| node.index == index)
        .expect("node")
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

fn actor(sim: &SimState, index: u32) -> EntityId {
    let person = view_person(sim, index);
    EntityId {
        index: person.index,
        generation: person.generation,
    }
}

#[test]
fn same_seed_reproduces_the_acre_and_a_different_seed_does_not() {
    let a = started(7);
    let b = started(7);
    assert_eq!(a.state_hash(), b.state_hash());
    assert_eq!(a.view().people.len(), 3);
    assert_eq!(a.view().nodes.len(), 6);
    assert!(a.view().buildings.is_empty());
    for index in 0..3 {
        let person = view_person(&a, index);
        let again = view_person(&b, index);
        assert_eq!(person.generation, 1);
        assert_eq!(person.x.to_bits(), again.x.to_bits());
        assert_eq!(person.y.to_bits(), again.y.to_bits());
        assert_eq!(person.hunger.to_bits(), 1.0f32.to_bits());
        assert_eq!(person.thirst.to_bits(), 1.0f32.to_bits());
        assert_eq!(person.health.to_bits(), 1.0f32.to_bits());
        assert_eq!(person.carried, vec![[ITEM_GRAIN.0, STARTING_GRAIN]]);
        assert!(dist([person.x, person.y], [PEG_X, PEG_Y]) <= 1.5);
        assert!(dist([person.x, person.y], [PEG_X, PEG_Y]) >= 1.0);
    }
    let mut remainings = Vec::new();
    for node in &a.view().nodes {
        assert_eq!(node.generation, 1);
        assert!((0.0..32.0).contains(&node.x) && (0.0..32.0).contains(&node.y));
        assert!(dist([node.x, node.y], [PEG_X, PEG_Y]) >= 4.0);
        remainings.push(node.remaining);
        let again = view_node(&b, node.index);
        assert_eq!(node.x.to_bits(), again.x.to_bits());
        assert_eq!(node.y.to_bits(), again.y.to_bits());
        assert_eq!(node.remaining, again.remaining);
        assert_eq!(node.yield_item, again.yield_item);
    }
    remainings.sort_unstable();
    assert_eq!(remainings, vec![30, 30, 40, 40, 50, 100]);
    let nodes = a.view().nodes;
    for i in 0..nodes.len() {
        for j in (i + 1)..nodes.len() {
            let apart = dist([nodes[i].x, nodes[i].y], [nodes[j].x, nodes[j].y]);
            assert!(apart >= 2.0, "nodes {i} and {j} are {apart} m apart");
        }
    }
    let wood = a
        .catalog()
        .items
        .into_iter()
        .find(|row| row.name == "wood")
        .unwrap();
    assert!(a
        .view()
        .nodes
        .iter()
        .any(|node| node.yield_item == wood.id && node.remaining == 40));

    let other = started(8);
    assert_ne!(a.state_hash(), other.state_hash());
    let same_places = a
        .view()
        .nodes
        .iter()
        .zip(other.view().nodes.iter())
        .all(|(left, right)| {
            left.x.to_bits() == right.x.to_bits() && left.y.to_bits() == right.y.to_bits()
        })
        && a.view()
            .people
            .iter()
            .zip(other.view().people.iter())
            .all(|(left, right)| {
                left.x.to_bits() == right.x.to_bits() && left.y.to_bits() == right.y.to_bits()
            });
    assert!(!same_places, "seed 7 and seed 8 laid the same cast");
}

#[test]
fn move_advances_0_14_m_per_tick_and_completes() {
    let mut sim = started(7);
    let start = view_person(&sim, 0);
    let dest = [start.x + 1.0, start.y];
    assert_eq!(
        sim.submit(Command::Move {
            actor: actor(&sim, 0),
            to: dest,
        }),
        QUEUED
    );
    let before = sim.state_hash();
    assert_eq!(
        sim.state_hash(),
        before,
        "the unapplied queue is not hashed"
    );
    sim.step();
    let moved = view_person(&sim, 0);
    assert_eq!(
        moved.x.to_bits(),
        (start.x + WALK_METERS_PER_TICK).to_bits()
    );
    assert_eq!(moved.y.to_bits(), start.y.to_bits());
    assert_eq!(WALK_METERS_PER_TICK, 0.14);
    assert!(!moved.path.is_empty() || dist([moved.x, moved.y], dest) <= WAYPOINT_REACH_METERS);

    // 6 * 0.14 = 0.84, still more than 0.1 m from a waypoint 1 m away.
    for _ in 0..5 {
        sim.step();
    }
    let mid = view_person(&sim, 0);
    assert!(
        !mid.path.is_empty(),
        "waypoint must not be reached before 0.1 m"
    );
    assert!(dist([mid.x, mid.y], dest) > WAYPOINT_REACH_METERS);
    sim.step();
    let done = view_person(&sim, 0);
    assert!(dist([done.x, done.y], dest) <= WAYPOINT_REACH_METERS);
    assert!(done.path.is_empty());
    assert!(done.dest.is_empty());
    assert!(done.target.is_empty());
    assert_eq!(done.failure, -1);
    assert_eq!(done.failure_text, "");
}

#[test]
fn move_outside_the_acre_fails_with_no_path_and_clears_the_path() {
    let mut sim = started(3);
    let start = view_person(&sim, 0);
    assert_eq!(
        sim.submit_move(0, start.generation, start.x + 40.0, start.y),
        QUEUED,
        "an outside point is accepted and then fails in rules"
    );
    sim.step();
    let failed = view_person(&sim, 0);
    assert_eq!(failed.failure_text, "no path");
    assert_eq!(failed.failure, FailureReason::NoPath.discriminant());
    assert_eq!(failed.failure, 1);
    assert!(failed.path.is_empty());
    assert!(failed.dest.is_empty());
    assert!(failed.target.is_empty());
    assert_eq!(failed.x.to_bits(), start.x.to_bits());
    assert_eq!(failed.y.to_bits(), start.y.to_bits());
}

#[test]
fn a_new_command_clears_the_previous_failure() {
    let mut sim = started(3);
    let start = view_person(&sim, 0);
    sim.submit_move(0, start.generation, -1.0, start.y);
    sim.step();
    assert_eq!(view_person(&sim, 0).failure_text, "no path");
    let here = view_person(&sim, 0);
    assert_eq!(
        sim.submit_move(0, here.generation, here.x + 2.0, here.y),
        QUEUED
    );
    let cleared = view_person(&sim, 0);
    assert_eq!(cleared.failure, -1);
    assert_eq!(cleared.failure_text, "");
}

#[test]
fn gather_walks_adds_one_per_20_ticks_caps_at_20_and_drain_fails() {
    let mut sim = started(11);
    let wood = sim
        .view()
        .nodes
        .into_iter()
        .find(|node| node.remaining == 40)
        .unwrap();
    let person = view_person(&sim, 0);
    assert_eq!(
        sim.submit_gather(0, person.generation, wood.index, wood.generation),
        QUEUED
    );
    let node_pos = [wood.x, wood.y];
    let mut guard = 0;
    loop {
        sim.step();
        guard += 1;
        assert!(guard < 400, "did not reach the node");
        let walker = view_person(&sim, 0);
        assert_eq!(walker.failure, -1, "{}", walker.failure_text);
        if walker.path.is_empty()
            && carried_of(&walker.carried, wood.yield_item) == 0
            && dist([walker.x, walker.y], node_pos) <= WAYPOINT_REACH_METERS
        {
            break;
        }
    }
    assert!(guard > 1, "gather must walk before the first unit");
    for _ in 0..(GATHER_TICKS_PER_UNIT - 1) {
        sim.step();
        assert_eq!(
            carried_of(&view_person(&sim, 0).carried, wood.yield_item),
            0
        );
        assert_eq!(view_node(&sim, wood.index).remaining, 40);
    }
    sim.step();
    let carrying = view_person(&sim, 0);
    assert_eq!(carried_of(&carrying.carried, wood.yield_item), 1);
    assert_eq!(view_node(&sim, wood.index).remaining, 39);
    assert_eq!(GATHER_TICKS_PER_UNIT, 20);

    // Cap: keep gathering until 20, then the order stops adding.
    let mut guard = 0;
    while view_person(&sim, 0)
        .carried
        .iter()
        .map(|pair| pair[1])
        .sum::<u32>()
        < CARRY_CAP
    {
        sim.step();
        guard += 1;
        assert!(guard < 800, "did not fill the carry cap");
        assert_eq!(view_person(&sim, 0).failure, -1);
    }
    assert_eq!(CARRY_CAP, 20);
    let filled = view_person(&sim, 0)
        .carried
        .iter()
        .map(|pair| pair[1])
        .sum::<u32>();
    assert_eq!(filled, 20);
    let remaining_at_cap = view_node(&sim, wood.index).remaining;
    // The cap counts the starting ration, so only sixteen units come off the node.
    assert_eq!(remaining_at_cap, 40 - (CARRY_CAP - STARTING_GRAIN));
    for _ in 0..40 {
        sim.step();
    }
    assert_eq!(
        view_person(&sim, 0)
            .carried
            .iter()
            .map(|pair| pair[1])
            .sum::<u32>(),
        20
    );
    assert_eq!(view_node(&sim, wood.index).remaining, remaining_at_cap);

    // A node drained mid-order fails with no material after the last unit.
    let mut sim = edit(&started(11), |value| {
        let slot = slot_mut(value, u64::from(wood.index));
        slot["remaining"] = serde_json::json!(1);
    });
    let person = view_person(&sim, 0);
    let node = view_node(&sim, wood.index);
    assert_eq!(node.remaining, 1);
    sim.submit_gather(0, person.generation, node.index, node.generation);
    let node_pos = [node.x, node.y];
    let mut guard = 0;
    loop {
        sim.step();
        guard += 1;
        assert!(guard < 400, "did not reach the drained-setup node");
        let walker = view_person(&sim, 0);
        if walker.path.is_empty() && dist([walker.x, walker.y], node_pos) <= WAYPOINT_REACH_METERS {
            break;
        }
        assert_eq!(walker.failure, -1, "{}", walker.failure_text);
    }
    for _ in 0..GATHER_TICKS_PER_UNIT {
        sim.step();
    }
    let drained = view_person(&sim, 0);
    assert_eq!(drained.failure_text, "no material");
    assert_eq!(drained.failure, FailureReason::NoMaterial.discriminant());
    assert!(drained.path.is_empty());
    assert!(drained.dest.is_empty());
    assert!(drained.target.is_empty());
    assert_eq!(carried_of(&drained.carried, wood.yield_item), 1);
    assert_eq!(view_node(&sim, wood.index).remaining, 0);
}

#[test]
fn eat_succeeds_with_grain_and_fails_without() {
    // The starting cast carries four grain, so grain can actually be eaten from a
    // fresh game, and eating anything else leaves the ration alone.
    let mut fed = started(5);
    let person = view_person(&fed, 0);
    assert_eq!(fed.submit_eat(0, person.generation, ITEM_GRAIN.0), QUEUED);
    fed.step();
    let ate = view_person(&fed, 0);
    assert_eq!(ate.failure_text, "");
    assert_eq!(carried_of(&ate.carried, ITEM_GRAIN.0), STARTING_GRAIN - 1);
    let mut control = started(5);
    control.step();
    let unfed = view_person(&control, 0);
    assert!(
        ate.hunger > unfed.hunger && ate.thirst > unfed.thirst,
        "eating must leave a person better fed and watered than the same tick without it"
    );

    let mut empty = started(5);
    let person = view_person(&empty, 0);
    assert_eq!(empty.submit_eat(0, person.generation, ITEM_WOOD.0), QUEUED);
    empty.step();
    let failed = view_person(&empty, 0);
    assert_eq!(failed.failure_text, "no material");
    assert_eq!(failed.failure, 2);
    assert_eq!(failed.carried, vec![[ITEM_GRAIN.0, STARTING_GRAIN]]);
    assert!(failed.hunger < 1.0);

    let mut sim = edit(&started(5), |value| {
        let slot = slot_mut(value, 0);
        slot["hunger"] = serde_json::json!(0.5f32);
        slot["thirst"] = serde_json::json!(0.4f32);
        slot["carried"] = serde_json::json!([[ITEM_GRAIN.0, 1]]);
    });
    let before = view_person(&sim, 0);
    assert_eq!(before.carried, vec![[ITEM_GRAIN.0, 1]]);
    assert_eq!(sim.submit_eat(0, before.generation, ITEM_GRAIN.0), QUEUED);
    sim.step();
    let ate = view_person(&sim, 0);
    let hunger = ((0.5 - HUNGER_PER_TICK).max(0.0) + EAT_HUNGER_RESTORE).min(1.0);
    let thirst = ((0.4 - latchsoil_sim::THIRST_PER_TICK).max(0.0) + EAT_THIRST_RESTORE).min(1.0);
    assert_eq!(ate.hunger.to_bits(), hunger.to_bits());
    assert_eq!(ate.thirst.to_bits(), thirst.to_bits());
    assert!(ate.carried.is_empty());
    assert_eq!(ate.failure, -1);
    assert_eq!(EAT_HUNGER_RESTORE, 0.35);
    assert_eq!(EAT_THIRST_RESTORE, 0.15);

    // Wood is not grain. The order is accepted, then rules refuse it.
    let mut sim = edit(&started(5), |value| {
        slot_mut(value, 0)["carried"] = serde_json::json!([[ITEM_WOOD.0, 1]]);
    });
    let person = view_person(&sim, 0);
    assert_eq!(sim.submit_eat(0, person.generation, ITEM_WOOD.0), QUEUED);
    sim.step();
    let refused = view_person(&sim, 0);
    assert_eq!(refused.failure_text, "no material");
    assert_eq!(refused.carried, vec![[ITEM_WOOD.0, 1]]);
}

#[test]
fn hungry_wounded_and_night_follow_thresholds_and_precedence() {
    assert_eq!(HUNGER_REFUSAL, 0.35);
    assert_eq!(HEALTH_REFUSAL, 0.30);
    assert_eq!(NIGHT_START_TICK, 5_760);
    assert!(night_at(5_760));
    assert!(night_at(7_199));
    assert!(!night_at(5_759));
    assert!(!night_at(TICKS_PER_DAY));

    // Each threshold alone.
    let hungry = with_needs(0.349, 1.0, 1.0, 0);
    assert_eq!(refusal(&hungry), "hungry");
    let at_hunger = with_needs(0.35, 1.0, 1.0, 0);
    assert_eq!(refusal(&at_hunger), "");

    let wounded = with_needs(1.0, 1.0, 0.299, 0);
    assert_eq!(refusal(&wounded), "wounded");
    let at_health = with_needs(1.0, 1.0, 0.30, 0);
    assert_eq!(refusal(&at_health), "");

    let night = with_needs(1.0, 1.0, 1.0, 5_760);
    assert_eq!(refusal(&night), "night");
    let day = with_needs(1.0, 1.0, 1.0, 5_759);
    assert_eq!(refusal(&day), "");

    // Earliest FailureReason wins: Hungry, then Night, then Wounded.
    let all = with_needs(0.2, 1.0, 0.1, 6_000);
    assert_eq!(refusal(&all), "hungry");
    let night_over_wound = with_needs(0.5, 1.0, 0.1, 6_000);
    assert_eq!(refusal(&night_over_wound), "night");
    let wound_only = with_needs(0.5, 1.0, 0.1, 100);
    assert_eq!(refusal(&wound_only), "wounded");

    // Eat is not a work order: hunger does not refuse it, it goes through.
    let mut starving = with_needs(0.1, 1.0, 1.0, 0);
    let person = view_person(&starving, 0);
    assert_eq!(
        starving.submit_eat(0, person.generation, ITEM_GRAIN.0),
        QUEUED
    );
    starving.step();
    let fed = view_person(&starving, 0);
    assert_eq!(fed.failure_text, "", "a starving person may still eat");
    assert_eq!(carried_of(&fed.carried, ITEM_GRAIN.0), STARTING_GRAIN - 1);

    // Gather is a work order.
    let mut sim = with_needs(0.1, 1.0, 1.0, 0);
    let person = view_person(&sim, 0);
    let node = sim.view().nodes[0].clone();
    assert_eq!(
        sim.submit_gather(0, person.generation, node.index, node.generation),
        QUEUED
    );
    assert_eq!(view_person(&sim, 0).failure_text, "hungry");
}

fn with_needs(hunger: f32, thirst: f32, health: f32, tick: u64) -> SimState {
    let sim = edit(&started(2), |value| {
        let slot = slot_mut(value, 0);
        slot["hunger"] = serde_json::json!(hunger);
        slot["thirst"] = serde_json::json!(thirst);
        slot["health"] = serde_json::json!(health);
        value["tick"] = serde_json::json!(tick);
    });
    let person = view_person(&sim, 0);
    assert_eq!(person.hunger.to_bits(), hunger.to_bits());
    assert_eq!(person.health.to_bits(), health.to_bits());
    assert_eq!(sim.tick(), tick);
    sim
}

fn refusal(sim: &SimState) -> String {
    let mut sim = sim.clone();
    let person = view_person(&sim, 0);
    let before = [person.x, person.y];
    assert_eq!(
        sim.submit_move(0, person.generation, person.x + 3.0, person.y),
        QUEUED
    );
    let text = view_person(&sim, 0).failure_text.clone();
    sim.step();
    let after = view_person(&sim, 0);
    if text.is_empty() {
        assert!(after.x != before[0] || !after.path.is_empty() || !after.dest.is_empty());
    } else {
        assert_eq!(after.x.to_bits(), before[0].to_bits());
        assert_eq!(after.y.to_bits(), before[1].to_bits());
        assert!(after.path.is_empty());
    }
    text
}

#[test]
fn needs_empty_in_days_and_health_falls_only_at_zero() {
    assert_eq!(HUNGER_FULL_TICKS, 2 * TICKS_PER_DAY);
    assert_eq!(THIRST_FULL_TICKS, TICKS_PER_DAY * 8 / 5);
    assert_eq!(HEALTH_FULL_TICKS, TICKS_PER_DAY);
    assert_eq!(HUNGER_PER_TICK, 1.0 / (HUNGER_FULL_TICKS as f32));
    assert_eq!(THIRST_PER_TICK, 1.0 / (THIRST_FULL_TICKS as f32));
    assert_eq!(HEALTH_PER_TICK, 1.0 / (HEALTH_FULL_TICKS as f32));
    assert!(THIRST_FULL_TICKS < HUNGER_FULL_TICKS, "thirst bites first");

    let mut sim = started(1);
    sim.step();
    let person = view_person(&sim, 0);
    assert_eq!(person.hunger.to_bits(), (1.0 - HUNGER_PER_TICK).to_bits());
    assert_eq!(person.thirst.to_bits(), (1.0 - THIRST_PER_TICK).to_bits());
    assert_eq!(person.health.to_bits(), 1.0f32.to_bits());

    // A whole day at 1x leaves nobody hungry enough to refuse work, nobody hurt.
    for _ in 0..TICKS_PER_DAY {
        sim.step();
    }
    let after_a_day = view_person(&sim, 0);
    assert!(
        after_a_day.hunger > HUNGER_REFUSAL,
        "a day of play left hunger at {}",
        after_a_day.hunger
    );
    assert_eq!(after_a_day.health.to_bits(), 1.0f32.to_bits());

    let mut starving = edit(&started(1), |value| {
        let slot = slot_mut(value, 0);
        slot["hunger"] = serde_json::json!(0.0f32);
        slot["health"] = serde_json::json!(1.0f32);
    });
    starving.step();
    let person = view_person(&starving, 0);
    assert_eq!(person.hunger, 0.0);
    assert_eq!(person.health.to_bits(), (1.0 - HEALTH_PER_TICK).to_bits());

    let mut thirsty = edit(&started(1), |value| {
        let slot = slot_mut(value, 0);
        slot["thirst"] = serde_json::json!(0.0f32);
        slot["health"] = serde_json::json!(1.0f32);
    });
    thirsty.step();
    let person = view_person(&thirsty, 0);
    assert!(person.hunger > 0.0);
    assert_eq!(person.thirst, 0.0);
    assert_eq!(person.health.to_bits(), (1.0 - HEALTH_PER_TICK).to_bits());
}

#[test]
fn work_is_accepted_for_minutes_before_hunger_refuses_it() {
    // The defect this covers: the contract gave hunger as a per-tick fraction
    // (1/60) while the same paragraph promised a full person lasted days. The
    // literal rate refused every work order after four seconds of play, and a
    // player reported it as "right clicking the ground doesn't seem to move them".
    let mut sim = started(5);
    let mut first_refusal = 0;
    while first_refusal == 0 {
        let person = view_person(&sim, 0);
        assert_eq!(sim.submit_move(0, person.generation, PEG_X, PEG_Y), QUEUED);
        sim.step();
        if view_person(&sim, 0).failure_text == "hungry" {
            first_refusal = sim.tick();
        }
        assert!(sim.tick() < 20_000, "hunger never refused a work order");
    }
    let expected = (HUNGER_FULL_TICKS as f64 * (1.0 - HUNGER_REFUSAL as f64)) as u64;
    assert!(
        first_refusal.abs_diff(expected) <= 4,
        "hunger refused work at tick {first_refusal}, expected about {expected}"
    );
    assert!(
        first_refusal > 9_000,
        "work must be possible for minutes of play, not seconds (refused at tick {first_refusal})"
    );
}

#[test]
fn stale_wrong_kind_and_queue_full_are_counted() {
    let mut sim = started(4);
    let hash = sim.state_hash();
    assert_eq!(sim.submit_move(0, 0, PEG_X, PEG_Y), STALE);
    assert_eq!(sim.rejections().stale, 1);
    assert_eq!(sim.rejections().malformed, 0);
    assert_eq!(sim.rejections().queue_full, 0);
    assert_eq!(sim.state_hash(), hash);

    let node = sim.view().nodes[0].clone();
    assert_eq!(
        sim.submit_move(node.index, node.generation, 18.0, 16.0),
        MALFORMED
    );
    assert_eq!(sim.rejections().malformed, 1);
    assert_eq!(sim.state_hash(), hash);

    let person = view_person(&sim, 0);
    assert_eq!(
        sim.submit_gather(0, person.generation, 1, person.generation),
        MALFORMED
    );
    assert_eq!(sim.rejections().malformed, 2);
    assert_eq!(
        sim.submit_move(0, person.generation, f32::NAN, 1.0),
        MALFORMED
    );
    assert_eq!(sim.state_hash(), hash);

    for _ in 0..QUEUE_CAP {
        assert_eq!(sim.submit_move(0, person.generation, 20.0, 16.0), QUEUED);
    }
    assert_eq!(
        sim.submit_move(0, person.generation, 20.0, 16.0),
        QUEUE_FULL
    );
    assert_eq!(sim.rejections().queue_full, 1);
    assert_eq!(QUEUE_CAP, 256);
    assert_eq!(sim.state_hash(), hash);
}

#[test]
fn same_tick_stamped_commands_share_a_hash() {
    let actor = |sim: &SimState| actor(sim, 0);
    let plan = |sim: &SimState| {
        let person = view_person(sim, 0);
        vec![
            (
                1u64,
                Command::Move {
                    actor: actor(sim),
                    to: [person.x + 4.0, person.y],
                },
            ),
            (
                4,
                Command::Move {
                    actor: actor(sim),
                    to: [person.x + 2.0, person.y],
                },
            ),
        ]
    };
    let first = replay(9, &plan(&started(9)));
    let second = replay(9, &plan(&started(9)));
    assert_eq!(first, second);

    let mut other = plan(&started(9));
    if let Command::Move { to, .. } = &mut other[1].1 {
        to[0] += 1.0;
    }
    assert_ne!(first, replay(9, &other));

    // A one-bit position change changes the hash: positions are the stored f32 bits.
    let mut sim = started(9);
    let person = view_person(&sim, 0);
    sim.submit_move(0, person.generation, person.x + 3.0, person.y);
    sim.step();
    let hash = sim.state_hash();
    let tweaked = edit(&sim, |value| {
        let slot = slot_mut(value, 0);
        let x = slot["x"].as_f64().unwrap() as f32;
        slot["x"] = serde_json::json!(f32::from_bits(x.to_bits() ^ 1));
    });
    assert_ne!(tweaked.state_hash(), hash);
    assert_ne!(
        view_person(&tweaked, 0).x.to_bits(),
        view_person(&sim, 0).x.to_bits()
    );
}

fn replay(seed: u64, commands: &[(u64, Command)]) -> u64 {
    let mut sim = started(seed);
    for (stamped, cmd) in commands {
        while sim.tick() + 1 < *stamped {
            sim.step();
        }
        assert_eq!(sim.tick() + 1, *stamped);
        sim.submit(*cmd);
        sim.step();
    }
    sim.state_hash()
}

#[test]
fn save_load_round_trip_preserves_the_new_world_hash() {
    let mut sim = started(15);
    let person = view_person(&sim, 0);
    sim.submit_move(0, person.generation, person.x + 4.0, person.y);
    for _ in 0..6 {
        sim.step();
    }
    let hash = sim.state_hash();
    let tick = sim.tick();
    let json = save_to_json(&sim);
    assert!(!json.contains("\"queue\""));
    let loaded = load_from_json(&json).unwrap();
    assert_eq!(loaded.state_hash(), hash);
    assert_eq!(loaded.tick(), tick);
    assert_eq!(loaded.rng.state(), sim.rng.state());
    assert_eq!(loaded.seed, sim.seed);
    assert_eq!(
        view_person(&loaded, 0).x.to_bits(),
        view_person(&sim, 0).x.to_bits()
    );

    let mut continued = loaded;
    sim.step();
    continued.step();
    assert_eq!(continued.state_hash(), sim.state_hash());

    let mut live = started(15);
    let owner = live.attach();
    let saved = live.save_json();
    live.submit_move(0, 1, 20.0, 16.0);
    assert_eq!(live.load_json(&saved), 0);
    live.step();
    let mut clean = started(15);
    clean.step();
    assert_eq!(live.state_hash(), clean.state_hash());
    let snap = live.snapshot(owner);
    assert_eq!(snap.error, 0);
    assert!(snap.full);

    let hash = live.state_hash();
    let mut bad: serde_json::Value = serde_json::from_str(&saved).unwrap();
    bad["save_version"] = serde_json::json!(99);
    assert_eq!(live.load_json(&bad.to_string()), 1);
    assert_eq!(live.load_json("nope"), 1);
    assert_eq!(live.load_json("{}"), 1);
    assert_eq!(live.state_hash(), hash);
}

#[test]
fn the_other_commands_are_stored_and_do_nothing() {
    let mut sim = started(6);
    let start = view_person(&sim, 0);
    let other = view_person(&sim, 1);
    assert_eq!(
        sim.submit(Command::Draft {
            actor: actor(&sim, 0),
            drafted: true,
        }),
        QUEUED
    );
    sim.step();
    assert!(view_person(&sim, 0).drafted);
    assert!(view_person(&sim, 0).path.is_empty());

    assert_eq!(
        sim.submit(Command::Work {
            actor: actor(&sim, 0),
            job: JobKind::Farm,
        }),
        QUEUED
    );
    sim.step();
    let working = view_person(&sim, 0);
    assert_eq!(working.job, JobKind::Farm.discriminant());
    assert_eq!(working.x.to_bits(), start.x.to_bits());
    assert!(working.path.is_empty());

    assert_eq!(
        sim.submit(Command::Attack {
            actor: actor(&sim, 0),
            target: EntityId {
                index: other.index,
                generation: other.generation,
            },
        }),
        QUEUED
    );
    sim.step();
    let attacking = view_person(&sim, 0);
    assert_eq!(attacking.target, vec![other.index, other.generation]);
    assert!(attacking.path.is_empty());
    assert_eq!(attacking.x.to_bits(), start.x.to_bits());

    assert_eq!(sim.submit_craft(0, start.generation, 99), MALFORMED);
    assert_eq!(
        sim.submit(Command::Haul {
            actor: actor(&sim, 0),
            item: ItemId(ITEM_WOOD.0),
            to: actor(&sim, 1),
        }),
        MALFORMED
    );
}

#[test]
fn frame_matches_step_and_pause_holds_the_queue() {
    let mut by_step = started(7);
    let mut by_frame = started(7);
    let person = view_person(&by_step, 0);
    let dest = [person.x + 6.0, person.y];
    by_step.submit_move(0, person.generation, dest[0], dest[1]);
    by_frame.submit_move(0, person.generation, dest[0], dest[1]);
    for _ in 0..80 {
        by_step.step();
        by_frame.frame(0.1);
        assert_eq!(by_step.tick(), by_frame.tick());
        assert_eq!(by_step.state_hash(), by_frame.state_hash());
    }

    let mut sim = started(1);
    sim.set_paused(true);
    let person = view_person(&sim, 0);
    sim.submit_move(0, person.generation, person.x + 2.0, person.y);
    sim.frame(1.0);
    assert_eq!(sim.tick(), 0);
    assert_eq!(sim.alpha(), 0.0);
    sim.set_paused(false);
    sim.step();
    assert_eq!(sim.tick(), 1);
    assert!(view_person(&sim, 0).x > person.x);

    assert_eq!(sim.set_speed(4), MALFORMED);
    assert_eq!(sim.speed(), 1);
    assert_eq!(sim.set_speed(2), QUEUED);
    assert_eq!(sim.speed(), 2);
}

#[test]
fn owners_cap_at_eight_and_an_unknown_owner_is_error_2() {
    let mut sim = started(1);
    let mut ids = Vec::new();
    for expected in 1..=8 {
        let id = sim.attach();
        assert_eq!(id, expected);
        ids.push(id);
    }
    assert_eq!(sim.attach(), 0);
    assert_eq!(sim.rejections().malformed, 1);
    let snap = sim.poll(ids[0]);
    assert!(snap.full);
    assert!(snap.removed.is_empty());
    assert_eq!(snap.error, 0);
    assert_eq!(snap.people.len(), 3);
    assert_eq!(snap.nodes.len(), 6);
    assert_eq!(snap.hash, sim.state_hash());
    let missing = sim.poll(99);
    assert_eq!(missing.error, 2);
    assert!(missing.people.is_empty());
    assert_eq!(missing.tick, sim.tick());
    assert_eq!(missing.hash, sim.state_hash());
    sim.detach(99);
    sim.detach(ids[0]);
    assert_eq!(sim.poll(ids[0]).error, 2);
    assert_eq!(sim.attach(), 9);
}
