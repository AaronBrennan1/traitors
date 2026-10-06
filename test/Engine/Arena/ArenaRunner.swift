import Foundation

/// Runs one mini-game from the countdown to the hand-back of the result, on screen or headless.
final class ArenaRunner {
    enum Stage { case countdown, playing, finished }

    let game: any ArenaGame
    /// The game, when it is the gauntlet.
    var gauntlet: Gauntlet? { game as? Gauntlet }
    private(set) var stage = Stage.countdown
    private(set) var countdown = 2.7
    private var owed = 0.0
    /// A press of the button, and a strike let go, that no step has taken yet.
    private var pressed = false
    private var shot: Vec2?

    init(_ setup: ArenaSetup) {
        game = ArenaGames.make(setup)
    }

    /// How far the screen is between the last step and the next, 0...1, for drawing in between.
    var alpha: Double { stage == .playing ? min(1, owed / game.stepSeconds) : 1 }

    /// The human pressed the button. It is kept until a step can take it, however the frames fall.
    func press() {
        if stage == .playing { pressed = true }
    }

    /// The human let a strike go.
    func shoot(_ v: Vec2) {
        if stage == .playing { shot = v }
    }

    /// Moves the game on by a frame. The game itself always runs in whole steps, and a long
    /// frame is caught up, not slowed down.
    func advance(_ dt: Double, input: ArenaInput) {
        switch stage {
        case .countdown:
            countdown -= dt
            if countdown <= 0 { stage = .playing }
        case .playing:
            game.input = input
            owed = min(owed + dt, 0.25)
            let tick = game.stepSeconds
            while owed >= tick, !game.finished {
                if pressed {
                    game.press()
                    pressed = false
                }
                if let v = shot {
                    game.shoot(v)
                    shot = nil
                }
                game.step()
                owed -= tick
            }
            if game.finished { stage = .finished }
        case .finished:
            break
        }
    }

    func result() -> MissionResult {
        MissionResult(teamTotal: game.teamTotal, sunkBy: game.sunkBy, ledger: game.ledger)
    }

    /// Plays a planned mission out with a bot in every seat.
    static func play(_ run: MissionRun) -> MissionResult {
        play(ArenaSetup(run: run, autopilot: true))
    }

    static func play(_ setup: ArenaSetup) -> MissionResult {
        let runner = ArenaRunner(setup)
        while !runner.game.finished { runner.game.step() }
        return runner.result()
    }

    // MARK: - Measuring

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
                       hand: Hand = .bot, form: Double? = nil) -> ArenaSetup {
        var rng = SeededRNG(seed: seed)
        let cast = (0..<alive).map { p in
            ArenaSeat(id: p, skill: p == 0 ? (hand == .strong ? 1.4 : 0.5) : rng.range(0.5, 0.8), perception: rng.range(0.5, 0.9),
                      deceit: rng.range(0.45, 0.95), isHuman: p == 0 && hand != .bot)
        }
        let roll = rng.gaussian()
        return ArenaSetup(kind: kind, day: day, seed: rng.next(), quirkSeed: seed, cast: cast, saboteurs: sabotage ? [1] : [],
                          form: form ?? roll, autopilot: hand != .idle)
    }

    /// How often the company makes its goal at a table of this size, with seat 0 as given.
    static func winRate(_ kind: MissionKind, games: Int, seed: UInt64, alive: Int = Rules.seats, day: Int = 1,
                        hand: Hand = .bot, sabotage: Bool) -> Double {
        var won = 0
        for g in 0..<games {
            let runner = ArenaRunner(sample(kind, seed: seed &+ UInt64(g) &* 7919, sabotage: sabotage, alive: alive, day: day, hand: hand))
            while !runner.game.finished { runner.game.step() }
            if runner.game.won { won += 1 }
        }
        return Double(won) / Double(max(games, 1))
    }

    /// The same question asked of the dice alone, with no game played.
    static func abstractWinRate(_ kind: MissionKind, games: Int, seed: UInt64, alive: Int = Rules.seats, effort: Double,
                                sabotage: Bool) -> Double {
        var won = 0
        let traits = Array(repeating: Personality.average, count: alive)
        for g in 0..<games {
            var run = MissionRun(kind: kind, day: 1, alive: Array(0..<alive), human: 0, traitors: [1], runner: sabotage ? 1 : nil,
                                 traits: traits, quirkSeed: 1, rng: SeededRNG(seed: seed &+ UInt64(g) &* 7919))
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
    static func par(_ kind: MissionKind, games: Int, seed: UInt64, alive: Int, form: Double? = nil) -> (head: Double, swing: Double) {
        var totals: [Double] = []
        for g in 0..<games {
            let runner = ArenaRunner(sample(kind, seed: seed &+ UInt64(g) &* 7919, sabotage: false, alive: alive, form: form))
            // The whole clock, however early the goal is in.
            runner.gauntlet?.seals = false
            while !runner.game.finished { runner.game.step() }
            totals.append(Double(runner.game.teamTotal))
        }
        let n = Double(max(totals.count, 1))
        let mean = totals.reduce(0, +) / n
        let spread = (totals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n).squareRoot()
        let head = mean / Double(alive)
        return (head, head > 0 ? spread / head : 0)
    }

    /// One game in detail: what the company got against its goal, and how often each thing happened.
    static func trace(_ kind: MissionKind, seed: UInt64) {
        let setup = sample(kind, seed: seed, sabotage: true)
        let runner = ArenaRunner(setup)
        while !runner.game.finished { runner.game.step() }
        let core = runner.game, r = runner.result()
        print("== \(kind.rawValue), seed \(seed): team \(core.teamTotal) of \(core.goal) in \(String(format: "%.1f", core.time))s, form \(String(format: "%+.2f", setup.form)), sunk by \(r.sunkBy.map(String.init) ?? "nobody")")
        print("  brought home by seat: " + zip(setup.cast, core.tally).map { "\($0.id):\($1)" }.joined(separator: " ")
              + (runner.gauntlet.map { "   near misses " + $0.runners.map { "\($0.nearMisses)" }.joined(separator: " ") } ?? ""))
        print("  hand used \(core.acts.reduce(0, +)) times, cost \(core.loss.reduce(0, +))")
        var tally: [String: Int] = [:]
        for e in r.ledger?.events ?? [] { tally[e.code.rawValue + (e.actor == 1 ? "*" : ""), default: 0] += 1 }
        print("  events (* is the seat with the hand): " + tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", "))
    }

    /// How each course plays: what a runner is good for on it against what the goal assumes, how
    /// often the company wins left alone and with a hand against it, how deadly it is, what the
    /// hand costs, and what gets seen of whoever used it.
    static func report(games: Int, seed: UInt64, kinds: [MissionKind] = MissionKind.allCases) {
        func pc(_ x: Double) -> String { String(format: "%3.0f", 100 * x) }
        print("== par: bags a head, measured (stored), and the swing of the company's day in shares (\(games) games each)")
        for kind in kinds {
            let name = kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
            let cells = [8, 7, 6, 5].map { n -> String in
                let p = par(kind, games: games, seed: seed &+ UInt64(n), alive: n)
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
            let dice = [abstractWinRate(kind, games: games * 5, seed: next(), effort: 1, sabotage: false),
                        abstractWinRate(kind, games: games * 5, seed: next(), effort: 0, sabotage: false),
                        abstractWinRate(kind, games: games * 5, seed: next(), effort: 1, sabotage: true),
                        abstractWinRate(kind, games: games * 5, seed: next(), effort: 1.5, sabotage: true)]
            var cells = [dice.map(pc).joined(separator: " /")]
            for n in [8, 5] {
                let played = [winRate(kind, games: games, seed: next(), alive: n, sabotage: false),
                              winRate(kind, games: games, seed: next(), alive: n, hand: .idle, sabotage: false),
                              winRate(kind, games: games, seed: next(), alive: n, sabotage: true),
                              winRate(kind, games: games, seed: next(), alive: n, hand: .strong, sabotage: true)]
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
                let setup = sample(kind, seed: seed &+ UInt64(g) &* 7919, sabotage: true)
                let runner = ArenaRunner(setup)
                while !runner.game.finished { runner.game.step() }
                let core = runner.game, r = runner.result()
                downs += Double(core.ledger.events.filter { $0.code == .downed }.count) / Double(setup.cast.count)
                near += Double(runner.gauntlet?.runners.reduce(0) { $0 + $1.nearMisses } ?? 0) / Double(setup.cast.count)
                acts += Double(core.acts.reduce(0, +))
                loss += core.loss.reduce(0, +)
                seconds += core.time
                if r.sunkBy != nil { sunk += 1 }
                let seen = SightingDeriver.derive(core.ledger, day: 1, perception: setup.cast.map(\.perception), human: nil, seed: setup.seed)
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
                String(format: "%@ %.0f/%.0f (%.1f)", $0.rawValue, 100 * q[$0.index] / n, 100 * f[$0.index] / max(others, 1), Tuning.sight($0))
            }
            print("               seen % of the hand / of others (lift assumed): " + sights.joined(separator: "  "))
        }
    }
}
