import Foundation

/// Market Day Scramble. Nine stalls in a square, six of them selling something for the feast.
/// Buy, carry up to three things, and bring them to the cart. Shoppers get in the way and in the way of being seen.
final class MarketCore: ArenaCore {
    struct Stall {
        /// 0...5 sell something on the list; 6 fish, 7 flowers, 8 books do not.
        var type: Int
        var pos: Vec2
        var stock = 3
        var restock = 0.0
        var onList: Bool { type < 6 }
    }

    struct Shopper {
        var pos: Vec2
        var goal: Vec2
        var path: [Vec2] = []
    }

    static let cell = 30.0
    static let perStall = 2
    static let hands = 3

    private(set) var stalls: [Stall] = []
    private(set) var shoppers: [Shopper] = []
    let cart: Vec2
    /// The stalls whose basket a traitor has a letter for.
    private(set) var marked: [Int] = []
    private var done: Set<Int> = []
    private var bought: [PlayerID: [Int]] = [:]
    private var visits: [PlayerID: (stall: Int, since: Double)] = [:]
    private var hidden: Set<PlayerID> = []

    override init(_ setup: ArenaSetup) {
        var g = ArenaGrid(cols: 15, rows: 17, cell: Self.cell)
        cart = g.centre(7, 1)
        super.init(setup)
        size = Vec2(450, 510)
        vision = 175
        var dice = SeededRNG.derived(setup.seed, 7)
        let types = dice.shuffled(Array(0..<9))
        var n = 0
        for r in [5, 9, 13] {
            for c in [2, 6, 10] {
                g.wall(c, r)
                g.wall(c + 1, r)
                // Customers stand in front of the stall, on the side nearer the cart.
                stalls.append(Stall(type: types[n], pos: Vec2(Double(c + 1) * Self.cell, (Double(r) - 0.45) * Self.cell)))
                n += 1
            }
        }
        grid = g
        marked = Array(dice.shuffled(stalls.indices.filter { !stalls[$0].onList }).prefix(setup.questSteps))
        for (i, s) in stalls.enumerated() {
            spots.append(Spot(id: i, pos: s.pos, reach: 24, hold: s.onList ? 0.7 : 3, tag: s.type, offMission: !s.onList))
        }
        for _ in 0..<14 {
            let p = openPoint(&dice)
            shoppers.append(Shopper(pos: p, goal: openPoint(&dice)))
        }
        for (i, a) in actors.enumerated() {
            a.pos = cart + Vec2(Double(i) * 26 - 91, 32)
            bought[a.id] = Array(repeating: 0, count: stalls.count)
        }
        ready()
    }

    private func openPoint(_ dice: inout SeededRNG) -> Vec2 {
        while true {
            let p = Vec2(dice.range(20, 430), dice.range(70, 490))
            if grid?.isSolid(p) == false { return p }
        }
    }

    /// Whether a stall still has something on this player's list.
    func needs(_ a: ArenaActor, _ stall: Int) -> Bool {
        stalls[stall].onList && (bought[a.id]?[stall] ?? 0) < Self.perStall
    }

    override func sees(_ w: ArenaActor, _ p: ArenaActor) -> Bool {
        // Deep in a crowd, only someone standing right there can pick you out.
        if hidden.contains(p.id), w.pos.distance(to: p.pos) > 50 { return false }
        return super.sees(w, p)
    }

    override func zone(of a: ArenaActor) -> UInt8 {
        if a.pos.distance(to: cart) < 110 { return Zone.task }
        guard let i = stalls.indices.first(where: { stalls[$0].pos.distance(to: a.pos) < 30 }) else { return Zone.open }
        return stalls[i].onList ? Zone.task : Zone.off
    }

    override func idlePoint(for a: ArenaActor) -> Vec2? { rng.pick(stalls.filter { !$0.onList }.map(\.pos)) }
    override func decoy(for a: ArenaActor) -> Spot? { spots.first { $0.offMission && !marked.contains($0.id) } ?? spots.first { $0.offMission } }

    override func canUse(_ s: Spot, _ a: ArenaActor) -> Bool {
        let stall = stalls[s.id]
        if !stall.onList { return true }
        return stall.stock > 0 && needs(a, s.id) && a.carry < Self.hands
    }

    override func used(_ s: Spot, _ a: ArenaActor) {
        if stalls[s.id].onList {
            stalls[s.id].stock -= 1
            bought[a.id]?[s.id] += 1
            a.carry += 1
            log(.itemBought, a, a: stalls[s.id].type)
        } else if isQuester(a), marked.contains(s.id), !done.contains(s.id), questOpen {
            done.insert(s.id)
            questStep(a, seen: a.holdSeen)
        } else if rng.chance(0.15) {
            addBonus(1, at: s.pos, "BARGAIN +1")
        }
    }

    override func tick(_ dt: Double) {
        for i in stalls.indices where stalls[i].stock < 3 {
            stalls[i].restock += dt
            if stalls[i].restock >= 6 {
                stalls[i].restock = 0
                stalls[i].stock += 1
            }
        }
        for i in shoppers.indices {
            if shoppers[i].path.isEmpty {
                shoppers[i].goal = openPoint(&rng)
                shoppers[i].path = grid?.path(from: shoppers[i].pos, to: shoppers[i].goal) ?? []
            }
            guard let next = shoppers[i].path.first else { continue }
            let d = shoppers[i].pos.distance(to: next)
            if d < 3 { shoppers[i].path.removeFirst() } else { shoppers[i].pos += (next - shoppers[i].pos) * (min(d, 34 * dt) / d) }
        }
        veils = shoppers.map { ($0.pos, 13) }

        for a in actors {
            let crowd = shoppers.filter { $0.pos.distance(to: a.pos) < 40 }.count >= 3
            if crowd != hidden.contains(a.id) {
                if crowd { hidden.insert(a.id) } else { hidden.remove(a.id) }
                log(.crowdCover, a, a: crowd ? 1 : 0)
            }
            // Who stood at which stall, and for how long.
            let at = stalls.indices.first { stalls[$0].pos.distance(to: a.pos) < 30 }
            if at != visits[a.id]?.stall {
                if let v = visits[a.id] { log(.stallVisited, a, a: stalls[v.stall].type, b: Int((time - v.since) * 10)) }
                visits[a.id] = at.map { ($0, time) }
            }
            guard a.stun <= 0 else { stand(a); continue }
            if isBot(a) { think(a, dt) } else { slide(a, input.move * 122, dt) }
            if a.carry > 0, a.pos.distance(to: cart) < 36 {
                addCount(a.carry, for: a, at: cart)
                a.carry = 0
            }
        }
    }

    override func safeNow(_ a: ArenaActor) -> Bool { hidden.contains(a.id) || super.safeNow(a) }

    private func think(_ a: ArenaActor, _ dt: Double) {
        a.wantsInteract = false
        let speed = 116 * (0.8 + 0.22 * a.seat.skill)
        if let m = marked.first(where: { !done.contains($0) }), runQuest(a, at: spots[m], speed: speed, dt) { return }
        if runErrand(a, speed: speed, dt) { return }
        let owed = a.seat.target - count(of: a) - a.carry
        let open = stalls.indices.filter { needs(a, $0) && stalls[$0].stock > 0 }
        if a.carry >= Self.hands || (a.carry > 0 && (owed <= 0 || open.isEmpty)) {
            travel(a, to: cart, speed: speed, dt, within: 24)
            return
        }
        guard owed > 0, !ahead(a), let stall = open.min(by: { stalls[$0].pos.distance(to: a.pos) < stalls[$1].pos.distance(to: a.pos) }) else {
            travel(a, to: cart + Vec2(Double(a.id) * 24 - 84, 36), speed: speed * 0.6, dt, within: 10)
            return
        }
        if travel(a, to: stalls[stall].pos, speed: speed * (0.75 + 0.25 * drive(a)), dt, within: 10) { a.wantsInteract = true }
    }

    override func props() -> [Prop] {
        var out = [Prop(id: 200, kind: .cart, pos: cart)]
        for (i, s) in stalls.enumerated() {
            let mine = human.map { needs($0, i) && s.stock > 0 } ?? false
            out.append(Prop(id: i, kind: .stall, pos: s.pos + Vec2(0, 0.95 * Self.cell), state: s.type, value: Double(s.stock) / 3,
                            tint: mine ? (human?.id ?? -1) : -1, secret: marked.contains(i) && !done.contains(i)))
        }
        for (i, s) in shoppers.enumerated() { out.append(Prop(id: 100 + i, kind: .shopper, pos: s.pos, state: i % 4)) }
        return out
    }
}
