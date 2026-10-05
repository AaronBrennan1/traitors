import Foundation

/// The order the courses come up in over a game.
enum MissionDeck {
    /// The Great Hall is always first, being the plainest. The rest come in any order.
    static func deal(rng: inout SeededRNG) -> [MissionKind] {
        [.greatHall] + rng.shuffled(MissionKind.allCases.filter { $0 != .greatHall })
    }
}
