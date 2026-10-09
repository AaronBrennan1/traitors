import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

@Suite struct SightingTests {
    @Test(.tags(.sweep), .enabled(if: fullRun)) func whatIsSeenStaysPrivateUntilSomeoneSaysIt() throws {
        for seed in 1...40 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            run(&game, to: .gameOver)
            for s in game.sightings {
                #expect(!s.witnesses.has(s.subject))
                #expect(s.witnesses != 0)
            }
            // Nothing in a mission report gives away what was seen.
            for case .mission(let r) in game.log {
                let text = String(data: try JSONEncoder().encode(r), encoding: .utf8) ?? ""
                #expect(!text.contains("witnesses"))
            }
            // No two honest sightings of the same player on the same day can contradict each other.
            for a in game.sightings where a.kind == .inView {
                #expect(!game.sightings.contains { $0.day == a.day && $0.subject == a.subject && $0.kind.suspicious })
            }
        }
    }

    @Test(.tags(.balance), .enabled(if: fullRun)) func sightingsAreAsTellingAsTheTableAssumes() {
        // Eight average players, seat 1 with the shadow's hand, over many missions.
        var acting = 0.0, others = 0.0
        var seenActing = Array(repeating: 0.0, count: SightingKind.allCases.count), seenOthers = seenActing
        var rng = SeededRNG(seed: 31)
        for i in 0..<6000 {
            var run = MissionRun(kind: .greatHall, day: 1, alive: Array(0..<Rules.seats), human: nil, traitors: [1, 2], runner: 1,
                                 traits: Array(repeating: .average, count: Rules.seats), quirkSeed: UInt64(i), rng: rng.fork())
            run.resolve(human: nil)
            for p in run.order {
                let on = p == 1 && run.runnerAttempt
                if on { acting += 1 } else { others += 1 }
                for s in run.sightings where s.subject == p {
                    #expect(!s.witnesses.has(p) && s.witnesses != 0)
                    if on { seenActing[s.kind.index] += 1 } else { seenOthers[s.kind.index] += 1 }
                }
            }
        }
        #expect(acting > 1000)
        for kind in [SightingKind.offTask, .loiter, .emptyHanded, .startled] {
            let ratio = (seenActing[kind.index] / acting) / (seenOthers[kind.index] / others)
            #expect(abs(ratio / BeliefTuning().sight(kind) - 1) < 0.2, "\(kind): \(ratio) against \(BeliefTuning().sight(kind))")
        }
        #expect(seenOthers[SightingKind.inView.index] > 0)
    }
}
