import Foundation
import Testing
@testable import TraitorsEngine

/// Plays the human seat with simple fixed choices so a full game can be driven in a test.
@MainActor
func autoInput(_ game: Game) -> HumanInput {
    switch game.phase {
    case .mission:
        return .mission(MissionResult())
    case .roundTable:
        return .say(.pass, target: nil, chip: nil)
    case .voting:
        return .vote(game.choices[0])
    case .night:
        switch game.nightChoice {
        case .murder: return .murder(game.choices[0])
        case .recruit: return .recruit(game.choices[0])
        case .offer: return .recruitAnswer(true)
        case .none: return .next
        }
    case .finaleChoice:
        return .finale(end: false)
    default:
        return .next
    }
}

@MainActor
func play(seed: UInt64, name: String?, preference: RolePreference = .random) -> Game {
    var game = Game(seed: seed, humanName: name, preference: preference)
    var steps = 0
    while game.phase != .gameOver, steps < 600 {
        game.advance(autoInput(game))
        steps += 1
    }
    return game
}

@MainActor
@Test func allBotGamesTerminateWithAWinner() {
    for seed in 1...200 {
        let game = play(seed: UInt64(seed), name: nil)
        #expect(game.phase == .gameOver)
        #expect(game.winner != nil)
    }
}

@MainActor
@Test func humanGamesTerminateInEveryRole() {
    for seed in 1...120 {
        for pref in RolePreference.allCases {
            let game = play(seed: UInt64(seed), name: "Tester", preference: pref)
            #expect(game.phase == .gameOver, "seed \(seed) \(pref) stuck in \(game.phase)")
            #expect(game.winner != nil)
        }
    }
}

@MainActor
@Test func sameSeedGivesSameGame() throws {
    let a = play(seed: 77, name: "Tester", preference: .traitor)
    let b = play(seed: 77, name: "Tester", preference: .traitor)
    let enc = JSONEncoder()
    enc.outputFormatting = .sortedKeys
    #expect(try enc.encode(a.log) == enc.encode(b.log))
    #expect(a.winner == b.winner)
}

@MainActor
@Test func rolePreferenceIsHonoured() {
    for seed in 1...40 {
        #expect(Game(seed: UInt64(seed), humanName: "T", preference: .traitor).players[0].role == .traitor)
        #expect(Game(seed: UInt64(seed), humanName: "T", preference: .faithful).players[0].role == .faithful)
        #expect(Game(seed: UInt64(seed), humanName: "T").team.count == Rules.traitors)
    }
}

@MainActor
@Test func saveAndLoadMidGameContinuesIdentically() throws {
    var game = Game(seed: 9, humanName: "Tester", preference: .faithful)
    for _ in 0..<14 { game.advance(autoInput(game)) }
    let data = try JSONEncoder().encode(game)
    var restored = try JSONDecoder().decode(Game.self, from: data)
    var steps = 0
    while game.phase != .gameOver, steps < 600 {
        game.advance(autoInput(game))
        restored.advance(autoInput(restored))
        steps += 1
    }
    #expect(restored.phase == .gameOver)
    #expect(restored.winner == game.winner)
    #expect(restored.log.count == game.log.count)
}

@MainActor
@Test func faithfulBotsNeverSuspectThemselvesAndBeliefsAreNormalised() {
    var game = Game(seed: 3, humanName: nil)
    while game.phase != .missionResult { game.advance(.next) }
    let v = game.view()
    for b in game.aliveBots where game.players[b].role == .faithful {
        let belief = Inference.compute(view: v, observer: FaithfulBrain.observer(game.minds[b], game.players[b].personality))
        #expect(belief.marginal(b) == 0)
        #expect(abs(belief.weights.reduce(0, +) - 1) < 1e-9)
        let total = (0..<Rules.seats).reduce(0.0) { $0 + belief.marginal($1) }
        #expect(abs(total - Double(Rules.traitors)) < 1e-9)
    }
}

@MainActor
@Test func theNightIsOnlyTheTraitorsAfterALoss() {
    var quiet = 0, afterLoss = 0
    for seed in 1...150 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        var days: [Int: Bool] = [:]
        while game.phase != .gameOver {
            if game.phase == .missionResult, let r = game.report { days[game.day] = r.groupWon }
            game.advance(.next)
        }
        for event in game.log {
            guard case .night(let day, let victim, let recruitNight) = event, let won = days[day] else { continue }
            let acted = victim != nil || recruitNight
            if won {
                quiet += 1
                #expect(!acted, "seed \(seed): the traitors had night \(day) after the company won")
            } else {
                afterLoss += 1
                #expect(acted, "seed \(seed): nothing happened on night \(day), which was the traitors'")
            }
        }
    }
    #expect(quiet > 20 && afterLoss > 20)
}

@MainActor
func playToMission(seed: UInt64, preference: RolePreference) -> Game {
    var game = Game(seed: seed, humanName: "Tester", preference: preference)
    while game.phase != .mission { game.advance(.next) }
    return game
}

/// Plays on from a mission that has just been handed in to the night that follows, and through it.
@MainActor
func playThroughNight(_ game: Game) -> (choice: NightChoice, game: Game) {
    var game = game
    let day = game.day
    var choice = NightChoice.none
    var steps = 0
    while game.phase != .gameOver, game.day == day, steps < 200 {
        if game.phase == .night { choice = game.nightChoice }
        game.advance(autoInput(game))
        steps += 1
    }
    return (choice, game)
}

@MainActor
func night(_ day: Int, in game: Game) -> (victim: PlayerID?, recruit: Bool)? {
    for case .night(day, let victim, let recruit) in game.log { return (victim, recruit) }
    return nil
}

@MainActor
@Test func aWinKeepsTheTraitorsInWhateverTheirHandDid() {
    for seed in 1...40 {
        var game = playToMission(seed: UInt64(seed), preference: .traitor)
        game.mission?.runner = nil
        game.advance(.mission(MissionResult(sabotage: 3, teamTotal: 999, sunkBy: 0)))
        #expect(game.report?.groupWon == true && game.sunkBy == nil && !game.traitorsMayAct)
        let quiet = playThroughNight(game)
        if let n = night(1, in: quiet.game) {
            #expect(n.victim == nil && !n.recruit, "seed \(seed)")
            #expect(quiet.choice == .none)
            #expect(quiet.game.feed.contains { $0.text == Host.quietNight })
        }
    }
}

@MainActor
@Test func murderFollowsAGroupLoss() {
    for seed in 1...40 {
        var game = playToMission(seed: UInt64(seed), preference: .traitor)
        game.mission?.runner = nil
        game.advance(.mission(MissionResult(teamTotal: 0)))
        #expect(game.report?.groupWon == false && game.sunkBy == nil && game.traitorsMayAct)
        let after = playThroughNight(game)
        if let n = night(1, in: after.game) {
            // The night is theirs: a murder, or a recruitment if the table has just taken one of them.
            #expect(n.victim != nil || n.recruit, "seed \(seed)")
            if after.game.players[0].fate != .banished { #expect(after.choice != .none) }
        }
    }
}

/// Games with the human faithful, stopped at a mission where one bot traitor is left with the recruitment still to use.
@MainActor
func loneTraitorMissions() -> [Game] {
    var out: [Game] = []
    for seed in 1...200 {
        var game = Game(seed: UInt64(seed), humanName: "Tester", preference: .faithful)
        var steps = 0
        while game.phase != .gameOver, steps < 600 {
            if game.phase == .mission, game.aliveTraitors.count == 1, !game.recruitmentUsed, game.alive.count >= 6 {
                out.append(game)
                break
            }
            game.advance(autoInput(game))
            steps += 1
        }
        if out.count == 12 { break }
    }
    return out
}

@MainActor
@Test func groupWinBlocksRecruit() {
    let found = loneTraitorMissions()
    #expect(found.count >= 5)
    var blocked = 0, recruited = 0
    for start in found {
        let day = start.day
        var won = start
        won.mission?.runner = nil
        var lost = won
        let lone = won.aliveTraitors[0]

        won.advance(.mission(MissionResult(teamTotal: 999)))
        let quiet = playThroughNight(won).game
        if let n = night(day, in: quiet) {
            blocked += 1
            #expect(n.victim == nil && !n.recruit)
            #expect(!quiet.recruitmentUsed && !quiet.tally.recruited)
            #expect(quiet.aliveTraitors == [lone])
        }

        lost.advance(.mission(MissionResult(teamTotal: 0)))
        let fell = playThroughNight(lost).game
        if let n = night(day, in: fell) {
            recruited += 1
            #expect(n.recruit && fell.recruitmentUsed)
        }
    }
    #expect(blocked > 0 && recruited > 0)
}

@MainActor
@Test func theHandIsOpenOnARecruitDay() {
    var tried = 0
    for seed in 1...150 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        while game.phase != .gameOver {
            game.advance(.next)
            if game.phase == .missionResult, game.aliveTraitors.count == 1, !game.recruitmentUsed, game.mission?.runnerAttempt == true {
                tried += 1
            }
        }
    }
    // A lone traitor only sees another mission when a win has already kept them in once.
    #expect(tried > 3)
}

@MainActor
@Test func aFaithfulHumanCannotSinkTheDay() {
    for seed in 1...40 {
        var game = playToMission(seed: UInt64(seed), preference: .faithful)
        var claimed = game
        game.advance(.mission(MissionResult(effort: 1, sabotage: 3)))
        claimed.advance(.mission(MissionResult(effort: 1)))
        // Whatever a faithful's result says about the hand is ignored.
        #expect(game.sunkBy != 0 && game.mission?.humanAttempt == false)
        #expect(game.report?.teamTotal == claimed.report?.teamTotal)
    }
}

@MainActor
@Test func aMissionKeepsNoPerPlayerNumbers() {
    var game = playToMission(seed: 4, preference: .faithful)
    game.advance(.mission(MissionResult()))
    let report = game.report!
    // The table is told what the company did together and nothing about anyone in it.
    #expect(Mirror(reflecting: report).children.compactMap(\.label) == ["kind", "day", "teamTotal", "teamGoal", "groupWon", "potEarned"])
    #expect(Mirror(reflecting: MissionResult()).children.compactMap(\.label) == ["effort", "sabotage", "teamTotal", "sunkBy", "ledger"])
    #expect(report.groupWon == (report.teamTotal >= report.teamGoal))
    #expect(game.feed.contains { $0.kind == .result && $0.text.contains("between you") })
    // Nothing said about the mission names a player.
    for beat in game.feed where beat.kind == .result || beat.kind == .host {
        for p in game.players { #expect(!beat.text.contains(p.name), "\(beat.text)") }
    }
}

@MainActor
@Test func theDiceGiveTheCompanyTheOddsTheGauntletDoes() {
    for kind in MissionKind.allCases {
        for alive in 5...8 {
            let alone = ArenaRunner.abstractWinRate(kind, games: 3000, seed: 3, alive: alive, effort: 1, sabotage: false)
            #expect(abs(alone - 0.75) < 0.08, "\(kind) left alone with \(alive) alive: \(alone)")
            let idle = ArenaRunner.abstractWinRate(kind, games: 3000, seed: 4, alive: alive, effort: 0, sabotage: false)
            #expect(abs(idle - 0.28) < 0.08, "\(kind) with the player idle and \(alive) alive: \(idle)")
            let against = ArenaRunner.abstractWinRate(kind, games: 3000, seed: 5, alive: alive, effort: 1, sabotage: true)
            #expect(abs(against - 0.13) < 0.08, "\(kind) with the hand against it and \(alive) alive: \(against)")
        }
    }
}

@MainActor
@Test func theHandCostsTheCompanyItsDayMoreOftenThanNot() {
    for kind in MissionKind.allCases {
        let alone = ArenaRunner.winRate(kind, games: 24, seed: 3, sabotage: false)
        let against = ArenaRunner.winRate(kind, games: 24, seed: 3, sabotage: true)
        #expect(alone > 0.5, "\(kind) left alone: \(alone)")
        #expect(against < 0.5 && against < alone, "\(kind) with the hand against it: \(against)")
    }
}

@MainActor
@Test func aHumanWhoIsOutWatchesTheMissionAndAnyInputMovesOn() {
    var watched = 0
    for seed in 1...60 {
        var game = Game(seed: UInt64(seed), humanName: "Tester", preference: .faithful)
        var steps = 0
        while game.phase != .gameOver, steps < 600 {
            if game.phase == .mission, !game.humanAlive {
                watched += 1
                game.advance(.next)
                #expect(game.phase == .missionResult)
                #expect(game.mission?.human == nil)
            } else {
                game.advance(autoInput(game))
            }
            steps += 1
        }
        #expect(game.phase == .gameOver)
    }
    #expect(watched > 0)
}

// MARK: - Beliefs

@MainActor
@Test func beliefsWorkForAnyTeamSize() {
    var game = Game(seed: 5, humanName: nil)
    while game.phase != .voteReveal { game.advance(.next) }
    for size in 1...3 {
        var replay = Replay(count: Rules.seats, observer: .publicView(count: Rules.seats), teamSize: size)
        // A reveal fixes one seat, which a team of one cannot always absorb, so feed only what was said.
        replay.feed(game.log.filter { if case .banished = $0 { return false } else { return true } })
        let belief = replay.belief()
        #expect(abs(belief.weights.reduce(0, +) - 1) < 1e-9)
        let total = (0..<Rules.seats).reduce(0.0) { $0 + belief.marginal($1) }
        #expect(abs(total - Double(size)) < 1e-9, "team of \(size)")
    }
}

@MainActor
@Test func feedingTheLogInPiecesGivesTheSameBelief() {
    var game = Game(seed: 8, humanName: nil)
    while game.phase != .gameOver { game.advance(.next) }
    let observer = FaithfulBrain.observer(game.minds[3], game.players[3].personality)
    let whole = Inference.compute(log: game.log, count: Rules.seats, observer: observer)
    var replay = Replay(count: Rules.seats, observer: observer)
    for event in game.log {
        _ = replay.belief()
        replay.feed(event)
    }
    let pieces = replay.belief()
    #expect(whole.masks == pieces.masks)
    for (a, b) in zip(whole.weights, pieces.weights) { #expect(abs(a - b) < 1e-12) }
}

@MainActor
@Test func theTopSuspectAlwaysComesWithReasons() {
    for seed in 1...20 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        while game.phase != .voteReveal { game.advance(.next) }
        let v = game.view()
        for b in game.aliveBots where game.players[b].role == .faithful {
            let belief = Inference.compute(view: v, observer: FaithfulBrain.observer(game.minds[b], game.players[b].personality))
            guard let top = FaithfulBrain.topSuspect(v, belief, me: b), belief.marginal(top) > 0.5, belief.marginal(top) < 1 else { continue }
            #expect(!belief.reasons(for: top).isEmpty, "seed \(seed): \(b) suspects \(top) for no reason")
        }
    }
}

// MARK: - Sightings and testimony

@MainActor
@Test func whatIsSeenStaysPrivateUntilSomeoneSaysIt() throws {
    for seed in 1...40 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        while game.phase != .gameOver { game.advance(.next) }
        for s in game.sightings {
            #expect(!s.witnesses.has(s.subject))
            #expect(s.witnesses != 0)
        }
        // Nothing in a mission report gives away what was seen.
        for case .mission(let r) in game.log {
            let text = String(data: try JSONEncoder().encode(r), encoding: .utf8) ?? ""
            #expect(!text.contains("witnesses"))
        }
        // No two honest sightings of the same player on the same day can contradict each other.
        for a in game.sightings where a.kind == .inView {
            #expect(!game.sightings.contains { $0.day == a.day && $0.subject == a.subject && $0.kind.suspicious })
        }
    }
}

@MainActor
@Test func sightingsAreAsTellingAsTheTableAssumes() {
    // Eight average players, seat 1 with the shadow's hand, over many missions.
    var acting = 0.0, others = 0.0
    var seenActing = Array(repeating: 0.0, count: SightingKind.allCases.count), seenOthers = seenActing
    var rng = SeededRNG(seed: 31)
    for i in 0..<6000 {
        var run = MissionRun(kind: .greatHall, day: 1, alive: Array(0..<Rules.seats), human: nil, traitors: [1, 2], runner: 1,
                             traits: Array(repeating: .average, count: Rules.seats), quirkSeed: UInt64(i), rng: rng.fork())
        run.resolve(human: nil)
        for p in run.order {
            let on = p == 1 && run.runnerAttempt
            if on { acting += 1 } else { others += 1 }
            for s in run.sightings where s.subject == p {
                #expect(!s.witnesses.has(p) && s.witnesses != 0)
                if on { seenActing[s.kind.index] += 1 } else { seenOthers[s.kind.index] += 1 }
            }
        }
    }
    #expect(acting > 1000)
    for kind in [SightingKind.offTask, .loiter, .emptyHanded, .startled] {
        let ratio = (seenActing[kind.index] / acting) / (seenOthers[kind.index] / others)
        #expect(abs(ratio / Tuning.sight(kind) - 1) < 0.2, "\(kind): \(ratio) against \(Tuning.sight(kind))")
    }
    #expect(seenOthers[SightingKind.inView.index] > 0)
}

/// A table of eight on day one, just after a mission the company lost or won.
@MainActor
func quietTable(won: Bool = false) -> [PublicEvent] {
    [.mission(MissionReport(kind: .greatHall, day: 1, teamTotal: won ? 50 : 40, teamGoal: 45, groupWon: won, potEarned: 0))]
}

@MainActor
@Test func aLostDayMakesWhatWasSeenCountForMore() {
    let n = Rules.seats
    // Seat 0 saw seat 2 standing by a lever when its trap went.
    var me = Observer(id: 0, gut: Array(repeating: 0, count: n), temper: 1)
    me.sightings = [Sighting(day: 1, subject: 2, kind: .atTheWorks, witnesses: SeatMask.seat(0))]
    func suspicion(_ log: [PublicEvent]) -> Double { Inference.compute(log: log, count: n, observer: me).marginal(2) }
    var blank = me
    blank.sightings = []
    func baseline(_ log: [PublicEvent]) -> Double { Inference.compute(log: log, count: n, observer: blank).marginal(2) }

    // A day the company lost is likelier to have had a hand against it, so what was seen weighs more.
    #expect(suspicion(quietTable(won: false)) > suspicion(quietTable(won: true)) + 0.02)
    #expect(suspicion(quietTable(won: true)) > baseline(quietTable(won: true)) + 0.02)
    // With nothing seen of anyone, how the day went says nothing about who.
    #expect(abs(baseline(quietTable(won: true)) - baseline(quietTable(won: false))) < 1e-9)
    // The quiet night after a win follows from the win, and adds nothing to it.
    let quiet = PublicEvent.night(day: 1, victim: nil, recruitNight: false)
    #expect(abs(suspicion(quietTable(won: true) + [quiet]) - suspicion(quietTable(won: true))) < 1e-9)
}

@MainActor
func says(_ speaker: PlayerID, _ kind: StatementKind, _ target: PlayerID, _ chip: Chip) -> PublicEvent {
    .statement(Statement(day: 1, speaker: speaker, kind: kind, target: target, chip: chip, text: ""))
}

@MainActor
@Test func testimonyOnlyCountsWhereTheSpeakerIsFaithful() {
    let n = Rules.seats
    let before = Inference.compute(log: quietTable(), count: n, observer: .publicView(count: n))
    let chip = Chip(kind: .sighting, subject: 2, day: 1, sight: .emptyHanded, strength: 1)
    let after = Inference.compute(log: quietTable() + [says(1, .doubt, 2, chip)], count: n, observer: .publicView(count: n))
    // Seat 2 looks worse overall.
    #expect(after.marginal(2) > before.marginal(2) + 0.02)
    // But not in the worlds where the witness is the traitor: there the two of them together are less likely than before.
    let pair = SeatMask.seat(1) | SeatMask.seat(2)
    #expect(after.mass(team: pair) < before.mass(team: pair))
}

@MainActor
@Test func hearingWhatYouAlreadySawChangesNothingAboutThem() {
    let n = Rules.seats
    let seen = Sighting(day: 1, subject: 2, kind: .emptyHanded, witnesses: SeatMask.seat(0) | SeatMask.seat(1))
    var me = Observer.publicView(count: n)
    me.id = 0
    me.sightings = [seen]
    let before = Inference.compute(log: quietTable(), count: n, observer: me)
    // A flat statement with no target, so only the testimony itself is in play.
    let told = PublicEvent.statement(Statement(day: 1, speaker: 1, kind: .pass, target: nil,
                                               chip: Chip(kind: .sighting, subject: 2, day: 1, sight: .emptyHanded, strength: 1), text: ""))
    let after = Inference.compute(log: quietTable() + [told], count: n, observer: me)
    let other = SeatMask.seat(2) | SeatMask.seat(5)
    #expect(abs(after.mass(team: other) / after.mass(team: SeatMask.seat(3) | SeatMask.seat(5))
                - before.mass(team: other) / before.mass(team: SeatMask.seat(3) | SeatMask.seat(5))) < 1e-9)
}

@MainActor
@Test func aWitnessWhoKnowsBetterSuspectsTheLiar() {
    let n = Rules.seats
    var me = Observer.publicView(count: n)
    me.id = 0
    me.sightings = [Sighting(day: 1, subject: 2, kind: .inView, witnesses: SeatMask.seat(0))]
    let before = Inference.compute(log: quietTable(), count: n, observer: me)
    let lie = Chip(kind: .sighting, subject: 2, day: 1, sight: .emptyHanded, strength: 1)
    let after = Inference.compute(log: quietTable() + [says(1, .accuse, 2, lie)], count: n, observer: me)
    #expect(after.marginal(1) > 0.8)
    #expect(after.marginal(1) > before.marginal(1) + 0.3)
}

@MainActor
@Test func aSightingBeforeARecruitNightCountsAgainstWhoeverWasSeenAndNobodyElse() {
    let n = Rules.seats
    let chip = Chip(kind: .sighting, subject: 2, day: 1, sight: .atTheWorks, strength: 1)
    let day: [PublicEvent] = quietTable() + [says(1, .doubt, 2, chip)]
    let without: [PublicEvent] = quietTable()
    func after(_ log: [PublicEvent]) -> Belief {
        // Seat 7 is banished as a traitor, then the survivor recruits.
        let full = log + [.banished(day: 1, player: 7, role: .traitor), .night(day: 1, victim: nil, recruitNight: true)]
        return Inference.compute(log: full, count: n, observer: .publicView(count: n))
    }
    // The hand is open on a recruit day too, so what seat 2 was seen doing points at seat 2
    // as the traitor who was already there.
    #expect(after(day).marginal(2) > after(without).marginal(2) + 0.02)
    // It has no bearing on which of two players nobody mentioned was recruited by seat 4.
    let base = SeatMask.seat(7) | SeatMask.seat(4)
    func odds(_ b: Belief) -> Double { b.mass(team: base | SeatMask.seat(3)) / b.mass(team: base | SeatMask.seat(5)) }
    #expect(abs(odds(after(day)) - odds(after(without))) < 1e-9)
}

// MARK: - Planning

@MainActor
@Test func lookingAheadNeverMovesTheGame() throws {
    var game = Game(seed: 12, humanName: nil)
    while game.phase != .voteReveal { game.advance(.next) }
    let enc = JSONEncoder()
    enc.outputFormatting = .sortedKeys
    let before = try enc.encode(game)
    let v = game.view()
    let known = game.team.flatMap { game.minds[$0].exposed }
    let listeners = Listeners.build(view: v, team: game.team, known: known)
    let a = VoteSim.pBanish(view: v, listeners: listeners, fixed: [], rng: .derived(game.seed, 1))
    let b = VoteSim.pBanish(view: v, listeners: listeners, fixed: [], rng: .derived(game.seed, 1))
    #expect(a == b)
    #expect(abs(a.reduce(0, +) - 1) < 1e-9)
    let plan = TeamPlanner.plan(view: v, team: game.team, known: known, seed: game.seed)
    let again = TeamPlanner.plan(view: v, team: game.team, known: known, seed: game.seed)
    #expect(try enc.encode(plan) == enc.encode(again))
    #expect(try enc.encode(game) == before)
}

@MainActor
@Test func theTeamPlanSurvivesASave() throws {
    var game = Game(seed: 21, humanName: "Tester", preference: .traitor)
    while game.phase != .roundTable { game.advance(autoInput(game)) }
    #expect(game.teamPlan != nil)
    let restored = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
    #expect(restored.teamPlan?.scapegoat == game.teamPlan?.scapegoat)
    #expect(restored.teamPlan?.stances == game.teamPlan?.stances)
    #expect(restored.sightings == game.sightings)
}

@MainActor
@Test func aTraitorVouchesForAPartnerAtMostOnceATable() {
    for seed in 1...80 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        while game.phase != .gameOver { game.advance(.next) }
        var role = Array(repeating: Role.faithful, count: game.players.count)
        for p in game.players where p.role == .traitor && !p.wasRecruited { role[p.id] = .traitor }
        var count: [PlayerID: Int] = [:]
        for event in game.log {
            switch event {
            case .statement(let s):
                if let t = s.target, s.kind == .vouch || s.kind == .defend, role[s.speaker] == .traitor, role[t] == .traitor {
                    count[s.speaker, default: 0] += 1
                    #expect(count[s.speaker]! <= 1, "seed \(seed): \(s.speaker) spoke up for a partner twice at one table")
                }
            case .banished:
                count = [:]
            case .night(_, nil, true):
                for p in game.players where p.wasRecruited { role[p.id] = .traitor }
            default: break
            }
        }
    }
}

@MainActor
@Test func aTraitorIsNeverTheFirstToNameAPartner() {
    for seed in 201...280 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        while game.phase != .gameOver { game.advance(.next) }
        var role = Array(repeating: Role.faithful, count: game.players.count)
        for p in game.players where p.role == .traitor && !p.wasRecruited { role[p.id] = .traitor }
        var named: Set<PlayerID> = []
        var day = 0
        for event in game.log {
            switch event {
            case .statement(let s):
                // "Named" is anything said today that points the finger, by someone outside the team.
                if s.day != day { day = s.day; named = [] }
                guard let t = s.target, s.kind.names else { break }
                if role[s.speaker] == .traitor, role[t] == .traitor, s.kind == .accuse || s.kind == .callout {
                    #expect(named.contains(t), "seed \(seed): \(s.speaker) opened on partner \(t)")
                }
                if role[s.speaker] == .faithful { named.insert(t) }
            case .night(_, nil, true):
                for p in game.players where p.wasRecruited { role[p.id] = .traitor }
            default: break
            }
        }
    }
}

// MARK: - The table

@MainActor
@Test func whatBotsCiteFromTheRecordIsTrue() {
    for seed in 1...30 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        var checked = 0
        while game.phase != .gameOver {
            game.advance(.next)
            let v = game.view()
            for s in v.index.statements.dropFirst(checked) {
                guard let chip = s.chip else { continue }
                #expect(Chips.holds(chip, view: v), "seed \(seed) day \(s.day): \(s.speaker) cited \(chip.kind) falsely")
            }
            checked = v.index.statements.count
        }
    }
}

@MainActor
@Test func aMadeUpClaimFromTheRecordDoesNotHold() {
    var game = Game(seed: 6, humanName: nil)
    while game.phase != .gameOver { game.advance(.next) }
    let v = game.view()
    guard let b = v.index.banishments.first(where: { $0.role == .faithful }) else { return }
    let voters = v.index.votes[b.day]?[1] ?? [:]
    let innocent = (0..<Rules.seats).first { voters[$0] != nil && voters[$0] != b.player }
    if let innocent {
        #expect(!Chips.holds(Chip(kind: .votedOutFaithful, subject: innocent, day: b.day, other: b.player), view: v))
    }
    if let guilty = (0..<Rules.seats).first(where: { voters[$0] == b.player }) {
        #expect(Chips.holds(Chip(kind: .votedOutFaithful, subject: guilty, day: b.day, other: b.player), view: v))
    }
}

@MainActor
@Test func onlyTraitorsEverInventASighting() {
    var lies = 0
    for seed in 1...100 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        while game.phase != .gameOver { game.advance(.next) }
        var role = Array(repeating: Role.faithful, count: game.players.count)
        for p in game.players where p.role == .traitor && !p.wasRecruited { role[p.id] = .traitor }
        for event in game.log {
            if case .night(_, nil, true) = event { for p in game.players where p.wasRecruited { role[p.id] = .traitor } }
            guard case .statement(let s) = event, let chip = s.chip, chip.isTestimony else { continue }
            let real = game.sightings.contains { $0.day == chip.day && $0.subject == chip.subject && $0.kind == chip.sight && $0.witnesses.has(s.speaker) }
            if !real {
                lies += 1
                #expect(role[s.speaker] == .traitor, "seed \(seed): faithful \(s.speaker) invented a sighting")
            }
        }
        #expect(game.tally.liesCaught <= game.tally.liesTold)
    }
    #expect(lies > 0)
}

@MainActor
@Test func theHumanCanAnswerAChargeButNeverHasTo() {
    var answered = 0
    for seed in 1...80 {
        var game = Game(seed: UInt64(seed), humanName: "Tester", preference: seed % 2 == 0 ? .traitor : .faithful)
        var steps = 0
        while game.phase != .gameOver, steps < 600 {
            if game.phase == .roundTable {
                let options = game.defenceOptions()
                let step = game.tableStep
                if !options.isEmpty, seed % 3 == 0 {
                    game.advance(.rebut(options.count - 1))
                    answered += 1
                    #expect(game.log.contains { if case .statement(let s) = $0 { return s.speaker == 0 && s.defence != nil } else { return false } })
                } else {
                    game.advance(.say(.pass, target: nil, chip: nil))
                }
                // Either way the turn is spent.
                #expect(game.phase != .roundTable || game.tableStep != step)
            } else {
                game.advance(autoInput(game))
            }
            steps += 1
        }
        #expect(game.phase == .gameOver)
    }
    #expect(answered > 0)
}

@MainActor
@Test func theHumanIsToldWhatTheySawAndCanCiteIt() {
    var cited = 0
    for seed in 1...40 {
        var game = Game(seed: UInt64(seed), humanName: "Tester", preference: .faithful)
        while game.phase != .roundTable, game.phase != .gameOver { game.advance(autoInput(game)) }
        guard game.phase == .roundTable else { continue }
        let mine = game.minds[0].seen.filter { $0.day == game.day && $0.kind.suspicious }
        for s in mine {
            let chips = game.notebook(about: s.subject, suspicious: true)
            #expect(chips.contains { $0.kind == .sighting && $0.sight == s.kind })
        }
        if let s = mine.first(where: { game.players[$0.subject].alive }),
           let chip = game.notebook(about: s.subject, suspicious: true).first(where: { $0.kind == .sighting }) {
            game.advance(.say(.accuse, target: s.subject, chip: chip))
            #expect(game.view().index.told.contains { $0.by == 0 && $0.about == s.subject })
            cited += 1
        }
    }
    #expect(cited > 0)
}

// MARK: - The gauntlet

@MainActor
@Test func everyCourseIsWellMade() {
    #expect(MissionKind.allCases.count == 5)
    for kind in MissionKind.allCases {
        let spec = kind.spec
        for alive in 5...8 {
            // More than everyone but one could manage on an ordinary day, and less than everyone could.
            let goal = Double(spec.teamGoal(alive: alive)), head = spec.head(alive: alive)
            #expect(head > 3, "\(kind)")
            #expect(goal > head * Double(alive - 1) && goal < head * Double(alive), "\(kind)")
        }
        for row in Courses.blueprint(kind).rows { #expect(row.count == Course.cols, "\(kind): \(row)") }
        let course = Course(kind)
        // There is a way on foot from the hoard to the vault, and somewhere to wake up along it.
        #expect((course.index(at: course.hoard).map { course.toVault[$0] } ?? -1) > 20, "\(kind)")
        #expect((course.index(at: course.vault).map { course.toHoard[$0] } ?? -1) > 20, "\(kind)")
        #expect(course.braziers.count == 3, "\(kind)")
        // A lever, a sconce and the vault door: the hand always has more than one thing to work.
        #expect(course.mechanisms.contains { if case .lever = $0.kind { return true } else { return false } }, "\(kind)")
        #expect(course.mechanisms.contains { if case .sconce = $0.kind { return true } else { return false } }, "\(kind)")
        #expect(course.mechanisms.last?.kind == .vault)
        #expect(course.hazards.count >= 5, "\(kind)")
    }
}

@MainActor
@Test func theDeckOpensInTheGreatHall() {
    for seed in 1...200 {
        var rng = SeededRNG(seed: UInt64(seed))
        let deck = MissionDeck.deal(rng: &rng)
        #expect(deck.first == .greatHall && Set(deck) == Set(MissionKind.allCases) && deck.count == MissionKind.allCases.count)
    }
}

@MainActor
@Test func theLedgerSurvivesASave() throws {
    let result = ArenaRunner.play(ArenaRunner.sample(.greatHall, seed: 3, sabotage: true))
    let ledger = try #require(result.ledger)
    #expect(ledger.ticks > 100 && ledger.x.count == ledger.ticks * ledger.seats.count)
    let back = try JSONDecoder().decode(MissionLedger.self, from: JSONEncoder().encode(ledger))
    #expect(back == ledger)
}

/// Eight players standing in a row for twenty seconds, with nothing happening.
@MainActor
func stillLedger(seen: SeatMask = 0, zone: UInt8 = Zone.task) -> MissionLedger {
    var l = MissionLedger(seats: Array(0..<8))
    for _ in 0..<100 {
        l.sample(x: (0..<8).map { Double($0) * 30 }, y: Array(repeating: 0, count: 8), zone: Array(repeating: zone, count: 8),
                 seen: (0..<8).map { $0 == 1 ? seen : 0 })
    }
    return l
}

@MainActor
func derived(_ l: MissionLedger) -> [Sighting] {
    // The human always takes in what they are placed to see, so seat 0 makes the outcome certain.
    SightingDeriver.derive(l, day: 1, perception: Array(repeating: 0.5, count: 8), human: 0, seed: 1).sightings
}

@MainActor
@Test func sightingsComeFromWhatTheRecordShows() {
    let watcher = SeatMask.seat(0)
    // Watched all game and nothing odd: vouched for.
    #expect(derived(stillLedger(seen: watcher)) == [Sighting(day: 1, subject: 1, kind: .inView, witnesses: watcher)])
    // Standing about away from the work.
    #expect(derived(stillLedger(seen: watcher, zone: Zone.open)).contains(Sighting(day: 1, subject: 1, kind: .loiter, witnesses: watcher)))
    // Somewhere that does nothing for the mission.
    #expect(derived(stillLedger(seen: watcher, zone: Zone.off)).contains(Sighting(day: 1, subject: 1, kind: .offTask, witnesses: watcher)))

    for (event, kind) in [(MissionEvent(tick: 5, actor: 1, code: .sprung, seen: watcher), SightingKind.atTheWorks),
                          (MissionEvent(tick: 5, actor: 1, code: .balked, seen: watcher), .startled),
                          (MissionEvent(tick: 5, actor: 1, code: .tell, a: SightingKind.emptyHanded.index, seen: watcher), .emptyHanded)] {
        var l = stillLedger(seen: watcher)
        l.events = [event]
        // Something odd was seen, so nobody says they did nothing odd.
        #expect(derived(l) == [Sighting(day: 1, subject: 1, kind: kind, witnesses: watcher)])
    }
    // The truth of whose hand it was is never a sighting, ordinary work is nothing to mention,
    // and nobody is a witness to themselves.
    var l = stillLedger()
    l.events = [MissionEvent(tick: 5, actor: 1, code: .sabotage, seen: watcher),
                MissionEvent(tick: 5, actor: 1, code: .banked, seen: watcher),
                MissionEvent(tick: 6, actor: 2, code: .sprung, seen: SeatMask.seat(2))]
    #expect(derived(l).isEmpty)
}

@MainActor
@Test func aPlayedOutMissionIsSettledFromItsRecord() {
    var game = playToMission(seed: 9, preference: .traitor)
    game.mission?.runner = nil
    let partner = game.aliveTraitors.first { $0 != 0 }!
    let faithful = game.aliveFaithful[0]
    var ledger = stillLedger()
    ledger.events = [MissionEvent(tick: 5, actor: partner, code: .sprung, seen: SeatMask.seat(0))]

    // A faithful cannot be blamed for the day, whatever the game says.
    var wrong = game
    wrong.advance(.mission(MissionResult(teamTotal: 10, sunkBy: faithful, ledger: ledger)))
    #expect(wrong.sunkBy == nil && wrong.traitorsMayAct)

    var lost = game
    lost.advance(.mission(MissionResult(teamTotal: 10, sunkBy: partner, ledger: ledger)))
    #expect(lost.sunkBy == partner && lost.traitorsMayAct)
    // What was seen is exactly what the record shows, not the dice.
    #expect(lost.mission?.sightings == [Sighting(day: 1, subject: partner, kind: .atTheWorks, witnesses: SeatMask.seat(0))])

    // The pot is the team's haul against its goal.
    game.advance(.mission(MissionResult(teamTotal: 999, ledger: ledger)))
    let report = game.report!
    #expect(report.teamTotal == 999 && report.teamGoal == report.kind.spec.teamGoal(alive: 8) && report.groupWon)
    #expect(report.potEarned == 3200)
}

@MainActor
@Test func breakfastOnlyAsksWhoWasOutOfSightAfterALostDay() {
    var told = 0
    for seed in 1...80 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        var won = false
        while game.phase != .gameOver {
            if game.phase == .missionResult, let r = game.report { won = r.groupWon }
            let day = game.day
            game.advance(.next)
            guard game.day == day + 1 else { continue }
            let clue = game.feed.contains { $0.text.contains("never out of sight") }
            if clue { told += 1 }
            #expect(!(clue && won), "seed \(seed) day \(day)")
            won = true
        }
    }
    #expect(told > 20)
}

@MainActor
@Test func everyCoursePlaysItselfOutTheSameWayTwice() {
    for kind in MissionKind.allCases {
        let setup = ArenaRunner.sample(kind, seed: 12, sabotage: true)
        let a = ArenaRunner.play(setup), b = ArenaRunner.play(setup)
        #expect(a == b, "\(kind) is not deterministic")
        #expect((a.teamTotal ?? 0) > 0, "\(kind)")

        // However the frames fall, it is the same game.
        let ragged = ArenaRunner(setup)
        var frame = 0
        while ragged.stage != .finished {
            ragged.advance([1.0 / 60, 1.0 / 120, 1.0 / 30, 0.05, 0.004][frame % 5], input: ArenaInput())
            frame += 1
        }
        #expect(ragged.result() == a, "\(kind) depends on the frame rate")
    }
}

@MainActor
@Test func nobodyEndsUpInAWallOrInsideAnyoneElse() {
    for kind in MissionKind.allCases {
        let core = Gauntlet(ArenaRunner.sample(kind, seed: 21, sabotage: true))
        var worst = 2 * Feel.radius
        while !core.finished {
            core.step()
            for (i, r) in core.runners.enumerated() where r.up {
                #expect(!course(core).grid.isSolid(r.pos), "\(kind): seat \(r.id) is in a wall")
                #expect(r.pos.x >= 0 && r.pos.y >= 0 && r.pos.x <= core.course.size.x && r.pos.y <= core.course.size.y)
                #expect(r.speed <= Feel.dashSpeed + Feel.shove + 1, "\(kind): seat \(r.id) at \(r.speed)")
                #expect(r.carry >= 0 && r.carry <= Feel.maxCarry)
                for o in core.runners[(i + 1)...] where o.up { worst = min(worst, o.pos.distance(to: r.pos)) }
            }
        }
        // A crowd in a corner can be squeezed a little, and no more.
        #expect(worst > 2 * Feel.radius - 6, "\(kind): two runners \(worst) apart")
        #expect(core.tick <= core.totalTicks + Feel.overtime)
    }
}

@MainActor
private func course(_ core: Gauntlet) -> Course { core.course }

/// A straight corridor with a drop across it some tiles deep, and one player at the controls.
@MainActor
func gapRun(tiles: Int) -> Gauntlet {
    var rows = ["#############", "#VVVVVVVVVVV#", "#VVVVVVVVVVV#", "#...........#", "#.....B.....#", "#...........#"]
    rows += Array(repeating: "#           #", count: tiles)
    rows += ["#...........#", "#.....B.....#", "#...........#", "#.....B.....#", "#...........#", "#HHHHHHHHHHH#", "#HHHHHHHHHHH#", "#############"]
    let setup = ArenaSetup(kind: .greatHall, day: 1, seed: 1, quirkSeed: 1,
                           cast: [ArenaSeat(id: 0, skill: 0.5, perception: 0.5, deceit: 0.5, isHuman: true)], saboteurs: [], autopilot: false)
    return Gauntlet(setup, course: Course(.greatHall, Blueprint(rows: rows, traps: [])))
}

/// Whether running straight up and dashing some way short of the drop gets a runner across it.
@MainActor
func clears(tiles: Int, dashAt short: Double) -> Bool {
    let core = gapRun(tiles: tiles)
    // The drop starts above the five rows of floor over the hoard.
    let edge = Course.cell * 8
    core.input.move = Vec2(0, 1)
    var pressed = false
    for _ in 0..<Feel.ticks(6) {
        let r = core.runners[0]
        if !r.up { return false }
        if r.pos.y > edge + Double(tiles) * Course.cell + Feel.radius, r.dash == 0, core.standable(r.pos) { return true }
        if !pressed, r.pos.y >= edge - short {
            pressed = true
            core.press()
        }
        core.step()
    }
    return false
}

@MainActor
@Test func aDashClearsTwoTilesAndNeverThree() {
    let tries = stride(from: -14.0, through: 40, by: 2)
    #expect(tries.contains { clears(tiles: 2, dashAt: $0) })
    #expect(!tries.contains { clears(tiles: 3, dashAt: $0) })
    // Walking off the edge is a fall, with a moment's grace.
    #expect(!clears(tiles: 1, dashAt: -1000))
}

@MainActor
@Test func everyTrapWarnsBeforeItStrikes() {
    for kind in MissionKind.allCases {
        for (i, start) in Course(kind).hazards.enumerated() where start.kind != .blade && start.kind != .gust {
            var h = start
            var warned = 0
            for t in 0..<Feel.ticks(80) {
                let act = min(2, t / Feel.ticks(25))
                // Set it off out of turn now and then, as a hand or a foot on a plate would.
                if t % 400 == 399 { _ = h.trip(by: nil) }
                if t % 400 == 199 { _ = h.plate() }
                let was = h.state
                _ = h.step(act: act)
                if h.state == .warn { warned += 1 }
                if h.state == .live, was != .live {
                    // The step it strikes on is the last of the warning.
                    #expect(was == .warn && warned + 1 >= Feel.ticks(0.4), "\(kind) trap \(i) struck after \(warned + 1) steps of warning")
                    warned = 0
                }
                if h.state == .rest { warned = 0 }
            }
        }
    }
}

@MainActor
@Test func aPressIsNeverLostBetweenFrames() {
    let runner = ArenaRunner(ArenaRunner.sample(.greatHall, seed: 2, sabotage: false, hand: .idle))
    while runner.stage == .countdown { runner.advance(0.1, input: ArenaInput()) }
    // A frame too short for a step, and the press still lands on the next one.
    runner.press()
    runner.advance(0.001, input: ArenaInput())
    #expect(runner.core.runners[0].dash == 0)
    runner.advance(1.0 / 60, input: ArenaInput())
    runner.advance(1.0 / 60, input: ArenaInput())
    #expect(runner.core.runners[0].dash > 0)

    // A press a moment before the dash is ready again goes off when it is.
    let core = runner.core
    while core.runners[0].cooldown > 5 { core.step() }
    #expect(core.runners[0].cooldown > 0 && core.runners[0].dash == 0)
    core.press()
    for _ in 0..<6 { core.step() }
    #expect(core.runners[0].dash > 0)
}

@MainActor
@Test func onlyTheSeatWithTheHandEverUsesIt() {
    var used = 0
    for kind in MissionKind.allCases {
        let clean = ArenaRunner.play(ArenaRunner.sample(kind, seed: 5, sabotage: false))
        #expect(clean.sunkBy == nil)
        #expect(clean.ledger?.events.contains { $0.code == .sabotage } == false, "\(kind)")
        for seed in 1...4 {
            let setup = ArenaRunner.sample(kind, seed: UInt64(seed), sabotage: true)
            let r = ArenaRunner.play(setup)
            #expect(r.sunkBy == nil || r.sunkBy == 1)
            for e in r.ledger?.events ?? [] where e.code == .sabotage {
                used += 1
                #expect(e.actor == 1, "\(kind)")
            }
            for s in SightingDeriver.derive(r.ledger!, day: 1, perception: setup.cast.map(\.perception), human: nil, seed: setup.seed).sightings {
                #expect(!s.witnesses.has(s.subject) && s.witnesses != 0)
            }
        }
    }
    #expect(used > 20)
}

@MainActor
@Test func standingByAMechanismReadsTheSameWhoeverWorkedIt() {
    func sprung(by hand: PlayerID?) -> [MissionEvent] {
        let core = Gauntlet(ArenaRunner.sample(.greatHall, seed: 4, sabotage: true))
        let m = core.course.mechanisms.firstIndex { if case .lever = $0.kind { return true } else { return false } }!
        let at = core.course.mechanisms[m].pos
        // Seats 1 and 2 stand at the lever with seat 0 close by and looking; everyone else is far off.
        for i in core.runners.indices { core.runners[i].pos = core.course.hoard }
        core.runners[1].pos = at + Vec2(30, 0)
        core.runners[2].pos = at + Vec2(40, 8)
        core.runners[0].pos = at + Vec2(90, 0)
        for i in 1...2 {
            core.runners[i].vel = .zero
            core.runners[i].seenBy = SeatMask.seat(0)
        }
        core.spring(m, by: hand)
        return core.ledger.events.filter { $0.code == .sprung }
    }
    let castle = sprung(by: nil), traitor = sprung(by: 1)
    // The same two names, seen by the same eyes, whether it was the castle or seat 1.
    #expect(castle == traitor)
    #expect(castle.map(\.actor).sorted() == [1, 2])
    #expect(castle.allSatisfy { $0.seen == SeatMask.seat(0) })
}

@MainActor
@Test func aFullVaultSealsUnlessItIsSpilled() {
    let core = Gauntlet(ArenaRunner.sample(.greatHall, seed: 6, sabotage: false, hand: .idle))
    core.teamTotal = core.goal
    for _ in 0..<Feel.seal / 2 { core.step() }
    #expect(core.sealing > 0.3 && !core.finished)
    // Gold back out of the vault breaks the seal, and it starts again from nothing.
    let before = core.teamTotal
    core.spring(core.course.mechanisms.count - 1, by: nil)
    #expect(core.teamTotal < before)
    core.step()
    #expect(core.sealing == 0 && !core.finished)
    core.teamTotal = core.goal + 50
    for _ in 0..<Feel.seal { core.step() }
    #expect(core.finished && core.won)
    #expect(core.tick < core.totalTicks / 2)
}

// MARK: - Staging

@MainActor
@Test func stagingKeepsEverySlateAndHoldsTheResultBack() {
    // Seat 1 takes four votes, seat 2 three and seat 3 one, written in an order that would give it away early.
    let targets = [1, 1, 1, 1, 2, 2, 2, 3]
    let feed = targets.enumerated().map { Beat(kind: .vote, speaker: $0.offset, target: $0.element, text: "") }
        + [Beat(kind: .banish, target: 1, text: "", role: .traitor)]
    let script = VoteScript(feed: feed)
    #expect(script.rounds == 1)
    #expect(script.steps.count == 9)
    #expect(script.banished == 1)
    let final = script.tally(shown: 8)
    #expect(final.first { $0.player == 1 }?.votes == 4)
    #expect(final.first { $0.player == 2 }?.votes == 3)
    #expect(final.first { $0.player == 3 }?.votes == 1)
    // With one slate left to turn the front two are level.
    let late = script.tally(shown: 7)
    #expect(late.first { $0.player == 1 }?.votes == late.first { $0.player == 2 }?.votes)
    #expect(script.slatesLeft(after: 6) == 1)
    var voters: Set<PlayerID> = []
    for step in script.steps { if case .slate(let voter, _, _) = step { voters.insert(voter) } }
    #expect(voters.count == 8)
}

@MainActor
@Test func stagingSplitsATieIntoTwoRoundsAndStartsTheCountAgain() {
    var feed = [Beat(kind: .speech, speaker: 4, text: "said before the vote")]
    feed += [(0, 1), (3, 2), (4, 1), (5, 2)].map { Beat(kind: .vote, speaker: $0.0, target: $0.1, text: "") }
    feed.append(Beat(kind: .host, text: "tie"))
    feed += [(0, 1), (3, 2)].map { Beat(kind: .vote, speaker: $0.0, target: $0.1, text: "") }
    feed.append(Beat(kind: .host, text: "fate"))
    feed.append(Beat(kind: .banish, target: 2, text: "", role: nil))
    feed.append(Beat(kind: .host, text: "over"))
    let script = VoteScript(feed: feed)
    #expect(script.rounds == 2)
    #expect(script.revoteStart == 6)
    #expect(script.tally(shown: 5).map(\.votes).reduce(0, +) == 4)
    #expect(script.tally(shown: 7).map(\.votes).reduce(0, +) == 1)
    if case .line = script.steps[0] {} else { Issue.record("the discussion comes first") }
    if case .banish(2, nil) = script.steps[9] {} else { Issue.record("the banishment keeps its place") }
    if case .verdict = script.steps[10] {} else { Issue.record("what follows the banishment is the verdict") }
}

@MainActor
@Test func stagingReadsRealGamesWithoutLosingAnyone() {
    for seed in 1...25 {
        for pref in [RolePreference.faithful, .traitor] {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: pref)
            #expect(Place.of(game) == .hall)
            var steps = 0
            while game.phase != .gameOver, steps < 600 {
                game.advance(Autopilot.input(for: game))
                steps += 1
                if game.phase == .voteReveal {
                    let script = VoteScript(feed: game.feed)
                    let slates = script.steps.filter { if case .slate = $0 { return true } else { return false } }.count
                    #expect(slates == game.feed.filter { $0.kind == .vote }.count)
                    #expect(script.banished != nil)
                    #expect(Place.of(game) == (game.finale ? .fireOfTruth : .roundTable))
                }
                if game.phase == .breakfast {
                    let morning = MorningScript(game: game)
                    #expect(Set(morning.arrivals.flatMap { $0 }) == Set(game.alive))
                    #expect(morning.arrivals.flatMap { $0 }.count == game.alive.count)
                    if let victim = morning.victim {
                        #expect(!game.players[victim].alive)
                        #expect(morning.seats(game).contains(victim))
                    }
                    #expect(morning.lines.count + (morning.victim == nil ? 0 : 1) == game.feed.count)
                }
                if game.phase == .night, game.nightChoice == .offer { #expect(Place.of(game) == .bedchamber) }
            }
        }
    }
}

@MainActor
@Test func stagingColourIsTheSameEveryTimeAndNamesNobodyStillPlaying() {
    let names = Cast.bots.map(\.name)
    for voice in [Voice.blunt, .loud, .wry, .quiet, .warm, .sly, .earnest, .plain] {
        for day in 1...6 {
            let words = Flavour.lastWords(voice, seat: 3, seed: 42, day: day)
            #expect(words == Flavour.lastWords(voice, seat: 3, seed: 42, day: day))
            let quiet = Flavour.quietNightReaction(voice, seat: 3, seed: 42, day: day)
            let over = Flavour.murderReaction(voice, victim: "Zed", seat: 3, seed: 42, day: day)
            for name in names {
                #expect(!words.contains(name))
                #expect(!quiet.contains(name))
                #expect(!over.contains(name))
            }
        }
    }
}
