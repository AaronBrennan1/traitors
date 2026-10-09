import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

@Suite struct BeliefTests {
    @Test func beliefsWorkForAnyTeamSize() {
        var game = Game(seed: 5, humanName: nil)
        run(&game, to: .voteReveal)
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

    @Test func feedingTheLogInPiecesGivesTheSameBelief() {
        var game = Game(seed: 8, humanName: nil)
        run(&game, to: .gameOver)
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

    @Test func theTopSuspectAlwaysComesWithReasons() {
        for seed in 1...20 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            run(&game, to: .voteReveal)
            let v = game.view()
            for b in game.aliveBots where game.players[b].role == .faithful {
                let belief = Inference.compute(view: v, observer: FaithfulBrain.observer(game.minds[b], game.players[b].personality))
                guard let top = FaithfulBrain.topSuspect(v, belief, me: b), belief.marginal(top) > 0.5, belief.marginal(top) < 1 else { continue }
                #expect(!belief.reasons(for: top).isEmpty, "seed \(seed): \(b) suspects \(top) for no reason")
            }
        }
    }
}

@Suite struct RecallTests {
    /// The minds in a game carry their inference over from one question to the next. At every
    /// step of whole games, what each of them holds is to the last bit what it would work out
    /// from the first day: for itself, for an onlooker, and for its model of everyone else.
    @Test func whatAMindCarriesOverIsExactlyWhatItWouldWorkOutAfresh() {
        var checked = 0, warm = 0
        for seed in seeds(1...16, quick: 3) {
            var game = Game(seed: UInt64(seed), humanName: seed % 4 == 0 ? "Tester" : nil)
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                game.auto()
                let v = game.view()
                for b in game.aliveBots {
                    var mind = game.minds[b]
                    let traits = game.players[b].personality
                    let afresh = Inference.compute(view: v, observer: FaithfulBrain.observer(mind, traits))
                    let carried = FaithfulBrain.honest(view: v, mind: &mind, p: traits)
                    #expect(carried.masks == afresh.masks && carried.weights == afresh.weights, "seed \(seed) day \(game.day) \(game.phase): seat \(b)")
                    checked += 1
                    guard game.players[b].role == .traitor else { continue }
                    let known = game.team.flatMap { game.minds[$0].exposed }
                    let onlooker = TraitorBrain.publicReplay(v, mind: &mind).belief(), plain = TraitorBrain.publicBelief(v)
                    #expect(onlooker.weights == plain.weights && onlooker.masks == plain.masks, "seed \(seed) day \(game.day): the onlooker")
                    let modelled = Listeners.build(view: v, team: game.team, known: known, recall: &mind.recall)
                    let rebuilt = Listeners.build(view: v, team: game.team, known: known)
                    #expect(modelled.ids == rebuilt.ids)
                    for (a, b) in zip(modelled.beliefs, rebuilt.beliefs) { #expect(a.weights == b.weights && a.masks == b.masks, "seed \(seed) day \(game.day): a listener") }
                    warm += 1
                }
            }
        }
        #expect(checked > 100 && warm > 20)
    }

    @Test func aRecallHandedADifferentHistoryStartsAgain() {
        let n = Rules.seats
        let first: [PublicEvent] = [.mission(MissionReport(kind: .greatHall, day: 1, teamTotal: 40, teamGoal: 45, groupWon: false, potEarned: 0)),
                                    .statement(Statement(day: 1, speaker: 1, kind: .accuse, target: 2, chip: nil, text: ""))]
        // The same length and the same first event, and a different second one.
        var second = first
        second[1] = .statement(Statement(day: 1, speaker: 3, kind: .vouch, target: 2, chip: nil, text: ""))
        var recall = Recall()
        let observer = Observer.publicView(count: n)
        let a = recall.replay(.anyone, of: PublicRecord(first), seats: n, observer: observer).belief()
        let b = recall.replay(.anyone, of: PublicRecord(second), seats: n, observer: observer).belief()
        #expect(a.weights == Inference.compute(log: first, count: n, observer: observer).weights)
        #expect(b.weights == Inference.compute(log: second, count: n, observer: observer).weights)
        #expect(a.weights != b.weights)
        // And a mind whose hunches have moved gets the answer for the hunches it has now.
        var moved = observer
        moved.gut[2] = 0.8
        let c = recall.replay(.anyone, of: PublicRecord(second), seats: n, observer: moved).belief()
        #expect(c.weights == Inference.compute(log: second, count: n, observer: moved).weights && c.weights != b.weights)
    }
}

@Suite struct GameRecordTests {
    @Test func aGamesIndexIsTheOneBuiltFromItsLog() throws {
        for seed in seeds(1...30, quick: 4) {
            var game = Game(seed: UInt64(seed), humanName: seed % 3 == 0 ? "Tester" : nil)
            var seat = TestSeat()
            game.play(&seat)
            #expect(RecordPicture.of(game.record.index) == RecordPicture.of(LogIndex(log: game.log, count: Rules.seats)), "seed \(seed)")
            let back = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
            #expect(RecordPicture.of(back.record.index) == RecordPicture.of(game.record.index), "seed \(seed)")
        }
    }
}

enum RecordPicture {
    /// Everything the index answers with, written out in a fixed order so two can be compared whole.
    static func of(_ ix: LogIndex) -> String {
        var votes: [String] = []
        for day in ix.votes.keys.sorted() {
            for round in ix.votes[day]!.keys.sorted() {
                let slate = ix.votes[day]![round]!
                votes.append("\(day).\(round):" + slate.keys.sorted().map { "\($0)>\(slate[$0]!)" }.joined(separator: ","))
            }
        }
        return [String(describing: ix.reports), String(describing: ix.statements), String(describing: ix.banishments),
                String(describing: ix.victims), votes.joined(separator: " "), String(describing: ix.mismatches),
                String(describing: ix.attacks), String(describing: ix.blame), String(describing: ix.vouches),
                String(describing: ix.flags), String(describing: ix.told), String(describing: ix.challenges)].joined(separator: "\n")
    }

}
