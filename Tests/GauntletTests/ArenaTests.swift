import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsGauntlet
@testable import TraitorsLab

/// The mini-games by themselves: courses, physics, traps, the hand, and that the same round plays out the same way twice.
@Suite struct ArenaTests {
    @Test func everyCourseIsWellMade() {
        for kind in MissionKind.courses {
            for row in Courses.blueprint(kind).rows { #expect(row.count == Course.cols, "\(kind): \(row)") }
            let course = Course(kind)
            // There is a way on foot from the hoard to the vault, and somewhere to wake up along it.
            #expect((course.index(at: course.hoard).map { course.toVault[$0] } ?? -1) > 20, "\(kind)")
            #expect((course.index(at: course.vault).map { course.toHoard[$0] } ?? -1) > 20, "\(kind)")
            #expect(course.braziers.count == 3, "\(kind)")
            // A lever, a sconce and the vault door: the hand always has more than one thing to work.
            #expect(course.mechanisms.contains { if case .lever = $0.kind { return true } else { return false } }, "\(kind)")
            #expect(course.mechanisms.contains { if case .sconce = $0.kind { return true } else { return false } }, "\(kind)")
            #expect(course.mechanisms.last?.kind == .vault)
            #expect(course.hazards.count >= 5, "\(kind)")
        }
    }

    @Test func theLedgerSurvivesASave() throws {
        let result = ArenaSession.play(ArenaSession.sample(.greatHall, seed: 3, sabotage: true))
        let ledger = try #require(result.ledger)
        #expect(ledger.ticks > 100 && ledger.x.count == ledger.ticks * ledger.seats.count)
        let back = try JSONDecoder().decode(MissionLedger.self, from: JSONEncoder().encode(ledger))
        #expect(back == ledger)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func everyCoursePlaysItselfOutTheSameWayTwice() {
        for kind in MissionKind.allCases {
            let setup = ArenaSession.sample(kind, seed: 12, sabotage: true)
            let a = ArenaSession.play(setup), b = ArenaSession.play(setup)
            #expect(a == b, "\(kind) is not deterministic")
            #expect((a.teamTotal ?? 0) > 0, "\(kind)")

            // However the frames fall, it is the same game.
            let ragged = ArenaSession(setup)
            var frame = 0
            while ragged.stage != .finished {
                ragged.advance([1.0 / 60, 1.0 / 120, 1.0 / 30, 0.05, 0.004][frame % 5], input: ArenaInput())
                frame += 1
            }
            #expect(ragged.result() == a, "\(kind) depends on the frame rate")
        }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func nobodyEndsUpInAWallOrInsideAnyoneElse() {
        for kind in MissionKind.courses {
            let core = Gauntlet(ArenaSession.sample(kind, seed: 21, sabotage: true))
            var worst = 2 * Feel.radius
            while !core.finished {
                core.step()
                for (i, r) in core.runners.enumerated() where r.up {
                    #expect(!course(core).grid.isSolid(r.pos), "\(kind): seat \(r.id) is in a wall")
                    #expect(r.pos.x >= 0 && r.pos.y >= 0 && r.pos.x <= core.course.size.x && r.pos.y <= core.course.size.y)
                    #expect(r.speed <= Feel.dashSpeed + Feel.shove + 1, "\(kind): seat \(r.id) at \(r.speed)")
                    #expect(r.carry >= 0 && r.carry <= Feel.maxCarry)
                    for o in core.runners[(i + 1)...] where o.up { worst = min(worst, o.pos.distance(to: r.pos)) }
                }
            }
            // A crowd in a corner can be squeezed a little, and no more.
            #expect(worst > 2 * Feel.radius - 6, "\(kind): two runners \(worst) apart")
            #expect(core.tick <= core.totalTicks + Feel.overtime)
        }
    }

    @Test func aDashClearsTwoTilesAndNeverThree() {
        let tries = stride(from: -14.0, through: 40, by: 2)
        #expect(tries.contains { clears(tiles: 2, dashAt: $0) })
        #expect(!tries.contains { clears(tiles: 3, dashAt: $0) })
        // Walking off the edge is a fall, with a moment's grace.
        #expect(!clears(tiles: 1, dashAt: -1000))
    }

    @Test func everyTrapWarnsBeforeItStrikes() {
        for kind in MissionKind.courses {
            for (i, start) in Course(kind).hazards.enumerated() where start.kind != .blade && start.kind != .gust {
                var h = start
                var warned = 0
                for t in 0..<Feel.ticks(80) {
                    let act = min(2, t / Feel.ticks(25))
                    // Set it off out of turn now and then, as a hand or a foot on a plate would.
                    if t % 400 == 399 { _ = h.trip(by: nil) }
                    if t % 400 == 199 { _ = h.plate() }
                    let was = h.state
                    _ = h.step(act: act)
                    if h.state == .warn { warned += 1 }
                    if h.state == .live, was != .live {
                        // The step it strikes on is the last of the warning.
                        #expect(was == .warn && warned + 1 >= Feel.ticks(0.4), "\(kind) trap \(i) struck after \(warned + 1) steps of warning")
                        warned = 0
                    }
                    if h.state == .rest { warned = 0 }
                }
            }
        }
    }

    @Test func aPressIsNeverLostBetweenFrames() {
        let runner = ArenaSession(ArenaSession.sample(.greatHall, seed: 2, sabotage: false, hand: .idle))
        while runner.stage == .countdown { runner.advance(0.1, input: ArenaInput()) }
        // A frame too short for a step, and the press still lands on the next one.
        runner.press()
        runner.advance(0.001, input: ArenaInput())
        #expect(runner.gauntlet!.runners[0].dash == 0)
        runner.advance(1.0 / 60, input: ArenaInput())
        runner.advance(1.0 / 60, input: ArenaInput())
        #expect(runner.gauntlet!.runners[0].dash > 0)

        // A press a moment before the dash is ready again goes off when it is.
        let core = runner.gauntlet!
        while core.runners[0].cooldown > 5 { core.step() }
        #expect(core.runners[0].cooldown > 0 && core.runners[0].dash == 0)
        core.press()
        for _ in 0..<6 { core.step() }
        #expect(core.runners[0].dash > 0)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func everyGameKeepsEveryoneOnTheFloor() {
        for kind in MissionKind.games {
            let game = core(kind, seed: 21)
            var step = 0
            var walled = Array(repeating: 0, count: game.actors.count)
            while !game.finished {
                game.step()
                step += 1
                // Every step is a lot to look at. A few times a second is enough to catch anyone going through a wall.
                guard step % 7 == 0 else { continue }
                for (i, a) in game.actors.enumerated() {
                    #expect(a.pos.x >= 0 && a.pos.y >= 0 && a.pos.x <= game.size.x && a.pos.y <= game.size.y, "\(kind): seat \(a.id) at \(a.pos)")
                    // A bot may clip the corner of a wall as it cuts round it. It may not stay in one.
                    walled[i] = game.grid?.isSolid(a.pos) == true && a.stun <= 0 ? walled[i] + 1 : 0
                    #expect(walled[i] < 3, "\(kind): seat \(a.id) is in a wall")
                }
                #expect(game.teamTotal >= 0)
            }
            // The clock is the only thing that ends one of these, and the record runs the length of it.
            #expect(abs(game.time - game.totalTime) < 0.1, "\(kind)")
            #expect(abs(Double(game.ledger.ticks) - game.totalTime * Double(MissionLedger.hz)) <= 2, "\(kind)")
            #expect(game.ledger.x.count == game.ledger.ticks * game.actors.count, "\(kind)")
            #expect(game.tally.count == game.actors.count && game.tally.reduce(0, +) > 0, "\(kind)")
        }
    }

    @Test func aPressOrAStrikeIsNeverLostBetweenFramesInAnyGame() {
        // A whistle in the round-up: the dog is sent on the press, however short the frame it came in.
        let herd = ArenaSession(ArenaSession.sample(.sheepRoundUp, seed: 2, sabotage: false, hand: .idle))
        while herd.stage == .countdown { herd.advance(0.1, input: ArenaInput()) }
        let sheep = herd.play as! SheepCore
        #expect(sheep.dogBy == nil)
        herd.press()
        herd.advance(0.001, input: ArenaInput())
        #expect(sheep.dogBy == nil)
        herd.advance(1.0 / 30, input: ArenaInput())
        herd.advance(1.0 / 30, input: ArenaInput())
        #expect(sheep.dogBy == 0)

        // A strike on the lawn: one sliotar gone, and a ball in the air.
        let lawn = ArenaSession(ArenaSession.sample(.hurley, seed: 2, sabotage: false, hand: .idle))
        while lawn.stage == .countdown { lawn.advance(0.1, input: ArenaInput()) }
        let hurley = lawn.play as! HurleyCore
        let before = hurley.actors[0].aux
        lawn.shoot(Vec2(0, 0.6))
        lawn.advance(0.001, input: ArenaInput())
        #expect(hurley.actors[0].aux == before)
        lawn.advance(1.0 / 30, input: ArenaInput())
        lawn.advance(1.0 / 30, input: ArenaInput())
        #expect(hurley.actors[0].aux == before - 1 && hurley.balls.contains { $0.by == 0 })
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func theWorksGoByThemselvesInEveryGameAndTheRecordReadsTheSame() {
        for kind in MissionKind.games {
            // Nobody has the hand, and things still go: somebody is written down as standing by, or nobody was there.
            var slips = 0
            for seed in 1...3 {
                let game = core(kind, seed: UInt64(seed), sabotage: false)
                while !game.finished { game.step() }
                slips += game.ledger.events.filter { $0.code == .spilled }.count
                #expect(!game.ledger.events.contains { $0.code == .sabotage }, "\(kind)")
                #expect(game.loss.allSatisfy { $0 == 0 } && game.sunkBy == nil, "\(kind)")
            }
            #expect(slips >= 3, "\(kind): the works slipped \(slips) times in three games")

            // With the hand in play, each use is written down privately, and whoever used it is among those standing by.
            let game = core(kind, seed: 7)
            while !game.finished { game.step() }
            let events = game.ledger.events
            for (i, e) in events.enumerated() where e.code == .sabotage {
                #expect(e.actor == 1, "\(kind)")
                #expect(events[i...].prefix(12).contains { $0.code == .sprung && $0.actor == 1 }, "\(kind): the hand left no mark of who was there")
            }
            #expect(game.acts[1] == events.filter { $0.code == .sabotage }.count, "\(kind)")
            #expect(game.loss[1] <= Double(game.acts[1] * type(of: game).handCost), "\(kind)")
        }
    }

    @Test func standingByAMechanismReadsTheSameWhoeverWorkedIt() {
        func sprung(by hand: PlayerID?) -> [MissionEvent] {
            let core = Gauntlet(ArenaSession.sample(.greatHall, seed: 4, sabotage: true))
            let m = core.course.mechanisms.firstIndex { if case .lever = $0.kind { return true } else { return false } }!
            let at = core.course.mechanisms[m].pos
            // Seats 1 and 2 stand at the lever with seat 0 close by and looking; everyone else is far off.
            for i in core.runners.indices { core.runners[i].pos = core.course.hoard }
            core.runners[1].pos = at + Vec2(30, 0)
            core.runners[2].pos = at + Vec2(40, 8)
            core.runners[0].pos = at + Vec2(90, 0)
            for i in 1...2 {
                core.runners[i].vel = .zero
                core.runners[i].seenBy = SeatMask.seat(0)
            }
            core.spring(m, by: hand)
            return core.ledger.events.filter { $0.code == .sprung }
        }
        let castle = sprung(by: nil), traitor = sprung(by: 1)
        // The same two names, seen by the same eyes, whether it was the castle or seat 1.
        #expect(castle == traitor)
        #expect(castle.map(\.actor).sorted() == [1, 2])
        #expect(castle.allSatisfy { $0.seen == SeatMask.seat(0) })
    }

    @Test func aFullVaultSealsUnlessItIsSpilled() {
        let core = Gauntlet(ArenaSession.sample(.greatHall, seed: 6, sabotage: false, hand: .idle))
        core.teamTotal = core.goal
        for _ in 0..<Feel.seal / 2 { core.step() }
        #expect(core.sealing > 0.3 && !core.finished)
        // Gold back out of the vault breaks the seal, and it starts again from nothing.
        let before = core.teamTotal
        core.spring(core.course.mechanisms.count - 1, by: nil)
        #expect(core.teamTotal < before)
        core.step()
        #expect(core.sealing == 0 && !core.finished)
        core.teamTotal = core.goal + 50
        for _ in 0..<Feel.seal { core.step() }
        #expect(core.finished && core.won)
        #expect(core.tick < core.totalTicks / 2)
    }
}
