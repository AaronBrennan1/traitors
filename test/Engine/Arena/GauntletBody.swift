import Foundation

/// One player on the course.
struct Runner {
    let seat: ArenaSeat
    var id: PlayerID { seat.id }
    var pos: Vec2
    /// Where they were a step ago, for the screen to draw between.
    var last: Vec2
    var vel = Vec2.zero
    var facing = Vec2(0, 1)
    /// The stick this step, length 0...1.
    var move = Vec2.zero

    /// Bags in their arms.
    var carry = 0
    /// Bags they have put in the vault themselves. Shown to the player; the table never hears it.
    var banked = 0
    var streak = 0
    var bestStreak = 0
    var nearMisses = 0

    /// Steps of dash left.
    var dash = 0
    var dashDir = Vec2(0, 1)
    var cooldown = 0
    /// Steps a press is still waiting to be acted on.
    var buffer = 0
    var stagger = 0
    /// Steps until they get up again. Above 0 they are out of the game.
    var down = 0
    var fell = false
    /// Steps of being untouchable after getting up.
    var blink = 0
    /// Steps stood on nothing.
    var offFloor = 0
    var greed = 0
    var nearCool = 0
    var sinceBank = 10_000
    var inVault = false
    var checkpoint: Vec2

    // The shadow's hand.
    var handCool = 0
    /// Steps stood by a mechanism, and since anyone new came into view.
    var lurk = 0
    var sinceViewer = 10_000
    /// Steps stood at the vault door with nothing to put in.
    var atDoor = 0

    // Sight, refreshed five times a second.
    var seenBy: SeatMask = 0
    var newViewers: SeatMask = 0

    init(_ seat: ArenaSeat, at p: Vec2) {
        self.seat = seat
        pos = p
        last = p
        checkpoint = p
    }

    var up: Bool { down == 0 }
    var speed: Double { vel.length }
    /// As fast as they can run with what they are carrying.
    var top: Double { Feel.speed * (1 - Feel.carryDrag * Double(carry)) }
    var mass: Double { 1 + 0.25 * Double(carry) }
    /// Whether nothing can touch them this step.
    var untouchable: Bool { blink > 0 || (dash > 0 && Feel.dashTicks - dash < Feel.dashGrace) }
    /// 0 when the dash has just gone, 1 when it is ready again.
    var dashReady: Double { 1 - Double(cooldown) / Double(Feel.dashCooldown) }
}

/// A bag of gold lying loose on the floor.
struct Bag {
    var pos = Vec2.zero
    /// Steps before it is gone. 0 is a bag that is not there.
    var ttl = 0
    var age = 0
    /// Private: the seat whose hand put it there, or -1.
    var blame = -1
}

extension Gauntlet {
    // MARK: - Moving

    /// One step of a runner's own movement: the press, the dash, the stick.
    func move(_ i: Int) {
        var r = runners[i]
        r.last = r.pos
        if r.down > 0 {
            r.down -= 1
            if r.down == 0 { wake(&r) }
            runners[i] = r
            return
        }
        r.cooldown = max(0, r.cooldown - 1)
        r.stagger = max(0, r.stagger - 1)
        r.blink = max(0, r.blink - 1)
        r.handCool = max(0, r.handCool - 1)
        r.nearCool = max(0, r.nearCool - 1)
        r.sinceBank += 1
        r.sinceViewer += 1
        let stick = r.move.capped(1)

        if r.buffer > 0 {
            r.buffer -= 1
            if r.stagger == 0, r.dash == 0 {
                if canSabotage(r) {
                    r.buffer = 0
                    runners[i] = r
                    sabotage(i)
                    r = runners[i]
                } else if r.cooldown == 0 {
                    r.buffer = 0
                    r.dashDir = stick.length > Feel.restStick ? stick.unit : r.facing
                    r.dash = Feel.dashTicks
                    r.cooldown = Feel.dashCooldown
                    cues.append(.dash(r.id))
                }
            }
        }

        if r.dash > 0 {
            r.dash -= 1
            r.vel = r.dashDir * (r.dash > 0 ? Feel.dashSpeed : r.top)
        } else if r.stagger > 0 {
            let s = r.speed
            r.vel = s > 1 ? r.vel * (max(0, s - Feel.skid * Feel.tick) / s) : .zero
        } else {
            let want = stick * r.top
            r.vel += (want - r.vel).capped((stick.length > 0.05 ? Feel.accel : Feel.brake) * Feel.tick)
        }
        var p = r.pos + r.vel * Feel.tick
        for h in hazards where h.blows(r.pos) { p += h.push * Feel.tick }
        r.pos = pushedOut(p)
        if r.speed > 20 { r.facing = r.vel.unit }
        runners[i] = r
    }

    /// Moves a point out of any wall it has ended up in, and keeps it on the course.
    func pushedOut(_ point: Vec2) -> Vec2 {
        var p = point
        let grid = course.grid, cell = grid.cell, rad = Feel.radius
        for _ in 0..<2 {
            let (c, r) = grid.cellOf(p)
            for dr in -1...1 {
                for dc in -1...1 where grid.isSolid(c + dc, r + dr) {
                    let lo = Vec2(Double(c + dc) * cell, Double(r + dr) * cell)
                    let near = Vec2(clamp(p.x, lo.x, lo.x + cell), clamp(p.y, lo.y, lo.y + cell))
                    let d = p - near
                    let dist = d.length
                    if dist >= rad { continue }
                    if dist > 1e-6 {
                        p = near + d * (rad / dist)
                    } else {
                        // Right inside it: out by the nearest face.
                        let left = p.x - lo.x, right = lo.x + cell - p.x, below = p.y - lo.y, above = lo.y + cell - p.y
                        let least = min(left, right, below, above)
                        if least == left { p.x = lo.x - rad }
                        else if least == right { p.x = lo.x + cell + rad }
                        else if least == below { p.y = lo.y - rad }
                        else { p.y = lo.y + cell + rad }
                    }
                }
            }
        }
        return p
    }

    /// Keeps runners from standing in one another. Whoever is dashing sends the other one skidding.
    func separate() {
        let need = 2 * Feel.radius
        for _ in 0..<2 {
            for i in runners.indices where runners[i].up {
                for j in runners.indices where j > i && runners[j].up {
                    let d = runners[j].pos - runners[i].pos
                    let dist = d.length
                    guard dist < need else { continue }
                    let n = dist > 1e-6 ? d * (1 / dist) : Vec2(i % 2 == 0 ? 1 : -1, 0)
                    let mi = runners[i].mass, mj = runners[j].mass
                    let overlap = need - dist
                    runners[i].pos = runners[i].pos - n * (overlap * mj / (mi + mj))
                    runners[j].pos += n * (overlap * mi / (mi + mj))
                    if runners[i].dash > 0, runners[j].dash == 0 { shove(j, n) }
                    if runners[j].dash > 0, runners[i].dash == 0 { shove(i, n * -1) }
                }
            }
        }
        for i in runners.indices where runners[i].up { runners[i].pos = pushedOut(runners[i].pos) }
    }

    private func shove(_ i: Int, _ n: Vec2) {
        guard runners[i].stagger == 0 else { return }
        runners[i].vel += n * Feel.shove
        runners[i].stagger = Feel.stagger
        cues.append(.bump(runners[i].pos))
    }

    // MARK: - What the course does to them

    /// Whether there is something to stand on here right now.
    func standable(_ p: Vec2) -> Bool {
        guard let i = course.index(at: p) else { return false }
        switch course.tiles[i] {
        case .wall, .void: return false
        case .crumble: return floor[i] >= 0
        default: return true
        }
    }

    /// Everything that happens to a runner where they have ended up: the floor, the traps, the gold.
    func settle(_ i: Int) {
        guard runners[i].up else { return }
        var r = runners[i]
        let p = r.pos

        if r.dash == 0 {
            if standable(p) {
                r.offFloor = 0
                if let t = course.index(at: p), course.tiles[t] == .crumble, floor[t] == 0 {
                    floor[t] = Int16(Gauntlet.crackTicks)
                    cues.append(.cracked(course.centre(of: t)))
                }
            } else {
                r.offFloor += 1
                if r.offFloor > Feel.coyote {
                    runners[i] = r
                    fall(i, by: nil)
                    return
                }
            }
            for h in hazards.indices where hazards[h].kind == .darts {
                if hazards[h].plates.contains(where: { $0.distance(to: p) < 14 }), hazards[h].plate() { cues.append(.warned(h)) }
            }
        }

        if !r.untouchable {
            for h in hazards.indices {
                if hazards[h].hits(p) {
                    runners[i] = r
                    fall(i, by: h)
                    return
                }
                if r.nearCool == 0, r.speed > 80, hazards[h].grazes(p) {
                    r.nearCool = Feel.ticks(0.75)
                    r.nearMisses += 1
                    r.cooldown = max(0, r.cooldown - Feel.nearRefund)
                    cues.append(.nearMiss(r.id, at: p))
                }
            }
        }

        // Gold on the floor, at the hoard and into the vault.
        if r.carry < Feel.maxCarry {
            for b in bags.indices where bags[b].ttl > 0 && bags[b].age > 20 && bags[b].pos.distance(to: p) < Feel.pickup {
                bags[b].ttl = 0
                r.carry += 1
                cues.append(.pickup(r.id))
                if r.carry == Feel.maxCarry { break }
            }
        }
        let tile = course.tile(at: p)
        if tile == .hoard, hoardOpen {
            if r.carry == 0 {
                r.carry = 1
                r.greed = 0
                cues.append(.pickup(r.id))
            } else if r.carry < Feel.maxCarry {
                r.greed += 1
                if r.greed >= Feel.greed {
                    r.greed = 0
                    r.carry += 1
                    cues.append(.pickup(r.id))
                }
            }
        } else {
            r.greed = 0
        }
        if tile == .vault {
            if r.carry > 0 {
                r.streak += 1
                r.bestStreak = max(r.bestStreak, r.streak)
                let bonus = r.streak >= Feel.streakBonus ? 1 : 0
                let n = r.carry + bonus
                teamTotal += n
                r.banked += n
                r.carry = 0
                r.sinceBank = 0
                lead = p
                cues.append(.banked(r.id, bags: n, bonus: bonus, at: p))
                log(.banked, i, a: n)
            } else if !r.inVault, r.sinceBank > Feel.ticks(2) {
                // Up at the vault with nothing to put in it.
                log(.tell, i, a: SightingKind.emptyHanded.index)
            }
        }
        r.inVault = tile == .vault
        if let b = course.braziers.first(where: { $0.distance(to: p) < 45 }) { r.checkpoint = b }

        // Hanging about the vault door with empty arms.
        if r.carry == 0, r.speed < Feel.slow, r.sinceBank > Feel.ticks(2), course.vaultMouth.distance(to: p) <= Feel.reach {
            r.atDoor += 1
            if r.atDoor == Feel.ticks(0.7) { log(.tell, i, a: SightingKind.emptyHanded.index) }
        } else {
            r.atDoor = 0
        }

        // Standing by a mechanism, and leaving it the moment somebody looks.
        if r.speed < Feel.slow, nearLever(p) {
            r.lurk += 1
        } else {
            if r.lurk >= Feel.ticks(0.5), r.sinceViewer <= Feel.ticks(0.5), r.speed >= Feel.slow { log(.balked, i) }
            r.lurk = 0
        }
        runners[i] = r
    }

    private func nearLever(_ p: Vec2) -> Bool {
        course.mechanisms.contains { $0.kind != .vault && $0.pos.distance(to: p) <= Feel.reach }
    }

    /// Puts a runner down: caught by a trap, or off the edge when `by` is nil.
    func fall(_ i: Int, by h: Int?) {
        var r = runners[i]
        let n = r.carry
        let culprit = h.flatMap { hazards[$0].by } ?? gustBlame(r.pos) ?? darkBlame(r.pos)
        if n > 0 {
            if h == nil {
                // Over the edge, and the gold with them.
                if let c = culprit { blame(c, Double(n)) }
            } else {
                scatter(n, from: r.pos, blame: -1)
                if let c = culprit { blame(c, 0.7 * Double(n)) }
            }
        }
        r.carry = 0
        r.streak = 0
        r.greed = 0
        r.dash = 0
        r.vel = .zero
        r.fell = h == nil
        r.down = Feel.respawn
        r.lurk = 0
        runners[i] = r
        cues.append(.downed(r.id, at: r.pos, fell: r.fell))
        log(.downed, i, a: n, b: h ?? -1)
    }

    private func wake(_ r: inout Runner) {
        // A little apart, so two who went down together do not get up in each other.
        r.pos = pushedOut(r.checkpoint + Vec2(Double(r.id % 3 - 1) * 22, Double(r.id % 2) * 22 - 11))
        r.last = r.pos
        r.blink = Feel.blink
        r.offFloor = 0
        cues.append(.woke(r.id))
    }

    /// Drops bags round a point, wherever there is floor for them.
    func scatter(_ n: Int, from p: Vec2, blame: Int, throwDown: Bool = false) {
        for _ in 0..<n {
            guard let b = bags.firstIndex(where: { $0.ttl == 0 }) else { return }
            var at: Vec2?
            for attempt in 0..<4 {
                let reach = (throwDown ? rng.range(90, Gauntlet.spillThrow) : rng.range(14, Feel.scatter)) / Double(attempt + 1)
                let angle = throwDown ? rng.range(-2.1, -1.04) : rng.range(0, 2 * Double.pi)
                let q = p + Vec2(cos(angle), sin(angle)) * reach
                if standable(q), !course.grid.isSolid(q) { at = q; break }
            }
            if at == nil, standable(p) { at = p }
            // Nowhere for it to land: it is gone.
            guard let spot = at else {
                if blame >= 0 { self.blame(blame, 1) }
                continue
            }
            bags[b] = Bag(pos: spot, ttl: Feel.looseTicks, age: 0, blame: blame)
        }
    }

    /// Loose bags do not lie there for ever, and a floor that has given way takes them with it.
    func ageBags() {
        for b in bags.indices where bags[b].ttl > 0 {
            bags[b].ttl -= 1
            bags[b].age += 1
            if bags[b].ttl == 0 || !standable(bags[b].pos) {
                bags[b].ttl = 0
                if bags[b].blame >= 0 { blame(bags[b].blame, 1) }
            }
        }
    }
}
