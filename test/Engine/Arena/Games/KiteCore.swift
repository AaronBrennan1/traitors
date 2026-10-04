import Foundation

/// Cliffside Kite Race. Everyone runs the cliff path from left to right, twice round, with a
/// kite overhead. `pos.x` is distance along the course, `z` is how high the kite is flying.
final class KiteCore: ArenaCore {
    struct Ring {
        var x: Double
        var height: Double
    }

    struct Spire {
        var x: Double
        var height: Double
    }

    struct Gull {
        var pos: Vec2
        var speed: Double
    }

    static let lap = 1500.0
    static let low = 30.0, high = 250.0

    private(set) var rings: [Ring] = []
    private(set) var spires: [Spire] = []
    private(set) var gulls: [Gull] = []
    /// Spires a traitor has to leave their string caught on.
    private(set) var marked: [Int] = []
    private var done: Set<Int> = []
    private var passed: [PlayerID: Int] = [:]
    private var combo: [PlayerID: Int] = [:]
    /// Who is caught on which spire, and since when.
    private var snagged: [PlayerID: (spire: Int, since: Double, calm: Bool)] = [:]
    private var free: [PlayerID: Double] = [:]
    private var tug: [PlayerID: Double] = [:]
    private var gust: [PlayerID: Double] = [:]
    private var misses: [PlayerID: Bool] = [:]
    private var dips: [PlayerID: Int] = [:]
    private var nerve: [PlayerID: (spire: Int, go: Bool)] = [:]

    override init(_ setup: ArenaSetup) {
        super.init(setup)
        size = Vec2(Self.lap * 2 + 120, 60)
        vision = 150
        var dice = SeededRNG.derived(setup.seed, 7)
        for l in 0..<2 {
            for i in 0..<7 {
                rings.append(Ring(x: Double(l) * Self.lap + 170 + Double(i) * 200, height: dice.range(110, 225)))
            }
            // Sea stacks stand between the rings and well below them.
            for i in 0..<3 {
                spires.append(Spire(x: Double(l) * Self.lap + 270 + Double(i) * 400, height: 48 + Double(i) * 16))
            }
        }
        let pick = dice.int(3)
        // The same stack on both laps. One catch is enough until late in the game.
        marked = [pick, pick + 3]
        questGoal = setup.questSteps
        for i in 0..<3 {
            let at = totalTime * (0.2 + 0.27 * Double(i)) + dice.range(-3, 3)
            cover.append(CoverWindow(start: at, end: at + 3, kind: .chaos))
        }
        gulls = [Gull(pos: Vec2(900, 170), speed: -70), Gull(pos: Vec2(2300, 130), speed: -55)]
        for (i, a) in actors.enumerated() {
            a.pos = Vec2(20 + Double(i % 4) * 14, 6 + Double(i) * 6)
            a.z = 140
        }
        ready()
    }

    var course: Double { Self.lap * 2 }
    override func canInteract(_ a: ArenaActor) -> Bool { snagged[a.id] != nil }

    override func sees(_ w: ArenaActor, _ p: ArenaActor) -> Bool { abs(w.pos.x - p.pos.x) <= vision }
    override func zone(of a: ArenaActor) -> UInt8 { a.pos.x >= course ? Zone.task : Zone.open }

    private func release(_ a: ArenaActor, by other: ArenaActor?) {
        guard let s = snagged.removeValue(forKey: a.id) else { return }
        let held = time - s.since
        log(.snag, a, a: s.spire, b: Int(held * 10))
        // Caught for a good while and never a tug at the string.
        if held >= 2.5, s.calm, !marked.contains(s.spire) || !isQuester(a) { tell(.atQuestObject, a) }
        free[a.id] = time + 1.2
        tug[a.id] = 0
        if other != nil { cues.append(.popup("FREED", Vec2(a.pos.x, a.pos.y), seat: a.id, bad: false)) }
    }

    override func tick(_ dt: Double) {
        for i in gulls.indices {
            gulls[i].pos.x += gulls[i].speed * dt
            if gulls[i].pos.x < -40 {
                gulls[i].pos = Vec2(course + 60, rng.range(110, 220))
            }
        }
        if coverActive {
            for a in actors where gust[a.id] == nil { gust[a.id] = rng.range(-70, 70) }
        } else {
            gust = [:]
        }
        for a in actors {
            guard a.stun <= 0 else { stand(a); continue }
            var move = Vec2.zero
            var tugging = false
            if isBot(a) { (move, tugging) = think(a) } else { move = input.move; tugging = input.interact }

            if let s = snagged[a.id] {
                stand(a)
                // Any kite passing close knocks the string loose.
                if let other = actors.first(where: { $0 !== a && snagged[$0.id] == nil && abs($0.pos.x - a.pos.x) < 30 && abs($0.z - a.z) < 34 }) {
                    release(a, by: other)
                    continue
                }
                if tugging {
                    snagged[a.id]?.calm = false
                    tug[a.id, default: 0] += dt
                    if tug[a.id]! >= 0.45 { release(a, by: nil) }
                } else if time - s.since >= 3, marked.contains(s.spire), !done.contains(s.spire), isQuester(a), questOpen {
                    done.insert(s.spire)
                    questStep(a)
                }
                continue
            }

            let ahead = actors.contains { $0 !== a && $0.pos.x > a.pos.x && $0.pos.x - a.pos.x < 60 && abs($0.z - a.z) < 30 }
            let run = 58.0 * (ahead ? 1.25 : 1)
            a.vel = Vec2(move.x * run, 0)
            a.pos.x = clamp(a.pos.x + a.vel.x * dt, 0, course + 60)
            a.z = clamp(a.z + move.y * 150 * dt + (gust[a.id] ?? 0) * dt, Self.low, Self.high)

            // Rings only count in order, so running back through one earns nothing.
            while let r = rings.dropFirst(passed[a.id, default: 0]).first, a.pos.x >= r.x {
                passed[a.id, default: 0] += 1
                misses[a.id] = nil
                if abs(a.z - r.height) < 24 {
                    log(.ringPassed, a, a: passed[a.id]!)
                    addCount(1, for: a)
                    combo[a.id, default: 0] += 1
                    if combo[a.id]! % 3 == 0 { addBonus(1, at: a.pos, "COMBO +1") }
                } else {
                    combo[a.id] = 0
                }
            }
            for g in gulls where abs(g.pos.x - a.pos.x) < 16 && abs(g.pos.y - a.z) < 18 {
                a.stun = 1
                combo[a.id] = 0
                cues.append(.popup("GULL!", a.pos, seat: a.id, bad: true))
            }
            if time >= free[a.id, default: 0] {
                for (i, s) in spires.enumerated() where abs(s.x - a.pos.x) < 13 && abs(s.height - a.z) < 17 {
                    snagged[a.id] = (i, time, true)
                    a.z = s.height
                    a.pos.x = s.x
                    // Steering down onto the rock with no wind to blame.
                    if !coverActive { tell(.offTask, a) }
                }
            }
        }
    }

    /// What a bot does with its stick this step, and whether it is tugging at a caught string.
    private func think(_ a: ArenaActor) -> (Vec2, Bool) {
        if let s = snagged[a.id] {
            let mine = isQuester(a) && marked.contains(s.spire) && !done.contains(s.spire) && questOpen
            if mine {
                if spooked(a) { return (.zero, true) }
                return (.zero, false)
            }
            return (.zero, time - s.since > 0.25 + 0.5 * (1 - a.seat.skill))
        }
        guard a.pos.x < course else { return (.zero, false) }
        // Pace the run to finish with a little time to spare.
        let due = course * min(1, progress / 0.9)
        let run = a.pos.x > due + 40 ? 0.35 : 1.0
        var height = 150.0
        let next = rings.first { $0.x > a.pos.x }
        if let r = next {
            if misses[a.id] == nil {
                let left = rings.filter { $0.x > a.pos.x }.count
                let owed = Double(a.seat.target - count(of: a))
                misses[a.id] = !rng.chance(clamp(owed / Double(max(left, 1)), 0, 1))
            }
            height = r.height + (misses[a.id] == true ? (r.height > 160 ? -40 : 40) : 0)
        }
        // The spire comes before the ring: come down onto it when the coast is clear.
        if questDue(a), let m = marked.first(where: { !done.contains($0) && spires[$0].x > a.pos.x - 5 }),
           spires[m].x - a.pos.x < 90, dips[a.id] != m {
            noteTry(a)
            // Nerve is settled once for each spire: with eyes on the kite, only a cool head goes through with it.
            if nerve[a.id]?.spire != m { nerve[a.id] = (m, safeNow(a) || rng.chance(0.25 + 0.55 * a.seat.deceit)) }
            if nerve[a.id]?.go == true { height = spires[m].height } else { dips[a.id] = m }
        }
        let steer = clamp((height - a.z) / 20, -1, 1)
        return (Vec2(run, steer), false)
    }

    override func props() -> [Prop] {
        var out: [Prop] = []
        for (i, r) in rings.enumerated() { out.append(Prop(id: i, kind: .ring, pos: Vec2(r.x, 0), z: r.height)) }
        for (i, s) in spires.enumerated() {
            out.append(Prop(id: 100 + i, kind: .spire, pos: Vec2(s.x, 0), z: s.height, secret: marked.contains(i) && !done.contains(i)))
        }
        for (i, g) in gulls.enumerated() { out.append(Prop(id: 200 + i, kind: .gull, pos: Vec2(g.pos.x, 0), z: g.pos.y)) }
        for a in actors {
            out.append(Prop(id: 300 + a.id, kind: .kite, pos: a.pos, z: a.z, state: snagged[a.id] == nil ? 0 : 1, tint: a.id))
        }
        return out
    }
}
