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
    /// The count the engine expects of a bot today. The game plays the bot towards it.
    let target: Int
}

/// Everything a mini-game is dealt before it starts.
struct ArenaSetup {
    let kind: MissionKind
    let day: Int
    let seed: UInt64
    let quirkSeed: UInt64
    /// Everyone playing, in seat order.
    let cast: [ArenaSeat]
    /// Who has the side quest to do today: the bot who means to try it, and a human traitor.
    let questers: [PlayerID]
    let questSteps: Int
    /// A bot plays the human's seat, for tests and unattended runs.
    var autopilot: Bool

    init(kind: MissionKind, day: Int, seed: UInt64, quirkSeed: UInt64, cast: [ArenaSeat], questers: [PlayerID],
         questSteps: Int = 1, autopilot: Bool = true) {
        self.kind = kind
        self.day = day
        self.seed = seed
        self.quirkSeed = quirkSeed
        self.cast = cast
        self.questers = questers
        self.questSteps = questSteps
        self.autopilot = autopilot
    }

    /// The day's mission as the engine planned it.
    init(run: MissionRun, autopilot: Bool) {
        var dice = SeededRNG.derived(run.layoutSeed, 3)
        var questers: [PlayerID] = []
        if run.questOpen {
            if let r = run.runner, r != run.human, run.runnerAttempt { questers.append(r) }
            if let h = run.human, run.traitors.contains(h) { questers.append(h) }
        }
        let cast = run.order.sorted().map { p -> ArenaSeat in
            let mine = p == run.human
            let target = run.targets[p] ?? MissionRun.sample(run.kind, skill: run.skill[p], questing: questers.contains(p), rng: &dice)
            return ArenaSeat(id: p, skill: run.skill[p], perception: run.perception[p], deceit: run.deceit[p],
                             isHuman: mine, target: target)
        }
        self.init(kind: run.kind, day: run.day, seed: run.layoutSeed, quirkSeed: run.quirkSeed, cast: cast,
                  questers: questers, questSteps: run.questSteps, autopilot: autopilot)
    }
}

/// What the human is doing with their thumbs this frame.
struct ArenaInput {
    /// The stick, length 0...1, already turned into the arena's own axes.
    var move = Vec2.zero
    var interact = false
    /// A strike let go this frame: which way and how hard, length 0...1.
    var shot: Vec2?
}

/// Everything a stage knows how to draw.
enum PropKind: String {
    case stone, turfLight, turfHeavy, stack, hollow, bogOak
    case brazier, lantern
    case sheep, pen, dog
    case chest, eel, boat
    case tile, crack
    case stall, cart, shopper
    case ring, spire, kite, gull
    case sigil, post, bell, statue
    case target, ball
    case station, pot, herbShelf
}

/// One thing in the arena, as the stage should show it this frame.
struct Prop {
    var id: Int
    var kind: PropKind
    var pos: Vec2
    /// Height off the ground.
    var z = 0.0
    /// What it is doing, in the game's own terms: lit or out, which colour, how full.
    var state = 0
    var value = 0.0
    /// Seat whose colour it wears, or -1.
    var tint = -1
    /// Carries the mark only a traitor on the side quest can see.
    var secret = false
    var hidden = false
}

/// Somewhere a player can stand and hold Interact.
struct Spot {
    let id: Int
    var pos: Vec2
    var reach = 30.0
    var hold = 1.0
    /// What kind of thing it is, in the game's own terms.
    var tag = 0
    /// Has nothing to do with the day's work, so being seen at it is worth mentioning.
    var offMission = false
}

/// Things for the screen to do that do not change the game.
enum ArenaCue {
    case popup(String, Vec2, seat: PlayerID?, bad: Bool)
    case banner(String)
    case flash(bad: Bool)
    case shake
    case burst(Vec2, seat: PlayerID?)
}

/// A square grid of walls for the games that have them. It blocks feet, sight or both.
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
