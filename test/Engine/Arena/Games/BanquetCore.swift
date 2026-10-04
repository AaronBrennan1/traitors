import Foundation

/// The Banquet Prep. Orders move through the kitchen one job at a time: fetch, chop, into a
/// pot, off the heat, plate, serve. Every job done is one for whoever did it.
final class BanquetCore: ArenaCore {
    enum Job: Int { case fetch, chop, plate, serve }

    struct Station {
        var job: Job
        var pos: Vec2
        var stand: Vec2
    }

    struct Pot {
        var pos: Vec2
        var stand: Vec2
        /// 0 empty, 1 cooking, 2 ready to come off, 3 burnt.
        var state = 0
        var timer = 0.0
        /// Wants a pinch of herb while it cooks.
        var seasoning = false
        var headTable = false
        var herbed = false
    }

    static let cell = 32.0
    static let herb = 1

    private(set) var stations: [Station] = []
    private(set) var pots: [Pot] = []
    /// Jobs waiting at each kind of station, and chopped food waiting for a pot.
    private(set) var waiting: [Job: Int] = [.fetch: 3, .chop: 0, .plate: 0, .serve: 0]
    private(set) var chopped = 0
    let shelf: Vec2
    private var orders = 0
    /// When the head table's order goes in. One per piece of the side quest.
    private var headTimes: [Double] = []
    private var headDue = false
    private var claims: [PlayerID: Int] = [:]

    override init(_ setup: ArenaSetup) {
        var g = ArenaGrid(cols: 11, rows: 13, cell: Self.cell)
        shelf = g.centre(1, 11)
        super.init(setup)
        size = Vec2(11 * Self.cell, 13 * Self.cell)
        vision = 105
        // The pantry is a walled room along the top with its door in the middle.
        for c in 0..<5 where c != 2 { g.wall(c, 9) }
        for r in 9..<13 { g.wall(5, r) }
        g.open(5, 10)
        func counter(_ c: Int, _ r: Int, _ standC: Int, _ standR: Int) -> (Vec2, Vec2) {
            g.wall(c, r, opaque: false)
            return (g.centre(c, r), g.centre(standC, standR))
        }
        var s = counter(1, 12, 1, 10); stations.append(Station(job: .fetch, pos: s.0, stand: s.1))
        s = counter(3, 12, 3, 10); stations.append(Station(job: .fetch, pos: s.0, stand: s.1))
        s = counter(8, 12, 8, 11); stations.append(Station(job: .chop, pos: s.0, stand: s.1))
        s = counter(10, 9, 9, 9); stations.append(Station(job: .chop, pos: s.0, stand: s.1))
        s = counter(0, 5, 1, 5); stations.append(Station(job: .plate, pos: s.0, stand: s.1))
        s = counter(0, 2, 1, 2); stations.append(Station(job: .plate, pos: s.0, stand: s.1))
        s = counter(5, 0, 5, 1); stations.append(Station(job: .serve, pos: s.0, stand: s.1))
        for (c, r) in [(4, 6), (6, 6), (5, 4)] {
            g.wall(c, r, opaque: false)
            pots.append(Pot(pos: g.centre(c, r), stand: g.centre(c, r) + Vec2(c == 4 ? -Self.cell : (c == 6 ? Self.cell : 0), c == 5 ? -Self.cell : 0)))
        }
        g.wall(0, 12, opaque: false)
        grid = g
        for (i, st) in stations.enumerated() { spots.append(Spot(id: i, pos: st.stand, reach: 20, hold: 1.1, tag: st.job.rawValue)) }
        for (i, p) in pots.enumerated() { spots.append(Spot(id: 20 + i, pos: p.stand, reach: 20, hold: 1.1, tag: 10)) }
        spots.append(Spot(id: 30, pos: shelf, reach: 22, hold: 2, tag: 11))
        var dice = SeededRNG.derived(setup.seed, 7)
        headTimes = (0..<setup.questSteps).map { totalTime * (0.3 + 0.3 * Double($0)) + dice.range(-4, 4) }
        for (i, a) in actors.enumerated() {
            a.pos = g.centre(2 + i % 4 * 2, 7 + i / 4)
        }
        ready()
        // Nobody on the side quest sets off before there is nearly a pot to put the herb in.
        for a in actors { a.questStart = headTimes[0] - 7 }
    }

    private var seasoningAsked: Bool { pots.contains { $0.state == 1 && $0.seasoning && !$0.herbed } }
    var headPot: Int? { pots.firstIndex { $0.headTable && $0.state == 1 && !$0.herbed } }

    override func zone(of a: ArenaActor) -> UInt8 {
        // The kitchen floor is all work. The pantry is for fetching, and the back of it for nothing much.
        if a.pos.y < 9 * Self.cell || a.pos.x > 5 * Self.cell { return Zone.task }
        return a.pos.x < 2.5 * Self.cell && a.pos.y > 10.5 * Self.cell ? Zone.off : Zone.open
    }

    /// A kitchen in full flow is its own cover: nobody is watching anybody's hands.
    override func safeNow(_ a: ArenaActor) -> Bool { true }

    override func idlePoint(for a: ArenaActor) -> Vec2? { shelf + Vec2(Self.cell * rng.range(0.6, 2.5), 4) }
    override func decoy(for a: ArenaActor) -> Spot? { spots.first { $0.id == 30 } }

    override func canUse(_ s: Spot, _ a: ArenaActor) -> Bool {
        if s.id == 30 { return a.carry == 0 }
        if s.id >= 20 {
            let p = pots[s.id - 20]
            if a.carry == Self.herb {
                return p.state == 1 && !p.herbed && (p.seasoning || (p.headTable && isQuester(a) && questOpen))
            }
            return (p.state == 0 && chopped > 0) || p.state >= 2
        }
        return a.carry == 0 && (waiting[stations[s.id].job] ?? 0) > 0
    }

    override func holdTime(_ s: Spot, _ a: ArenaActor) -> Double {
        s.id >= 20 && a.carry == Self.herb ? 2 : s.hold
    }

    override func used(_ s: Spot, _ a: ArenaActor) {
        if s.id == 30 {
            a.carry = Self.herb
            log(.ingredientTaken, a, a: Self.herb, seen: a.holdSeen)
            // Nothing on the stove is asking for it.
            if !pots.contains(where: { $0.state == 1 && $0.seasoning }) { log(.tell, a, a: SightingKind.offTask.index, seen: a.holdSeen) }
            return
        }
        if s.id >= 20 {
            let i = s.id - 20
            log(.potInteraction, a, a: i, b: a.carry, seen: a.holdSeen)
            if a.carry == Self.herb {
                a.carry = 0
                pots[i].herbed = true
                if pots[i].headTable, !pots[i].seasoning { questStep(a, seen: a.holdSeen) } else { addCount(1, for: a, at: pots[i].pos) }
            } else if pots[i].state == 0 {
                chopped -= 1
                orders += 1
                pots[i] = Pot(pos: pots[i].pos, stand: pots[i].stand, state: 1, timer: 5, seasoning: orders % 3 == 0)
                if headDue {
                    // The head table's stew cooks slowly, and everyone can see which pot it is.
                    headDue = false
                    pots[i].headTable = true
                    pots[i].seasoning = false
                    pots[i].timer = 18
                    cues.append(.banner("HEAD TABLE'S ORDER IS ON"))
                }
                addCount(1, for: a, at: pots[i].pos)
            } else {
                let burnt = pots[i].state == 3
                pots[i] = Pot(pos: pots[i].pos, stand: pots[i].stand)
                if !burnt {
                    waiting[.plate, default: 0] += 1
                    addCount(1, for: a, at: pots[i].pos)
                }
            }
            return
        }
        let job = stations[s.id].job
        waiting[job, default: 0] -= 1
        log(.stationClaimed, a, a: job.rawValue)
        addCount(1, for: a, at: stations[s.id].pos)
        switch job {
        case .fetch: waiting[.chop, default: 0] += 1
        case .chop: chopped += 1
        case .plate: waiting[.serve, default: 0] += 1
        case .serve:
            log(.orderServed, a)
            addBonus(2, at: stations[s.id].pos, "SERVED +2")
        }
    }

    override func tick(_ dt: Double) {
        // There is always more to fetch.
        if (waiting[.fetch] ?? 0) < 3 { waiting[.fetch, default: 0] += 1 }
        if let at = headTimes.first, time >= at {
            headTimes.removeFirst()
            headDue = true
        }
        for i in pots.indices where pots[i].state == 1 || pots[i].state == 2 {
            pots[i].timer -= dt
            guard pots[i].timer <= 0 else { continue }
            if pots[i].state == 1 {
                pots[i].state = 2
                pots[i].timer = 9
            } else {
                pots[i].state = 3
                addBonus(-1, at: pots[i].pos, "BURNT")
            }
        }
        for a in actors {
            guard a.stun <= 0 else { stand(a); continue }
            if isBot(a) { think(a, dt) } else { slide(a, input.move * 120, dt) }
        }
    }

    private func think(_ a: ArenaActor, _ dt: Double) {
        a.wantsInteract = false
        let speed = 114 * (0.8 + 0.22 * a.seat.skill)
        if questDue(a), headPot != nil || headDue || !headTimes.isEmpty {
            // Shelf first, so the herb is in hand when the head table's pot goes on.
            if a.carry != Self.herb {
                noteTry(a)
                if travel(a, to: shelf, speed: speed, dt, within: 12) { a.wantsInteract = true }
                return
            }
            if let head = headPot {
                if runQuest(a, at: spots.first { $0.id == 20 + head }!, speed: speed, dt) { return }
            } else if time >= (headTimes.first ?? 0) - 6 {
                // Hover by the stove until it does.
                travel(a, to: Vec2(5 * Self.cell, 7.5 * Self.cell), speed: speed, dt, within: 12)
                return
            }
        }
        if runErrand(a, speed: speed, dt) { return }
        if a.carry == Self.herb {
            // A herb in hand goes in whichever pot asks for it, or back on the shelf's account.
            guard let i = pots.firstIndex(where: { $0.state == 1 && $0.seasoning && !$0.herbed }) else {
                if !(isQuester(a) && questOpen) { a.carry = 0 }
                stand(a)
                return
            }
            if travel(a, to: pots[i].stand, speed: speed, dt, within: 10) { a.wantsInteract = true }
            return
        }
        guard wants(a), !ahead(a) else {
            claims[a.id] = nil
            travel(a, to: Vec2((3 + Double(a.id % 4) * 1.4) * Self.cell, 8 * Self.cell), speed: speed * 0.5, dt, within: 14)
            return
        }
        // Keep to a job once chosen, as long as it is still there to do.
        if let c = claims[a.id], let s = spots.first(where: { $0.id == c }), canUse(s, a) || a.holdSpot == c {
            if travel(a, to: s.pos, speed: speed * (0.8 + 0.2 * drive(a)), dt, within: 10) { a.wantsInteract = true }
            return
        }
        let taken = Set(claims.filter { $0.key != a.id }.values)
        var open = spots.filter { $0.id != 30 && canUse($0, a) && !taken.contains($0.id) }
        if seasoningAsked, !taken.contains(30) { open.append(spots.first { $0.id == 30 }!) }
        claims[a.id] = open.min { $0.pos.distance(to: a.pos) < $1.pos.distance(to: a.pos) }?.id
        if claims[a.id] == nil { stand(a) }
    }

    override func props() -> [Prop] {
        var out: [Prop] = []
        for (i, s) in stations.enumerated() {
            out.append(Prop(id: i, kind: .station, pos: s.pos, state: s.job.rawValue, value: (waiting[s.job] ?? 0) > 0 ? 1 : 0))
        }
        for (i, p) in pots.enumerated() {
            let glow = (p.state == 0 && chopped > 0) || p.state >= 2 || (p.state == 1 && p.seasoning && !p.herbed)
            out.append(Prop(id: 20 + i, kind: .pot, pos: p.pos, state: p.state + (p.headTable ? 10 : 0) + (p.seasoning && !p.herbed ? 100 : 0),
                            value: glow ? 1 : 0, secret: p.headTable && p.state == 1 && !p.herbed))
        }
        out.append(Prop(id: 30, kind: .herbShelf, pos: shelf + Vec2(-Self.cell, Self.cell)))
        return out
    }
}
