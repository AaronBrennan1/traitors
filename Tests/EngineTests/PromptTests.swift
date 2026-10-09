import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

/// The game's interface: it says what it is waiting for, takes an answer that fits, and refuses
/// one that does not without moving.
@Suite struct PromptTests {
    /// Whether the prompt takes this answer, worked out from the prompt alone.
    static func fits(_ answer: Answer, _ prompt: Prompt) -> Bool {
        switch (prompt, answer) {
        case (.proceed, .proceed): return true
        case (.playMission, .mission): return true
        case (.playMission(let run), .proceed): return run.human == nil
        case (.speak, .say(.pass, _, _)): return true
        case (.speak(_, let targets, _), .say(_, let target, _)): return target.map(targets.contains) ?? false
        case (.speak(_, _, let defences), .rebut(let i)): return defences.indices.contains(i)
        case (.vote(_, let candidates), .vote(let p)): return candidates.contains(p)
        case (.murder(let candidates, _), .murder(let p)): return candidates.contains(p)
        case (.recruit(let candidates), .recruit(let p)): return candidates.contains(p)
        case (.answerOffer, .offer): return true
        case (.endOrBanish, .finale): return true
        default: return false
        }
    }

    /// One of everything, with players who are in, out, the human, and off the end of the table.
    static func everyAnswer(_ game: Game) -> [Answer] {
        let people: [PlayerID] = [0, 1, 2, 3, 4, 5, 6, 7, 99, -1]
        var out: [Answer] = [.proceed, .mission(MissionResult()), .say(.pass, target: nil, chip: nil), .say(.accuse, target: nil, chip: nil),
                             .rebut(0), .rebut(99), .rebut(-1), .offer(accept: true), .offer(accept: false), .finale(end: true), .finale(end: false)]
        for p in people {
            out += [.say(.accuse, target: p, chip: nil), .say(.defend, target: p, chip: nil), .say(.question, target: p, chip: nil),
                    .vote(p), .murder(p), .recruit(p)]
        }
        return out
    }

    @Test(.tags(.sweep)) func anAnswerThatDoesNotFitIsRefusedAndNothingMoves() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        var asked: Set<String> = []
        for seed in seeds(1...40, quick: 3) {
            for pref in [RolePreference.faithful, .traitor] {
                var game = Game(seed: UInt64(seed), humanName: "Tester", preference: pref)
                var cap = StepCap()
                while game.phase != .gameOver, cap.allows(game) {
                    let prompt = game.prompt
                    asked.insert(String(describing: prompt).prefix { $0 != "(" }.description)
                    // Every wrong answer in turn, at the same game: each is refused, and after all of them it has not moved.
                    var copy = game
                    for answer in Self.everyAnswer(game) where !Self.fits(answer, prompt) {
                        #expect(throws: GameError.self, "seed \(seed), \(prompt): took \(answer)") { try copy.advance(answer) }
                    }
                    #expect(try enc.encode(copy) == enc.encode(game), "seed \(seed), \(prompt): a refused answer moved the game")
                    game.auto()
                }
                // Once it is over nothing is taken at all.
                guard case .over(let winner) = game.prompt else { Issue.record("seed \(seed) ended on \(game.prompt)"); continue }
                #expect(winner == game.winner && winner != nil)
                #expect(throws: GameError.gameOver) { try game.advance(.proceed) }
            }
        }
        if fullRun {
            // Every kind of prompt came up somewhere. The offer is rare, and has a test to itself below.
            #expect(asked.isSuperset(of: ["proceed", "playMission", "speak", "vote", "murder", "recruit", "endOrBanish"]), "\(asked.sorted())")
        }
    }

    @Test func aTapSaysWhereItLeads() {
        for seed in seeds(1...30, quick: 5) {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: seed % 2 == 0 ? .traitor : .faithful)
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                let before = game.prompt
                game.auto()
                guard case .proceed(let then) = before else { continue }
                let after = game.phase
                switch then {
                case .breakfast, .morning: #expect(after == .breakfast, "seed \(seed)")
                case .missionBrief: #expect(after == .missionBrief, "seed \(seed)")
                case .mission: #expect(after == .mission, "seed \(seed)")
                // With the human out the table and the vote run through to the banishment.
                case .roundTable, .fireOfTruth: #expect([.roundTable, .voting, .voteReveal, .finaleChoice, .finaleReveal].contains(after), "seed \(seed): \(after)")
                case .vote: #expect(after == .voting || after == .voteReveal, "seed \(seed): \(after)")
                case .night: #expect(after == .night, "seed \(seed): \(after)")
                case .ending: #expect(after == .gameOver, "seed \(seed): \(after)")
                }
            }
        }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func refusingTheOfferIsTheEndOfYou() {
        var refused = 0
        for seed in 1...200 where refused < 4 {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: .faithful)
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                guard case .answerOffer(let from) = game.prompt else { game.auto(); continue }
                refused += 1
                let day = game.day
                var joined = game
                for answer in Self.everyAnswer(game) where !Self.fits(answer, game.prompt) {
                    #expect(throws: GameError.self, "seed \(seed): the offer took \(answer)") { try joined.advance(answer) }
                }
                game.go(.offer(accept: false))
                #expect(game.players[0].fate == .murdered && !game.players[0].alive, "seed \(seed)")
                #expect(game.players[0].role == .faithful && game.aliveTraitors == [from])
                #expect(game.outcome?.morning?.victim == 0 && game.outcome?.morning?.recruitNight == true)
                if let n = night(day, in: game) { #expect(n.victim == 0 && n.recruit) } else { Issue.record("seed \(seed): no night logged") }
                joined.go(.offer(accept: true))
                #expect(joined.players[0].role == .traitor && joined.players[0].alive && joined.outcome?.morning?.victim == nil)
                break
            }
        }
        #expect(refused > 0)
    }

    @Test func whatWasResolvedIsHandedOverAsData() {
        var votes = 0, mornings = 0, missions = 0, ties = 0
        for seed in seeds(1...40, quick: 6) {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: seed % 2 == 0 ? .traitor : .faithful)
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                game.auto()
                switch game.phase {
                case .missionResult:
                    guard case .mission(let report, let noticed) = game.outcome else { Issue.record("seed \(seed): no mission outcome"); break }
                    missions += 1
                    #expect(report.day == game.day && report.groupWon == game.report?.groupWon)
                    #expect(noticed.allSatisfy { $0.witnesses.has(0) })
                case .voting:
                    if case .vote(2, let candidates) = game.prompt {
                        ties += 1
                        #expect(game.outcome?.vote?.tied.filter { $0 != 0 } == candidates && game.outcome?.vote?.banished == nil)
                    }
                case .voteReveal:
                    guard let vote = game.outcome?.vote, let out = vote.banished else { Issue.record("seed \(seed): no vote outcome"); break }
                    votes += 1
                    #expect(!game.players[out].alive && game.players[out].fate == .banished)
                    #expect(vote.role == (game.finale ? nil : game.players[out].role))
                    #expect(vote.winner == game.winner)
                    // The slates are the ones in the public record, round for round.
                    for (i, round) in vote.rounds.enumerated() {
                        var logged: [Ballot] = []
                        for case .vote(game.day, i + 1, let voter, let target) in game.log { logged.append(Ballot(voter: voter, target: target)) }
                        #expect(Array(logged.suffix(round.count)) == round, "seed \(seed) day \(game.day) round \(i + 1)")
                    }
                case .breakfast where game.day > 1:
                    guard let morning = game.outcome?.morning else { Issue.record("seed \(seed): no morning outcome"); break }
                    mornings += 1
                    if let n = night(game.day - 1, in: game) { #expect(n.victim == morning.victim && n.recruit == morning.recruitNight) }
                    #expect(morning.traitorsHadTheNight || morning.victim == nil)
                case .roundTable, .night, .missionBrief:
                    #expect(game.outcome == nil, "seed \(seed): \(game.phase) still holds an outcome")
                default: break
                }
            }
        }
        #expect(votes > 0 && mornings > 0 && missions > 0)
        if fullRun { #expect(ties > 0) }
    }
}
