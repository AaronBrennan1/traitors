import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsLab
@testable import TraitorsGauntlet

/// The seam the screen plays a mini-game through: time and thumbs in, what to show and the result out.
@Suite struct SessionTests {
    static func playing(_ kind: MissionKind, seed: UInt64 = 2, sabotage: Bool = false, hand: ArenaSession.Hand = .idle) -> ArenaSession {
        let session = ArenaSession(ArenaSession.sample(kind, seed: seed, sabotage: sabotage, hand: hand))
        while session.stage == .countdown { session.advance(0.1, input: ArenaInput()) }
        return session
    }

    @Test func theCountdownRunsThreeTwoOneAndThenItIsPlaying() {
        let session = ArenaSession(ArenaSession.sample(.greatHall, seed: 2, sabotage: false, hand: .idle))
        var seen: [Int] = []
        while let n = session.countdownNumber {
            if seen.last != n { seen.append(n) }
            // Nothing moves before the start.
            #expect(session.tally.allSatisfy { $0 == 0 } && session.clock.fraction == 1)
            session.advance(1.0 / 60, input: ArenaInput())
        }
        #expect(seen == [3, 2, 1] && session.stage == .playing)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func aRoundSkippedPartWayIsStillARoundPlayed() {
        for kind in MissionKind.allCases {
            // Watched for a while with bots in every seat, then skipped: the same round as one never watched at all.
            let setup = ArenaSession.sample(kind, seed: 12, sabotage: true)
            let whole = ArenaSession.play(setup)
            let session = ArenaSession(setup)
            for _ in 0..<600 { session.advance(1.0 / 60, input: ArenaInput()) }
            #expect(session.stage == .playing, "\(kind)")
            session.finish()
            #expect(session.stage == .finished && session.result() == whole, "\(kind): skipping changed how the round came out")
            #expect(session.clock.secondsLeft == 0 || kind.isGauntlet, "\(kind)")
            // And nothing more happens to it.
            session.advance(1, input: ArenaInput())
            #expect(session.result() == whole)
        }
    }

    @Test func whatTheGameAsksToBeShownIsHandedOverOnce() {
        let session = Self.playing(.greatHall, hand: .bot)
        var all = 0
        for _ in 0..<900 {
            session.advance(1.0 / 60, input: ArenaInput())
            all += session.takeCues().count
            #expect(session.takeCues().isEmpty)
        }
        #expect(all > 0)
    }

    @Test func theClockAndTheTallyAreTheGamesOwn() {
        let session = Self.playing(.sheepRoundUp, hand: .bot)
        var last = session.clock
        for _ in 0..<1200 {
            session.advance(1.0 / 30, input: ArenaInput())
            let now = session.clock
            #expect(now.secondsLeft <= last.secondsLeft && now.fraction <= last.fraction && now.fraction >= 0)
            #expect(now.urgent == (session.play.timeLeft < 8))
            last = now
        }
        #expect(session.tally.count == session.setup.cast.count && session.tally.reduce(0, +) > 0)
        #expect(session.teamTotal == session.play.teamTotal && session.goal == session.play.goal)
        #expect(session.sealing == nil)
    }

    @Test func onlyWhoeverIsAtTheControlsHasAPanelOrAResult() {
        // A bot in every seat: nobody to show a button to.
        let watched = Self.playing(.greatHall, hand: .bot)
        #expect(watched.panel == nil && watched.player == nil && watched.playerResult == nil && watched.ownHand == nil)

        // A faithful at the controls has a panel, and no hand to be shown anything of.
        let played = Self.playing(.greatHall, hand: .idle)
        let panel = played.panel
        #expect(panel != nil && panel?.handInReach == false && panel?.bags?.have == 0)
        #expect(played.player == 0 && played.setup.human == 0 && !played.setup.humanHasHand)
        played.finish()
        #expect(played.playerResult?.count == 0 && played.ownHand == nil)
        #expect(played.playerResult?.extras.count == 2)
    }

    @Test func theButtonOnlyShowsTheHandWhereAPressWouldBeTheHand() {
        // Seat 0 is a human with the hand, standing at the first lever.
        let setup = ArenaSetup(kind: .greatHall, day: 1, seed: 4, quirkSeed: 4,
                               cast: (0..<4).map { ArenaSeat(id: $0, skill: 0.5, perception: 0.5, deceit: 0.5, isHuman: $0 == 0) },
                               saboteurs: [0], autopilot: false)
        #expect(setup.humanHasHand)
        let session = ArenaSession(setup)
        while session.stage == .countdown { session.advance(0.1, input: ArenaInput()) }
        let core = session.gauntlet!
        #expect(session.panel?.handInReach == false)
        let lever = core.course.mechanisms.first { if case .lever = $0.kind { return true } else { return false } }!
        core.runners[0].pos = lever.pos
        core.runners[0].vel = .zero
        #expect(session.panel?.handInReach == core.canSabotage(core.runners[0]))
        #expect(session.panel?.handInReach == true)
        // Running past it is not standing at it: a press there is a dash.
        session.advance(1.0 / 60, input: ArenaInput(move: Vec2(1, 0), hold: false))
        core.runners[0].pos = lever.pos
        #expect(session.panel?.handInReach == false)
    }
}
