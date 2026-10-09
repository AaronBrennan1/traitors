import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds

/// A table of eight on day one, just after a mission the company lost or won.
func quietTable(won: Bool = false) -> [PublicEvent] {
    [.mission(MissionReport(kind: .greatHall, day: 1, teamTotal: won ? 50 : 40, teamGoal: 45, groupWon: won, potEarned: 0))]
}

func says(_ speaker: PlayerID, _ kind: StatementKind, _ target: PlayerID, _ chip: Chip) -> PublicEvent {
    .statement(Statement(day: 1, speaker: speaker, kind: kind, target: target, chip: chip, text: ""))
}

/// Inference from hand-built logs: each test sets up one small situation and asks what a mind makes of it.
@Suite struct InferenceTests {
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
}
