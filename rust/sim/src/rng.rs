//! Deterministic RNG. The saved word is the stream, not a seed we re-hash.
//!
//! Algorithm: Sebastiano Vigna's public-domain splitmix64
//! (<https://xoshiro.di.unimi.it/splitmix64.c>), the fixed-increment mixer from
//! Java 8's `SplittableRandom`. No external RNG crate — the stream has to be
//! ours to pin.

use serde::{Deserialize, Serialize};

/// 64-bit splitmix64 generator.
///
/// `state` is the entire stream. [`SplitMix64::from_state`] (and a save/load of
/// that word) resumes the sequence at the next draw, which is what makes a
/// loaded run reproduce.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    /// Start a stream. The seed is the initial state, before any mix.
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    /// The word a save must store. Not a hash of the history — the history is this word.
    pub fn state(&self) -> u64 {
        self.state
    }

    /// Resume a stream from a saved [`Self::state`] word.
    pub fn from_state(state: u64) -> Self {
        Self { state }
    }

    /// Next value in the stream. Advances `state` by the golden-ratio increment, then mixes.
    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Value in the half-open range `[lo, hi)`.
    ///
    /// `next_u64() % (hi - lo)`, so the mapping is deterministic. The modulo
    /// bias is at most one part in the span. Panics if `hi <= lo`.
    pub fn next_in_range(&mut self, lo: u64, hi: u64) -> u64 {
        assert!(hi > lo, "next_in_range requires hi > lo");
        let span = hi - lo;
        lo.wrapping_add(self.next_u64() % span)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitmix64_matches_the_published_stream_for_seed_1234567() {
        // Rosetta Code "Pseudo-random numbers/Splitmix64", which publishes the
        // first five outputs of the reference mixer for seed 1234567.
        // Pinned so a later refactor cannot silently change the stream.
        let mut rng = SplitMix64::new(1_234_567);
        assert_eq!(rng.state(), 1_234_567);
        assert_eq!(rng.next_u64(), 6_457_827_717_110_365_317);
        assert_eq!(rng.next_u64(), 3_203_168_211_198_807_973);
        assert_eq!(rng.next_u64(), 9_817_491_932_198_370_423);
        assert_eq!(rng.next_u64(), 4_593_380_528_125_082_431);
        assert_eq!(rng.next_u64(), 16_408_922_859_458_223_821);
    }

    #[test]
    fn from_state_resumes_mid_stream() {
        let mut rng = SplitMix64::new(1_234_567);
        let _ = rng.next_u64();
        let _ = rng.next_u64();
        let mid = rng.state();
        let expected = rng.next_u64();

        let mut restored = SplitMix64::from_state(mid);
        assert_eq!(restored.state(), mid);
        assert_eq!(restored.next_u64(), expected);
    }

    #[test]
    fn next_in_range_is_deterministic_and_half_open() {
        let mut a = SplitMix64::new(99);
        let mut b = SplitMix64::new(99);
        for _ in 0..64 {
            let v = a.next_in_range(3, 11);
            assert_eq!(v, b.next_in_range(3, 11));
            assert!((3..11).contains(&v));
        }
    }

    #[test]
    #[should_panic(expected = "hi > lo")]
    fn next_in_range_rejects_an_empty_span() {
        let mut rng = SplitMix64::new(1);
        let _ = rng.next_in_range(5, 5);
    }
}
