import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsGauntlet
@testable import TraitorsLab

/// Set `FULL=1` to run everything. Without it the sweeps and the statistical guards are skipped, so
/// a debug `swift test` stays quick. The whole suite takes seconds in a release build:
/// `FULL=1 swift test -c release -Xswiftc -enable-testing`.
let fullRun = ProcessInfo.processInfo.environment["FULL"] != nil

extension Tag {
    /// Plays many whole games.
    @Tag static var sweep: Self
    /// Checks a measured rate against a tolerance. Fails when tuning changes; update deliberately.
    @Tag static var balance: Self
    /// Compares against a recorded run. See GoldenTests.
    @Tag static var golden: Self
}

/// The seeds a sweep covers: all of them on a full run, the first few otherwise.
func seeds(_ all: ClosedRange<Int>, quick: Int) -> ClosedRange<Int> {
    fullRun ? all : all.lowerBound...min(all.upperBound, all.lowerBound + quick - 1)
}

func course(_ core: Gauntlet) -> Course { core.course }

/// A straight corridor with a drop across it some tiles deep, and one player at the controls.
func gapRun(tiles: Int) -> Gauntlet {
    var rows = ["#############", "#VVVVVVVVVVV#", "#VVVVVVVVVVV#", "#...........#", "#.....B.....#", "#...........#"]
    rows += Array(repeating: "#           #", count: tiles)
    rows += ["#...........#", "#.....B.....#", "#...........#", "#.....B.....#", "#...........#", "#HHHHHHHHHHH#", "#HHHHHHHHHHH#", "#############"]
    let setup = ArenaSetup(kind: .greatHall, day: 1, seed: 1, quirkSeed: 1,
                           cast: [ArenaSeat(id: 0, skill: 0.5, perception: 0.5, deceit: 0.5, isHuman: true)], saboteurs: [], autopilot: false)
    return Gauntlet(setup, course: Course(.greatHall, Blueprint(rows: rows, traps: [])))
}

/// Whether running straight up and dashing some way short of the drop gets a runner across it.
func clears(tiles: Int, dashAt short: Double) -> Bool {
    let core = gapRun(tiles: tiles)
    // The drop starts above the five rows of floor over the hoard.
    let edge = Course.cell * 8
    core.input.move = Vec2(0, 1)
    var pressed = false
    for _ in 0..<Feel.ticks(6) {
        let r = core.runners[0]
        if !r.up { return false }
        if r.pos.y > edge + Double(tiles) * Course.cell + Feel.radius, r.dash == 0, core.standable(r.pos) { return true }
        if !pressed, r.pos.y >= edge - short {
            pressed = true
            core.press()
        }
        core.step()
    }
    return false
}

/// A game other than the gauntlet, to step by hand.
func core(_ kind: MissionKind, seed: UInt64, sabotage: Bool = true, hand: ArenaSession.Hand = .bot) -> ArenaCore {
    ArenaGames.make(ArenaSession.sample(kind, seed: seed, sabotage: sabotage, hand: hand)) as! ArenaCore
}
