import Foundation
import TraitorsCore

/// Castle Lantern Run. Flame goes from the brazier in the middle to lanterns round the walls,
/// which burn down. What is lit can be seen from a distance; what is not, only from close by.
final class LanternCore: ArenaCore {
    struct Lantern {
        var pos: Vec2
        /// 1 freshly lit, 0 out.
        var burn: Double
        var tower: Bool
    }

    static let cell = 32.0
    static let burnTime = 13.0
    static let dim = 0.3

    override class var pace: Double { 8 }

    private(set) var lanterns: [Lantern] = []
    let brazier: Vec2
    /// Seconds the brazier stays smothered, when no flame can be taken from it.
    private(set) var smothered = 0.0

    override init(_ setup: ArenaSetup) {
        let n = 15
        brazier = Vec2(Double(n) * Self.cell / 2, Double(n) * Self.cell / 2)
        super.init(setup)
        size = Vec2(Double(n) * Self.cell, Double(n) * Self.cell)
        vision = 250
        var g = ArenaGrid(cols: n, rows: n, cell: Self.cell)
        // Four corner towers, each a walled room with its door towards the middle.
        for (cx, cy) in [(0, 0), (n - 4, 0), (0, n - 4), (n - 4, n - 4)] {
            for dx in 0..<4 {
                for dy in 0..<4 where dx == 0 || dy == 0 || dx == 3 || dy == 3 {
                    let inner = (cx == 0 ? dx == 3 : dx == 0) || (cy == 0 ? dy == 3 : dy == 0)
                    if inner { g.wall(cx + dx, cy + dy) }
                }
            }
            let doorX = cx == 0 ? cx + 3 : cx, doorY = cy == 0 ? cy + 1 : cy + 2
            g.open(doorX, doorY)
            lanterns.append(Lantern(pos: g.centre(cx == 0 ? 1 : n - 2, cy == 0 ? 1 : n - 2), burn: 0, tower: true))
        }
        grid = g
        var dice = SeededRNG.derived(setup.seed, 7)
        for (c, r) in [(7, 1), (7, 13), (1, 7), (13, 7), (5, 4), (9, 4), (5, 10), (9, 10)] {
            lanterns.append(Lantern(pos: g.centre(c, r), burn: 0, tower: false))
        }
        for i in lanterns.indices { lanterns[i].burn = dice.chance(0.5) ? dice.range(0.4, 1) : 0 }
        // The brazier everyone comes back to, and the draughty tower rooms.
        works = [Works(id: 0, pos: brazier, reach: 40, text: "THE BRAZIER IS SMOTHERED")]
        for i in 0..<4 { works.append(Works(id: 1 + i, pos: lanterns[i].pos, reach: 30, text: "A COLD DRAUGHT")) }
        for (i, l) in lanterns.enumerated() {
            spots.append(Spot(id: i, pos: l.pos, reach: 30, hold: 3, tag: l.tower ? 1 : 0))
        }
        for (i, a) in actors.enumerated() {
            let angle = Double(i) / Double(actors.count) * 2 * Double.pi
            a.pos = brazier + Vec2(cos(angle), sin(angle)) * 46
        }
        ready()
    }

    override var hidesUnseen: Bool { true }

    /// How much of the castle is dark, 0...1.
    var darkness: Double { 1 - Double(lanterns.filter { $0.burn > 0 }.count) / Double(lanterns.count) }

    private func lit(_ p: Vec2) -> Bool {
        if smothered <= 0, p.distance(to: brazier) < 105 { return true }
        return lanterns.contains { $0.burn > 0 && $0.pos.distance(to: p) < 50 + 45 * $0.burn }
    }

    override func sees(_ w: ArenaActor, _ p: ArenaActor) -> Bool {
        let d = w.pos.distance(to: p.pos)
        guard d <= (lit(p.pos) ? vision : 62) else { return false }
        return grid?.clear(w.pos, p.pos) ?? true
    }

    private func inTower(_ p: Vec2) -> Bool {
        let c = Self.cell * 4
        return (p.x < c || p.x > size.x - c) && (p.y < c || p.y > size.y - c)
    }

    override func zone(of a: ArenaActor) -> UInt8 {
        if a.pos.distance(to: brazier) < 90 { return Zone.task }
        return inTower(a.pos) ? Zone.off : Zone.open
    }

    override func idlePoint(for a: ArenaActor) -> Vec2? { lanterns[rng.int(4)].pos + Vec2(rng.range(-10, 10), rng.range(-10, 10)) }

    override func used(_ s: Spot, _ a: ArenaActor) {
        if lanterns[s.id].burn > 0 {
            lanterns[s.id].burn = min(1, lanterns[s.id].burn + 0.5)
            cues.append(.popup("TRIMMED", s.pos, seat: a.id, bad: false))
        }
    }

    override func canUse(_ s: Spot, _ a: ArenaActor) -> Bool { lanterns[s.id].burn > 0 && lanterns[s.id].burn < 0.8 }

    /// A fire that is already smothered has nothing more to give.
    override func worksUsable(_ w: Works) -> Bool { super.worksUsable(w) && (w.id != 0 || smothered <= 0) }

    override func sprung(_ w: Works) {
        if w.id == 0 {
            smothered = 6
            for a in actors { a.carry = 0 }
        } else {
            for i in 0..<4 { lanterns[i].burn = 0 }
        }
    }

    override func tick(_ dt: Double) {
        smothered = max(0, smothered - dt)
        for i in lanterns.indices { lanterns[i].burn = max(0, lanterns[i].burn - dt / Self.burnTime) }
        for a in actors {
            guard a.stun <= 0 else { stand(a); continue }
            if isBot(a) { think(a, dt) } else { slide(a, input.move * 125, dt) }
            if a.carry == 0, smothered <= 0, a.pos.distance(to: brazier) < 30 {
                a.carry = 1
                cues.append(.burst(a.pos, seat: a.id))
            }
            guard a.carry == 1, a.hold == 0 else { continue }
            for i in lanterns.indices where lanterns[i].burn < Self.dim && lanterns[i].pos.distance(to: a.pos) < 24 {
                // A bot that has done its day's work carries its flame past.
                if isBot(a), !wants(a) { continue }
                lanterns[i].burn = 1
                a.carry = 0
                addCount(1, for: a, at: lanterns[i].pos)
                break
            }
        }
    }

    private func think(_ a: ArenaActor, _ dt: Double) {
        a.wantsInteract = false
        let speed = 118 * (0.8 + 0.2 * a.seat.skill)
        if runHand(a, speed: speed, dt) { return }
        if runHabit(a, speed: speed, dt) { return }
        if !wants(a) || ahead(a) {
            // Nothing owed: wait by the fire.
            travel(a, to: brazier + Vec2(Double(a.id % 3 - 1) * 40, 52), speed: speed * 0.6, dt, within: 12)
            return
        }
        if a.carry == 0 {
            a.plan = -1
            travel(a, to: brazier, speed: speed, dt, within: 26)
            return
        }
        if a.plan < 0 || lanterns[a.plan].burn >= Self.dim {
            // The nearest lantern that wants lighting and nobody else is already heading for.
            let taken = Set(actors.filter { $0 !== a && $0.carry == 1 }.map(\.plan))
            let open = lanterns.indices.filter { lanterns[$0].burn < Self.dim && !taken.contains($0) }
            a.plan = open.min { score(a, $0) < score(a, $1) } ?? -1
        }
        guard a.plan >= 0 else {
            travel(a, to: brazier + Vec2(0, 60), speed: speed * 0.5, dt, within: 14)
            return
        }
        travel(a, to: lanterns[a.plan].pos, speed: speed, dt, within: 18)
    }

    /// Tower lanterns are a long way round, so they are the last anyone thinks of.
    private func score(_ a: ArenaActor, _ i: Int) -> Double {
        lanterns[i].pos.distance(to: a.pos) + (lanterns[i].tower ? 260 : 0)
    }

    override func props() -> [Prop] {
        var out = [Prop(id: 100, kind: .brazier, pos: brazier, state: smothered > 0 ? 0 : 1)]
        for (i, l) in lanterns.enumerated() {
            out.append(Prop(id: i, kind: .lantern, pos: l.pos, state: l.burn > 0 ? 1 : 0, value: l.burn))
        }
        return out
    }
}
