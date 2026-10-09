import Foundation
import Testing
@testable import TraitorsCore

/// The public record and what each kind of statement means. Nothing here plays a game: the
/// logs are made up, so a failure is about the record and nothing else.
@Suite struct RecordTests {
    /// Everything the index answers with, written out in a fixed order so two can be compared whole.
    static func picture(_ ix: LogIndex) -> String {
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

    static func same(_ a: LogIndex, _ b: LogIndex) -> Bool { picture(a) == picture(b) }

    static let kinds: [StatementKind] = [.accuse, .defend, .selfDefend, .answer, .declare, .question, .pass, .callout, .doubt, .vouch, .challenge]

    /// A few days of table talk, votes, banishments and nights between eight seats, in no sensible order of play.
    static func madeUpLog(seed: UInt64) -> [PublicEvent] {
        var rng = SeededRNG(seed: seed)
        var log: [PublicEvent] = []
        var alive = Array(0..<Rules.seats)
        for day in 1...4 where alive.count > 3 {
            log.append(.mission(MissionReport(kind: .greatHall, day: day, teamTotal: 40 + rng.int(20), teamGoal: 50, groupWon: rng.chance(0.4), potEarned: 0)))
            for _ in 0..<(6 + rng.int(10)) {
                let speaker = rng.pick(alive), kind = rng.pick(kinds)
                let target = kind == .pass ? nil : rng.pick(alive.filter { $0 != speaker })
                var chip: Chip?
                if let target, rng.chance(0.3) {
                    chip = Chip(kind: rng.chance(0.5) ? .sighting : .caughtLie, subject: target, day: day, other: rng.pick(alive),
                                sight: rng.pick(SightingKind.allCases), strength: 1)
                }
                log.append(.statement(Statement(day: day, speaker: speaker, kind: kind, target: target, chip: chip, text: "")))
            }
            for round in 1...(rng.chance(0.3) ? 2 : 1) {
                for voter in alive { log.append(.vote(day: day, round: round, voter: voter, target: rng.pick(alive.filter { $0 != voter }))) }
            }
            let out = rng.pick(alive)
            alive.removeAll { $0 == out }
            log.append(.banished(day: day, player: out, role: rng.chance(0.3) ? .traitor : rng.chance(0.8) ? .faithful : nil))
            let victim = rng.chance(0.6) ? rng.pick(alive) : nil
            alive.removeAll { $0 == victim }
            log.append(.night(day: day, victim: victim, recruitNight: victim == nil && rng.chance(0.3)))
        }
        return log
    }

    @Test func theIndexKeptAsEventsArriveIsTheOneBuiltFromScratch() throws {
        for seed in 1...60 {
            let log = Self.madeUpLog(seed: UInt64(seed))
            var record = PublicRecord()
            for (i, event) in log.enumerated() {
                record.append(event)
                // After every event, not only at the end.
                guard Self.same(record.index, LogIndex(log: Array(log.prefix(i + 1)), count: Rules.seats)) else {
                    Issue.record("seed \(seed): the index went astray at event \(i), \(event)")
                    break
                }
            }
            #expect(record.count == log.count)
            // A save keeps the events and works the index out again.
            let back = try JSONDecoder().decode(PublicRecord.self, from: JSONEncoder().encode(record))
            #expect(back.count == log.count && Self.same(back.index, record.index), "seed \(seed)")
        }
    }

    @Test func everyKindOfStatementMeansOneThing() {
        for kind in Self.kinds {
            let e = kind.effect
            // Pushing for a banishment is going after someone; the reverse need not hold (a doubt).
            #expect(e.push <= e.attack, "\(kind)")
            // Nothing both points the finger and speaks up for its target.
            if e.names || e.flags { #expect(e.heat > 0 && !e.vouches, "\(kind)") }
            if e.reading == .defend || e.reading == .vouch { #expect(e.heat < 0 && e.attack == 0 && !e.names, "\(kind)") }
            if e.declares { #expect(e.names, "\(kind)") }
            if e.grudge { #expect(e.attack == 1, "\(kind)") }
            #expect((e.reading == nil) == (kind == .question || kind == .pass), "\(kind)")
        }
    }

    @Test func whatTheRecordSaysOfSomeoneIsOnlyWhatHappened() {
        // Seat 3 voted out a faithful on day one; seat 4 did not.
        var log: [PublicEvent] = [.statement(Statement(day: 1, speaker: 3, kind: .accuse, target: 5, chip: nil, text: ""))]
        log += [(3, 5), (4, 6), (2, 5), (1, 5)].map { .vote(day: 1, round: 1, voter: $0.0, target: $0.1) }
        log.append(.banished(day: 1, player: 5, role: .faithful))
        let seats = (0..<Rules.seats).map { Seat(id: $0, name: "P\($0)", alive: $0 != 5, revealed: $0 == 5 ? .faithful : nil, charisma: 0.5) }
        let view = TableView(day: 2, seats: seats, log: log, heat: Array(repeating: 0, count: Rules.seats))
        #expect(Chips.holds(Chip(kind: .votedOutFaithful, subject: 3, day: 1, other: 5), view: view))
        #expect(!Chips.holds(Chip(kind: .votedOutFaithful, subject: 4, day: 1, other: 5), view: view))
        #expect(Chips.holds(Chip(kind: .firstNamed, subject: 3, day: 1, other: 5), view: view))
        #expect(view.index.blame.first?.votes == 3 && view.index.blame.first?.voters == 4)
        // Having been right costs nothing; having been wrong costs standing.
        #expect(view.standing(3) < view.standing(4))
    }

    @Test func theSameSeedDrawsTheSameNumbers() {
        var a = SeededRNG(seed: 99), b = SeededRNG(seed: 99)
        #expect((0..<50).map { _ in a.next() } == (0..<50).map { _ in b.next() })
        // A fork is its own stream, and taking one moves the parent the same way every time.
        var c = SeededRNG(seed: 99), d = SeededRNG(seed: 99)
        var fc = c.fork(), fd = d.fork()
        #expect(fc.next() == fd.next() && c.next() == d.next())
        #expect(SeededRNG.derived(7, 1).state == SeededRNG.derived(7, 1).state && SeededRNG.derived(7, 1).state != SeededRNG.derived(7, 2).state)
    }
}

@Suite struct TuningTests {
    @Test func aTuningIsSetByNameAndAnUnknownNameIsRefused() throws {
        var tuning = Tuning()
        #expect(tuning == Tuning())
        try tuning.set("spread", 0.5)
        try tuning.set("sticks", 4)
        try tuning.set("liftWorks", 3)
        #expect(tuning.mission.spread == 0.5 && tuning.arena.sticks == 4 && tuning.belief.sight(.atTheWorks) == 3)
        #expect(tuning != Tuning())
        // Everything else is as it was.
        #expect(tuning.sightings == SightingTuning() && tuning.mission.handicap == MissionTuning().handicap)
        #expect(throws: Tuning.UnknownName(name: "nonsense")) { try tuning.set("nonsense", 1) }
        // It is part of a save, and comes back as it went.
        #expect(try JSONDecoder().decode(Tuning.self, from: JSONEncoder().encode(tuning)) == tuning)
    }

    @Test func aGoalIsEasierTheMoreItLetsTheCompanyOff() {
        let spec = MissionKind.greatHall.spec
        #expect(spec.teamGoal(alive: 8, handicap: 1.5) < spec.teamGoal(alive: 8, handicap: 0.5))
        #expect(spec.teamGoal(alive: 8, handicap: 0.5) < spec.teamGoal(alive: 8, handicap: 0))
    }
}
