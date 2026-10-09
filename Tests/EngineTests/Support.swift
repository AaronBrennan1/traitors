import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

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

/// Stops a loop that is waiting on a game, and says where it stuck, when the game never gets there.
struct StepCap {
    var steps = 0
    var limit = 600

    mutating func allows(_ game: Game, _ at: SourceLocation = #_sourceLocation) -> Bool {
        steps += 1
        if steps > limit { Issue.record("seed \(game.seed) still in \(game.phase) on day \(game.day) after \(limit) steps", sourceLocation: at) }
        return steps <= limit
    }
}

/// Plays a game on until it is in `phase`, tapping continue, or answering as `TestSeat` would.
func run(_ game: inout Game, to phase: Phase, answering: Bool = false, _ at: SourceLocation = #_sourceLocation) {
    var cap = StepCap()
    while game.phase != phase, cap.allows(game, at) {
        if answering { game.auto(at) } else { game.go(.proceed, at) }
    }
}

/// Plays the human seat with simple fixed choices so a full game can be driven in a test.
struct TestSeat: SeatPolicy {
    func answer(_ prompt: Prompt, in game: Game) -> Answer {
        switch prompt {
        case .proceed, .over: return .proceed
        case .playMission: return .mission(MissionResult())
        case .speak: return .say(.pass, target: nil, chip: nil)
        case .vote(_, let candidates): return .vote(candidates[0])
        case .murder(let candidates, _): return .murder(candidates[0])
        case .recruit(let candidates): return .recruit(candidates[0])
        case .answerOffer: return .offer(accept: true)
        case .endOrBanish: return .finale(end: false)
        }
    }
}

extension Game {
    /// Answers the prompt, and fails the test if the game refuses.
    mutating func go(_ answer: Answer = .proceed, _ at: SourceLocation = #_sourceLocation) {
        do { try advance(answer) } catch {
            Issue.record("seed \(seed), day \(day), \(phase): refused \(answer) with \(error)", sourceLocation: at)
        }
    }

    /// Answers the prompt as `TestSeat` would.
    mutating func auto(_ at: SourceLocation = #_sourceLocation) {
        go(TestSeat().answer(prompt, in: self), at)
    }
}

func play(seed: UInt64, name: String?, preference: RolePreference = .random) -> Game {
    var game = Game(seed: seed, humanName: name, preference: preference)
    var seat = TestSeat()
    game.play(&seat)
    return game
}

func playToMission(seed: UInt64, preference: RolePreference) -> Game {
    var game = Game(seed: seed, humanName: "Tester", preference: preference)
    run(&game, to: .mission)
    return game
}

/// Plays on from a mission that has just been handed in to the night that follows, and through it.
func playThroughNight(_ game: Game) -> (choice: NightChoice, game: Game) {
    var game = game
    let day = game.day
    var choice = NightChoice.none
    var steps = 0
    while game.phase != .gameOver, game.day == day, steps < 200 {
        if game.phase == .night { choice = NightChoice(game.prompt) }
        game.auto()
        steps += 1
    }
    return (choice, game)
}

func night(_ day: Int, in game: Game) -> (victim: PlayerID?, recruit: Bool)? {
    for case .night(day, let victim, let recruit) in game.log { return (victim, recruit) }
    return nil
}

/// Games with the human faithful, stopped at a mission where one bot traitor is left with the recruitment still to use.
func loneTraitorMissions() -> [Game] {
    var out: [Game] = []
    for seed in 1...200 {
        var game = Game(seed: UInt64(seed), humanName: "Tester", preference: .faithful)
        var steps = 0
        while game.phase != .gameOver, steps < 600 {
            if game.phase == .mission, game.aliveTraitors.count == 1, !game.recruitmentUsed, game.alive.count >= 6 {
                out.append(game)
                break
            }
            game.auto()
            steps += 1
        }
        if out.count == 12 { break }
    }
    return out
}

/// Eight players standing in a row for twenty seconds, with nothing happening.
func stillLedger(seen: SeatMask = 0, zone: UInt8 = Zone.task) -> MissionLedger {
    var l = MissionLedger(seats: Array(0..<8))
    for _ in 0..<100 {
        l.sample(x: (0..<8).map { Double($0) * 30 }, y: Array(repeating: 0, count: 8), zone: Array(repeating: zone, count: 8),
                 seen: (0..<8).map { $0 == 1 ? seen : 0 })
    }
    return l
}

func derived(_ l: MissionLedger) -> [Sighting] {
    // The human always takes in what they are placed to see, so seat 0 makes the outcome certain.
    SightingDeriver.derive(l, day: 1, perception: Array(repeating: 0.5, count: 8), human: 0, seed: 1).sightings
}

