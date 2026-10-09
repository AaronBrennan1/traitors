import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

@Suite struct GameFlowTests {
    @Test func allBotGamesTerminateWithAWinner() {
        for seed in seeds(1...200, quick: 15) {
            let game = play(seed: UInt64(seed), name: nil)
            #expect(game.phase == .gameOver, "seed \(seed) stuck in \(game.phase)")
            #expect(game.winner != nil, "seed \(seed)")
        }
    }

    @Test func humanGamesTerminateInEveryRole() {
        for seed in seeds(1...120, quick: 6) {
            for pref in RolePreference.allCases {
                let game = play(seed: UInt64(seed), name: "Tester", preference: pref)
                #expect(game.phase == .gameOver, "seed \(seed) \(pref) stuck in \(game.phase)")
                #expect(game.winner != nil)
            }
        }
    }

    @Test func sameSeedGivesSameGame() throws {
        let a = play(seed: 77, name: "Tester", preference: .traitor)
        let b = play(seed: 77, name: "Tester", preference: .traitor)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        #expect(try enc.encode(a.log) == enc.encode(b.log))
        #expect(a.winner == b.winner)
    }

    @Test func rolePreferenceIsHonoured() {
        for seed in 1...40 {
            #expect(Game(seed: UInt64(seed), humanName: "T", preference: .traitor).players[0].role == .traitor)
            #expect(Game(seed: UInt64(seed), humanName: "T", preference: .faithful).players[0].role == .faithful)
            #expect(Game(seed: UInt64(seed), humanName: "T").team.count == Rules.traitors)
        }
    }

    @Test func saveAndLoadMidGameContinuesIdentically() throws {
        var game = Game(seed: 9, humanName: "Tester", preference: .faithful)
        for _ in 0..<14 { game.auto() }
        let data = try JSONEncoder().encode(game)
        var restored = try JSONDecoder().decode(Game.self, from: data)
        var steps = 0
        while game.phase != .gameOver, steps < 600 {
            game.auto()
            restored.auto()
            steps += 1
        }
        #expect(restored.phase == .gameOver)
        #expect(restored.winner == game.winner)
        #expect(restored.log.count == game.log.count)
    }

    @Test func faithfulBotsNeverSuspectThemselvesAndBeliefsAreNormalised() {
        var game = Game(seed: 3, humanName: nil)
        run(&game, to: .missionResult)
        let v = game.view()
        for b in game.aliveBots where game.players[b].role == .faithful {
            let belief = Inference.compute(view: v, observer: FaithfulBrain.observer(game.minds[b], game.players[b].personality))
            #expect(belief.marginal(b) == 0)
            #expect(abs(belief.weights.reduce(0, +) - 1) < 1e-9)
            let total = (0..<Rules.seats).reduce(0.0) { $0 + belief.marginal($1) }
            #expect(abs(total - Double(Rules.traitors)) < 1e-9)
        }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func theNightIsOnlyTheTraitorsAfterALoss() {
        var quiet = 0, afterLoss = 0
        for seed in 1...150 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            var days: [Int: Bool] = [:]
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                if game.phase == .missionResult, let r = game.report { days[game.day] = r.groupWon }
                game.go()
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

    @Test func aWinKeepsTheTraitorsInWhateverTheirHandDid() {
        for seed in 1...40 {
            var game = playToMission(seed: UInt64(seed), preference: .traitor)
            game.mission?.runner = nil
            game.go(.mission(MissionResult(sabotage: 3, teamTotal: 999, sunkBy: 0)))
            #expect(game.report?.groupWon == true && game.sunkBy == nil && !game.traitorsMayAct)
            let quiet = playThroughNight(game)
            if let n = night(1, in: quiet.game) {
                #expect(n.victim == nil && !n.recruit, "seed \(seed)")
                #expect(quiet.choice == .none)
                #expect(quiet.game.feed.contains { $0.text == Host.quietNight })
            }
        }
    }

    @Test func murderFollowsAGroupLoss() {
        for seed in 1...40 {
            var game = playToMission(seed: UInt64(seed), preference: .traitor)
            game.mission?.runner = nil
            game.go(.mission(MissionResult(teamTotal: 0)))
            #expect(game.report?.groupWon == false && game.sunkBy == nil && game.traitorsMayAct)
            let after = playThroughNight(game)
            if let n = night(1, in: after.game) {
                // The night is theirs: a murder, or a recruitment if the table has just taken one of them.
                #expect(n.victim != nil || n.recruit, "seed \(seed)")
                if after.game.players[0].fate != .banished { #expect(after.choice != .none) }
            }
        }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func groupWinBlocksRecruit() {
        let found = loneTraitorMissions()
        #expect(found.count >= 5)
        var blocked = 0, recruited = 0
        for start in found {
            let day = start.day
            var won = start
            won.mission?.runner = nil
            var lost = won
            let lone = won.aliveTraitors[0]

            won.go(.mission(MissionResult(teamTotal: 999)))
            let quiet = playThroughNight(won).game
            if let n = night(day, in: quiet) {
                blocked += 1
                #expect(n.victim == nil && !n.recruit)
                #expect(!quiet.recruitmentUsed && !quiet.tally.recruited)
                #expect(quiet.aliveTraitors == [lone])
            }

            lost.go(.mission(MissionResult(teamTotal: 0)))
            let fell = playThroughNight(lost).game
            if let n = night(day, in: fell) {
                recruited += 1
                #expect(n.recruit && fell.recruitmentUsed)
            }
        }
        #expect(blocked > 0 && recruited > 0)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func theHandIsOpenOnARecruitDay() {
        var tried = 0
        for seed in 1...150 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                game.go()
                if game.phase == .missionResult, game.aliveTraitors.count == 1, !game.recruitmentUsed, game.mission?.runnerAttempt == true {
                    tried += 1
                }
            }
        }
        // A lone traitor only sees another mission when a win has already kept them in once.
        #expect(tried > 3)
    }

    @Test func aFaithfulHumanCannotSinkTheDay() {
        for seed in 1...40 {
            var game = playToMission(seed: UInt64(seed), preference: .faithful)
            var claimed = game
            game.go(.mission(MissionResult(effort: 1, sabotage: 3)))
            claimed.go(.mission(MissionResult(effort: 1)))
            // Whatever a faithful's result says about the hand is ignored.
            #expect(game.sunkBy != 0 && game.mission?.humanAttempt == false)
            #expect(game.report?.teamTotal == claimed.report?.teamTotal)
        }
    }

    @Test func aMissionKeepsNoPerPlayerNumbers() {
        var game = playToMission(seed: 4, preference: .faithful)
        game.go(.mission(MissionResult()))
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

    @Test(.tags(.balance), .enabled(if: fullRun)) func theDiceGiveTheCompanyTheOddsTheGauntletDoes() {
        for kind in MissionKind.allCases {
            for alive in 5...8 {
                let alone = ArenaSession.abstractWinRate(kind, games: 3000, seed: 3, alive: alive, effort: 1, sabotage: false)
                #expect(abs(alone - 0.75) < 0.08, "\(kind) left alone with \(alive) alive: \(alone)")
                let idle = ArenaSession.abstractWinRate(kind, games: 3000, seed: 4, alive: alive, effort: 0, sabotage: false)
                #expect(abs(idle - 0.28) < 0.08, "\(kind) with the player idle and \(alive) alive: \(idle)")
                let against = ArenaSession.abstractWinRate(kind, games: 3000, seed: 5, alive: alive, effort: 1, sabotage: true)
                #expect(abs(against - 0.13) < 0.08, "\(kind) with the hand against it and \(alive) alive: \(against)")
            }
        }
    }

    @Test(.tags(.balance), .enabled(if: fullRun)) func theHandCostsTheCompanyItsDayMoreOftenThanNot() {
        for kind in MissionKind.allCases {
            let alone = ArenaSession.winRate(kind, games: 24, seed: 3, sabotage: false)
            let against = ArenaSession.winRate(kind, games: 24, seed: 3, sabotage: true)
            #expect(alone > 0.5, "\(kind) left alone: \(alone)")
            #expect(against < 0.5 && against < alone, "\(kind) with the hand against it: \(against)")
        }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func aHumanWhoIsOutWatchesTheMissionAndAnyInputMovesOn() {
        var watched = 0
        for seed in 1...60 {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: .faithful)
            var steps = 0
            while game.phase != .gameOver, steps < 600 {
                if game.phase == .mission, !game.humanAlive {
                    watched += 1
                    game.go()
                    #expect(game.phase == .missionResult)
                    #expect(game.mission?.human == nil)
                } else {
                    game.auto()
                }
                steps += 1
            }
            #expect(game.phase == .gameOver)
        }
        #expect(watched > 0)
    }
}

/// Tuning is a value a game is handed. Two games with different numbers do not touch each other.
@Suite struct GameTuningTests {
    @Test func aGameIsPlayedByTheNumbersItWasGiven() throws {
        var kind = Tuning()
        try kind.set("handicap", 3)
        var harsh = Tuning()
        try harsh.set("handicap", -2)
        var easy = Game(seed: 5, humanName: nil, options: GameOptions(tuning: kind))
        var hard = Game(seed: 5, humanName: nil, options: GameOptions(tuning: harsh))
        var plain = Game(seed: 5, humanName: nil)
        run(&easy, to: .missionResult)
        run(&hard, to: .missionResult)
        run(&plain, to: .missionResult)
        let goals = [easy, plain, hard].map { $0.report!.teamGoal }
        #expect(goals[0] < goals[1] && goals[1] < goals[2], "\(goals)")
        // The one played by the shipped numbers is the one a game with no tuning plays.
        var again = Game(seed: 5, humanName: nil, options: GameOptions(tuning: Tuning()))
        run(&again, to: .missionResult)
        #expect(again.report == plain.report)
        // And it goes into the save with the game.
        let back = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(easy))
        #expect(back.options.tuning == kind && back.mission?.teamGoal == easy.mission?.teamGoal)
    }

    @Test func aTableWeighsEvidenceByItsOwnTuning() throws {
        var sceptical = BeliefTuning()
        sceptical.sightLift = Array(repeating: 1, count: sceptical.sightLift.count)
        let saw = [Sighting(day: 1, subject: 2, kind: .atTheWorks, witnesses: SeatMask.seat(0))]
        var me = Observer(id: 0, gut: Array(repeating: 0, count: Rules.seats), temper: 1)
        me.sightings = saw
        let log: [PublicEvent] = [.mission(MissionReport(kind: .greatHall, day: 1, teamTotal: 40, teamGoal: 45, groupWon: false, potEarned: 0))]
        let usual = Inference.compute(log: log, count: Rules.seats, observer: me).marginal(2)
        let unmoved = Inference.compute(log: log, count: Rules.seats, observer: me, tuning: sceptical).marginal(2)
        // With every sighting worth nothing, having seen something changes nothing.
        #expect(usual > unmoved + 0.05)
        #expect(abs(unmoved - Double(Rules.traitors) / Double(Rules.seats - 1)) < 1e-9)
    }
}
