import Foundation
import TraitorsEngine
import TraitorsCore
import TraitorsMinds
import TraitorsGauntlet

extension Autopilot {
    /// Launch arguments that open the app on each scene worth looking at, found by playing seeds forward.
    static func scenes(seeds: ClosedRange<UInt64>) -> [(name: String, arguments: String)] {
        var found: [String: String] = [:]
        let wanted = ["tie, human votes again", "fate decides", "human banished", "human murdered",
                      "human murders", "recruitment offer", "human recruits", "spectator vote", "finale choice", "quiet night"]
        for seed in seeds {
            for pref in [RolePreference.faithful, .traitor] {
                var g = Game(seed: seed, humanName: "Aaron", preference: pref)
                var steps = 0
                var seat = Seat()
                func note(_ name: String, _ stop: String) {
                    if found[name] == nil { found[name] = "-autoplay 1 -seed \(seed) -role \(pref.rawValue) \(stop)" }
                }
                while g.phase != .gameOver, steps < 600 {
                    let before = g.tally.quietNights
                    guard (try? g.advance(seat.answer(g.prompt, in: g))) != nil else { break }
                    steps += 1
                    let asked = g.prompt
                    switch g.phase {
                    case .voting:
                        if case .vote(2, _) = asked { note("tie, human votes again", "-stopPhase voting -stopDay \(g.day) -stopVoteRound 2") }
                    case .voteReveal:
                        let script = VoteScript(game: g)
                        let stop = "-stopPhase voteReveal -stopDay \(g.day)"
                        if let me = g.human, script.banished == me { note("human banished", stop) }
                        if !g.humanAlive, script.banished != g.human, !g.finale { note("spectator vote", stop) }
                        if g.outcome?.vote?.byFate == true { note("fate decides", stop) }
                    case .breakfast:
                        let stop = "-stopPhase breakfast -stopDay \(g.day)"
                        if let me = g.human, g.players[me].fate == .murdered, g.players[me].fateDay == g.day - 1 { note("human murdered", stop) }
                        if g.tally.quietNights > before { note("quiet night", stop) }
                    case .night:
                        let night = NightChoice(asked)
                        if night != .none { note(["murder": "human murders", "offer": "recruitment offer", "recruit": "human recruits"][night.rawValue]!,
                                                 "-stopPhase night -stopDay \(g.day) -stopNight \(night.rawValue)") }
                    case .finaleChoice:
                        note("finale choice", "-stopPhase finaleChoice -stopDay \(g.day)")
                    default: break
                    }
                }
            }
            if found.count == wanted.count { break }
        }
        return wanted.map { ($0, found[$0] ?? "not found in seeds \(seeds.lowerBound)...\(seeds.upperBound)") }
    }
}
