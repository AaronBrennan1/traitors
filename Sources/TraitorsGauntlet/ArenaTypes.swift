import Foundation
import TraitorsCore

public struct Vec2: Codable, Equatable {
    public package(set) var x = 0.0
    public package(set) var y = 0.0

    public static let zero = Vec2()

    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }

    public var length: Double { (x * x + y * y).squareRoot() }
    var unit: Vec2 { let l = length; return l > 1e-9 ? self * (1 / l) : .zero }
    public func distance(to o: Vec2) -> Double { (self - o).length }
    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    func capped(_ most: Double) -> Vec2 { let l = length; return l > most ? self * (most / l) : self }
}

/// One player as the mini-game needs to know them.
public struct ArenaSeat {
    public let id: PlayerID
    let skill: Double
    package let perception: Double
    let deceit: Double
    public let isHuman: Bool

    package init(id: PlayerID, skill: Double, perception: Double, deceit: Double, isHuman: Bool) {
        self.id = id
        self.skill = skill
        self.perception = perception
        self.deceit = deceit
        self.isHuman = isHuman
    }
}

/// Everything a mini-game is dealt before it starts.
public struct ArenaSetup {
    public let kind: MissionKind
    let day: Int
    package let seed: UInt64
    let quirkSeed: UInt64
    /// Everyone playing, in seat order.
    public let cast: [ArenaSeat]
    /// Who has the shadow's hand today: the bot who means to use it, and a human traitor.
    let saboteurs: [PlayerID]
    /// How good a day the bots are having, as one roll for all of them. 0 is an ordinary day.
    package let form: Double
    /// A bot plays the human's seat, for tests and unattended runs.
    public package(set) var autopilot: Bool
    /// The numbers the round is played by.
    package var tuning = Tuning()

    package init(kind: MissionKind, day: Int, seed: UInt64, quirkSeed: UInt64, cast: [ArenaSeat], saboteurs: [PlayerID],
         form: Double = 0, autopilot: Bool = true, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        self.kind = kind
        self.day = day
        self.seed = seed
        self.quirkSeed = quirkSeed
        self.cast = cast
        self.saboteurs = saboteurs
        self.form = form
        self.autopilot = autopilot
    }

    /// The human's seat, when there is a human in the cast.
    public var human: PlayerID? { cast.first(where: \.isHuman)?.id }
    /// The human is a traitor with the shadow's hand today. Nobody else is shown anything of it.
    public var humanHasHand: Bool { human.map(saboteurs.contains) ?? false }

}

/// What the human is doing with their thumbs this frame. A press of the button and a strike let
/// go both go through `ArenaSession`, which holds on to them until a step can take them.
public struct ArenaInput {
    /// The stick, length 0...1, in the arena's own axes.
    public var move = Vec2.zero
    /// The button is being held down.
    public var hold = false

    public init(move: Vec2 = Vec2.zero, hold: Bool = false) {
        self.move = move
        self.hold = hold
    }
}

/// Everything a stage knows how to draw, in the games that are not the gauntlet.
public enum PropKind: String {
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
public struct Prop {
    public package(set) var id: Int
    public package(set) var kind: PropKind
    public package(set) var pos: Vec2
    /// Height off the ground.
    public package(set) var z = 0.0
    /// What it is doing, in the game's own terms: lit or out, which colour, how full.
    public package(set) var state = 0
    public package(set) var value = 0.0
    /// Seat whose colour it wears, or -1.
    public package(set) var tint = -1
    public package(set) var hidden = false
}

/// Somewhere a player can stand and hold the button.
struct Spot {
    let id: Int
    var pos: Vec2
    var reach = 30.0
    var hold = 1.0
    /// What kind of thing it is, in the game's own terms.
    var tag = 0
    /// Has nothing to do with the day's work.
    var offMission = false
}

/// Things for the screen and the speaker to do that do not change the game.
public enum ArenaCue {
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

    // What the other games ask of the screen, in their own words.
    case popup(String, Vec2, seat: PlayerID?, bad: Bool)
    case banner(String)
    case flash(bad: Bool)
    case shake
    case burst(Vec2, seat: PlayerID?)
}

/// A square grid of walls. It blocks feet, sight or both.
public struct ArenaGrid {
    public let cols: Int
    public let rows: Int
    public let cell: Double
    var solid: [Bool]
    public package(set) var opaque: [Bool]

    init(cols: Int, rows: Int, cell: Double) {
        self.cols = cols
        self.rows = rows
        self.cell = cell
        solid = Array(repeating: false, count: cols * rows)
        opaque = solid
    }

    public func inside(_ c: Int, _ r: Int) -> Bool { c >= 0 && r >= 0 && c < cols && r < rows }
    public func index(_ c: Int, _ r: Int) -> Int { r * cols + c }
    func cellOf(_ p: Vec2) -> (c: Int, r: Int) { (Int((p.x / cell).rounded(.down)), Int((p.y / cell).rounded(.down))) }
    public func centre(_ c: Int, _ r: Int) -> Vec2 { Vec2((Double(c) + 0.5) * cell, (Double(r) + 0.5) * cell) }

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

    public func isSolid(_ p: Vec2) -> Bool {
        let (c, r) = cellOf(p)
        return !inside(c, r) || solid[index(c, r)]
    }

    public func isSolid(_ c: Int, _ r: Int) -> Bool { !inside(c, r) || solid[index(c, r)] }

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
