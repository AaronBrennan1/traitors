import Foundation
import Testing
@testable import TraitorsEngine

/// Plays the human seat with simple fixed choices so a full game can be driven in a test.
@MainActor
func autoInput(_ game: Game) -> HumanInput {
    switch game.phase {
    case .mission:
        return .mission(MissionResult(score: 0.8, questDone: false))
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
@Test func murderOnlyFollowsACompletedSideQuest() {
    for seed in 1...150 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        var questDone: [Int: Bool] = [:]
        while game.phase != .gameOver {
            if game.phase == .missionResult { questDone[game.day] = game.questBy != nil }
            game.advance(.next)
        }
        for event in game.log {
            if case .night(let day, let victim, let recruitNight) = event, victim != nil, !recruitNight {
                #expect(questDone[day] == true, "seed \(seed): murder on night \(day) without a side quest")
            }
        }
    }
}

@MainActor
func playToMission(seed: UInt64, preference: RolePreference) -> Game {
    var game = Game(seed: seed, humanName: "Tester", preference: preference)
    while game.phase != .mission { game.advance(.next) }
    return game
}

@MainActor
@Test func humanTraitorEarnsTheMurderByFinishingTheSideQuest() {
    for seed in 1...40 {
        var game = playToMission(seed: UInt64(seed), preference: .traitor)
        game.mission?.runner = nil
        var idle = game
        game.advance(.mission(MissionResult(score: 0.9, questDone: true)))
        #expect(game.questBy == 0)
        #expect(game.report?.units.first { $0.players == [0] }?.anomalous == false)
        idle.advance(.mission(MissionResult(score: 0.9, questDone: false)))
        #expect(idle.questBy == nil)
    }
}

@MainActor
@Test func faithfulHumanCannotClaimTheSideQuest() {
    for seed in 1...40 {
        var game = playToMission(seed: UInt64(seed), preference: .faithful)
        game.advance(.mission(MissionResult(score: 0.2, questDone: true)))
        #expect(game.questBy != 0)
        #expect(game.report?.units.first { $0.players == [0] }?.anomalous == true)
    }
}

@MainActor
@Test func underParIsExactlyWhatTheReportFlags() {
    var game = Game(seed: 11, humanName: nil)
    while game.phase != .gameOver { game.advance(.next) }
    for event in game.log {
        guard case .mission(let r) = event else { continue }
        #expect(r.steps == r.kind.spec.steps && r.par == r.kind.spec.par)
        for u in r.units { #expect(u.anomalous == (u.count < r.par)) }
    }
}

@MainActor
@Test func declaredSlipRateMatchesWhatHonestPlayersDo() {
    var rng = SeededRNG(seed: 5)
    for kind in MissionKind.allCases {
        for skill in [0.3, 0.5, 0.8] {
            let n = 20_000
            let slips = (0..<n).filter { _ in MissionRun.sample(kind, skill: skill, questing: false, rng: &rng) < kind.spec.par }.count
            #expect(abs(Double(slips) / Double(n) - MissionRun.slipRate(skill: skill)) < 0.03, "\(kind) at skill \(skill)")
        }
    }
}

@MainActor
@Test func theBoardShowsWhatTheBotsActuallyScoredInTheGame() {
    var game = playToMission(seed: 4, preference: .faithful)
    let run = game.mission!
    let bots = run.order.filter { $0 != 0 }
    #expect(Set(run.targets.keys) == Set(bots))
    let seen = bots[0], unseen = bots[1]
    game.advance(.mission(MissionResult(score: 0.8, questDone: false, rivals: [seen: 1])))
    #expect(game.report?.units.first { $0.players == [seen] }?.count == 1)
    #expect(game.report?.units.first { $0.players == [unseen] }?.count == run.targets[unseen])
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
                #expect(game.report?.units.contains { $0.players == [0] } == false)
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
    // Eight average players, seat 1 on the side quest, over many missions.
    var questing = 0.0, others = 0.0
    var seenQuesting = Array(repeating: 0.0, count: SightingKind.allCases.count), seenOthers = seenQuesting
    var rng = SeededRNG(seed: 31)
    for i in 0..<6000 {
        var run = MissionRun(kind: .bogRelay, day: 1, alive: Array(0..<Rules.seats), human: nil, traitors: [1, 2], runner: 1,
                             caution: 0, questOdds: 0.9, questOpen: true,
                             traits: Array(repeating: .average, count: Rules.seats), quirkSeed: UInt64(i), rng: rng.fork())
        run.resolve(human: nil)
        for p in run.order {
            let on = p == 1 && run.runnerAttempt
            if on { questing += 1 } else { others += 1 }
            for s in run.sightings where s.subject == p {
                #expect(!s.witnesses.has(p) && s.witnesses != 0)
                if on { seenQuesting[s.kind.index] += 1 } else { seenOthers[s.kind.index] += 1 }
            }
        }
    }
    #expect(questing > 1000)
    for kind in [SightingKind.offTask, .loiter, .brokeAway, .startled] {
        let ratio = (seenQuesting[kind.index] / questing) / (seenOthers[kind.index] / others)
        #expect(abs(ratio / Tuning.sight(kind) - 1) < 0.2, "\(kind): \(ratio) against \(Tuning.sight(kind))")
    }
    // Nobody on the side quest is ever seen to have done nothing odd.
    #expect(seenQuesting[SightingKind.inView.index] == 0)
    #expect(seenOthers[SightingKind.inView.index] > 0)
}

/// A table of eight on day one, just after a mission in which nobody slipped.
@MainActor
func quietTable() -> [PublicEvent] {
    let units = (0..<Rules.seats).map { MissionUnit(players: [$0], count: 6, anomalous: false, innocentRate: 0.25, questRate: 0.33, detail: "") }
    return [.mission(MissionReport(kind: .bogRelay, day: 1, steps: 10, par: 6, units: units, scores: [:], potEarned: 0, lines: []))]
}

@MainActor
func says(_ speaker: PlayerID, _ kind: StatementKind, _ target: PlayerID, _ chip: Chip) -> PublicEvent {
    .statement(Statement(day: 1, speaker: speaker, kind: kind, target: target, chip: chip, text: ""))
}

@MainActor
@Test func testimonyOnlyCountsWhereTheSpeakerIsFaithful() {
    let n = Rules.seats
    let before = Inference.compute(log: quietTable(), count: n, observer: .publicView(count: n))
    let chip = Chip(kind: .sighting, subject: 2, day: 1, sight: .brokeAway, strength: 1)
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
    let seen = Sighting(day: 1, subject: 2, kind: .brokeAway, witnesses: SeatMask.seat(0) | SeatMask.seat(1))
    var me = Observer.publicView(count: n)
    me.id = 0
    me.sightings = [seen]
    let before = Inference.compute(log: quietTable(), count: n, observer: me)
    // A flat statement with no target, so only the testimony itself is in play.
    let told = PublicEvent.statement(Statement(day: 1, speaker: 1, kind: .pass, target: nil,
                                               chip: Chip(kind: .sighting, subject: 2, day: 1, sight: .brokeAway, strength: 1), text: ""))
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
    let lie = Chip(kind: .sighting, subject: 2, day: 1, sight: .brokeAway, strength: 1)
    let after = Inference.compute(log: quietTable() + [says(1, .accuse, 2, lie)], count: n, observer: me)
    #expect(after.marginal(1) > 0.8)
    #expect(after.marginal(1) > before.marginal(1) + 0.3)
}

@MainActor
@Test func aSightingFromBeforeTheyWereRecruitedIsNotHeldAgainstTheRecruit() {
    let n = Rules.seats
    let chip = Chip(kind: .sighting, subject: 2, day: 1, sight: .atQuestObject, strength: 1)
    let day: [PublicEvent] = quietTable() + [says(1, .doubt, 2, chip)]
    let without: [PublicEvent] = quietTable()
    func recruitOdds(_ log: [PublicEvent]) -> Double {
        // Seat 7 is banished as a traitor, then the survivor recruits.
        let full = log + [.banished(day: 1, player: 7, role: .traitor), .night(day: 1, victim: nil, recruitNight: true)]
        let b = Inference.compute(log: full, count: n, observer: .publicView(count: n))
        // Seat 2 as the recruit of seat 4, against seat 3 as the recruit of seat 4.
        let base = SeatMask.seat(7) | SeatMask.seat(4)
        return b.mass(team: base | SeatMask.seat(2)) / b.mass(team: base | SeatMask.seat(3))
    }
    // With seat 4 as the original traitor, what seat 2 was seen doing has no bearing on who was recruited,
    // beyond seat 2 now being the more suspected and so the less attractive recruit.
    #expect(recruitOdds(day) <= recruitOdds(without) + 1e-9)
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

// MARK: - Mini-games played out

@MainActor
@Test func everyMissionHasASaneSpec() {
    #expect(MissionKind.allCases.count == 10)
    for kind in MissionKind.allCases {
        let spec = kind.spec
        #expect(spec.par > 0 && spec.par < spec.steps, "\(kind)")
        #expect(MissionRun.threshold(kind) > 0.4 && MissionRun.threshold(kind) < 0.7, "\(kind)")
        #expect(spec.teamGoal(alive: 8) > spec.par * 8 / 2 && spec.teamGoal(alive: 8) <= spec.steps * 8, "\(kind)")
        #expect(kind.questText(steps: 1) != kind.questText(steps: 2), "\(kind)")
    }
}

@MainActor
@Test func noTwoEasyGamesForATraitorFallOnConsecutiveDays() {
    for seed in 1...500 {
        var rng = SeededRNG(seed: UInt64(seed))
        let deck = MissionDeck.deal(rng: &rng)
        #expect(Set(deck) == Set(MissionKind.allCases))
        #expect(MissionDeck.balanced(deck), "seed \(seed)")
    }
}

@MainActor
@Test func theLedgerSurvivesASave() throws {
    let result = ArenaRunner.play(ArenaRunner.sample(.bogRelay, seed: 3, questing: true))
    let ledger = try #require(result.ledger)
    #expect(ledger.ticks > 300 && ledger.x.count == ledger.ticks * ledger.seats.count)
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
    // Standing about away from any station.
    #expect(derived(stillLedger(seen: watcher, zone: Zone.open)).contains(Sighting(day: 1, subject: 1, kind: .loiter, witnesses: watcher)))
    // Somewhere that does nothing for the mission.
    #expect(derived(stillLedger(seen: watcher, zone: Zone.off)).contains(Sighting(day: 1, subject: 1, kind: .offTask, witnesses: watcher)))

    for (event, kind) in [(MissionEvent(tick: 5, actor: 1, code: .questStep, seen: watcher), SightingKind.atQuestObject),
                          (MissionEvent(tick: 5, actor: 1, code: .interactDone, b: SightingDeriver.offMission, seen: watcher), .atQuestObject),
                          (MissionEvent(tick: 5, actor: 1, code: .interactAbort, b: SightingDeriver.offMission, seen: watcher), .startled),
                          (MissionEvent(tick: 5, actor: 1, code: .tell, a: SightingKind.brokeAway.index, seen: watcher), .brokeAway)] {
        var l = stillLedger(seen: watcher)
        l.events = [event]
        // Something odd was seen, so nobody says they did nothing odd.
        #expect(derived(l) == [Sighting(day: 1, subject: 1, kind: kind, witnesses: watcher)])
    }
    // Ordinary work at a station is nothing to mention, and nobody is a witness to themselves.
    var l = stillLedger()
    l.events = [MissionEvent(tick: 5, actor: 1, code: .interactDone, seen: watcher),
                MissionEvent(tick: 6, actor: 2, code: .questStep, seen: SeatMask.seat(2))]
    #expect(derived(l).isEmpty)
}

@MainActor
@Test func aPlayedOutMissionIsSettledFromItsRecord() {
    var game = playToMission(seed: 9, preference: .traitor)
    game.mission?.runner = nil
    let partner = game.aliveTraitors.first { $0 != 0 }!
    let faithful = game.aliveFaithful[0]
    var ledger = stillLedger()
    ledger.events = [MissionEvent(tick: 5, actor: partner, code: .questStep, seen: SeatMask.seat(0))]

    // A faithful cannot be credited with the side quest, whatever the game says.
    var wrong = game
    wrong.advance(.mission(MissionResult(score: 0.8, questDone: false, teamTotal: 70, questBy: faithful, ledger: ledger)))
    #expect(wrong.questBy == nil)

    game.advance(.mission(MissionResult(score: 0.8, questDone: false, teamTotal: 70, questBy: partner, ledger: ledger)))
    #expect(game.questBy == partner)
    // What was seen is exactly what the record shows, not the dice.
    #expect(game.mission?.sightings == [Sighting(day: 1, subject: partner, kind: .atQuestObject, witnesses: SeatMask.seat(0))])
    // The pot is the team's haul against its goal.
    let report = game.report!
    #expect(report.teamTotal == 70 && report.teamGoal == report.kind.spec.teamGoal(alive: 8))
    #expect(report.potEarned == 3200)
}

@MainActor
@Test func theSideQuestIsLongerOnceFewAreLeft() {
    for seed in 1...30 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        while game.phase != .gameOver {
            game.advance(.next)
            if game.phase == .missionResult, let run = game.mission {
                #expect(run.questSteps == (run.order.count <= 6 ? 2 : 1))
            }
        }
    }
}

@MainActor
@Test func breakfastOnlyNamesAFailedSideQuestWhenThereWasOne() {
    var told = 0
    for seed in 1...80 {
        var game = Game(seed: UInt64(seed), humanName: nil)
        var open = false, done = false
        while game.phase != .gameOver {
            if game.phase == .missionResult, let run = game.mission { open = run.questOpen; done = game.questBy != nil }
            let day = game.day
            game.advance(.next)
            guard game.day == day + 1 else { continue }
            let clue = game.feed.contains { $0.text.contains("shadow's task went undone") }
            if clue { told += 1 }
            if clue { #expect(open && !done, "seed \(seed) day \(day)") }
            open = false
        }
    }
    #expect(told > 20)
}

@MainActor
@Test func everyMiniGamePlaysItselfOutTheSameWayTwice() {
    for kind in MissionKind.allCases {
        let setup = ArenaRunner.sample(kind, seed: 12, questing: true)
        let a = ArenaRunner.play(setup), b = ArenaRunner.play(setup)
        #expect(a == b, "\(kind) is not deterministic")
        // Nobody can score more than the mission allows, and the record covers the whole game.
        #expect(a.rivals?.values.allSatisfy { $0 >= 0 && $0 <= kind.spec.steps } == true)
        #expect(Double(a.ledger?.ticks ?? 0) > kind.spec.baseSeconds * Double(MissionLedger.hz) * 0.9)
    }
}

@MainActor
@Test func botsInTheMiniGamesLandNearTheirCountsAndTheSideQuestMostlyComesOff() {
    for kind in MissionKind.allCases {
        var miss = 0.0, seats = 0.0, done = 0.0
        let games = 40
        for g in 0..<games {
            let setup = ArenaRunner.sample(kind, seed: UInt64(100 + g), questing: true)
            let r = ArenaRunner.play(setup)
            for s in setup.cast {
                miss += abs(Double((r.rivals?[s.id] ?? 0) - s.target))
                seats += 1
            }
            if r.questBy == 1 { done += 1 }
            #expect(r.questBy == nil || r.questBy == 1)
            for s in SightingDeriver.derive(r.ledger!, day: 1, perception: setup.cast.map(\.perception), human: nil, seed: setup.seed).sightings {
                #expect(!s.witnesses.has(s.subject) && s.witnesses != 0)
            }
        }
        #expect(miss / seats < 0.9, "\(kind): bots finish \(miss / seats) off their counts")
        #expect(done / Double(games) > 0.45 && done / Double(games) <= 1, "\(kind): side quest done \(done / Double(games))")
    }
}

@MainActor
@Test func nobodyGetsTheSideQuestInAGameWithoutOne() {
    for kind in MissionKind.allCases {
        let r = ArenaRunner.play(ArenaRunner.sample(kind, seed: 5, questing: false))
        #expect(r.questBy == nil)
        #expect(r.ledger?.events.contains { $0.code == .questStep || $0.code == .questTry } == false, "\(kind)")
    }
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
