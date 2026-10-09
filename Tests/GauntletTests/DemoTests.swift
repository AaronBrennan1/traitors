import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsGauntlet

/// The demonstrations shown in place of written rules. Each is the real game with a script at the
/// controls, so a change to a game can leave its demonstration showing nothing. These fail when one does.
@Suite struct DemoTests {
    nonisolated static let reels: [(MissionKind, ArenaDemo.Reel)] = MissionKind.allCases.flatMap { kind in ArenaDemo.Reel.allCases.map { (kind, $0) } }

    /// Plays a demonstration to its end a frame at a time, and says what the game made of it.
    private func run(_ demo: ArenaDemo, frame: Double) -> (tally: [Int], spilt: Int, used: Int, time: Double) {
        var frames = 0, spilt = 0
        while !demo.ended, frames < 20_000 {
            demo.advance(frame)
            frames += 1
            // What the screen is told came off the pile.
            for cue in demo.session.takeCues() {
                switch cue {
                case .spilled: spilt += 1
                case .popup(_, _, seat: nil, bad: true): spilt += 1
                default: break
                }
            }
        }
        return (demo.session.tally, spilt, demo.session.ownHand?.uses ?? 0, demo.time)
    }

    @Test(arguments: reels) func everyDemonstrationShowsWhatItSaysItDoes(kind: MissionKind, reel: ArenaDemo.Reel) {
        let demo = ArenaDemo(kind, reel: reel)
        #expect(demo.faults.isEmpty, "\(kind) \(reel): \(demo.faults)")
        // Long enough to follow and short enough to sit through, in two or three parts.
        #expect((3.5...12).contains(demo.duration), "\(kind) \(reel) runs \(demo.duration)s")
        #expect((2...3).contains(demo.beatStarts.count) && demo.beatStarts == demo.beatStarts.sorted(), "\(kind) \(reel): \(demo.beatNames)")

        let shown = run(demo, frame: 1.0 / 60)
        #expect(demo.ended)
        switch reel {
        case .play:
            // The player scores, and nothing puts them down on the way.
            #expect(shown.tally[0] >= 1, "\(kind)")
            #expect(shown.used == 0)
        case .hand:
            // The hand goes off once, and takes something off the pile.
            #expect(shown.used == 1 && shown.spilt == 1, "\(kind)")
        }
    }

    @Test(arguments: reels) func aDemonstrationPlaysTheSameHoweverTheFramesFall(kind: MissionKind, reel: ArenaDemo.Reel) {
        let demo = ArenaDemo(kind, reel: reel)
        let smooth = run(demo, frame: 1.0 / 120)
        demo.restart()
        let rough = run(demo, frame: 1.0 / 15)
        #expect(smooth.tally == rough.tally && smooth.spilt == rough.spilt && abs(smooth.time - rough.time) < 0.1, "\(kind) \(reel)")
        // Sought to its poster, it is the same game part of the way through.
        demo.seek(demo.poster)
        #expect(abs(demo.time - demo.poster * demo.duration) < 0.1 && !demo.ended)
    }
}
