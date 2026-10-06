import Foundation

/// Hurley Target Practice. Everyone stands along the near edge of the lawn with ten sliotars
/// and strikes at targets further up it. `y` is distance up the lawn.
final class HurleyCore: ArenaCore {
    struct Target {
        var pos: Vec2
        var radius: Double
        /// 0 near, 1 a cart that rolls, 2 far on the wall, 3 the gold one beside the bell.
        var kind: Int
        var speed = 0.0
        var down = 0.0
    }

    struct Ball {
        var id: Int
        var by: PlayerID
        var from: Vec2
        var to: Vec2
        var t = 0.0
        var flight: Double
    }

    static let shots = 10
    static let reload = 2.2

    override class var pace: Double { 7 }
    override class var handCost: Int { 5 }
    override class var swing: Double { 0.6 }

    private(set) var targets: [Target] = []
    private(set) var balls: [Ball] = []
    let bell: Vec2
    private(set) var streak = 0
    private var nextBall = 0
    private var bellTries: [PlayerID: Int] = [:]
    private(set) var bellSwing = 0.0
    /// When each player last put a ball down by the bell.
    private var byBell: [PlayerID: Double] = [:]

    override init(_ setup: ArenaSetup) {
        var dice = SeededRNG.derived(setup.seed, 7)
        bell = Vec2(dice.chance(0.5) ? 84 : 306, 452)
        super.init(setup)
        size = Vec2(390, 480)
        // Only the players either side are close enough to see where a strike was aimed.
        vision = 105
        for x in [70.0, 195, 320] { targets.append(Target(pos: Vec2(x, 180), radius: 21, kind: 0)) }
        targets.append(Target(pos: Vec2(100, 290), radius: 18, kind: 1, speed: 38))
        targets.append(Target(pos: Vec2(290, 320), radius: 18, kind: 1, speed: -30))
        targets.append(Target(pos: Vec2(195, 410), radius: 15, kind: 2, speed: 16))
        targets.append(Target(pos: bell + Vec2(bell.x < 195 ? 34 : -34, -6), radius: 15, kind: 3))
        for (i, a) in actors.enumerated() {
            a.pos = Vec2(28 + Double(i) * (334 / Double(max(actors.count - 1, 1))), 26)
            a.aux = Double(Self.shots)
            a.wait = dice.range(1, 4)
        }
        // A ball on the bell startles every target on the lawn.
        works = [Works(id: 0, pos: bell, reach: 13, text: "THE BELL! THE TARGETS DROP")]
        ready()
    }

    override func meter(for a: ArenaActor) -> (label: String, value: Double)? { ("SLIOTARS \(Int(a.aux))", a.aux / Double(Self.shots)) }
    override func zone(of a: ArenaActor) -> UInt8 { Zone.task }

    /// Nobody leaves the line. Whoever has just put a ball down by the bell is the one who was at it.
    override func standingBy(_ a: ArenaActor, _ w: Works) -> Bool { time - (byBell[a.id] ?? -9) < 1.5 }
    override func canSabotage(_ a: ArenaActor) -> Works? { nil }

    override func sprung(_ w: Works) {
        bellSwing = 1
        streak = 0
        for i in targets.indices { targets[i].down = max(targets[i].down, 3) }
    }

    /// Where a strike of a given direction and strength comes down.
    func landing(from p: Vec2, _ shot: Vec2) -> Vec2 {
        p + shot.unit * (110 + 420 * min(1, shot.length))
    }

    private func strike(_ a: ArenaActor, at point: Vec2) {
        guard a.aux >= 1, a.stun <= 0 else { return }
        a.aux -= 1
        a.stun = Self.reload
        let flight = 0.45 + a.pos.distance(to: point) / 700
        balls.append(Ball(id: nextBall, by: a.id, from: a.pos, to: point, flight: flight))
        nextBall += 1
    }

    private func land(_ b: Ball) {
        guard let a = actor(b.by) else { return }
        // Two strikes landing together on one target both count.
        let hit = targets.indices.first { (targets[$0].down <= 0 || targets[$0].down > 1.2) && targets[$0].pos.distance(to: b.to) <= targets[$0].radius }
        let nearBell = b.to.distance(to: bell)
        if nearBell <= 26, hit == nil { byBell[a.id] = time }
        if nearBell <= 13 {
            bellSwing = 1
            cues.append(.popup("DONG", bell, seat: nil, bad: false))
            // Rung on purpose, it is the hand. Rung by a wild strike, it is only a noise.
            if isSaboteur(a), a.handCool <= 0, worksUsable(works[0]) {
                sabotage(a, works[0])
                a.handLeft -= 1
                a.nextAct = time + Self.handCooldown + rng.range(0.5, 3)
            }
        } else if nearBell <= 26, hit == nil {
            // A miss that came down by the bell and not by anything worth points.
            tell(.offTask, a)
        }
        if let i = hit {
            targets[i].down = 1.6
            streak += 1
            addCount(1, for: a, at: b.to)
            if targets[i].kind == 3 { addBonus(1, at: b.to, "GOLD +1") }
            if streak % 5 == 0 { addBonus(1, at: b.to, "STREAK \(streak) +1") }
        } else {
            streak = 0
            cues.append(.burst(b.to, seat: nil))
        }
    }

    override func tick(_ dt: Double) {
        bellSwing = max(0, bellSwing - dt)
        for i in targets.indices {
            targets[i].down = max(0, targets[i].down - dt)
            targets[i].pos.x += targets[i].speed * dt
            if targets[i].pos.x > 340 || targets[i].pos.x < 50 { targets[i].speed = -targets[i].speed }
        }
        var flying: [Ball] = []
        for var b in balls {
            b.t += dt
            if b.t >= b.flight { land(b) } else { flying.append(b) }
        }
        balls = flying

        for a in actors {
            if isBot(a) {
                if a.wait <= 0, a.stun <= 0, a.aux >= 1 { think(a) }
            } else if let shot, shot.length > 0.12 {
                strike(a, at: landing(from: a.pos, shot))
            }
        }
    }

    private func think(_ a: ArenaActor) {
        // Spread the ten strikes over the game.
        a.wait = max(Self.reload, timeLeft / max(a.aux, 1) * rng.range(0.6, 1.0) - 0.5)
        if isSaboteur(a), a.handLeft > 0, time >= a.nextAct, a.handCool <= 0, worksUsable(works[0]), bellTries[a.id, default: 0] < 6 {
            bellTries[a.id, default: 0] += 1
            let wide = 8 + 16 * (1 - a.seat.skill)
            strike(a, at: bell + Vec2(rng.gaussian() * wide, rng.gaussian() * wide))
            return
        }
        // Whether this one lands is settled by what the bot still owes against the strikes it has left.
        let owed = Double(a.target - count(of: a))
        let hit = rng.chance(clamp(owed / max(a.aux, 1), 0, 1))
        let aimed = balls.map(\.to)
        let live = targets.filter { t in t.down <= 0 && !aimed.contains { $0.distance(to: t.pos) < 60 } }
        guard let t = live.isEmpty ? targets.first : rng.pick(live) else { return }
        let flight = 0.45 + a.pos.distance(to: t.pos) / 700
        var point = t.pos + Vec2(t.speed * flight, 0)
        point = point + (hit ? Vec2(rng.range(-0.5, 0.5), rng.range(-0.5, 0.5)) * t.radius
                             : Vec2(rng.chance(0.5) ? 1 : -1, rng.range(-1, 1)).unit * (t.radius + rng.range(8, 30)))
        strike(a, at: point)
    }

    override func props() -> [Prop] {
        var out = [Prop(id: 200, kind: .bell, pos: bell, value: bellSwing)]
        for (i, t) in targets.enumerated() { out.append(Prop(id: i, kind: .target, pos: t.pos, state: t.kind, hidden: t.down > 0)) }
        for b in balls {
            let k = b.t / b.flight
            out.append(Prop(id: 300 + b.id % 100, kind: .ball, pos: b.from + (b.to - b.from) * k, z: sin(k * Double.pi) * 60, tint: b.by))
        }
        return out
    }
}
