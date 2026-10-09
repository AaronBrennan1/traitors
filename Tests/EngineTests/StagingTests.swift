import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

@Suite struct StagingTests {
    let names = ["You"] + Cast.bots.map(\.name)

    @Test func stagingKeepsEverySlateAndHoldsTheResultBack() {
        // Seat 1 takes four votes, seat 2 three and seat 3 one, written in an order that would give it away early.
        let targets = [1, 1, 1, 1, 2, 2, 2, 3]
        let ballots = targets.enumerated().map { Ballot(voter: $0.offset, target: $0.element) }
        let script = VoteScript(VoteOutcome(rounds: [ballots], banished: 1, role: .traitor), names: names)
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

    @Test func stagingSplitsATieIntoTwoRoundsAndStartsTheCountAgain() {
        let first = [(0, 1), (3, 2), (4, 1), (5, 2)].map { Ballot(voter: $0.0, target: $0.1) }
        let second = [(0, 1), (3, 2)].map { Ballot(voter: $0.0, target: $0.1) }
        // Level twice over, so the lot decides, and the banishment ends the game.
        let vote = VoteOutcome(rounds: [first, second], tied: [1, 2], byFate: true, banished: 2, role: nil, winner: .traitor)
        let script = VoteScript(vote, lead: [Beat(kind: .speech, speaker: 4, text: "said before the vote")], names: names)
        #expect(script.rounds == 2)
        #expect(script.revoteStart == 6)
        #expect(script.tally(shown: 5).map(\.votes).reduce(0, +) == 4)
        #expect(script.tally(shown: 7).map(\.votes).reduce(0, +) == 1)
        if case .line = script.steps[0] {} else { Issue.record("the discussion comes first") }
        if case .banish(2, nil) = script.steps[9] {} else { Issue.record("the banishment keeps its place") }
        if case .verdict = script.steps[10] {} else { Issue.record("what follows the banishment is the verdict") }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func stagingReadsRealGamesWithoutLosingAnyone() {
        for seed in 1...25 {
            for pref in [RolePreference.faithful, .traitor] {
                var game = Game(seed: UInt64(seed), humanName: "Tester", preference: pref)
                #expect(Place.of(game) == .hall)
                var steps = 0
                while game.phase != .gameOver, steps < 600 {
                    game.go(Autopilot.Seat().answer(game.prompt, in: game))
                    steps += 1
                    if game.phase == .voteReveal {
                        let script = VoteScript(game: game)
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
                    if case .answerOffer = game.prompt { #expect(Place.of(game) == .bedchamber) }
                }
            }
        }
    }

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
}
