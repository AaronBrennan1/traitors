import Foundation

/// Sheep Round-Up. Sheep run from whoever is near, so they are walked into pens from behind.
/// Each wears a ribbon in the colour of the pen it belongs in.
final class SheepCore: ArenaCore {
    struct Sheep {
        var id: Int
        var pos: Vec2
        var vel = Vec2.zero
        var colour: Int
        var blackFace: Bool
        /// Whoever last had it moving.
        var herder: PlayerID?
        /// How long that player has been at it.
        var herded = 0.0
        var drift = Vec2.zero
    }

    struct Pen {
        var centre: Vec2
        var half: Vec2
        func holds(_ p: Vec2) -> Bool { abs(p.x - centre.x) < half.x && abs(p.y - centre.y) < half.y }
    }

    private(set) var sheep: [Sheep] = []
    let pens: [Pen]
    private(set) var dog = Vec2(220, 300)
    private var dogGoal: Vec2?
    private(set) var dogBy: PlayerID?
    /// The black-faced sheep a traitor has to put in the wrong pen.
    private(set) var marked: [Int] = []
    private var nextID = 0
    private var wasPressing = false
    private var claims: [PlayerID: Int] = [:]
    private var gustClock = 0.0

    override init(_ setup: ArenaSetup) {
        pens = [Pen(centre: Vec2(34, 250), half: Vec2(34, 46)), Pen(centre: Vec2(406, 250), half: Vec2(34, 46)),
                Pen(centre: Vec2(220, 34), half: Vec2(50, 34))]
        super.init(setup)
        size = Vec2(440, 520)
        vision = 190
        ledger.spread = 300
        for _ in 0..<26 { spawn(anywhere: true) }
        var dice = SeededRNG.derived(setup.seed, 7)
        let faces = sheep.filter(\.blackFace).map(\.id)
        marked = Array(dice.shuffled(faces).prefix(setup.questSteps))
        let first = totalTime * dice.range(0.25, 0.4), second = totalTime * dice.range(0.6, 0.75)
        cover = [CoverWindow(start: first, end: first + 5, kind: .chaos), CoverWindow(start: second, end: second + 5, kind: .chaos)]
        for (i, a) in actors.enumerated() { a.pos = Vec2(90 + Double(i) * 37, 130 + Double(i % 2) * 30) }
        ready()
    }

    override var coverVision: Double { 95 }
    override var sightRadius: Double? { coverActive ? coverVision : nil }
    override func canInteract(_ a: ArenaActor) -> Bool { true }

    private func spawn(anywhere: Bool) {
        let pos = anywhere ? Vec2(rng.range(90, 350), rng.range(150, 480)) : Vec2(rng.range(60, 380), rng.range(470, 505))
        sheep.append(Sheep(id: nextID, pos: pos, colour: rng.int(3), blackFace: nextID % 5 == 2))
        nextID += 1
    }

    override func idlePoint(for a: ArenaActor) -> Vec2? { Vec2(rng.chance(0.5) ? 30 : 410, rng.range(470, 505)) }
    override func farPoint(for a: ArenaActor) -> Vec2? { Vec2(rng.chance(0.5) ? 24 : 416, 500) }
    override func zone(of a: ArenaActor) -> UInt8 {
        if a.pos.y > 455, a.pos.x < 60 || a.pos.x > 380 { return Zone.off }
        // The bottom of the field is where people stand back out of the flock's way.
        return a.pos.y > 410 ? Zone.task : Zone.open
    }

    private func whistle(_ a: ArenaActor) {
        let heading = a.vel.length > 5 ? a.vel.unit : Vec2(0, -1)
        dogGoal = a.pos + heading * 130
        dogBy = a.id
        log(.dogCommand, a, a: Int(heading.x * 100), b: Int(heading.y * 100))
    }

    override func tick(_ dt: Double) {
        // A gust throws the whole flock about.
        if coverActive {
            gustClock -= dt
            if gustClock <= 0 {
                gustClock = 0.6
                log(.gust, nil)
                for i in sheep.indices { sheep[i].vel += Vec2(rng.range(-90, 90), rng.range(-90, 90)) }
            }
        }
        if let g = dogGoal {
            let d = dog.distance(to: g)
            if d < 6 { dogGoal = nil } else { dog += (g - dog) * (min(d, 190 * dt) / d) }
        }
        for a in actors {
            guard a.stun <= 0 else { stand(a); continue }
            if isBot(a) { think(a, dt) } else { slide(a, input.move * 118, dt) }
        }
        if let me = human {
            if input.interact, !wasPressing { whistle(me) }
            wasPressing = input.interact
        }
        flock(dt)
    }

    private func flock(_ dt: Double) {
        var penned: [(Int, Int)] = []
        for i in sheep.indices {
            var push = Vec2.zero
            if let near = actors.min(by: { $0.pos.distance(to: sheep[i].pos) < $1.pos.distance(to: sheep[i].pos) }),
               near.pos.distance(to: sheep[i].pos) < 74 {
                sheep[i].herded = sheep[i].herder == near.id ? sheep[i].herded + dt : 0
                sheep[i].herder = near.id
            }
            for a in actors {
                let away = sheep[i].pos - a.pos
                let d = away.length
                if d < 74, d > 0.1 { push += away.unit * ((74 - d) * 3.2) }
            }
            // Left to itself a sheep shies away from a gate. It only goes in with somebody behind it.
            for pen in pens {
                let away = sheep[i].pos - pen.centre
                if away.length < 95, away.length > 0.1 { push += away.unit * ((95 - away.length) * 1.5) }
            }
            let fromDog = sheep[i].pos - dog
            if fromDog.length < 90, fromDog.length > 0.1 { push += fromDog.unit * ((90 - fromDog.length) * 3.5) }
            for j in sheep.indices where j != i {
                let apart = sheep[i].pos - sheep[j].pos
                let d = apart.length
                if d < 20, d > 0.1 { push += apart.unit * ((20 - d) * 5) } else if d < 70 { push += apart.unit * -0.5 }
            }
            if rng.chance(0.02) { sheep[i].drift = Vec2(rng.range(-12, 12), rng.range(-12, 12)) }
            let want = (push + sheep[i].drift).capped(78)
            sheep[i].vel = (sheep[i].vel * 0.86 + want * 0.14).capped(110)
            var p = sheep[i].pos + sheep[i].vel * dt
            p = Vec2(clamp(p.x, 8, size.x - 8), clamp(p.y, 8, size.y - 8))
            sheep[i].pos = p
            if let pen = pens.firstIndex(where: { $0.holds(p) }) { penned.append((i, pen)) }
        }
        for (i, pen) in penned.reversed() {
            let s = sheep.remove(at: i)
            let herder = s.herder.flatMap(actor)
            log(.sheepPenned, herder, a: s.id, b: pen)
            claims = claims.filter { $0.value != s.id }
            if s.colour == pen {
                if let herder { addCount(1, for: herder, at: s.pos) }
            } else {
                addBonus(-1, at: s.pos, "WRONG PEN")
                let focus = sheep.min { a, b in
                    guard let herder else { return false }
                    return a.pos.distance(to: herder.pos) < b.pos.distance(to: herder.pos)
                }
                // It only reads as deliberate if this was the sheep they were working.
                if let herder, s.herded > 3, focus == nil || focus!.pos.distance(to: herder.pos) > s.pos.distance(to: herder.pos) {
                    // Standing at the wrong gate as a sheep goes in is something people remember.
                    tell(.offTask, herder)
                    if marked.contains(s.id) { questStep(herder) }
                }
            }
            spawn(anywhere: false)
            // The mark moves on if its sheep went home after all.
            if let at = marked.firstIndex(of: s.id), questOpen {
                marked.remove(at: at)
                if let other = sheep.first(where: { $0.blackFace && !marked.contains($0.id) }) { marked.append(other.id) }
            }
        }
    }

    /// Where to stand to walk a sheep towards a pen: just behind it.
    private func behind(_ s: Sheep, pen: Int) -> Vec2 {
        s.pos + (s.pos - pens[pen].centre).unit * 30
    }

    private func think(_ a: ArenaActor, _ dt: Double) {
        let speed = 112 * (0.8 + 0.25 * a.seat.skill)
        if questDue(a), let s = sheep.first(where: { marked.contains($0.id) }) {
            noteTry(a)
            // Any pen but its own, whichever is nearest.
            let wrong = pens.indices.filter { $0 != s.colour }.min { pens[$0].centre.distance(to: s.pos) < pens[$1].centre.distance(to: s.pos) }!
            travel(a, to: behind(s, pen: wrong), speed: speed, dt, within: 5)
            return
        }
        if runErrand(a, speed: speed, dt) { return }
        guard wants(a), !ahead(a) else {
            // Hang back out of the flock's way.
            claims[a.id] = nil
            travel(a, to: Vec2(120 + Double(a.id) * 28, 440), speed: speed * 0.5, dt, within: 20)
            return
        }
        var mine = claims[a.id].flatMap { id in sheep.first { $0.id == id } }
        if mine == nil {
            let taken = Set(claims.values)
            mine = sheep.filter { !taken.contains($0.id) && !(marked.contains($0.id) && isQuester(a)) }
                .min { $0.pos.distance(to: a.pos) + $0.pos.distance(to: pens[$0.colour].centre) * 0.6
                    < $1.pos.distance(to: a.pos) + $1.pos.distance(to: pens[$1.colour].centre) * 0.6 }
            claims[a.id] = mine?.id
            // A sharp bot sends the dog to bring the far ones in.
            if let s = mine, s.pos.distance(to: a.pos) > 200, dogGoal == nil, rng.chance(0.3 * a.seat.skill) {
                dogGoal = behind(s, pen: s.colour)
                dogBy = a.id
                log(.dogCommand, a)
            }
        }
        guard let s = mine else { stand(a); return }
        travel(a, to: behind(s, pen: s.colour), speed: speed * (0.75 + 0.25 * drive(a)), dt, within: 5)
    }

    override func props() -> [Prop] {
        var out: [Prop] = []
        for (i, p) in pens.enumerated() { out.append(Prop(id: 200 + i, kind: .pen, pos: p.centre, state: i)) }
        for s in sheep {
            out.append(Prop(id: s.id, kind: .sheep, pos: s.pos, state: s.colour, value: s.blackFace ? 1 : 0, secret: marked.contains(s.id)))
        }
        out.append(Prop(id: 300, kind: .dog, pos: dog, tint: dogBy ?? -1))
        return out
    }
}
