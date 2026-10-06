import Foundation

/// The order the games come up in over a play-through.
enum MissionDeck {
    /// Every game once and the gauntlet once, on whichever of its courses comes up, in any order.
    static func deal(rng: inout SeededRNG) -> [MissionKind] {
        rng.shuffled(MissionKind.games + [rng.pick(MissionKind.courses)])
    }
}
