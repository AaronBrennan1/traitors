import Foundation
import TraitorsCore

/// Somewhere in the game, found afresh every step, so it can be a thing that moves.
typealias Mark = (any ArenaPlay) -> Vec2?
/// Something about the game that is so or is not.
typealias Cond = (any ArenaPlay) -> Bool

/// One thing a demonstration's thumbs do. Nothing here is timed against the game's own numbers:
/// a step ends when the game says it has happened, so a change of tuning moves the demonstration
/// with it and does not quietly break it.
enum DemoStep {
    /// The start of a new part of the demonstration. The name is what VoiceOver and the tests call it.
    case beat(String)
    /// Runs to somewhere, round the walls where there are any.
    case go(Mark, within: Double = 8, timeout: Double = 6)
    /// Holds the stick one way for a while.
    case steer(Vec2, seconds: Double)
    /// Thumbs off.
    case rest(Double)
    /// One press of the button, landing with whatever the next step does.
    case tap
    /// Keeps the button down, stick at rest, until something is so.
    case hold(until: Cond, timeout: Double = 4)
    /// Draws a strike back over some seconds and lets it go to come down on a mark.
    case pull(to: Mark, draw: Double = 0.9)
    /// The stick wherever the game in front of it says, until something is so.
    case drive(until: Cond, timeout: Double = 8, (any ArenaPlay) -> Vec2)
    /// Thumbs off until something is so.
    case wait(until: Cond, timeout: Double = 5)
    /// Something that has to be so by now. If it is not, that is a fault, and the tests say which.
    case expect(String, Cond)
}

/// A demonstration of one game: how its floor is set, and what the thumbs then do on it.
struct DemoPlan {
    var seed: UInt64 = 7
    /// How many others are on the floor with the player.
    var bots = 2
    /// Arranges the game before the first step: where the player starts, what is already on the pile.
    var stage: (any ArenaPlay) -> Void = { _ in }
    /// A game laid out specially, where the ordinary one would not fit the picture.
    var make: ((ArenaSetup) -> any ArenaPlay)? = nil
    var steps: [DemoStep]
    /// Seconds the last of it is left on the screen.
    var tail = 1.0
}

/// Plays a `DemoPlan` through a game, one step of the game at a time.
final class DemoDirector: ArenaDirector {
    private let steps: [DemoStep]
    private let tail: Double
    private var at = 0
    /// Seconds into the step in hand.
    private var clock = 0.0
    private var lingered = 0.0
    private var tapDue = false
    private var path: [Vec2] = []
    private var pathGoal: Vec2?

    private(set) var thumbs = ArenaDemo.Thumbs()
    /// Where each beat began, in seconds of the game.
    private(set) var beats: [(name: String, time: Double)] = []
    /// Steps that ran out of time, and things that should have been so and were not.
    private(set) var faults: [String] = []
    private(set) var done = false

    init(_ plan: DemoPlan) {
        steps = plan.steps
        tail = plan.tail
    }

    func drive(_ play: any ArenaPlay) -> (input: ArenaInput, press: Bool, shot: Vec2?) {
        let dt = play.stepSeconds
        var move = Vec2.zero
        var hold = false, steering = false
        var pull: Vec2?
        var shot: Vec2?

        // Steps that take no time are passed straight over, until one wants the thumbs.
        var passes = 0
        scan: while at < steps.count, passes <= steps.count {
            passes += 1
            switch steps[at] {
            case .beat(let name):
                beats.append((name, play.time))
                next()
                continue scan
            case .expect(let what, let cond):
                if !cond(play) { fault("expected \(what)") }
                next()
                continue scan
            case .tap:
                tapDue = true
                next()
                continue scan
            case .go(let mark, let within, let timeout):
                guard let me = Self.eye(play), let target = mark(play) else {
                    fault("nowhere to go")
                    next()
                    continue scan
                }
                if me.distance(to: target) <= within { next(); continue scan }
                if clock >= timeout {
                    fault("still \(Int(me.distance(to: target))) short after \(timeout)s")
                    next()
                    continue scan
                }
                move = heading(play, from: me, to: target)
                steering = true
            case .steer(let v, let seconds):
                if clock >= seconds { next(); continue scan }
                move = v.capped(1)
                steering = true
            case .rest(let seconds):
                if clock >= seconds { next(); continue scan }
            case .hold(let until, let timeout):
                if until(play) { next(); continue scan }
                if clock >= timeout {
                    fault("held for \(timeout)s and nothing came of it")
                    next()
                    continue scan
                }
                hold = true
            case .wait(let until, let timeout):
                if until(play) { next(); continue scan }
                if clock >= timeout {
                    fault("waited \(timeout)s for nothing")
                    next()
                    continue scan
                }
            case .drive(let until, let timeout, let stick):
                if until(play) { next(); continue scan }
                if clock >= timeout {
                    fault("drove for \(timeout)s and never got there")
                    next()
                    continue scan
                }
                move = stick(play).capped(1)
                steering = true
            case .pull(let mark, let draw):
                guard let me = Self.eye(play), let target = mark(play) else {
                    fault("nothing to aim at")
                    next()
                    continue scan
                }
                // A strike comes down 110 points out at the least, and 420 further at full draw.
                let reach = me.distance(to: target)
                let full = (target - me).unit * clamp((reach - 110) / 420, 0.13, 1)
                // Drawn back, held a moment on the aim, and let go.
                if clock >= draw + 0.3 {
                    shot = full
                    next()
                    break scan
                }
                let k = min(1, clock / draw)
                pull = full * (1 - (1 - k) * (1 - k))
            }
            clock += dt
            break scan
        }

        if at >= steps.count {
            lingered += dt
            if lingered >= tail { done = true }
        }
        let press = tapDue
        if tapDue {
            tapDue = false
            thumbs.taps += 1
        }
        thumbs.stick = move
        thumbs.steering = steering
        thumbs.holding = hold
        thumbs.pull = pull
        return (ArenaInput(move: move, hold: hold), press, shot)
    }

    /// Which beat is in hand: the last one begun.
    var beat: Int { max(0, beats.count - 1) }

    private func next() {
        at += 1
        clock = 0
        path = []
        pathGoal = nil
    }

    private func fault(_ what: String) {
        faults.append("step \(at) in \"\(beats.last?.name ?? "the start")\": \(what)")
    }

    // MARK: - Finding the way

    /// Where the player is standing, whichever game it is.
    static func eye(_ play: any ArenaPlay) -> Vec2? {
        if let core = play as? ArenaCore { return core.human?.pos }
        if let g = play as? Gauntlet, let i = g.human { return g.runners[i].pos }
        return nil
    }

    private static func walls(_ play: any ArenaPlay) -> ArenaGrid? {
        if let core = play as? ArenaCore { return core.grid }
        return (play as? Gauntlet)?.course.grid
    }

    /// Whether somebody of a player's width could walk straight from one point to another.
    private static func open(_ grid: ArenaGrid, _ a: Vec2, _ b: Vec2) -> Bool {
        let d = b - a
        guard d.length > 0.5 else { return true }
        let side = Vec2(-d.y, d.x).unit * 8
        return grid.walkable(a, b) && grid.walkable(a + side, b + side) && grid.walkable(a - side, b - side)
    }

    /// Which way to push the stick to get somewhere: straight at it when the way is open, and
    /// from one tile to the next when it is not.
    private func heading(_ play: any ArenaPlay, from me: Vec2, to target: Vec2) -> Vec2 {
        var aim = target
        if let grid = Self.walls(play), !Self.open(grid, me, target) {
            if pathGoal.map({ $0.distance(to: target) > 4 }) ?? true || path.isEmpty {
                path = grid.path(from: me, to: target)
                pathGoal = target
            }
            while path.count > 1, me.distance(to: path[0]) < 5 || Self.open(grid, me, path[1]) { path.removeFirst() }
            if let first = path.first { aim = first }
        }
        let d = aim - me
        guard d.length > 0.01 else { return .zero }
        // The thumb eases off over the last few points, the way a thumb does.
        let push = aim == target ? clamp(d.length / 14, 0.45, 1) : 1
        return d.unit * push
    }
}
