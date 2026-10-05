import Foundation

struct Vec2: Codable, Equatable {
    var x = 0.0
    var y = 0.0

    static let zero = Vec2()

    init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }

    var length: Double { (x * x + y * y).squareRoot() }
    var unit: Vec2 { let l = length; return l > 1e-9 ? self * (1 / l) : .zero }
    func distance(to o: Vec2) -> Double { (self - o).length }
    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    func capped(_ most: Double) -> Vec2 { let l = length; return l > most ? self * (most / l) : self }
}

/// One player as the mini-game needs to know them.
struct ArenaSeat {
    let id: PlayerID
    let skill: Double
    let perception: Double
    let deceit: Double
    let isHuman: Bool
}

/// Everything a run of the gauntlet is dealt before it starts.
struct ArenaSetup {
    let kind: MissionKind
    let day: Int
    let seed: UInt64
    let quirkSeed: UInt64
    /// Everyone playing, in seat order.
    let cast: [ArenaSeat]
    /// Who has the shadow's hand today: the bot who means to use it, and a human traitor.
    let saboteurs: [PlayerID]
    /// How good a day the bots are having, as one roll for all of them. 0 is an ordinary day.
    let form: Double
    /// A bot plays the human's seat, for tests and unattended runs.
    var autopilot: Bool

    init(kind: MissionKind, day: Int, seed: UInt64, quirkSeed: UInt64, cast: [ArenaSeat], saboteurs: [PlayerID],
         form: Double = 0, autopilot: Bool = true) {
        self.kind = kind
        self.day = day
        self.seed = seed
        self.quirkSeed = quirkSeed
        self.cast = cast
        self.saboteurs = saboteurs
        self.form = form
        self.autopilot = autopilot
    }

    /// The day's mission as the engine planned it.
    init(run: MissionRun, autopilot: Bool) {
        var saboteurs: [PlayerID] = []
        if let r = run.runner, r != run.human, run.runnerAttempt { saboteurs.append(r) }
        if let h = run.human, run.traitors.contains(h) { saboteurs.append(h) }
        let cast = run.order.sorted().map { p in
            ArenaSeat(id: p, skill: run.skill[p], perception: run.perception[p], deceit: run.deceit[p], isHuman: p == run.human)
        }
        self.init(kind: run.kind, day: run.day, seed: run.layoutSeed, quirkSeed: run.quirkSeed, cast: cast,
                  saboteurs: saboteurs, form: run.form, autopilot: autopilot)
    }
}

/// What the human is doing with their thumb this frame. A press of Dash goes through
/// `ArenaRunner.press()`, which holds on to it until a step can take it.
struct ArenaInput {
    /// The stick, length 0...1, in the course's own axes.
    var move = Vec2.zero
}

/// Things for the screen and the speaker to do that do not change the game.
enum ArenaCue {
    case pickup(PlayerID)
    case banked(PlayerID, bags: Int, bonus: Int, at: Vec2)
    case downed(PlayerID, at: Vec2, fell: Bool)
    case woke(PlayerID)
    case dash(PlayerID)
    case bump(Vec2)
    case nearMiss(PlayerID, at: Vec2)
    /// A trap, by its place in the course's list, has begun to warn or has gone off.
    case warned(Int)
    case fired(Int)
    case cracked(Vec2)
    case gave(Vec2)
    case lights(band: Int, out: Bool)
    case spilled(Vec2, bags: Int)
    case act(Int)
    case sealing, unsealed, sealed, overtime
    /// The shadow's hand was used. Only that player's own screen may show it.
    case hand(PlayerID)
}

/// A square grid of walls. It blocks feet, sight or both.
struct ArenaGrid {
    let cols: Int
    let rows: Int
    let cell: Double
    var solid: [Bool]
    var opaque: [Bool]

    init(cols: Int, rows: Int, cell: Double) {
        self.cols = cols
        self.rows = rows
        self.cell = cell
        solid = Array(repeating: false, count: cols * rows)
        opaque = solid
    }

    func inside(_ c: Int, _ r: Int) -> Bool { c >= 0 && r >= 0 && c < cols && r < rows }
    func index(_ c: Int, _ r: Int) -> Int { r * cols + c }
    func cellOf(_ p: Vec2) -> (c: Int, r: Int) { (Int((p.x / cell).rounded(.down)), Int((p.y / cell).rounded(.down))) }
    func centre(_ c: Int, _ r: Int) -> Vec2 { Vec2((Double(c) + 0.5) * cell, (Double(r) + 0.5) * cell) }

    mutating func wall(_ c: Int, _ r: Int, opaque see: Bool = true) {
        guard inside(c, r) else { return }
        solid[index(c, r)] = true
        opaque[index(c, r)] = see
    }

    mutating func open(_ c: Int, _ r: Int) {
        guard inside(c, r) else { return }
        solid[index(c, r)] = false
        opaque[index(c, r)] = false
    }

    func isSolid(_ p: Vec2) -> Bool {
        let (c, r) = cellOf(p)
        return !inside(c, r) || solid[index(c, r)]
    }

    func isSolid(_ c: Int, _ r: Int) -> Bool { !inside(c, r) || solid[index(c, r)] }

    /// True when nothing stands between two points.
    func clear(_ a: Vec2, _ b: Vec2) -> Bool {
        let d = a.distance(to: b)
        let steps = max(1, Int(d / (cell * 0.4)))
        for i in 1..<max(steps, 2) {
            let p = a + (b - a) * (Double(i) / Double(steps))
            let (c, r) = cellOf(p)
            if inside(c, r), opaque[index(c, r)] { return false }
        }
        return true
    }

    /// True when there is nothing to walk into between two points.
    func walkable(_ a: Vec2, _ b: Vec2) -> Bool {
        let steps = max(2, Int(a.distance(to: b) / (cell * 0.3)))
        for i in 0...steps where isSolid(a + (b - a) * (Double(i) / Double(steps))) { return false }
        return true
    }

    /// The nearest cell to a point that can be stood in.
    func nearestOpen(_ p: Vec2) -> (c: Int, r: Int) {
        let (c0, r0) = cellOf(p)
        if inside(c0, r0), !solid[index(c0, r0)] { return (c0, r0) }
        var best = (c: 0, r: 0), bestD = Double.infinity
        for r in 0..<rows {
            for c in 0..<cols where !solid[index(c, r)] {
                let d = centre(c, r).distance(to: p)
                if d < bestD { bestD = d; best = (c, r) }
            }
        }
        return best
    }

    /// Cell centres to walk through from one point to another, by the shortest way round the walls.
    func path(from a: Vec2, to b: Vec2) -> [Vec2] {
        let start = nearestOpen(a), goal = nearestOpen(b)
        let s = index(start.c, start.r), g = index(goal.c, goal.r)
        if s == g { return [b] }
        // Flood out from the goal, then walk downhill from the start.
        var dist = Array(repeating: -1, count: cols * rows)
        var queue = [g]
        dist[g] = 0
        var head = 0
        while head < queue.count, dist[s] < 0 {
            let i = queue[head]
            head += 1
            let c = i % cols, r = i / cols
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nc = c + dc, nr = r + dr
                guard inside(nc, nr) else { continue }
                let j = index(nc, nr)
                if dist[j] < 0, !solid[j] { dist[j] = dist[i] + 1; queue.append(j) }
            }
        }
        guard dist[s] >= 0 else { return [] }
        var out: [Vec2] = []
        var i = s
        while i != g {
            let c = i % cols, r = i / cols
            var next = i
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nc = c + dc, nr = r + dr
                guard inside(nc, nr) else { continue }
                let j = index(nc, nr)
                if dist[j] >= 0, dist[j] < dist[next] { next = j }
            }
            if next == i { break }
            i = next
            out.append(centre(i % cols, i / cols))
        }
        if out.isEmpty || !isSolid(b) { out.append(b) }
        return out
    }
}
