import Foundation
import TraitorsEngine
import TraitorsCore
import TraitorsMinds
import TraitorsGauntlet

/// Sample tables, and what the mini-games give when played many times over. For the simulator and the tests.
extension ArenaSession {
    /// Who is in seat 0 of a sample table.
    enum Hand {
        /// Another bot, as in a game with nobody playing.
        case bot
        /// The player, who never touches the controls.
        case idle
        /// The player, reading the traps about as well as they can be read.
        case strong
    }

    /// A table for one game, seat 1 with the shadow's hand when asked. The bots' day is rolled the way the engine rolls it.
    static func sample(_ kind: MissionKind, seed: UInt64, sabotage: Bool, alive: Int = Rules.seats, day: Int = 1,
                       hand: Hand = .bot, form: Double? = nil, tuning: Tuning = Tuning()) -> ArenaSetup {
        var rng = SeededRNG(seed: seed)
        let cast = (0..<alive).map { p in
            ArenaSeat(id: p, skill: p == 0 ? (hand == .strong ? 1.4 : 0.5) : rng.range(0.5, 0.8), perception: rng.range(0.5, 0.9),
                      deceit: rng.range(0.45, 0.95), isHuman: p == 0 && hand != .bot)
        }
        let roll = rng.gaussian()
        return ArenaSetup(kind: kind, day: day, seed: rng.next(), quirkSeed: seed, cast: cast, saboteurs: sabotage ? [1] : [],
                          form: form ?? roll, autopilot: hand != .idle, tuning: tuning)
    }

    /// How often the company makes its goal at a table of this size, with seat 0 as given.
    static func winRate(_ kind: MissionKind, games: Int, seed: UInt64, alive: Int = Rules.seats, day: Int = 1,
                        hand: Hand = .bot, sabotage: Bool, tuning: Tuning = Tuning()) -> Double {
        var won = 0
        for g in 0..<games {
            let runner = ArenaSession(sample(kind, seed: seed &+ UInt64(g) &* 7919, sabotage: sabotage, alive: alive, day: day, hand: hand, tuning: tuning))
            while !runner.play.finished { runner.play.step() }
            if runner.play.won { won += 1 }
        }
        return Double(won) / Double(max(games, 1))
    }

    /// The same question asked of the dice alone, with no game played.
    static func abstractWinRate(_ kind: MissionKind, games: Int, seed: UInt64, alive: Int = Rules.seats, effort: Double,
                                sabotage: Bool, tuning: Tuning = Tuning()) -> Double {
        var won = 0
        let traits = Array(repeating: Personality.average, count: alive)
        for g in 0..<games {
            var run = MissionRun(kind: kind, day: 1, alive: Array(0..<alive), human: 0, traitors: [1], runner: sabotage ? 1 : nil,
                                 traits: traits, quirkSeed: 1, rng: SeededRNG(seed: seed &+ UInt64(g) &* 7919), tuning: tuning)
            run.plan()
            // The dice decide whether the runner dares; here the question is what it costs when they do.
            run.runnerAttempt = sabotage
            run.resolve(human: MissionResult(effort: effort))
            if run.groupWon { won += 1 }
        }
        return Double(won) / Double(max(games, 1))
    }

    /// What an ordinary runner brings home on a course with nobody spoiling it: bags a head, and
    /// how far the company's day swings, in runners' shares.
    static func par(_ kind: MissionKind, games: Int, seed: UInt64, alive: Int, form: Double? = nil, tuning: Tuning = Tuning()) -> (head: Double, swing: Double) {
        var totals: [Double] = []
        for g in 0..<games {
            let runner = ArenaSession(sample(kind, seed: seed &+ UInt64(g) &* 7919, sabotage: false, alive: alive, form: form, tuning: tuning))
            // The whole clock, however early the goal is in.
            runner.gauntlet?.seals = false
            while !runner.play.finished { runner.play.step() }
            totals.append(Double(runner.play.teamTotal))
        }
        let n = Double(max(totals.count, 1))
        let mean = totals.reduce(0, +) / n
        let spread = (totals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n).squareRoot()
        let head = mean / Double(alive)
        return (head, head > 0 ? spread / head : 0)
    }

    /// One game in detail: what the company got against its goal, and how often each thing happened.
    static func trace(_ kind: MissionKind, seed: UInt64, tuning: Tuning = Tuning()) {
        let setup = sample(kind, seed: seed, sabotage: true, tuning: tuning)
        let runner = ArenaSession(setup)
        while !runner.play.finished { runner.play.step() }
        let core = runner.play, r = runner.result()
        print("== \(kind.rawValue), seed \(seed): team \(core.teamTotal) of \(core.goal) in \(String(format: "%.1f", core.time))s, form \(String(format: "%+.2f", setup.form)), sunk by \(r.sunkBy.map(String.init) ?? "nobody")")
        let home = zip(setup.cast, core.tally).map { "\($0.id):\($1)" }.joined(separator: " ")
        let misses = runner.gauntlet.map { "   near misses " + $0.runners.map { "\($0.nearMisses)" }.joined(separator: " ") } ?? ""
        print("  brought home by seat: " + home + misses)
        print("  hand used \(core.acts.reduce(0, +)) times, cost \(core.loss.reduce(0, +))")
        var tally: [String: Int] = [:]
        for e in r.ledger?.events ?? [] { tally[e.code.rawValue + (e.actor == 1 ? "*" : ""), default: 0] += 1 }
        print("  events (* is the seat with the hand): " + tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", "))
    }

    /// How each course plays: what a runner is good for on it against what the goal assumes, how
    /// often the company wins left alone and with a hand against it, how deadly it is, what the
    /// hand costs, and what gets seen of whoever used it.
    static func report(games: Int, seed: UInt64, kinds: [MissionKind] = MissionKind.allCases, tuning: Tuning = Tuning()) {
        func pc(_ x: Double) -> String { String(format: "%3.0f", 100 * x) }
        print("== par: bags a head, measured (stored), and the swing of the company's day in shares (\(games) games each)")
        for kind in kinds {
            let name = kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
            let cells = [8, 7, 6, 5].map { n -> String in
                let p = par(kind, games: games, seed: seed &+ UInt64(n), alive: n, tuning: tuning)
                return String(format: "%d: %.2f (%.2f) ±%.2f", n, p.head, kind.spec.head(alive: n), p.swing)
            }
            print("  \(name) " + cells.joined(separator: "   "))
        }
        print("== company wins %: left alone / seat 0 idle / hand against it / hand against it and a strong seat 0")
        print("   aim 78 / 40 / 20 / 45.   dice at 8, played at 8, played at 5")
        for kind in kinds {
            let name = kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
            var salt = seed &+ UInt64(kind.rawValue.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } & 0xffff) &* 104729
            func next() -> UInt64 { salt = salt &+ 15485863; return salt }
            let dice = [abstractWinRate(kind, games: games * 5, seed: next(), effort: 1, sabotage: false, tuning: tuning),
                        abstractWinRate(kind, games: games * 5, seed: next(), effort: 0, sabotage: false, tuning: tuning),
                        abstractWinRate(kind, games: games * 5, seed: next(), effort: 1, sabotage: true, tuning: tuning),
                        abstractWinRate(kind, games: games * 5, seed: next(), effort: 1.5, sabotage: true, tuning: tuning)]
            var cells = [dice.map(pc).joined(separator: " /")]
            for n in [8, 5] {
                let played = [winRate(kind, games: games, seed: next(), alive: n, sabotage: false, tuning: tuning),
                              winRate(kind, games: games, seed: next(), alive: n, hand: .idle, sabotage: false, tuning: tuning),
                              winRate(kind, games: games, seed: next(), alive: n, sabotage: true, tuning: tuning),
                              winRate(kind, games: games, seed: next(), alive: n, hand: .strong, sabotage: true, tuning: tuning)]
                cells.append(played.map(pc).joined(separator: " /"))
            }
            print("  \(name) " + cells.joined(separator: "     "))
        }
        print("== with the hand in play (\(games) games each)")
        for kind in kinds {
            var downs = 0.0, near = 0.0, acts = 0.0, loss = 0.0, sunk = 0.0, seconds = 0.0
            var q = Array(repeating: 0.0, count: SightingKind.allCases.count), f = q
            var others = 0.0
            for g in 0..<games {
                let setup = sample(kind, seed: seed &+ UInt64(g) &* 7919, sabotage: true, tuning: tuning)
                let runner = ArenaSession(setup)
                while !runner.play.finished { runner.play.step() }
                let core = runner.play, r = runner.result()
                downs += Double(core.ledger.events.filter { $0.code == .downed }.count) / Double(setup.cast.count)
                near += Double(runner.gauntlet?.runners.reduce(0) { $0 + $1.nearMisses } ?? 0) / Double(setup.cast.count)
                acts += Double(core.acts.reduce(0, +))
                loss += core.loss.reduce(0, +)
                seconds += core.time
                if r.sunkBy != nil { sunk += 1 }
                let seen = SightingDeriver.derive(core.ledger, day: 1, perception: setup.cast.map(\.perception), human: nil, seed: setup.seed, tuning: tuning.sightings)
                others += Double(setup.cast.count - 1)
                for s in seen.sightings {
                    if s.subject == 1 { q[s.kind.index] += 1 } else { f[s.kind.index] += 1 }
                }
            }
            let n = Double(max(games, 1))
            let name = kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
            print(String(format: "  %@ downed %.1f a runner, near misses %.1f, round %.0fs, hand used %.1f times, cost %.1f, sank the day %3.0f%%",
                         name, downs / n, near / n, seconds / n, acts / n, loss / n, 100 * sunk / n))
            let sights = SightingKind.allCases.map {
                String(format: "%@ %.0f/%.0f (%.1f)", $0.rawValue, 100 * q[$0.index] / n, 100 * f[$0.index] / max(others, 1), tuning.belief.sight($0))
            }
            print("               seen % of the hand / of others (lift assumed): " + sights.joined(separator: "  "))
        }
    }
}
