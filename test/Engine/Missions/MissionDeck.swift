import Foundation

/// The order the missions come up in over a game.
enum MissionDeck {
    /// True when no two games that are easy for a traitor fall on consecutive days, going round the deck.
    static func balanced(_ deck: [MissionKind]) -> Bool {
        guard deck.count > 1 else { return true }
        return !deck.indices.contains { deck[$0].coverHeavy && deck[($0 + 1) % deck.count].coverHeavy }
    }

    static func deal(rng: inout SeededRNG) -> [MissionKind] {
        for _ in 0..<64 {
            let deck = rng.shuffled(MissionKind.allCases)
            if balanced(deck) { return deck }
        }
        // Never yet needed: lay the easy games out with at least one other between each pair.
        var heavy = rng.shuffled(MissionKind.allCases.filter(\.coverHeavy))
        var deck: [MissionKind] = []
        for kind in rng.shuffled(MissionKind.allCases.filter { !$0.coverHeavy }) {
            if let h = heavy.popLast() { deck.append(h) }
            deck.append(kind)
        }
        return deck + heavy
    }
}
