import Foundation

/// Headless all-bot games, for balancing and for checking the bots earn their keep.
/// Driven by the `traitors-sim` command-line tool: [--games N] [--seed S] [--transcript] [--seat] [--arena] [--cores]
/// [--trace course] [--form x] [--scenes] [--tune name=value]
public enum TraitorsSim {
    public static func run(arguments: [String]) {
        var games = 2000
        var seed: UInt64 = 1
        var transcript = false
        var seat = false
        var arena = false
        var coresOnly = false
        var args = Array(arguments.dropFirst())
        while !args.isEmpty {
            let a = args.removeFirst()
            switch a {
            case "--games": games = Int(args.removeFirst()) ?? games
            case "--seed": seed = UInt64(args.removeFirst()) ?? seed
            case "--transcript": transcript = true
            case "--seat": seat = true
            case "--arena": arena = true
            case "--cores": arena = true; coresOnly = true
            case "--trace":
                if let kind = MissionKind(rawValue: args.removeFirst()) { ArenaRunner.trace(kind, seed: seed) }
                return
            case "--form":
                // What a runner brings home on each course on a day of a given form, to see what skill is worth.
                let form = Double(args.removeFirst()) ?? 0
                for kind in MissionKind.allCases {
                    print(String(format: "%@ %.2f bags a head at form %+.1f", kind.rawValue, ArenaRunner.par(kind, games: games, seed: seed, alive: 8, form: form).head, form))
                }
                return
            case "--scenes":
                // Launch arguments that open the app on each of the rarer scenes.
                for scene in Autopilot.scenes(seeds: seed...(seed + 400)) {
                    print("\(scene.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(scene.arguments)")
                }
                return
            case "--tune":
                let kv = args.removeFirst().split(separator: "=")
                if kv.count == 2, let x = Double(kv[1]) { Tuning.set(String(kv[0]), x) }
            default: break
            }
        }

        struct Summary {
            var games = 0
            var faithfulWins = 0
            var tables = 0
            var nights = 0, murders = 0, quiet = 0, groupWins = 0
            var banT = 0, banF = 0
            var firstT = 0
            var randomHit = 0.0
            var unanimous = 0
            var split = 0
            var certainByDay2 = 0
            var recruited = 0
            var unfinished = 0
            var kinds: [MissionKind: (played: Double, won: Double)] = [:]
            var brier = 0.0, brierN = 0
            var bins = Array(repeating: (sum: 0.0, hit: 0.0, n: 0.0), count: 5)
            var attempts = 0, sunk = 0, missions = 0
            var partnerDown = 0, bus = 0
            var lies = 0, caught = 0, callouts = 0, testimony = 0, challenges = 0
            var defences: [String: Int] = [:]
            var pairT = 0, sameT = 0, pairF = 0, sameF = 0
            /// Sightings by kind: seen of whoever used the hand, and seen of everyone else.
            var sights = Array(repeating: (q: 0.0, f: 0.0), count: SightingKind.allCases.count)
            var actingUnits = 0.0, otherUnits = 0.0
            /// Who traitors point at, against who would be pointed at by chance: [said, at a partner, partners expected].
            var aim: [String: (n: Double, hit: Double, base: Double)] = [:]
            /// Per table: how often a traitor does each thing to a partner and to a faithful, and a faithful to anyone.
            var acts: [String: (partner: Double, faithful: Double, honest: Double)] = [:]
            var chances = (partner: 0.0, faithful: 0.0, honest: 0.0)
            var firstNamed = (t: 0.0, f: 0.0), namers = (t: 0.0, f: 0.0)
        }

        func run(_ label: String, options: GameOptions) -> Summary {
            var s = Summary()
            for g in 0..<games {
                var game = Game(seed: seed &+ UInt64(g) &* 7919, humanName: nil, options: options)
                // Chance that a uniformly random banishment at the first table hits a traitor.
                s.randomHit += 2.0 / 8.0
                // Step manually so calibration can be sampled each evening.
                var steps = 0
                var sampledDay = 0
                while game.phase != .gameOver, steps < 500 {
                    game.advance(.next)
                    steps += 1
                    if game.phase == .missionResult, game.day != sampledDay {
                        sampledDay = game.day
                        if let run = game.mission {
                            // What was seen of whoever used the hand, against everyone else.
                            for p in run.order {
                                let acting = p == run.runner && run.runnerAttempt
                                if acting { s.actingUnits += 1 } else { s.otherUnits += 1 }
                                for sg in run.sightings where sg.subject == p {
                                    if acting { s.sights[sg.kind.index].q += 1 } else { s.sights[sg.kind.index].f += 1 }
                                }
                            }
                        }
                        let pub = game.publicSuspicion()
                        for p in game.alive {
                            let truth = game.players[p].role == .traitor ? 1.0 : 0.0
                            s.brier += (pub[p] - truth) * (pub[p] - truth)
                            s.brierN += 1
                            let b = min(4, Int(pub[p] * 5))
                            s.bins[b].sum += pub[p]; s.bins[b].hit += truth; s.bins[b].n += 1
                        }
                        if game.day == 2, game.aliveTraitors.contains(where: { pub[$0] > 0.9 }) { s.certainByDay2 += 1 }
                    }
                }
                if game.phase != .gameOver { s.unfinished += 1; continue }
                for case .mission(let r) in game.log {
                    var k = s.kinds[r.kind] ?? (0, 0)
                    k.played += 1
                    if r.groupWon { k.won += 1 }
                    s.kinds[r.kind] = k
                }
                // How often two traitors write the same name, against two faithful.
                var ballots: [Int: [(PlayerID, PlayerID, Role)]] = [:]
                var live = Array(repeating: Role.faithful, count: game.players.count)
                for p in game.players where p.role == .traitor && !p.wasRecruited { live[p.id] = .traitor }
                for event in game.log {
                    if case .vote(let day, 1, let voter, let target) = event { ballots[day, default: []].append((voter, target, live[voter])) }
                    if case .night(_, nil, true) = event { for p in game.players where p.wasRecruited { live[p.id] = .traitor } }
                }
                for day in ballots.keys.sorted() {
                    let b = ballots[day]!
                    for i in b.indices {
                        for j in b.indices where j > i && b[i].2 == b[j].2 {
                            if b[i].2 == .traitor { s.pairT += 1; if b[i].1 == b[j].1 { s.sameT += 1 } }
                            else { s.pairF += 1; if b[i].1 == b[j].1 { s.sameF += 1 } }
                        }
                    }
                }
                // What traitors actually do, to set the likelihood ratios from.
                var role = Array(repeating: Role.faithful, count: game.players.count)
                for p in game.players where p.role == .traitor && !p.wasRecruited { role[p.id] = .traitor }
                var up = Array(repeating: true, count: game.players.count)
                var first: [PlayerID: PlayerID] = [:]
                func note(_ key: String, _ from: PlayerID, _ to: PlayerID) {
                    var act = s.acts[key] ?? (0, 0, 0)
                    if role[from] != .traitor { act.honest += 1 } else if role[to] == .traitor { act.partner += 1 } else { act.faithful += 1 }
                    s.acts[key] = act
                    guard role[from] == .traitor else { return }
                    let others = up.indices.filter { up[$0] && $0 != from }
                    guard !others.isEmpty else { return }
                    var a = s.aim[key] ?? (0, 0, 0)
                    a.n += 1
                    if role[to] == .traitor { a.hit += 1 }
                    a.base += Double(others.filter { role[$0] == .traitor }.count) / Double(others.count)
                    s.aim[key] = a
                }
                for event in game.log {
                    switch event {
                    case .statement(let st):
                        guard let t = st.target else { break }
                        if st.kind.names, first[t] == nil { first[t] = st.speaker }
                        switch st.kind {
                        case .accuse, .callout, .challenge: note("accuse", st.speaker, t)
                        case .answer, .declare, .selfDefend: note("soft", st.speaker, t)
                        case .defend: note("defend", st.speaker, t)
                        case .vouch: note("vouch", st.speaker, t)
                        case .doubt: note("doubt", st.speaker, t)
                        default: break
                        }
                    case .vote(_, let round, let voter, let target):
                        if round == 1 { note("vote", voter, target) }
                    case .banished(_, let player, let r):
                        let ts = Double(up.indices.filter { up[$0] && role[$0] == .traitor }.count)
                        let fs = Double(up.indices.filter { up[$0] && role[$0] == .faithful }.count)
                        s.chances.partner += ts * (ts - 1)
                        s.chances.faithful += ts * fs
                        s.chances.honest += fs * (ts + fs - 1)
                        up[player] = false
                        if r == .faithful, let f = first[player] {
                            if role[f] == .traitor { s.firstNamed.t += 1 } else { s.firstNamed.f += 1 }
                            for o in up.indices where up[o] || o == f {
                                if role[o] == .traitor { s.namers.t += 1 } else { s.namers.f += 1 }
                            }
                        }
                        first = [:]
                    case .night(_, let victim, let recruitNight):
                        if let victim { up[victim] = false }
                        if recruitNight, victim == nil { for p in game.players where p.wasRecruited { role[p.id] = .traitor } }
                    default: break
                    }
                }
                s.attempts += game.tally.sabotageAttempts; s.sunk += game.tally.daysSunk
                s.missions += game.log.filter { if case .mission = $0 { return true } else { return false } }.count
                s.partnerDown += game.tally.partnerDown; s.bus += game.tally.busVotes
                s.lies += game.tally.liesTold; s.caught += game.tally.liesCaught
                s.callouts += game.tally.callouts; s.testimony += game.tally.testimony; s.challenges += game.tally.challenges
                for (k, v) in game.tally.defences { s.defences[k, default: 0] += v }
                s.games += 1
                if game.winner == .faithful { s.faithfulWins += 1 }
                let t = game.tally
                s.tables += t.roundTables
                s.nights += t.nights; s.murders += t.murders; s.quiet += t.quietNights; s.groupWins += t.groupWins
                s.banT += t.banishedTraitors; s.banF += t.banishedFaithful
                if t.firstBanishedTraitor == true { s.firstT += 1 }
                s.unanimous += t.unanimous
                if t.firstTableSplit { s.split += 1 }
                if t.recruited { s.recruited += 1 }
            }
            let n = Double(max(s.games, 1))
            func pct(_ x: Double) -> String { String(format: "%5.1f%%", 100 * x) }
            print("== \(label) (\(s.games) games, \(s.unfinished) unfinished)")
            print("  faithful win rate        \(pct(Double(s.faithfulWins) / n))")
            print("  round tables per game    \(String(format: "%.2f", Double(s.tables) / n))")
            print("  murder on nights         \(pct(Double(s.murders) / Double(max(s.nights, 1))))   quiet nights \(pct(Double(s.quiet) / Double(max(s.nights, 1))))")
            print("  company won its mission  \(pct(Double(s.groupWins) / Double(max(s.missions, 1))))")
            print("  banishments hit traitor  \(pct(Double(s.banT) / Double(max(s.banT + s.banF, 1))))")
            print("  first table hits traitor \(pct(Double(s.firstT) / n))   (random: 25.0%)")
            print("  unanimous votes          \(pct(Double(s.unanimous) / Double(max(s.tables, 1))))")
            print("  first table split        \(pct(Double(s.split) / n))")
            print("  traitor >0.9 by day 2    \(pct(Double(s.certainByDay2) / n))")
            print("  recruitment happened     \(pct(Double(s.recruited) / n))")
            print("  public Brier score       \(String(format: "%.3f", s.brier / Double(max(s.brierN, 1))))")
            let cal = s.bins.map { $0.n > 0 ? String(format: "%.2f→%.2f", $0.sum / $0.n, $0.hit / $0.n) : "-" }.joined(separator: "  ")
            print("  calibration (said→true)  \(cal)")
            print("  hand used / sank the day \(pct(Double(s.attempts) / Double(max(s.missions, 1)))) / \(pct(Double(s.sunk) / Double(max(s.attempts, 1))))")
            print("  partner voted for a banished traitor \(pct(Double(s.bus) / Double(max(s.partnerDown, 1))))")
            print("  same name: traitor pairs \(pct(Double(s.sameT) / Double(max(s.pairT, 1))))   faithful pairs \(pct(Double(s.sameF) / Double(max(s.pairF, 1))))")
            print("  per game: callouts \(String(format: "%.2f", Double(s.callouts) / n))  testimony \(String(format: "%.2f", Double(s.testimony) / n))  lies \(String(format: "%.2f", Double(s.lies) / n))  challenges \(String(format: "%.2f", Double(s.challenges) / n))")
            print("  lies caught              \(pct(Double(s.caught) / Double(max(s.lies, 1))))")
            let total = Double(max(s.defences.values.reduce(0, +), 1))
            print("  defences                 " + s.defences.keys.sorted().map { "\($0) \(Int((100 * Double(s.defences[$0]!) / total).rounded()))%" }.joined(separator: "  "))
            let ratios = s.aim.keys.sorted().map { key -> String in
                let a = s.aim[key]!
                let hit = a.hit / max(a.n, 1), base = a.base / max(a.n, 1)
                return String(format: "%@ %.2f/%.2f", key, hit / max(base, 1e-6), (1 - hit) / max(1 - base, 1e-6))
            }
            let seen = SightingKind.allCases.map { k -> String in
                let q = s.sights[k.index].q / max(s.actingUnits, 1), f = s.sights[k.index].f / max(s.otherUnits, 1)
                return String(format: "%@ %.1f (%.0f%% / %.0f%%)", k.rawValue, q / max(f, 1e-6), 100 * q, 100 * f)
            }
            print("  seen of the hand         " + seen.joined(separator: "  "))
            print("  traitor aim (both/only)  " + ratios.joined(separator: "  "))
            let rates = s.acts.keys.sorted().map { key -> String in
                let a = s.acts[key]!
                let honest = max(a.honest / max(s.chances.honest, 1), 1e-9)
                return String(format: "%@ %.2f/%.2f", key, a.partner / max(s.chances.partner, 1) / honest, a.faithful / max(s.chances.faithful, 1) / honest)
            }
            print("  against a faithful's rate " + rates.joined(separator: "  "))
            print("  first to name a faithful \(String(format: "%.2f", (s.firstNamed.t / max(s.namers.t, 1)) / max(s.firstNamed.f / max(s.namers.f, 1), 1e-6))) times likelier from a traitor")
            print("  company wins by mission  " + MissionKind.allCases.compactMap { kind in
                s.kinds[kind].map { "\(kind.rawValue) \(Int((100 * $0.won / max($0.played, 1)).rounded()))%" }
            }.joined(separator: "  "))
            return s
        }

        if seat {
            // A scripted stand-in for the human, to check no lazy strategy beats the bots
            // and that the bots do not single the human out.
            for (label, pref, hand, herd, effort) in [("faithful, votes with the table", RolePreference.faithful, false, true, 1.0),
                                                       ("faithful, votes at random", .faithful, false, false, 1.0),
                                                       ("faithful, idle in every mission", .faithful, false, true, 0.0),
                                                       ("traitor, never uses the hand", .traitor, false, true, 1.0),
                                                       ("traitor, idle in every mission", .traitor, false, true, 0.0),
                                                       ("traitor, always uses the hand", .traitor, true, true, 1.0)] {
                var wins = 0, firstOut = 0, banished = 0, murdered = 0, missions = 0, won = 0
                for g in 0..<games {
                    var game = Game(seed: seed &+ UInt64(g) &* 104729, humanName: "Seat", preference: pref)
                    var r = SeededRNG(seed: UInt64(g) &+ 99)
                    var steps = 0
                    while game.phase != .gameOver, steps < 600 {
                        game.advance(seatInput(game, hand: hand, herd: herd, effort: effort, rng: &r))
                        steps += 1
                    }
                    if game.players[0].role == game.winner { wins += 1 }
                    if game.players[0].fate == .banished { banished += 1; if game.players[0].fateDay == 1 { firstOut += 1 } }
                    if game.players[0].fate == .murdered { murdered += 1 }
                    for case .mission(let r) in game.log {
                        missions += 1
                        if r.groupWon { won += 1 }
                    }
                }
                let n = Double(games)
                print("== seat 0: \(label)")
                print(String(format: "  wins %.1f%%   banished %.1f%% (day 1: %.1f%%)   murdered %.1f%%   company won its mission %.1f%%",
                             100 * Double(wins) / n, 100 * Double(banished) / n, 100 * Double(firstOut) / n, 100 * Double(murdered) / n,
                             100 * Double(won) / Double(max(missions, 1))))
            }
        } else if transcript {
            var game = Game(seed: seed, humanName: nil)
            print("Traitors: " + game.team.map { game.players[$0].name }.joined(separator: ", "))
            var lastPhase = game.phase
            while game.phase != .gameOver {
                game.advance(.next)
                if game.phase != lastPhase || !game.feed.isEmpty {
                    print("--- day \(game.day) \(game.phase.rawValue)")
                    for b in game.feed { print("   [\(b.kind.rawValue)] \(b.text)") }
                    lastPhase = game.phase
                }
            }
            print("Winner: \(game.winner?.rawValue ?? "?")")
        } else if arena {
            // Every mission played out on its course by bots, so the sightings are the real thing.
            if !coresOnly { _ = run("smart vs smart, missions played out", options: GameOptions(arena: true)) }
            ArenaRunner.report(games: games, seed: seed)
        } else {
            _ = run("smart vs smart", options: GameOptions())
            _ = run("random faithful", options: GameOptions(randomFaithful: true))
            _ = run("random traitors", options: GameOptions(randomTraitors: true))
        }

    }

    /// An unimaginative player, silent at the table. `effort` is how much of an ordinary share they put into each mission.
    static func seatInput(_ game: Game, hand: Bool, herd: Bool, effort: Double = 1, rng: inout SeededRNG) -> HumanInput {
        switch game.phase {
        case .mission:
            return .mission(MissionResult(effort: effort, sabotage: hand && game.humanIsTraitor ? MissionRun.sabotageCost : 0))
        case .roundTable:
            return .say(.pass, target: nil, chip: nil)
        case .voting:
            var pool = game.choices
            if game.humanIsTraitor { let f = pool.filter { game.players[$0].role != .traitor }; if !f.isEmpty { pool = f } }
            if herd {
                let ix = game.view().index
                var counts = Array(repeating: 0, count: game.players.count)
                for v in game.alive { if let t = ix.declared(day: game.day, by: v) { counts[t] += 1 } }
                if let best = pool.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 { return .vote(best) }
            }
            return .vote(rng.pick(pool))
        case .night:
            switch game.nightChoice {
            case .murder: return .murder(game.partnerAdvice ?? rng.pick(game.choices))
            case .recruit: return .recruit(rng.pick(game.choices))
            case .offer: return .recruitAnswer(true)
            case .none: return .next
            }
        case .finaleChoice: return .finale(end: game.humanIsTraitor)
        default: return .next
        }
    }
}
