import Foundation
import Testing
import TraitorsEngine
@testable import test

/// The ceremonies' scripts, as values: what is shown, in what order, and what is heard with it.
@MainActor
@Suite struct TellingTests {
    static func game(seed: UInt64, _ preference: RolePreference, to phase: Phase, day: Int = 1) -> Game {
        var stop = Autopilot.Stop()
        stop.phase = phase
        stop.day = day
        return Autopilot.play(seed: seed, name: "Aoife", preference: preference, stop: stop)
    }

    @Test func aTraitorIsTouchedOnTheShoulderAndShownTheTurret() {
        let game = Self.game(seed: 4, .traitor, to: .roleReveal)
        let traitor = RoleTelling(game: game, role: .traitor), faithful = RoleTelling(game: game, role: .faithful)
        #expect(traitor.moments.last == .turret && faithful.moments.last == .reveal)
        #expect(traitor.moments.dropLast() == faithful.moments[...])
        // Everyone else is met once, before the blindfold goes on.
        let met = faithful.moments.compactMap { if case .meet(let p) = $0 { return p } else { return nil } }
        #expect(met == Array(1..<game.players.count))
        let touch = try! #require(faithful.moments.firstIndex(of: .touch))
        #expect(traitor.cue(touch) == .shoulder && faithful.cue(touch) == .footstep)
        #expect(faithful.blindfolded(shown: touch + 1) && !faithful.blindfolded(shown: faithful.moments.count) && !faithful.blindfolded(shown: 0))
        let reveal = try! #require(traitor.moments.firstIndex(of: .reveal))
        #expect(traitor.cue(reveal) == .declare(.traitor) && faithful.cue(reveal) == .declare(.faithful))
        #expect(traitor == RoleTelling(game: game, role: .traitor) && traitor != faithful)
    }

    @Test func aVoteIsToldSlateBySlateAndTheRoleComesLast() throws {
        var told = 0
        for seed in 1...12 {
            let game = Self.game(seed: UInt64(seed), seed % 2 == 0 ? .traitor : .faithful, to: .voteReveal)
            guard game.phase == .voteReveal, let vote = game.outcome?.vote, let out = vote.banished else { continue }
            told += 1
            let telling = VoteTelling(game: game)
            let m = telling.moments
            // One call for the slates, before the first of them.
            #expect(m.filter { $0 == .call }.count == 1)
            let firstSlate = try #require(m.firstIndex { if case .slate = $0 { return true } else { return false } })
            #expect(m[firstSlate - 1] == .call && telling.cue(firstSlate - 1) == .bell)
            // Every ballot is a slate, and the last of a round is turned slowly and loudly.
            let slates = m.filter { if case .slate = $0 { return true } else { return false } }
            #expect(slates.count == vote.rounds.map(\.count).reduce(0, +), "seed \(seed)")
            let last = try #require(m.lastIndex { if case .slate = $0 { return true } else { return false } })
            #expect(telling.cue(last) == .lateSlate && telling.hold(last) > telling.hold(firstSlate))
            // The count beside the slates is the vote's own, and is not ahead of what has been turned.
            #expect(telling.tally(shown: firstSlate).isEmpty)
            let final = telling.tally(shown: m.count)
            let lastRound = try #require(vote.rounds.last)
            for row in final { #expect(row.votes == lastRound.filter { $0.target == row.player }.count, "seed \(seed)") }
            // The walk, then what they were, and nothing is given away before it.
            let walk = try #require(telling.banishAt)
            #expect(m[walk] == .walk(out) && telling.cue(walk) == .boom)
            let declare = try #require(m.firstIndex(of: .declare(out, vote.role)))
            #expect(declare > walk && telling.cue(declare) == .declare(vote.role))
            #expect(!telling.declared(shown: declare).told && telling.declared(shown: declare + 1).told)
            #expect(telling.declared(shown: m.count).role == vote.role)
            // Told the same way every time.
            #expect(telling == VoteTelling(game: game))
        }
        #expect(told >= 6)
    }

    @Test func aTiedVoteIsPickedUpAtItsSecondRound() throws {
        // Seed 3, faithful: the first table ties and the human votes again.
        var game = Self.game(seed: 3, .faithful, to: .voting)
        var cap = 0
        while cap < 40, game.phase != .voteReveal {
            cap += 1
            try game.advance(Autopilot.Seat().answer(game.prompt, in: game))
            if game.phase == .voting, case .vote(2, _) = game.prompt {
                // Waiting on the second slate: the first round is told, and nobody has gone.
                let waiting = VoteTelling(game: game)
                #expect(waiting.banishAt == nil && waiting.revoteStart == nil)
                #expect(waiting.moments.contains { if case .slate(_, _, 1, _) = $0 { return true } else { return false } })
            }
        }
        let vote = try #require(game.outcome?.vote)
        guard vote.rounds.count == 2 else { return }
        let telling = VoteTelling(game: game)
        let start = try #require(telling.revoteStart)
        if case .slate(_, _, 2, _) = telling.moments[start] {} else { Issue.record("the revote starts on a second-round slate") }
        // The count starts again with it.
        #expect(telling.tally(shown: start).reduce(0) { $0 + $1.votes } == vote.rounds[0].count)
        #expect(telling.tally(shown: start + 1).reduce(0) { $0 + $1.votes } == 1)
    }

    @Test func breakfastNamesTheEmptyChairBeforeAnyoneSpeaksOfIt() throws {
        var murders = 0, quiet = 0
        for seed in 1...10 {
            for day in 2...3 {
                let game = Self.game(seed: UInt64(seed), .faithful, to: .breakfast, day: day)
                guard game.phase == .breakfast, game.day == day else { continue }
                let telling = BreakfastTelling(game: game)
                let m = telling.moments
                // Everybody still in walks in exactly once.
                let arrived = m.flatMap { moment -> [PlayerID] in if case .arrive(let group) = moment { return group } else { return [] } }
                #expect(arrived.sorted() == game.alive, "seed \(seed) day \(day)")
                if let victim = game.outcome?.morning?.victim {
                    murders += 1
                    #expect(telling.victim == victim && telling.seats.contains(victim))
                    let empty = try #require(m.firstIndex(of: .empty)), named = try #require(m.firstIndex(of: .victim(victim)))
                    #expect(named == empty + 1 && telling.cue(empty) == .heartbeat && telling.cue(named) == .boom)
                    // Until the chair has a name the rest of the screen keeps them seated.
                    #expect(!telling.told(shown: named) && telling.told(shown: named + 1))
                    let reactions = m.indices.filter { if case .react = m[$0] { return true } else { return false } }
                    #expect(reactions.allSatisfy { $0 > named })
                    #expect((m.first == .letter) == (victim == 0))
                } else {
                    quiet += 1
                    #expect(telling.victim == nil && telling.told(shown: 0) && !m.contains(.empty))
                }
                #expect(telling == BreakfastTelling(game: game))
            }
        }
        #expect(murders > 0 && murders + quiet >= 10)
    }

    @Test func whatACeremonySoundsGoesThroughTheEffectsInUse() {
        let kept = Feedback.effects
        defer { Feedback.effects = kept }
        let heard = RecordingEffects()
        Feedback.effects = heard
        Cue.bell.play()
        Cue.declare(.traitor).play()
        Feedback.play(.score(4))
        heard.setBed(.table, level: 1)
        #expect(heard.cues == [.bell, .declare(.traitor)] && heard.events == [.score(4)])
        #expect(heard.asked == [.cue(.bell), .cue(.declare(.traitor)), .event(.score(4)), .bed(.table)])
    }
}
