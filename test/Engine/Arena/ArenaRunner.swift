import Foundation

enum ArenaGames {
    static func make(_ setup: ArenaSetup) -> ArenaCore {
        switch setup.kind {
        case .bogRelay: return BogCore(setup)
        case .lanternRun: return LanternCore(setup)
        case .sheepRoundUp: return SheepCore(setup)
        case .shipwreckDive: return ShipCore(setup)
        case .ceiliChaos: return CeiliCore(setup)
        case .marketDay: return MarketCore(setup)
        case .kiteRace: return KiteCore(setup)
        case .hedgeMaze: return MazeCore(setup)
        case .hurley: return HurleyCore(setup)
        case .banquetPrep: return BanquetCore(setup)
        }
    }
}

/// Runs one mini-game from the countdown to the hand-back of the result, on screen or headless.
final class ArenaRunner {
    enum Stage { case countdown, playing, finished }

    let core: ArenaCore
    private(set) var stage = Stage.countdown
    private(set) var countdown = 2.7
    private var owed = 0.0

    init(_ setup: ArenaSetup) {
        core = ArenaGames.make(setup)
    }

    /// Moves the game on by a frame. The game itself always runs in fixed steps.
    func advance(_ dt: Double, input: ArenaInput) {
        switch stage {
        case .countdown:
            countdown -= dt
            if countdown <= 0 { stage = .playing }
        case .playing:
            core.input = input
            owed += dt
            while owed >= ArenaCore.tick, !core.finished {
                core.step(ArenaCore.tick)
                owed -= ArenaCore.tick
                core.input.shot = nil
            }
            if core.finished { stage = .finished }
        case .finished:
            break
        }
    }

    func result() -> MissionResult {
        let me = core.setup.cast.first { $0.isHuman }?.id
        var rivals: [PlayerID: Int] = [:]
        for a in core.actors where a.id != me { rivals[a.id] = core.count(of: a) }
        let mine = me.flatMap(core.actor).map(core.count(of:)) ?? 0
        return MissionResult(score: Double(mine) / Double(core.spec.steps), questDone: me != nil && core.questBy == me,
                             rivals: rivals, teamTotal: core.teamTotal, questBy: core.questBy, ledger: core.ledger)
    }

    /// Plays a planned mission out with a bot in every seat.
    static func play(_ run: MissionRun) -> MissionResult {
        play(ArenaSetup(run: run, autopilot: true))
    }

    static func play(_ setup: ArenaSetup) -> MissionResult {
        let runner = ArenaRunner(setup)
        while !runner.core.finished { runner.core.step(ArenaCore.tick) }
        return runner.result()
    }

    /// A table of eight for one game, seat 1 on the side quest when asked.
    static func sample(_ kind: MissionKind, seed: UInt64, questing: Bool, questSteps: Int = 1) -> ArenaSetup {
        var rng = SeededRNG(seed: seed)
        let cast = (0..<Rules.seats).map { p -> ArenaSeat in
            let skill = rng.range(0.3, 0.8)
            let on = questing && p == 1
            return ArenaSeat(id: p, skill: skill, perception: rng.range(0.3, 0.8), deceit: rng.range(0.3, 0.8), isHuman: false,
                             target: MissionRun.sample(kind, skill: skill, questing: on, rng: &rng))
        }
        return ArenaSetup(kind: kind, day: 1, seed: rng.next(), quirkSeed: seed, cast: cast, questers: questing ? [1] : [],
                          questSteps: questSteps)
    }

    /// One game in detail: what each bot was after and got, and how often each thing happened.
    static func trace(_ kind: MissionKind, seed: UInt64) {
        let setup = sample(kind, seed: seed, questing: true)
        let r = play(setup)
        print("== \(kind.rawValue), seed \(seed): team \(r.teamTotal ?? 0) of \(kind.spec.teamGoal(alive: setup.cast.count)), quest by \(r.questBy.map(String.init) ?? "nobody")")
        print("  target/got  " + setup.cast.map { "\($0.target)/\(r.rivals?[$0.id] ?? 0)" }.joined(separator: "  "))
        var tally: [String: Int] = [:]
        for e in r.ledger?.events ?? [] { tally[e.code.rawValue + (e.actor == 1 ? "*" : ""), default: 0] += 1 }
        print("  events (* is the seat on the side quest): " + tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", "))
    }

    /// How each game plays with bots in every seat: do they land on their counts, does the side
    /// quest come off about as often as it should, and what gets seen of whoever is on it.
    static func report(games: Int, seed: UInt64) {
        print("== mini-games played out by bots (\(games) each)")
        for kind in MissionKind.allCases {
            var miss = 0.0, seats = 0.0, done = 0.0, tried = 0.0, total = 0.0, goal = 0.0
            var q = Array(repeating: 0.0, count: SightingKind.allCases.count), f = q
            var others = 0.0
            for g in 0..<games {
                let setup = sample(kind, seed: seed &+ UInt64(g) &* 7919, questing: true)
                let r = play(setup)
                for s in setup.cast {
                    miss += abs(Double((r.rivals?[s.id] ?? 0) - s.target))
                    seats += 1
                }
                if r.ledger?.events.contains(where: { $0.code == .questTry }) == true { tried += 1 }
                if r.questBy != nil { done += 1 }
                total += Double(r.teamTotal ?? 0)
                goal += Double(kind.spec.teamGoal(alive: setup.cast.count))
                let seen = SightingDeriver.derive(r.ledger!, day: 1, perception: setup.cast.map(\.perception), human: nil, seed: setup.seed)
                others += Double(setup.cast.count - 1)
                for s in seen.sightings {
                    if s.subject == 1 { q[s.kind.index] += 1 } else { f[s.kind.index] += 1 }
                }
            }
            let n = Double(games)
            let name = kind.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            let sights = SightingKind.allCases.map { String(format: "%@ %.0f/%.0f", $0.rawValue, 100 * q[$0.index] / n, 100 * f[$0.index] / max(others, 1)) }
            print(String(format: "  %@ off target %.2f  quest tried %3.0f%% done %3.0f%%  team %3.0f%% of goal", name,
                         miss / max(seats, 1), 100 * tried / n, 100 * done / n, 100 * total / max(goal, 1)))
            print("                 seen % (on quest/others): " + sights.joined(separator: "  "))
        }
    }
}
