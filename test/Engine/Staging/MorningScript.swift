import Foundation

/// Breakfast laid out for telling: who walks in and in what order, whose chair stays empty,
/// and what is said once everyone has seen it.
struct MorningScript {
    /// The players walking in, a few at a time. The human, when still in, is in the first group
    /// so the rest arrive in front of them.
    var arrivals: [[PlayerID]] = []
    /// Whose chair is empty this morning.
    var victim: PlayerID?
    var humanIsVictim = false
    var firstDay = false
    /// Two of those at the table who say something about it.
    var reactors: [PlayerID] = []
    /// Everything in the feed other than the murder itself, in order.
    var lines: [Beat] = []

    init(game: Game) {
        firstDay = game.day == 1
        for beat in game.feed {
            if beat.kind == .murder, victim == nil, let target = beat.target {
                victim = target
            } else {
                lines.append(beat)
            }
        }
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
    func seats(_ game: Game) -> [PlayerID] {
        game.players.indices.filter { game.players[$0].alive || $0 == victim }
    }
}
