import Foundation
import TraitorsCore

/// The Hedge Maze. Sigils and map posts are scattered through it and the bell is in the middle.
/// Whatever anyone walks through goes on the shared map. Statues stand at the ends of dead ends.
public final class MazeCore: ArenaCore {
    struct Find {
        var pos: Vec2
        /// 0 sigil, 1 map post.
        var kind: Int
    }

    struct Statue {
        var pos: Vec2
        var cell: Int
        var searched = false
        var prize: Bool
    }

    /// Maze cells each way. The grid has a hedge between every pair, so it is twice this and one.
    public static let cells = 9
    public static let block = 26.0

    override class var pace: Double { 6 }
    override var swing: Double { 0.7 }

    private(set) var finds: [Find] = []
    private(set) var statues: [Statue] = []
    let bell: Vec2
    /// A find that has faded off the stones for a while, and when it comes back.
    private(set) var faded: [Int: Double] = [:]
    private var got: [PlayerID: Set<Int>] = [:]
    private var rung: Set<PlayerID> = []
    /// The shared map: which maze cells anyone has been through.
    public private(set) var revealed: [Bool]
    private var deadEnds: Set<Int> = []
    private var shifts: [Double] = []

    override init(_ setup: ArenaSetup) {
        let n = Self.cells, side = n * 2 + 1
        bell = Vec2(Double(side) * Self.block / 2, Double(side) * Self.block / 2)
        revealed = Array(repeating: false, count: n * n)
        super.init(setup)
        size = Vec2(Double(side) * Self.block, Double(side) * Self.block)
        vision = 150
        var dice = SeededRNG.derived(setup.seed, 7)
        var g = ArenaGrid(cols: side, rows: side, cell: Self.block)
        for r in 0..<side { for c in 0..<side { g.wall(c, r) } }

        // Carve a maze with one route between any two cells, then knock a few hedges through for loops.
        var seen = Array(repeating: false, count: n * n)
        var stack = [(n / 2, n / 2)]
        seen[(n / 2) * n + n / 2] = true
        g.open(n, n)
        while let (c, r) = stack.last {
            let next = dice.shuffled([(1, 0), (-1, 0), (0, 1), (0, -1)]).first { d in
                let nc = c + d.0, nr = r + d.1
                return nc >= 0 && nr >= 0 && nc < n && nr < n && !seen[nr * n + nc]
            }
            guard let d = next else { stack.removeLast(); continue }
            let nc = c + d.0, nr = r + d.1
            seen[nr * n + nc] = true
            g.open(c * 2 + 1 + d.0, r * 2 + 1 + d.1)
            g.open(nc * 2 + 1, nr * 2 + 1)
            stack.append((nc, nr))
        }
        for _ in 0..<9 {
            let c = 1 + dice.int(n - 1), r = dice.int(n)
            if dice.chance(0.5) { g.open(c * 2, r * 2 + 1) } else { g.open(r * 2 + 1, c * 2) }
        }
        // A little square round the bell.
        for dc in -1...1 { for dr in -1...1 { g.open(n + dc, n + dr) } }
        grid = g
        findDeadEnds()

        let corners = [(0, 0), (n - 1, 0), (0, n - 1), (n - 1, n - 1)]
        var used: Set<Int> = Set(deadEnds)
        used.insert((n / 2) * n + n / 2)
        // One sigil and one post in each quarter of the maze.
        for q in 0..<4 {
            for kind in 0..<2 {
                var cell = 0
                repeat {
                    let c = (q % 2) * (n / 2 + 1) + dice.int(n / 2), r = (q / 2) * (n / 2 + 1) + dice.int(n / 2)
                    cell = r * n + c
                } while used.contains(cell)
                used.insert(cell)
                finds.append(Find(pos: centre(cell), kind: kind))
            }
        }
        for (i, cell) in dice.shuffled(deadEnds.sorted()).prefix(5).enumerated() {
            statues.append(Statue(pos: centre(cell), cell: cell, prize: i % 3 == 2))
        }
        for (i, s) in statues.enumerated() {
            spots.append(Spot(id: i, pos: s.pos, reach: 20, hold: 2.5, offMission: true))
        }
        shifts = [totalTime * dice.range(0.3, 0.38), totalTime * dice.range(0.62, 0.7)]
        // The bell everyone ends at, and the statues at the ends of the dead ends.
        works = [Works(id: 0, pos: bell, reach: 18, text: "THE BELL ROPE SNAPS")]
        for (i, s) in statues.enumerated() { works.append(Works(id: 1 + i, pos: s.pos, reach: 20, text: "A SIGIL FADES")) }
        for (i, a) in actors.enumerated() {
            let corner = corners[i % 4]
            a.pos = centre(corner.1 * n + corner.0) + Vec2(Double(i / 4) * 8 - 4, 0)
            got[a.id] = []
            a.plan = -1
        }
        ready()
    }

    func centre(_ cell: Int) -> Vec2 {
        Vec2((Double(cell % Self.cells) * 2 + 1.5) * Self.block, (Double(cell / Self.cells) * 2 + 1.5) * Self.block)
    }

    func cell(at p: Vec2) -> Int? {
        let c = Int(p.x / Self.block), r = Int(p.y / Self.block)
        guard c % 2 == 1, r % 2 == 1, c / 2 < Self.cells, r / 2 < Self.cells else { return nil }
        return (r / 2) * Self.cells + c / 2
    }

    private func findDeadEnds() {
        guard let g = grid else { return }
        deadEnds = []
        for cell in 0..<Self.cells * Self.cells {
            let c = (cell % Self.cells) * 2 + 1, r = (cell / Self.cells) * 2 + 1
            let ways = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { !g.isSolid(c + $0.0, r + $0.1) }.count
            if ways == 1 { deadEnds.insert(cell) }
        }
    }

    public override var sightRadius: Double? { vision }

    /// How many of a player's nine they have, and whether they can ring the bell yet.
    func found(_ a: ArenaActor) -> Int { got[a.id]?.count ?? 0 }

    /// Counts some finds as already a player's, for a demonstration that starts part of the way in.
    func stage(found these: [Int], for a: ArenaActor) { got[a.id]?.formUnion(these) }

    override func zone(of a: ArenaActor) -> UInt8 {
        if a.pos.distance(to: bell) < 60 { return Zone.task }
        return cell(at: a.pos).map(deadEnds.contains) == true ? Zone.off : Zone.open
    }

    override func idlePoint(for a: ArenaActor) -> Vec2? { deadEnds.isEmpty ? nil : centre(rng.pick(deadEnds.sorted())) }

    override func sprung(_ w: Works) {
        // A find nobody can claim for a while.
        guard w.id != 0, let i = finds.indices.filter({ faded[$0] == nil }).min(by: { finds[$0].pos.distance(to: w.pos) < finds[$1].pos.distance(to: w.pos) }) else { return }
        faded[i] = time + 20
    }

    override func used(_ s: Spot, _ a: ArenaActor) {
        if statues[s.id].prize, !statues[s.id].searched {
            statues[s.id].searched = true
            addBonus(1, at: s.pos, "HIDDEN SIGIL +1")
        }
    }

    /// Moves a few hedges. A hedge only grows where it does not cut anything off.
    private func shift() {
        guard var g = grid else { return }
        let n = Self.cells
        var grown = 0, tries = 0
        while grown < 4, tries < 60 {
            tries += 1
            let c = 1 + rng.int(n - 1), r = rng.int(n)
            let (gc, gr) = rng.chance(0.5) ? (c * 2, r * 2 + 1) : (r * 2 + 1, c * 2)
            guard !g.isSolid(gc, gr), abs(gc - n) > 1 || abs(gr - n) > 1 else { continue }
            guard !actors.contains(where: { g.cellOf($0.pos) == (gc, gr) }) else { continue }
            g.wall(gc, gr)
            // Everything must still be reachable from the bell.
            let cut = (0..<n * n).contains { g.path(from: bell, to: centre($0)).isEmpty && centre($0) != bell }
            if cut { g.open(gc, gr) } else { grown += 1 }
        }
        for _ in 0..<5 {
            let c = 1 + rng.int(n - 1), r = rng.int(n)
            if rng.chance(0.5) { g.open(c * 2, r * 2 + 1) } else { g.open(r * 2 + 1, c * 2) }
        }
        grid = g
        gridVersion += 1
        findDeadEnds()
        for a in actors { a.path = [] }
        cues.append(.banner("THE HEDGES SHIFT"))
        cues.append(.shake)
    }

    override func tick(_ dt: Double) {
        if let at = shifts.first, time >= at {
            shifts.removeFirst()
            shift()
        }
        faded = faded.filter { $0.value > time }
        for a in actors {
            guard a.stun <= 0 else { stand(a); continue }
            if isBot(a) { think(a, dt) } else { slide(a, input.move * 122, dt, radius: 7) }

            if let c = cell(at: a.pos) {
                revealed[c] = true
            }
            // A bot that has done its day's work walks past the rest.
            for (i, f) in finds.enumerated() where got[a.id]?.contains(i) == false && faded[i] == nil && f.pos.distance(to: a.pos) < 15 && (!isBot(a) || wants(a)) {
                got[a.id]?.insert(i)
                addCount(1, for: a, at: f.pos)
                if f.kind == 1 { reveal(around: f.pos, by: a) }
            }
            if !rung.contains(a.id), found(a) >= 4, a.pos.distance(to: bell) < 24, !isBot(a) || wants(a) {
                rung.insert(a.id)
                addCount(1, for: a, at: bell)
                addBonus(1, at: bell, "BELL +1")
            }
        }
    }

    /// A map post fills in its corner of the map for everyone.
    private func reveal(around p: Vec2, by a: ArenaActor) {
        for c in 0..<Self.cells * Self.cells where centre(c).distance(to: p) < Self.block * 5 { revealed[c] = true }
    }

    private func think(_ a: ArenaActor, _ dt: Double) {
        a.wantsInteract = false
        let speed = 118 * (0.82 + 0.2 * a.seat.skill)
        if runHand(a, speed: speed, dt) { return }
        if runHabit(a, speed: speed, dt) { return }
        guard wants(a), !ahead(a) else {
            // Nothing owed: wait by the bell.
            travel(a, to: bell + Vec2(Double(a.id % 3 - 1) * 24, 34), speed: speed * 0.6, dt, within: 8)
            return
        }
        let left = finds.indices.filter { got[a.id]?.contains($0) == false && faded[$0] == nil }
        if found(a) >= 4, !rung.contains(a.id), a.target - count(of: a) == 1 || left.isEmpty {
            travel(a, to: bell, speed: speed, dt, within: 16)
            return
        }
        if a.plan < 0 || a.plan >= finds.count || got[a.id]?.contains(a.plan) == true || faded[a.plan] != nil {
            a.plan = left.min { finds[$0].pos.distance(to: a.pos) < finds[$1].pos.distance(to: a.pos) } ?? -1
        }
        guard a.plan >= 0 else {
            travel(a, to: bell, speed: speed, dt, within: 16)
            return
        }
        travel(a, to: finds[a.plan].pos, speed: speed * (0.8 + 0.2 * drive(a)), dt, within: 6)
    }

    public override func props() -> [Prop] {
        var out = [Prop(id: 200, kind: .bell, pos: bell)]
        let mine = human.flatMap { got[$0.id] } ?? []
        for (i, f) in finds.enumerated() {
            out.append(Prop(id: i, kind: f.kind == 0 ? .sigil : .post, pos: f.pos, state: mine.contains(i) ? 1 : 0, hidden: faded[i] != nil))
        }
        for (i, s) in statues.enumerated() {
            out.append(Prop(id: 100 + i, kind: .statue, pos: s.pos))
        }
        return out
    }
}
