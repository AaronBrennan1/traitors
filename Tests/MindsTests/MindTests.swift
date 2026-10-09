import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds

/// A mind is handed a table and asked one question. No game is played.
@Suite struct MindTests {
    static let n = Rules.seats

    static func table(_ log: [PublicEvent], day: Int = 1, out: [PlayerID] = []) -> TableView {
        let seats = (0..<n).map { Seat(id: $0, name: "P\($0)", alive: !out.contains($0), revealed: nil, charisma: 0.5) }
        return TableView(day: day, seats: seats, log: log, heat: Array(repeating: 0, count: n))
    }

    static func notes(_ id: PlayerID, seed: UInt64 = 1, seen: [Sighting] = []) -> BotMind {
        BotMind(id: id, gut: Array(repeating: 0, count: n), seen: seen, rng: SeededRNG(seed: seed))
    }

    static func mind(_ kind: MindKind, seat: PlayerID = 0, seed: UInt64 = 1, seen: [Sighting] = [], team: [PlayerID] = [0, 1]) -> any Mind {
        Minds.make(kind, notes: notes(seat, seed: seed, seen: seen), traits: .average,
                   conspiracy: Conspiracy(team: team, plan: nil, known: []))
    }

    @Test func aFaithfulMindHasNoHandAndNoNight() {
        var m = Self.mind(.faithful)
        let before = m.notes.rng.state
        let table = Self.table(quietTable())
        let hand = m.useTheHand(at: table, mustKill: true), victim = m.murder(at: table), recruit = m.recruit(at: table)
        #expect(!hand && victim == nil && recruit == nil)
        // And it has not so much as rolled a die over it.
        #expect(m.notes.rng.state == before)
    }

    @Test func aVoteIsAlwaysForSomeoneOnTheSlateAndNeverForOneself() {
        let table = Self.table(quietTable())
        for kind in [MindKind.faithful, .traitor, .random] {
            for seed in 1...40 {
                var m = Self.mind(kind, seed: UInt64(seed))
                let slate = [0, 2, 5, 6]
                let pick = m.vote(at: table, among: slate, declared: nil)
                #expect(slate.contains(pick) && pick != 0, "\(kind) seed \(seed) voted for \(pick)")
                // Two names tied and this seat not one of them.
                let tiebreak = m.vote(at: table, among: [3, 4], declared: nil)
                #expect([3, 4].contains(tiebreak), "\(kind)")
            }
        }
    }

    @Test func aMindThatWasThereSaysSoUnlessTheLiarIsItsPartner() {
        let saw = [Sighting(day: 1, subject: 4, kind: .inView, witnesses: SeatMask.seat(0))]
        let lie = Chip(kind: .sighting, subject: 4, day: 1, sight: .emptyHanded, strength: 1)
        #expect(Self.mind(.faithful, seen: saw).knowsBetter(than: lie, saidBy: 6) != nil)
        // It has to have been there that day, and seen something that cannot both be true.
        #expect(Self.mind(.faithful).knowsBetter(than: lie, saidBy: 6) == nil)
        #expect(Self.mind(.faithful, seen: saw).knowsBetter(than: Chip(kind: .sighting, subject: 4, day: 2, sight: .emptyHanded), saidBy: 6) == nil)
        // A traitor will catch out a faithful, and keeps quiet when the liar is one of its own.
        #expect(Self.mind(.traitor, seen: saw).knowsBetter(than: lie, saidBy: 6) != nil)
        #expect(Self.mind(.traitor, seen: saw).knowsBetter(than: lie, saidBy: 1) == nil)
        #expect(Self.mind(.random, seen: saw).knowsBetter(than: lie, saidBy: 6) == nil)
    }

    @Test func whoeverWasSeenAtTheWorksOnALostDayIsTheOneSuspected() throws {
        let saw = [Sighting(day: 1, subject: 2, kind: .atTheWorks, witnesses: SeatMask.seat(0))]
        let m = Self.mind(.faithful, seen: saw)
        let table = Self.table(quietTable(won: false))
        #expect(m.suspect(at: table) == 2)
        let of2 = try #require(m.opinion(of: 2, at: table)), of3 = try #require(m.opinion(of: 3, at: table))
        #expect(of2.suspicion > of3.suspicion + 0.05)
        #expect(of2.why?.kind == .sighting && of2.why?.sight == .atTheWorks)
        // A hunch is not something to hold against anyone.
        #expect(of3.why == nil)
        // A traitor is not honestly looking, and nobody is told what it thinks.
        #expect(Self.mind(.traitor, seen: saw).suspect(at: table) == nil)
        #expect(Self.mind(.traitor, seen: saw).opinion(of: 2, at: table) == nil)
    }

    @Test func aMindPlayingAtRandomSaysNothingAndFlipsACoin() {
        var m = Self.mind(.random)
        let table = Self.table(quietTable() + [says(3, .accuse, 0, Chip(kind: .gut, subject: 0, day: 1))])
        for phase in [TablePhase.opening, .accusations, .rebuttals, .openFloor] {
            let unprompted = m.speak(at: table, phase: phase, replyTo: nil), reply = m.speak(at: table, phase: phase, replyTo: 3)
            #expect(unprompted == nil && reply == nil)
        }
        var ends = 0
        for _ in 0..<200 where m.endTheGame(at: table) { ends += 1 }
        #expect(ends > 60 && ends < 140)
        // On a team, its murder is of somebody outside it.
        for seed in 1...30 {
            var t = Self.mind(.random, seed: UInt64(seed), team: [0, 1])
            let victim = t.murder(at: table)
            #expect(victim != nil && victim != 0 && victim != 1)
        }
    }

    @Test func anAccusedPlayerAlwaysHasSomethingToSay() {
        let me = Self.notes(0)
        #expect(Minds.defences(for: me, traits: .average, at: Self.table(quietTable())).isEmpty)
        let accused = Self.table(quietTable() + [says(3, .accuse, 0, Chip(kind: .gut, subject: 0, day: 1))])
        let options = Minds.defences(for: me, traits: .average, at: accused)
        #expect(options.contains { $0.defence == .denial })
        #expect(options.allSatisfy { $0.credibility >= 0 && $0.credibility <= 1 })
        // Once answered, the charge is no longer open.
        let answered = Self.table(accused.log + [.statement(Statement(day: 1, speaker: 0, kind: .selfDefend, target: 3, chip: nil, text: "", defence: .denial))])
        #expect(Minds.defences(for: me, traits: .average, at: answered).isEmpty)
        // A faithful mind asked to reply picks one of them.
        var m = Self.mind(.faithful)
        let reply = m.speak(at: accused, phase: .rebuttals, replyTo: 3)
        #expect(reply?.kind == .selfDefend && reply?.defence != nil)
    }
}
