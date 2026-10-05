import Foundation

enum HazardKind: String {
    /// A blade that swings from one side of the corridor to the other and never stops.
    case blade
    /// A barrel let go from a chute to roll the length of a lane.
    case barrel
    /// Spikes that come up through a patch of floor.
    case spikes
    /// A jet of flame across part of the corridor.
    case flame
    /// A row of darts, set off by a plate in the floor.
    case darts
    /// A gust that pushes everyone in its path sideways. It cannot hurt anyone by itself.
    case gust
}

enum HazardState {
    /// Not yet part of the course: it wakes in a later act.
    case asleep
    case rest
    /// Showing that it is about to go off.
    case warn
    case live
}

/// What a trap did this step, for the screen and the record.
enum HazardBeat {
    case none, warned, fired, rested
}

/// One trap. It keeps its own time, so anyone who watches it can learn it.
struct Hazard {
    let kind: HazardKind
    /// Where it swings, rolls or fires from and to. For spikes and gusts, opposite corners of the patch.
    let a: Vec2
    let b: Vec2
    /// Which way a gust pushes, and how hard.
    var push = Vec2.zero
    /// Steps from one going-off to the next in the first act.
    let period: Int
    /// The act it wakes in.
    var act = 0
    /// Steps into its cycle it starts, so that neighbours are out of step.
    var offset = 0
    /// Plates in the floor that set it off.
    var plates: [Vec2] = []

    private(set) var state = HazardState.asleep
    /// Steps left of the warning or of the going-off.
    private(set) var timer = 0
    /// Steps until it next warns.
    private(set) var clock = 0
    private var phase = 0.0
    /// Where the moving part is, and where it was a step ago.
    private(set) var pos: Vec2
    private(set) var last: Vec2
    /// This going-off was not on its own rhythm.
    private(set) var tripped = false
    /// Private: whose hand tripped it, if it was anyone's.
    private(set) var by: PlayerID?
    /// Times it will go off again straight away: a tripped trap sticks.
    private var again = 0
    /// How often a tripped trap goes off again before it settles.
    static var sticks = 2

    init(_ kind: HazardKind, from a: Vec2, to b: Vec2, period: Double, act: Int = 0, offset: Double = 0,
         push: Vec2 = .zero, plates: [Vec2] = []) {
        self.kind = kind
        self.a = a
        self.b = b
        self.period = Feel.ticks(period)
        self.act = act
        self.offset = Feel.ticks(offset)
        self.push = push
        self.plates = plates
        pos = a
        last = a
    }

    /// Steps of warning before it can hurt anyone.
    var warnTicks: Int {
        switch kind {
        case .blade: return Feel.ticks(0.5)
        case .barrel: return Feel.ticks(0.7)
        case .spikes: return Feel.ticks(0.5)
        case .flame: return Feel.ticks(0.6)
        case .darts: return Feel.ticks(0.4)
        case .gust: return Feel.ticks(0.8)
        }
    }

    var liveTicks: Int {
        switch kind {
        case .blade: return Feel.hurry
        case .barrel: return max(1, Int((a.distance(to: b) / Hazard.barrelSpeed * Double(Feel.hz)).rounded(.up)))
        case .spikes: return Feel.ticks(0.9)
        case .flame: return Feel.ticks(0.8)
        case .darts: return Feel.ticks(0.25)
        case .gust: return Feel.ticks(1.5)
        }
    }

    static let barrelSpeed = 150.0

    /// How thick the dangerous part is, from its middle.
    var size: Double {
        switch kind {
        case .blade, .barrel: return 13
        case .flame: return 8
        case .darts: return 4
        case .spikes, .gust: return 0
        }
    }

    var awake: Bool { state != .asleep }
    /// 0 at the start of the warning, 1 as it goes off.
    var warning: Double { state == .warn ? 1 - Double(timer) / Double(warnTicks) : 0 }
    /// Whether touching it now would put a runner down.
    var deadly: Bool {
        switch kind {
        case .blade: return awake
        case .gust: return false
        default: return state == .live
        }
    }
    /// A blade running fast after being tripped.
    var hurried: Bool { kind == .blade && state == .live }
    /// Whether it could be tripped this step.
    var ready: Bool { state == .rest && (kind != .darts || clock <= 0) }

    // MARK: - Time

    mutating func step(act now: Int) -> HazardBeat {
        last = pos
        let pace = Feel.actPace[min(now, Feel.actPace.count - 1)]
        if state == .asleep {
            guard now >= act else { return .none }
            state = .rest
            clock = max(1, Int(Double(period) * pace) - offset)
            phase = Double(offset) / Double(max(period, 1))
        }
        var beat = HazardBeat.none
        if kind == .blade {
            var rate = 1 / (Double(period) * pace)
            if state == .warn {
                timer -= 1
                if timer <= 0 { state = .live; timer = liveTicks; beat = .fired }
            } else if state == .live {
                rate *= Feel.hurryPace
                timer -= 1
                if timer <= 0 { settle(pace); beat = .rested }
            }
            phase += rate
            if phase >= 1 { phase -= 1 }
            pos = a + (b - a) * (0.5 - 0.5 * cos(2 * Double.pi * phase))
            return beat
        }
        switch state {
        case .asleep:
            break
        case .rest:
            clock -= 1
            // Darts wait for a foot on the plate.
            if clock <= 0, kind != .darts { state = .warn; timer = warnTicks; beat = .warned }
        case .warn:
            timer -= 1
            if timer <= 0 {
                state = .live
                timer = liveTicks
                pos = a
                last = a
                beat = .fired
            }
        case .live:
            timer -= 1
            if kind == .barrel {
                let d = pos.distance(to: b), stride = Hazard.barrelSpeed * Feel.tick
                pos = d <= stride ? b : pos + (b - pos) * (stride / d)
            }
            if timer <= 0 { settle(pace); beat = .rested }
        }
        return beat
    }

    private mutating func settle(_ pace: Double) {
        if again > 0, kind != .blade {
            again -= 1
            state = .warn
            timer = warnTicks
            if kind == .barrel { pos = a; last = a }
            return
        }
        state = .rest
        tripped = false
        by = nil
        clock = kind == .darts ? Feel.ticks(1) : max(Feel.ticks(0.4), Int(Double(period) * pace) - warnTicks - liveTicks)
        if kind == .barrel { pos = a; last = a }
    }

    /// Sets it off out of turn, with its usual warning. False when it is already going or not there yet.
    mutating func trip(by who: PlayerID?) -> Bool {
        guard ready else { return false }
        state = .warn
        timer = warnTicks
        tripped = true
        by = who
        again = Hazard.sticks
        return true
    }

    /// A foot on a plate. Nobody is to blame for that.
    mutating func plate() -> Bool {
        guard kind == .darts, ready else { return false }
        state = .warn
        timer = warnTicks
        return true
    }

    /// This trap as it will be some steps from now, if nobody touches it.
    func ahead(_ steps: Int, act now: Int) -> Hazard {
        var h = self
        for _ in 0..<max(0, steps) { _ = h.step(act: now) }
        return h
    }

    // MARK: - Reach

    /// The patch a spike bed or a gust covers.
    var patch: (lo: Vec2, hi: Vec2) {
        (Vec2(min(a.x, b.x), min(a.y, b.y)), Vec2(max(a.x, b.x), max(a.y, b.y)))
    }

    /// How far a point is from the middle of the dangerous part, wherever that is this step.
    func distance(to p: Vec2) -> Double {
        switch kind {
        case .blade, .barrel:
            return pos.distance(to: p)
        case .flame, .darts:
            return segmentNear(a, b, p)
        case .spikes, .gust:
            let (lo, hi) = patch
            let dx = max(lo.x - p.x, 0, p.x - hi.x), dy = max(lo.y - p.y, 0, p.y - hi.y)
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// Whether a runner standing here would be caught by it this step.
    func hits(_ p: Vec2) -> Bool {
        deadly && distance(to: p) < (size + Feel.radius) * Feel.forgiveness
    }

    /// Close enough to feel it go by, and not caught.
    func grazes(_ p: Vec2) -> Bool {
        guard deadly else { return false }
        let d = distance(to: p), hit = (size + Feel.radius) * Feel.forgiveness
        return d >= hit && d < hit + Feel.nearMiss
    }

    /// Whether a gust has hold of a runner standing here.
    func blows(_ p: Vec2) -> Bool {
        kind == .gust && state == .live && distance(to: p) <= 0
    }
}
