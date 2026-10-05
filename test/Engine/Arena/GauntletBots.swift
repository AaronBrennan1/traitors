import Foundation

/// An honest player's odd moment: somewhere to go and something to do there.
struct Errand {
    var kind: SightingKind
    /// The step it comes on at.
    var start: Int
    var timer = 0
    var arrived = false
    var target: Vec2?
}

/// What a bot keeps in its head from one look at the course to the next.
struct Bot {
    var rng: SeededRNG
    /// 0...1: how well it reads the traps today.
    var proficiency: Double
    /// Steps until it looks again.
    var wait = 0
    var stick = Vec2.zero
    /// How many bags it means to carry this trip.
    var wantCarry = 1
    var empty = false
    /// Where across the corridor it likes to run.
    var lane = 195.0
    /// Steps it has the traps' timing wrong by.
    var err = 0
    /// Steps it has been trying to move and getting nowhere, and steps left of stepping round whatever is in the way.
    var stuck = 0
    var dodge = 0
    var dodgeDir = Vec2.zero
    var errands: [Errand] = []

    // The shadow's hand.
    /// How often it means to use it today.
    var wanted = 0
    var nextAct = Int.max
    var target: Int?
    /// Steps spent getting to a mechanism, and steps stood at it.
    var chase = 0
    var lurk = 0
}

extension Gauntlet {
    /// How much the bots' day swings their play, per point of form.
    static var formGain = 0.12

    /// What a bot wants this look.
    private enum Intent {
        case go(Vec2)
        case stand
    }

    func seatBots() {
        var dice = SeededRNG.derived(setup.seed, 5)
        for seat in setup.cast {
            var b = Bot(rng: SeededRNG.derived(setup.seed, 11, UInt64(seat.id)),
                        proficiency: clamp(0.25 + 0.5 * seat.skill + Gauntlet.formGain * setup.form, 0.1, 0.95))
            b.wait = dice.int(12)
            b.lane = dice.range(55, course.size.x - 55)
            for kind in SightingKind.allCases where kind.suspicious {
                let rate = SightingModel.baseline(kind) * SightingModel.quirk(seed: setup.quirkSeed, player: seat.id, kind: kind)
                if dice.chance(rate) { b.errands.append(Errand(kind: kind, start: Int(Double(totalTicks) * dice.range(0.12, 0.8)))) }
            }
            b.errands.sort { $0.start < $1.start }
            if setup.saboteurs.contains(seat.id) {
                b.wanted = Gauntlet.sabotageActs + Int((2 * seat.deceit).rounded())
                b.nextAct = Int(Double(totalTicks) * dice.range(0.05, 0.15))
            }
            bots.append(b)
        }
    }

    /// How many times a bot on the hand uses it, before its nerve is counted.
    static var sabotageActs = 4

    /// One bot's turn. It only looks properly every few steps; between looks it keeps doing what it decided.
    func think(_ i: Int) {
        guard runners[i].up else { return }
        bots[i].wait -= 1
        if bots[i].wait > 0 {
            runners[i].move = bots[i].stick
            return
        }
        var b = bots[i]
        let pause = 6 + Int(((1 - b.proficiency) * 8).rounded())
        b.wait = pause
        if b.rng.chance(0.25) { b.err = Int((b.rng.gaussian() * (1 - b.proficiency) * 0.12 * Double(Feel.hz)).rounded()) }
        let r = runners[i]
        if r.carry == 0 {
            if !b.empty {
                b.empty = true
                b.wantCarry = 1 + (b.rng.chance(0.3 + 0.5 * b.proficiency) ? 1 : 0) + (b.rng.chance(0.55 * b.proficiency) ? 1 : 0)
            }
        } else {
            b.empty = false
        }
        let intent = hand(i, &b, pause) ?? errand(i, &b, pause) ?? haul(i, b)
        b.stick = steer(i, &b, intent)
        // Two runners pushing head on get nowhere: one of them has to step round.
        if b.dodge > 0 {
            b.dodge -= pause
            if b.stick.length > 0.5 { b.stick = (b.stick + b.dodgeDir).unit }
        } else if b.stick.length > 0.5, r.speed < 30, r.dash == 0 {
            b.stuck += pause
            if b.stuck > Feel.ticks(0.6) {
                b.stuck = 0
                b.dodge = Feel.ticks(0.5)
                let side = b.rng.chance(0.5) ? 1.0 : -1.0
                b.dodgeDir = Vec2(-b.stick.y, b.stick.x) * (1.4 * side)
            }
        } else {
            b.stuck = 0
        }
        bots[i] = b
        runners[i].move = b.stick
    }

    // MARK: - The day's work

    private func haul(_ i: Int, _ b: Bot) -> Intent {
        let r = runners[i]
        if r.carry < Feel.maxCarry {
            var best: Vec2?
            var bestD = r.carry == 0 ? 90.0 : 50.0
            for bag in bags where bag.ttl > 40 && bag.age > 20 {
                let d = bag.pos.distance(to: r.pos)
                if d < bestD, course.grid.walkable(r.pos, bag.pos) { bestD = d; best = bag.pos }
            }
            if let best { return .go(best) }
        }
        if r.carry == 0 {
            return hoardOpen ? follow(course.toHoard, from: r.pos, lane: b.lane) : .stand
        }
        if course.tile(at: r.pos) == .hoard, r.carry < b.wantCarry, hoardOpen {
            // Worth waiting for another bag only while there is time to get it home.
            let way = Double(course.index(at: r.pos).map { course.toVault[$0] } ?? 0) * Course.cell / (Feel.speed * 0.7)
            if timeLeft > way + 2 { return .stand }
        }
        return follow(course.toVault, from: r.pos, lane: b.lane)
    }

    /// Somewhere to head for that is a few tiles on along the way, keeping to the bot's own side of the corridor.
    private func follow(_ field: [Int], from p: Vec2, lane: Double) -> Intent {
        guard let first = course.next(from: p, by: field) else { return .stand }
        var aim = first
        var probe = first
        for _ in 0..<2 {
            guard let on = course.next(from: probe, by: field), clearRun(p, on) else { break }
            aim = on
            probe = on
        }
        var d = (aim - p).unit
        if abs(d.y) > 0.7 { d = (d + Vec2(clamp((lane - p.x) / 60, -0.7, 0.7), 0)).unit }
        return .go(p + d * 60)
    }

    /// Whether there is floor and no wall all the way from one point to another.
    private func clearRun(_ a: Vec2, _ b: Vec2) -> Bool {
        let steps = max(2, Int(a.distance(to: b) / 10))
        for k in 0...steps {
            let p = a + (b - a) * (Double(k) / Double(steps))
            if course.grid.isSolid(p) || !course.hasFloor(p) { return false }
        }
        return true
    }

    /// Whether a spot will still have floor some steps from now.
    private func floorAhead(_ p: Vec2, in steps: Int) -> Bool {
        guard let t = course.index(at: p) else { return false }
        switch course.tiles[t] {
        case .wall, .void: return false
        case .crumble:
            let f = Int(floor[t])
            return f == 0 || (f > 0 ? f > steps : -f <= steps)
        default: return true
        }
    }

    // MARK: - Steering

    /// Turns what a bot wants into a stick, round whatever the traps are about to do. This is where
    /// skill shows: a poor day is one where the bot has the traps' timing a little wrong.
    private func steer(_ i: Int, _ b: inout Bot, _ intent: Intent) -> Vec2 {
        let r = runners[i]
        var want = Vec2.zero
        if case .go(let aim) = intent, aim.distance(to: r.pos) > 6 { want = (aim - r.pos).unit }
        // Lean into a gust.
        for h in hazards where h.kind == .gust && h.state != .rest && h.awake && h.distance(to: r.pos) <= 0 {
            want = (want + h.push.unit * -0.9).capped(1)
        }

        // The traps as the bot expects them at five moments over the next half second.
        // In the dark they are harder to judge.
        let blind = dark.indices.contains { dark[$0] > 0 && course.band($0, holds: r.pos) }
        let dimmed = Int((b.rng.unit() - 0.5) * 20)
        var looks: [[Hazard]] = []
        var future = hazards
        for k in 0..<5 {
            let stride = k == 0 ? max(0, 5 + b.err + (blind ? dimmed : 0)) : 5
            for h in future.indices {
                for _ in 0..<stride { _ = future[h].step(act: act) }
            }
            looks.append(future)
        }
        let margin = blind ? 0 : 3 + 6 * (1 - b.proficiency)

        func deadly(_ p: Vec2, _ k: Int) -> Bool {
            looks[k].contains { $0.deadly && $0.distance(to: p) < $0.size + Feel.radius + margin }
        }

        // A gap ahead that a dash will clear.
        if want.length > 0.5, r.cooldown == 0, r.dash == 0, standable(r.pos) {
            let near = r.pos + want * 22, land = r.pos + want * 76
            if !floorAhead(near, in: 4), !course.grid.isSolid(near), floorAhead(land, in: 12), !course.grid.isSolid(land), !deadly(land, 1) {
                press(i)
                return want
            }
        }

        var options: [Vec2] = [.zero]
        if want.length > 0.5 {
            for angle in [0, 0.45, -0.45, 0.95, -0.95, 1.7, -1.7, Double.pi] {
                options.append(Vec2(want.x * cos(angle) - want.y * sin(angle), want.x * sin(angle) + want.y * cos(angle)))
            }
        } else {
            for k in 0..<8 {
                let angle = Double(k) * Double.pi / 4
                options.append(Vec2(cos(angle), sin(angle)))
            }
        }
        var best = Vec2.zero
        var bestScore = -Double.infinity
        for dir in options {
            var score = dir.length < 0.5 ? (want.length > 0.5 ? -3 : 0) : (want.length > 0.5 ? 10 * dir.dot(want) : -1)
            for k in 0..<5 {
                let steps = 5 * (k + 1)
                let p = r.pos + dir * (r.top * Double(steps) * Feel.tick)
                if course.grid.isSolid(p) { score -= 4; break }
                if !floorAhead(p, in: steps) { score -= 80; break }
                if deadly(p, k) { score -= 100 - 10 * Double(k); break }
            }
            if score > bestScore { bestScore = score; best = dir }
        }

        // Nothing is safe on foot: dash out if there is anywhere to dash to.
        if bestScore <= -60, r.cooldown == 0, r.dash == 0 {
            for dir in options where dir.length > 0.5 {
                let land = r.pos + dir * 76
                if floorAhead(land, in: 12), !course.grid.isSolid(land), !deadly(land, 1), !deadly(land, 2) {
                    press(i)
                    return dir
                }
            }
        }
        return best
    }

    // MARK: - Honest habits

    /// Runs a bot's odd moment if one is due. Nil when it has nothing of the kind on.
    private func errand(_ i: Int, _ b: inout Bot, _ pause: Int) -> Intent? {
        guard var e = b.errands.first, tick >= e.start else { return nil }
        let r = runners[i]
        func done() -> Intent? {
            b.errands.removeFirst()
            return nil
        }
        // Not everything can be got to in good time.
        if tick - e.start > Feel.ticks(18) { return done() }

        var out: Intent?
        switch e.kind {
        case .loiter:
            guard e.arrived || course.zone(at: r.pos) == Zone.open else { return nil }
            e.arrived = true
            e.timer += pause
            if e.timer > Feel.ticks(SightingDeriver.loiterSeconds + 0.8) { return done() }
            out = .stand
        case .offTask:
            if e.target == nil { e.target = course.alcoves.min { $0.distance(to: r.pos) < $1.distance(to: r.pos) } }
            guard let at = e.target else { return done() }
            if r.pos.distance(to: at) > 12 {
                out = approach(at, from: r.pos, lane: b.lane)
            } else {
                e.timer += pause
                if e.timer > Feel.ticks(SightingDeriver.offTaskSeconds + 0.8) { return done() }
                out = .stand
            }
        case .emptyHanded:
            // Back up to the vault a little after bringing something in, with nothing to bring.
            guard e.arrived || (r.carry == 0 && r.sinceBank < Feel.ticks(1)) else { return nil }
            e.arrived = true
            if r.sinceBank < Feel.ticks(2.2) {
                out = .go(course.vaultMouth + Vec2(0, -50))
            } else if course.tile(at: r.pos) != .vault {
                out = .go(course.vault)
            } else {
                return done()
            }
        case .startled, .atTheWorks:
            if e.target == nil {
                e.target = course.mechanisms.filter { $0.kind != .vault }.map(\.pos).min { $0.distance(to: r.pos) < $1.distance(to: r.pos) }
            }
            guard let at = e.target else { return done() }
            if r.pos.distance(to: at) > Feel.reach - 14 {
                out = approach(at, from: r.pos, lane: b.lane)
            } else {
                e.timer += pause
                let long = e.kind == .startled ? 3.0 : 7.0
                if e.timer > Feel.ticks(long) || (e.kind == .startled && e.timer > Feel.ticks(0.6) && r.sinceViewer < 12) { return done() }
                out = .stand
            }
        case .inView:
            return done()
        }
        b.errands[0] = e
        return out
    }

    /// Heads for a point that may be some way up or down the course.
    private func approach(_ at: Vec2, from p: Vec2, lane: Double) -> Intent {
        if abs(at.y - p.y) > 50 { return follow(at.y > p.y ? course.toVault : course.toHoard, from: p, lane: lane) }
        return .go(at)
    }

    // MARK: - The shadow's hand, for a bot

    /// Takes a bot traitor to a mechanism and has it work it when the coast is clear. Nil while it is just playing.
    private func hand(_ i: Int, _ b: inout Bot, _ pause: Int) -> Intent? {
        let r = runners[i]
        guard isSaboteur(r), acts[i] < b.wanted, tick >= b.nextAct, r.handCool == 0 else { return nil }
        // No call for it on a day that is being lost anyway.
        if progress > 0.3, Double(teamTotal) / progress < Gauntlet.lostCause * Double(goal) { return nil }
        if let m = b.target, !usable(course.mechanisms[m]) { b.target = nil }
        if b.target == nil {
            b.target = choose(for: r)
            b.chase = 0
            b.lurk = 0
        }
        guard let m = b.target else {
            b.nextAct = tick + Feel.ticks(2)
            return nil
        }
        let mech = course.mechanisms[m]
        func leave(_ lo: Double, _ hi: Double) -> Intent? {
            b.target = nil
            b.nextAct = tick + Feel.ticks(b.rng.range(lo, hi))
            return nil
        }
        if r.pos.distance(to: mech.pos) > Feel.reach - 14 {
            b.chase += pause
            if b.chase > Feel.ticks(9) { return leave(3, 6) }
            return approach(mech.pos, from: r.pos, lane: b.lane)
        }
        b.lurk += pause
        let deceit = r.seat.deceit
        let desperate = progress > 0.72
        // Someone has just come into view, and the bot loses its nerve.
        if r.sinceViewer < 12, !desperate, b.rng.chance(1 - 0.6 * deceit) { return leave(4, 8) }
        let tolerance = deceit < 0.4 ? 0 : deceit < 0.65 ? 1 : 2
        if r.seenBy.nonzeroBitCount <= tolerance || desperate {
            var ripe = true
            if case .lever(let h) = mech.kind {
                // Wait for somebody to be where it will land.
                ripe = b.lurk > Feel.ticks(1.5) || runners.indices.contains { $0 != i && runners[$0].up && hazards[h].distance(to: runners[$0].pos) < 60 }
            }
            if ripe, r.speed < Feel.restSpeed, b.stick.length < Feel.restStick {
                press(i)
                b.target = nil
                b.nextAct = tick + Feel.sabotageCooldown + Feel.ticks(b.rng.range(0.5, 3))
                // A nervous hand hangs back afterwards, or ducks out of the way.
                if b.rng.chance(Gauntlet.nerves * (1.3 - deceit)) {
                    b.errands.insert(Errand(kind: b.rng.chance(0.5) ? .offTask : .loiter, start: tick + Feel.ticks(0.5)), at: 0)
                }
            }
        } else if b.lurk > Feel.ticks(3) {
            // Hanging about waiting for a moment looks worse the longer it goes on.
            return leave(4, 8)
        }
        return .stand
    }

    /// How readily a bot shows its nerves after using the hand.
    static var nerves = 0.5

    /// Below this share of the goal, as the day is going, a bot on the hand leaves it alone.
    static var lostCause = 0.85

    /// Which mechanism to go for: the nearest, unless the vault is worth the walk or the lights would help.
    private func choose(for r: Runner) -> Int? {
        var best: Int?
        var bestCost = Double.infinity
        for (i, m) in course.mechanisms.enumerated() where usable(m) {
            var cost = abs(m.pos.y - r.pos.y) + 0.5 * abs(m.pos.x - r.pos.x)
            switch m.kind {
            case .vault: cost -= teamTotal >= Gauntlet.spillBags + 2 ? 1000 : -400
            case .sconce: cost -= r.seenBy.nonzeroBitCount >= 2 ? 150 : -60
            case .lever: break
            }
            if cost < bestCost { bestCost = cost; best = i }
        }
        return best
    }
}
