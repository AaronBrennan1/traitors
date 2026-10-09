import Foundation
import TraitorsCore

/// The Shipwreck Dive, seen in cross-section. `y` is height off the seabed: the boat floats at
/// the top, the wreck's rooms are at the bottom, and air only lasts so long in between.
public final class ShipCore: ArenaCore {
    struct Chest {
        var id: Int
        var pos: Vec2
        /// 0 small, 1 big, 2 the valuable one in a marked room.
        var kind: Int
        var home: Vec2
        var carrier: PlayerID?
    }

    struct Eel {
        var pos: Vec2
        var from: Double
        var to: Double
        var dir = 1.0
    }

    static let cell = 26.0
    static let air = 30.0

    override class var pace: Double { 6 }
    override class var handCost: Int { 2 }
    /// The wreck, top row first. `#` is hull, `.` is water.
    static let wreck = [
        "....................",
        ".####.#####.######..",
        ".#....#.....#....#..",
        ".#....#.....#....#..",
        ".#...............#..",
        ".###.####.####.###..",
        ".#.....#.....#...#..",
        ".#.....#.....#...#..",
        ".#...............#..",
        ".#################..",
    ]

    private(set) var chests: [Chest] = []
    private(set) var eels: [Eel] = []
    let boat: Vec2
    public let surface: Double
    /// Seconds of silt left in the water after part of the wreck falls in.
    public private(set) var silt = 0.0
    private var diveStart: [PlayerID: Double] = [:]
    private var rooms: [PlayerID: Int] = [:]
    private var wentIn: Set<PlayerID> = []

    override init(_ setup: ArenaSetup) {
        let rows = 21
        surface = Double(rows) * Self.cell - 30
        boat = Vec2(260, Double(rows) * Self.cell - 18)
        super.init(setup)
        size = Vec2(520, Double(rows) * Self.cell)
        vision = 120
        var g = ArenaGrid(cols: 20, rows: rows, cell: Self.cell)
        for (i, line) in Self.wreck.enumerated() {
            let r = Self.wreck.count - 1 - i
            for (c, ch) in line.enumerated() where ch == "#" { g.wall(c, r) }
        }
        grid = g
        var dice = SeededRNG.derived(setup.seed, 7)
        // Room floors: upper deck three rooms, lower deck three. The cabin is bottom right, the hold bottom left.
        let upper = [(2, 5), (4, 5), (7, 5), (10, 5), (13, 5), (15, 5)], lower = [(4, 1), (6, 1), (8, 1), (11, 1)]
        for (i, cell) in (dice.shuffled(upper).prefix(4) + dice.shuffled(lower).prefix(3)).enumerated() {
            let p = g.centre(cell.0, cell.1)
            chests.append(Chest(id: i, pos: p, kind: 0, home: p))
        }
        let big = g.centre(9, 6)
        chests.append(Chest(id: 7, pos: big, kind: 1, home: big))
        let cabin = g.centre(15, 1), hold = g.centre(2, 2)
        chests.append(Chest(id: 8, pos: cabin, kind: 2, home: cabin))
        // The boat's net, where everything comes up, and the rotten timbers of the hold.
        works = [Works(id: 0, pos: boat, reach: 30, text: "THE NET SLIPS"),
                 Works(id: 1, pos: hold, reach: 34, text: "THE HOLD FALLS IN")]
        dropOff = boat
        for c in chests { spots.append(Spot(id: c.id, pos: c.pos, reach: 26, hold: 1, tag: c.kind)) }
        eels = [Eel(pos: g.centre(4, 5), from: 66, to: 430), Eel(pos: g.centre(12, 12), from: 40, to: 480, dir: -1)]
        for (i, a) in actors.enumerated() {
            a.pos = Vec2(120 + Double(i) * 40, surface + 6)
            a.aux = Self.air
        }
        ready()
    }

    /// 0 open water, 1...3 the upper rooms, 4 the hold, 5 the middle, 6 the captain's cabin.
    private func room(_ p: Vec2) -> Int {
        guard let grid else { return 0 }
        let (c, r) = grid.cellOf(p)
        guard c >= 1, c <= 17, r >= 1, r <= 7 else { return 0 }
        if r >= 5 { return c < 6 ? 1 : (c < 12 ? 2 : 3) }
        if r <= 3 { return c < 7 ? 4 : (c < 13 ? 5 : 6) }
        return 0
    }

    public override var sightRadius: Double? { silt > 0 ? vision * 0.5 : vision }
    override var coverVision: Double { vision }

    override func sees(_ w: ArenaActor, _ p: ArenaActor) -> Bool {
        if silt > 0, w.pos.distance(to: p.pos) > vision * 0.5 { return false }
        return super.sees(w, p)
    }

    override func sprung(_ w: Works) {
        if w.id == 1 { silt = 8 }
    }
    package override func meter(for a: ArenaActor) -> (label: String, value: Double)? { ("AIR", a.aux / Self.air) }

    override func zone(of a: ArenaActor) -> UInt8 {
        if a.pos.y >= surface - 4 { return Zone.task }
        let r = room(a.pos)
        // The far corner of the hold has nothing in it.
        return r == 4 && a.pos.x < 100 ? Zone.off : Zone.open
    }

    override func idlePoint(for a: ArenaActor) -> Vec2? { grid?.centre(2, 1) }

    private func chest(_ id: Int) -> Chest? { chests.first { $0.id == id } }

    override func canUse(_ s: Spot, _ a: ArenaActor) -> Bool {
        guard let c = chest(s.id), c.carrier == nil else { return false }
        return a.carry == 0
    }

    override func used(_ s: Spot, _ a: ArenaActor) {
        guard let i = chests.firstIndex(where: { $0.id == s.id }) else { return }
        chests[i].carrier = a.id
        a.carry = chests[i].kind + 1
    }

    private func lose(_ a: ArenaActor) {
        guard let i = chests.firstIndex(where: { $0.carrier == a.id }) else { return }
        chests[i].carrier = nil
        chests[i].pos = chests[i].home
        a.carry = 0
    }

    private func pace(_ a: ArenaActor) -> Double {
        guard a.carry == 2 else { return a.carry > 0 ? 108 : 126 }
        // A big chest is slow unless somebody swims alongside.
        let helped = actors.contains { $0 !== a && $0.carry == 0 && $0.pos.distance(to: a.pos) < 46 }
        return helped ? 108 : 52
    }

    override func tick(_ dt: Double) {
        silt = max(0, silt - dt)
        for i in eels.indices {
            eels[i].pos.x += eels[i].dir * 46 * dt
            if eels[i].pos.x > eels[i].to { eels[i].dir = -1 }
            if eels[i].pos.x < eels[i].from { eels[i].dir = 1 }
        }
        for a in actors {
            let up = a.pos.y >= surface - 4
            if up {
                diveStart[a.id] = nil
                wentIn.remove(a.id)
                a.aux = min(Self.air, a.aux + dt * 14)
            } else {
                if diveStart[a.id] == nil { diveStart[a.id] = time }
                a.aux -= dt
                if a.aux <= 0 {
                    // Out of air: hauled up spluttering, and whatever was carried goes back down.
                    lose(a)
                    a.pos = Vec2(a.pos.x, surface + 6)
                    a.stun = 2.5
                    a.aux = Self.air * 0.3
                    a.path = []
                    log(.downed, a)
                    cues.append(.popup("OUT OF AIR", a.pos, seat: a.id, bad: true))
                }
            }
            let now = room(a.pos)
            if now != rooms[a.id, default: 0] {
                rooms[a.id] = now
                if now != 0 { wentIn.insert(a.id) }
            }
            guard a.stun <= 0 else { stand(a); continue }
            if isBot(a) { think(a, dt) } else { slide(a, input.move * pace(a), dt) }
            a.pos.y = min(a.pos.y, surface + 8)
            for e in eels where e.pos.distance(to: a.pos) < 15 && a.stun <= 0 {
                a.stun = 1.5
                log(.downed, a)
                cues.append(.popup("EEL!", a.pos, seat: a.id, bad: true))
            }
            if let i = chests.firstIndex(where: { $0.carrier == a.id }) {
                chests[i].pos = a.pos + Vec2(0, -12)
                if a.pos.distance(to: boat) < 44 { raise(i, a) }
            }
        }
    }

    private func raise(_ i: Int, _ a: ArenaActor) {
        let c = chests[i]
        addCount(1, for: a, at: boat)
        if c.kind == 1 {
            if let mate = actors.filter({ $0 !== a && $0.carry == 0 && $0.pos.distance(to: a.pos) < 60 })
                .min(by: { $0.pos.distance(to: a.pos) < $1.pos.distance(to: a.pos) }) {
                addCount(1, for: mate, at: mate.pos)
            }
            addBonus(2, at: boat)
        } else if c.kind == 2 {
            addBonus(1, at: boat)
        }
        a.carry = 0
        chests[i].carrier = nil
        chests[i].pos = c.home
    }

    private func think(_ a: ArenaActor, _ dt: Double) {
        a.wantsInteract = false
        let speed = pace(a) * (0.82 + 0.2 * a.seat.skill)
        let top = Vec2(clamp(a.pos.x, 60, 460), surface + 6)
        // Air comes first: head up while there is still enough to get there.
        let climb = (surface - a.pos.y) / 90 + 4
        if a.pos.y < surface - 4, a.aux < climb || a.plan == 9 {
            a.plan = 9
            travel(a, to: a.carry > 0 ? boat : top, speed: speed, dt, within: 10)
            return
        }
        if a.pos.y >= surface - 4 {
            if a.plan == 9 { a.plan = 0 }
            if a.aux < Self.air * 0.9 {
                // Getting your breath back is done clear of the net, out of the way of whoever is hauling.
                let side = index(of: a) % 2 == 0 ? -1.0 : 1.0
                travel(a, to: Vec2(boat.x + side * (64 + Double(index(of: a)) * 14), surface + 6), speed: 80, dt, within: 6)
                return
            }
        }
        if a.carry > 0 {
            a.plan = 0
            travel(a, to: boat, speed: speed, dt, within: 20)
            return
        }
        if runHand(a, speed: speed, dt) { return }
        if runHabit(a, speed: speed, dt) { return }
        // Swim alongside anyone struggling up with a big chest.
        if wants(a), let heavy = actors.first(where: { $0 !== a && $0.carry == 2 && $0.pos.distance(to: a.pos) < 150 }) {
            travel(a, to: heavy.pos + Vec2(20, 0), speed: 108, dt, within: 12)
            return
        }
        guard wants(a), !ahead(a) else {
            travel(a, to: top, speed: speed, dt, within: 10)
            return
        }
        let taken = Set(actors.filter { $0 !== a && $0.carry == 0 }.map(\.plan))
        let free = chests.filter { $0.carrier == nil && $0.kind != 1 && !taken.contains($0.id + 100) }
        guard let c = free.min(by: { $0.pos.distance(to: a.pos) < $1.pos.distance(to: a.pos) }) else {
            travel(a, to: top, speed: speed, dt, within: 10)
            return
        }
        a.plan = c.id + 100
        if travel(a, to: c.pos, speed: speed, dt, within: 12) { a.wantsInteract = true }
    }

    public override func props() -> [Prop] {
        var out = [Prop(id: 200, kind: .boat, pos: boat)]
        for c in chests {
            out.append(Prop(id: c.id, kind: .chest, pos: c.pos, state: c.kind))
        }
        for (i, e) in eels.enumerated() { out.append(Prop(id: 100 + i, kind: .eel, pos: e.pos, state: e.dir > 0 ? 1 : 0)) }
        return out
    }
}
