import Foundation
import TraitorsCore
import TraitorsMinds

/// Breakfast laid out for telling: who walks in and in what order, whose chair stays empty,
/// and what is said once everyone has seen it.
public struct MorningScript {
    /// The players walking in, a few at a time. The human, when still in, is in the first group
    /// so the rest arrive in front of them.
    public package(set) var arrivals: [[PlayerID]] = []
    /// Whose chair is empty this morning.
    public package(set) var victim: PlayerID?
    public package(set) var humanIsVictim = false
    var firstDay = false
    /// Two of those at the table who say something about it.
    public package(set) var reactors: [PlayerID] = []
    /// Everything said this morning other than the murder itself, in order.
    public package(set) var lines: [Beat] = []

    public init(game: Game) {
        firstDay = game.day == 1
        victim = game.outcome?.morning?.victim
        lines = game.feed.filter { $0.kind != .murder }
        humanIsVictim = victim != nil && victim == game.human

        // Its own stream, so the order people come down in never moves the game's.
        var rng = SeededRNG.derived(game.seed, UInt64(game.day), 0xB4EA)
        var walkers = rng.shuffled(game.alive.filter { $0 != game.human })
        var group: [PlayerID] = []
        if let me = game.human, game.players[me].alive { group.append(me) }
        var size = 2
        while !walkers.isEmpty {
            while group.count < size, !walkers.isEmpty { group.append(walkers.removeFirst()) }
            arrivals.append(group)
            group = []
            size = 2 + rng.int(2)
        }
        if !group.isEmpty { arrivals.append(group) }

        if !firstDay {
            reactors = Array(rng.shuffled(game.alive.filter { $0 != game.human }).prefix(2))
        }
    }

    /// The table as it was last night: everyone here now, plus the chair nobody comes to.
    public func seats(_ game: Game) -> [PlayerID] {
        game.players.indices.filter { game.players[$0].alive || $0 == victim }
    }
}
