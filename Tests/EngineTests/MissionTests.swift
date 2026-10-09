import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsGauntlet
@testable import TraitorsEngine
@testable import TraitorsLab

/// The day's mission as the rules see it: the deck, the record a mini-game hands back, and what is made of it.
@Suite struct MissionTests {
    @Test func everyGameAsksForADaysWorkAndNoMore() {
        // Five courses of the gauntlet and ten games of their own. Fails when a game is added: give it a goal.
        #expect(MissionKind.courses.count == 5 && MissionKind.games.count == 10)
        #expect(Set(MissionKind.courses + MissionKind.games) == Set(MissionKind.allCases))
        for kind in MissionKind.allCases {
            let spec = kind.spec
            for alive in 5...8 {
                // More than everyone but one could manage on an ordinary day, and less than everyone could.
                let goal = Double(spec.teamGoal(alive: alive, handicap: MissionTuning().handicap)), head = spec.head(alive: alive)
                #expect(head > 3, "\(kind)")
                #expect(goal > head * Double(alive - 1) && goal < head * Double(alive), "\(kind)")
            }
            #expect(kind.controls.count == 3 && !kind.hand.isEmpty && !kind.twist.isEmpty, "\(kind)")
            // The one line under a demonstration has to fit on one line.
            for line in [kind.gist, kind.handGist] {
                #expect(!line.isEmpty && line.count <= 45 && !line.contains("\n"), "\(kind): \(line)")
            }
        }
    }

    @Test func theDeckDealsEveryGameOnceAndOneCourseOfTheGauntlet() {
        var courses: Set<MissionKind> = [], openers: Set<MissionKind> = []
        for seed in 1...200 {
            var rng = SeededRNG(seed: UInt64(seed))
            let deck = MissionDeck.deal(rng: &rng)
            #expect(deck.count == MissionKind.games.count + 1 && Set(deck).count == deck.count, "seed \(seed)")
            #expect(Set(deck.filter { !$0.isGauntlet }) == Set(MissionKind.games), "seed \(seed)")
            #expect(deck.filter(\.isGauntlet).count == 1, "seed \(seed)")
            courses.formUnion(deck.filter(\.isGauntlet))
            openers.insert(deck[0])
        }
        // Every course turns up in some game, and no game always comes first.
        #expect(courses == Set(MissionKind.courses))
        #expect(openers.count > MissionKind.games.count)
    }

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

    @Test func aPlayedOutMissionIsSettledFromItsRecord() {
        var game = playToMission(seed: 9, preference: .traitor)
        game.mission?.runner = nil
        let partner = game.aliveTraitors.first { $0 != 0 }!
        let faithful = game.aliveFaithful[0]
        var ledger = stillLedger()
        ledger.events = [MissionEvent(tick: 5, actor: partner, code: .sprung, seen: SeatMask.seat(0))]

        // A faithful cannot be blamed for the day, whatever the game says.
        var wrong = game
        wrong.go(.mission(MissionResult(teamTotal: 10, sunkBy: faithful, ledger: ledger)))
        #expect(wrong.sunkBy == nil && wrong.traitorsMayAct)

        var lost = game
        lost.go(.mission(MissionResult(teamTotal: 10, sunkBy: partner, ledger: ledger)))
        #expect(lost.sunkBy == partner && lost.traitorsMayAct)
        // What was seen is exactly what the record shows, not the dice.
        #expect(lost.mission?.sightings == [Sighting(day: 1, subject: partner, kind: .atTheWorks, witnesses: SeatMask.seat(0))])

        // The pot is the team's haul against its goal.
        game.go(.mission(MissionResult(teamTotal: 999, ledger: ledger)))
        let report = game.report!
        #expect(report.teamTotal == 999 && report.teamGoal == report.kind.spec.teamGoal(alive: 8, handicap: MissionTuning().handicap) && report.groupWon)
        #expect(report.potEarned == 3200)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func breakfastOnlyAsksWhoWasOutOfSightAfterALostDay() {
        var told = 0
        for seed in 1...80 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            var won = false
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                if game.phase == .missionResult, let r = game.report { won = r.groupWon }
                let day = game.day
                game.go()
                guard game.day == day + 1 else { continue }
                let clue = game.feed.contains { $0.text.contains("never out of sight") }
                if clue { told += 1 }
                #expect(!(clue && won), "seed \(seed) day \(day)")
                won = true
            }
        }
        #expect(told > 20)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func onlyTheSeatWithTheHandEverUsesIt() {
        var used = 0
        for kind in MissionKind.allCases {
            let clean = ArenaSession.play(ArenaSession.sample(kind, seed: 5, sabotage: false))
            #expect(clean.sunkBy == nil)
            #expect(clean.ledger?.events.contains { $0.code == .sabotage } == false, "\(kind)")
            for seed in 1...4 {
                let setup = ArenaSession.sample(kind, seed: UInt64(seed), sabotage: true)
                let r = ArenaSession.play(setup)
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
}
