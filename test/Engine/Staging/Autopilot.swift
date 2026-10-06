import Foundation

/// Plays the human seat with fixed choices up to a chosen point. The app uses it to open on a
/// given scene, and the simulator uses the same inputs to find seeds that reach the rare ones.
enum Autopilot {
    struct Stop {
        var phase: Phase = .gameOver
        var day = 1
        /// Only stop in this round of voting, when set.
        var voteRound: Int?
        /// Only stop on a night with this decision in front of the human, when set.
        var night: NightChoice?

        func matches(_ g: Game) -> Bool {
            g.phase == phase && g.day >= day && (voteRound == nil || g.voteRound == voteRound) && (night == nil || g.nightChoice == night)
        }
    }

    static func play(seed: UInt64, name: String, preference: RolePreference, stop: Stop, mission: MissionKind? = nil) -> Game {
        var g = Game(seed: seed, humanName: name, preference: preference)
        if let mission, mission.isGauntlet, let slot = g.missionDeck.firstIndex(where: \.isGauntlet) {
            // The deck holds one course of the gauntlet. Make it the one asked for.
            g.missionDeck[slot] = mission
        }
        if let mission, let at = g.missionDeck.firstIndex(of: mission) {
            // Deal the deck so the requested mission falls on the day we stop.
            g.missionDeck.swapAt(at, (stop.day - 1) % g.missionDeck.count)
        }
        var steps = 0
        while g.phase != .gameOver, steps < 600 {
            if stop.matches(g) { break }
            g.advance(input(for: g))
            steps += 1
        }
        return g
    }

    static func input(for game: Game) -> HumanInput {
        switch game.phase {
        case .mission:
            return .mission(MissionResult(effort: game.humanIsTraitor ? 0.7 : 1.2, sabotage: game.humanIsTraitor ? MissionRun.sabotageCost : 0))
        case .roundTable:
            if let t = game.choices.first, let chip = game.notebook(about: t, suspicious: true).first, game.tableStep == 1 {
                return .say(.accuse, target: t, chip: chip)
            }
            return .say(.pass, target: nil, chip: nil)
        case .voting: return .vote(game.choices[0])
        case .night:
            switch game.nightChoice {
            case .murder: return .murder(game.partnerAdvice ?? game.choices[0])
            case .recruit: return .recruit(game.choices[0])
            case .offer: return .recruitAnswer(true)
            case .none: return .next
            }
        case .finaleChoice: return .finale(end: false)
        default: return .next
        }
    }

    /// Launch arguments that open the app on each scene worth looking at, found by playing seeds forward.
    static func scenes(seeds: ClosedRange<UInt64>) -> [(name: String, arguments: String)] {
        var found: [String: String] = [:]
        let wanted = ["tie, human votes again", "fate decides", "human banished", "human murdered",
                      "human murders", "recruitment offer", "human recruits", "spectator vote", "finale choice", "quiet night"]
        for seed in seeds {
            for pref in [RolePreference.faithful, .traitor] {
                var g = Game(seed: seed, humanName: "Aaron", preference: pref)
                var steps = 0
                func note(_ name: String, _ stop: String) {
                    if found[name] == nil { found[name] = "-autoplay 1 -seed \(seed) -role \(pref.rawValue) \(stop)" }
                }
                while g.phase != .gameOver, steps < 600 {
                    let before = g.tally.quietNights
                    g.advance(input(for: g))
                    steps += 1
                    switch g.phase {
                    case .voting where g.voteRound == 2:
                        note("tie, human votes again", "-stopPhase voting -stopDay \(g.day) -stopVoteRound 2")
                    case .voteReveal:
                        let script = VoteScript(feed: g.feed)
                        let stop = "-stopPhase voteReveal -stopDay \(g.day)"
                        if let me = g.human, script.banished == me { note("human banished", stop) }
                        if !g.humanAlive, script.banished != g.human, !g.finale { note("spectator vote", stop) }
                        if fateDecided(script) { note("fate decides", stop) }
                    case .breakfast:
                        let stop = "-stopPhase breakfast -stopDay \(g.day)"
                        if let me = g.human, g.players[me].fate == .murdered, g.players[me].fateDay == g.day - 1 { note("human murdered", stop) }
                        if g.tally.quietNights > before { note("quiet night", stop) }
                    case .night:
                        if g.nightChoice == .murder { note("human murders", "-stopPhase night -stopDay \(g.day) -stopNight murder") }
                        if g.nightChoice == .offer { note("recruitment offer", "-stopPhase night -stopDay \(g.day) -stopNight offer") }
                        if g.nightChoice == .recruit { note("human recruits", "-stopPhase night -stopDay \(g.day) -stopNight recruit") }
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

    /// A line stands between the last slate and the banishment only when the revote tied as well.
    private static func fateDecided(_ script: VoteScript) -> Bool {
        guard let lastSlate = script.steps.lastIndex(where: { if case .slate = $0 { return true } else { return false } }),
              let banish = script.steps.firstIndex(where: { if case .banish = $0 { return true } else { return false } }) else { return false }
        return banish > lastSlate + 1
    }
}
