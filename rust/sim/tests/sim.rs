//! Headless checks for the sim skeleton. No Godot process.

use latchsoil_sim::{
    load_from_json, save_to_json, BuildingKind, Clock, Command, EntityId, ItemId, JobKind,
    RecipeId, SaveError, Season, SimState, SplitMix64, DAYS_PER_SEASON, DAYS_PER_YEAR,
    SAVE_VERSION, TICKS_PER_DAY, TICKS_PER_SECOND,
};

fn sample_commands() -> Vec<Command> {
    let actor = EntityId(1);
    vec![
        Command::Move {
            actor,
            to: [1.5, 2.25],
        },
        Command::Gather {
            actor,
            node: EntityId(2),
        },
        Command::Eat {
            actor,
            item: ItemId(7),
        },
        Command::Haul {
            actor,
            item: EntityId(3),
            to: EntityId(4),
        },
        Command::Work {
            actor,
            job: JobKind::Haul,
        },
        Command::Place {
            actor,
            building: BuildingKind::Campfire,
            at: [8.0, 0.5],
        },
        Command::Craft {
            actor,
            recipe: RecipeId(9),
        },
        Command::Draft {
            actor,
            drafted: true,
        },
        Command::Attack {
            actor,
            target: EntityId(5),
        },
    ]
}

fn apply_all(sim: &mut SimState, commands: &[Command]) {
    for cmd in commands {
        sim.apply(cmd).expect("skeleton accepts every command");
    }
}

fn run(seed: u64, commands: &[Command]) -> u64 {
    let mut sim = SimState::new(seed);
    apply_all(&mut sim, commands);
    sim.state_hash()
}

#[test]
fn clock_boundaries_follow_the_constants() {
    // A day is 12 real minutes at 1x. A season is 10 days. A year is 40 days = 288_000 ticks.
    assert_eq!(TICKS_PER_SECOND, 10);
    assert_eq!(TICKS_PER_DAY, 12 * 60 * TICKS_PER_SECOND);
    assert_eq!(TICKS_PER_DAY, 7_200);
    assert_eq!(DAYS_PER_SEASON, 10);
    assert_eq!(DAYS_PER_YEAR, 40);
    assert_eq!(DAYS_PER_YEAR, 4 * DAYS_PER_SEASON);
    assert_eq!(TICKS_PER_DAY * DAYS_PER_YEAR, 288_000);

    let mut clock = Clock::new();
    assert_eq!(clock.tick(), 0);
    assert_eq!(clock.day(), 0);
    assert_eq!(clock.day_of_season(), 0);
    assert_eq!(clock.season(), Season::Sprout);
    assert_eq!(clock.year(), 0);

    clock.advance(5);
    assert_eq!(clock.tick(), 5);
    clock.advance(2);
    assert_eq!(clock.tick(), 7);

    let mut clock = Clock::new();
    clock.advance(TICKS_PER_DAY - 1);
    assert_eq!(clock.day(), 0);
    assert_eq!(clock.season(), Season::Sprout);
    clock.advance(1);
    assert_eq!(clock.tick(), TICKS_PER_DAY);
    assert_eq!(clock.day(), 1);
    assert_eq!(clock.day_of_season(), 1);

    let seasons = [
        Season::Sprout,
        Season::HighSun,
        Season::Stitchfall,
        Season::DeepBell,
    ];
    let mut clock = Clock::new();
    for day in 0..DAYS_PER_YEAR {
        assert_eq!(clock.tick(), day * TICKS_PER_DAY);
        assert_eq!(clock.day(), day);
        assert_eq!(clock.year(), 0);
        assert_eq!(clock.day_of_season(), day % DAYS_PER_SEASON);
        assert_eq!(clock.season(), seasons[(day / DAYS_PER_SEASON) as usize]);
        clock.advance(TICKS_PER_DAY);
    }
    assert_eq!(clock.tick(), 288_000);
    assert_eq!(clock.day(), DAYS_PER_YEAR);
    assert_eq!(clock.year(), 1);
    assert_eq!(clock.day_of_season(), 0);
    assert_eq!(clock.season(), Season::Sprout);

    let mut clock = Clock::new();
    clock.advance(TICKS_PER_DAY * DAYS_PER_SEASON - 1);
    assert_eq!(clock.day(), DAYS_PER_SEASON - 1);
    assert_eq!(clock.day_of_season(), DAYS_PER_SEASON - 1);
    assert_eq!(clock.season(), Season::Sprout);
    assert_eq!(clock.year(), 0);
    clock.advance(1);
    assert_eq!(clock.day(), DAYS_PER_SEASON);
    assert_eq!(clock.season(), Season::HighSun);
    assert_eq!(clock.day_of_season(), 0);
}

#[test]
fn same_seed_and_commands_share_a_hash_different_seed_does_not() {
    let commands = sample_commands();
    let first = run(7, &commands);
    let second = run(7, &commands);
    assert_eq!(first, second);

    let other_seed = run(8, &commands);
    assert_ne!(first, other_seed);

    // The seed is in the hash even when nothing has been ordered.
    assert_ne!(run(7, &[]), run(8, &[]));

    // A different command list is a different run.
    assert_ne!(first, run(7, &commands[..commands.len() - 1]));
}

#[test]
fn save_load_round_trip_preserves_hash_and_tick() {
    let mut sim = SimState::new(42);
    sim.clock
        .advance(TICKS_PER_DAY * (DAYS_PER_SEASON + 2) + 15);
    assert_eq!(sim.clock.season(), Season::HighSun);
    assert_eq!(sim.clock.year(), 0);
    let _ = sim.rng.next_u64();
    let _ = sim.rng.next_u64();
    apply_all(&mut sim, &sample_commands());

    let hash = sim.state_hash();
    let tick = sim.clock.tick();
    let loaded = load_from_json(&save_to_json(&sim)).expect("round trip");

    assert_eq!(loaded.state_hash(), hash);
    assert_eq!(loaded.clock.tick(), tick);
    assert_eq!(loaded.rng.state(), sim.rng.state());
    assert_eq!(loaded.save_version, SAVE_VERSION);
    assert_eq!(loaded.seed, sim.seed);
    assert_eq!(loaded.commands(), sim.commands());
}

#[test]
fn bumped_save_version_is_a_version_mismatch() {
    let sim = SimState::new(7);
    let mut value: serde_json::Value = serde_json::from_str(&save_to_json(&sim)).unwrap();
    value["save_version"] = serde_json::json!(SAVE_VERSION + 1);
    let err = load_from_json(&value.to_string()).unwrap_err();
    match err {
        SaveError::VersionMismatch { found, expected } => {
            assert_eq!(found, SAVE_VERSION + 1);
            assert_eq!(expected, SAVE_VERSION);
        }
        other => panic!("expected version mismatch, got {other:?}"),
    }
}

#[test]
fn splitmix64_restored_mid_stream_reproduces() {
    let mut live = SplitMix64::new(0x00C0_FFEE);
    let _ = live.next_u64();
    let _ = live.next_u64();
    let mid = live.state();
    let expected = live.next_u64();

    let mut from_word = SplitMix64::from_state(mid);
    assert_eq!(from_word.state(), mid);
    assert_eq!(from_word.next_u64(), expected);

    let mut sim = SimState::new(0x00C0_FFEE);
    let _ = sim.rng.next_u64();
    let _ = sim.rng.next_u64();
    assert_eq!(sim.rng.state(), mid);
    let json = save_to_json(&sim);
    let expected_from_sim = sim.rng.next_u64();
    assert_eq!(expected_from_sim, expected);

    let mut loaded = load_from_json(&json).unwrap();
    assert_eq!(loaded.rng.state(), mid);
    assert_eq!(loaded.rng.next_u64(), expected);
    assert_eq!(loaded.rng.state(), sim.rng.state());
}
