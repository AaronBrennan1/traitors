import Foundation
import TraitorsCore

/// What one square of a course is made of.
public enum Tile: UInt8 {
    case floor, wall
    /// Nothing at all: a drop.
    case void
    /// Floor that gives way a moment after it is stepped on, and comes back.
    case crumble
    case hoard, vault
    /// A recess off the corridor, where there is no work to do.
    case alcove
}

/// A trap as a course's drawing describes it. Its ends are wherever its mark appears in the rows.
struct Trap {
    var kind: HazardKind
    var mark: Character
    /// The mark of the lever that trips it, if it has one.
    var lever: Character? = nil
    /// The mark of the floor plates that set it off.
    var plate: Character? = nil
    var period = 3.0
    var act = 0
    var offset = 0.0
    var push = Vec2.zero
}

/// A course as it is drawn: rows from the vault at the top to the hoard at the bottom.
///
///     #  wall            .  floor          (space)  a drop
///     ~  crumbling floor H  the hoard      V  the vault
///     B  a brazier to wake up at           ,  an alcove
///     *  a candle sconce, in an alcove
///
/// Anything else is a mark that a `Trap` picks up.
struct Blueprint {
    var rows: [String]
    var traps: [Trap]
    /// How far anyone can see.
    var vision = 300.0
}

/// Something a hand can work: the lever of a trap, a candle sconce, or the vault door.
public struct Mechanism: Equatable {
    public enum Kind: Equatable {
        case lever(Int)
        case sconce(Int)
        case vault
    }
    public let kind: Kind
    public let pos: Vec2
}

/// A course laid out and ready to run: its floor, its traps as they start, and the way through it.
public struct Course {
    public static let cols = 13
    public static let cell = 30.0

    public let kind: MissionKind
    public let rows: Int
    public let size: Vec2
    public let vision: Double
    public private(set) var tiles: [Tile]
    /// Walls, for feet and for eyes.
    private(set) var grid: ArenaGrid
    public private(set) var hazards: [Hazard] = []
    public private(set) var mechanisms: [Mechanism] = []
    public private(set) var braziers: [Vec2] = []
    /// The stretch of the course each sconce lights, bottom and top.
    private(set) var bands: [(lo: Double, hi: Double)] = []
    public private(set) var crumbles: [Int] = []
    private(set) var alcoves: [Vec2] = []
    private(set) var hoard = Vec2.zero
    public private(set) var vault = Vec2.zero
    /// Where to stand to have a hand on the vault door.
    private(set) var vaultMouth = Vec2.zero
    /// Steps of floor from each tile to the vault and to the hoard, or -1 where there is no way.
    private(set) var toVault: [Int] = []
    private(set) var toHoard: [Int] = []
    /// Tiles beside a trap, where it is ordinary to stand and wait.
    private(set) var queue: [Bool] = []

    init(_ kind: MissionKind) {
        self.init(kind, Courses.blueprint(kind))
    }

    init(_ kind: MissionKind, _ plan: Blueprint) {
        self.kind = kind
        rows = plan.rows.count
        vision = plan.vision
        let cols = Course.cols, cell = Course.cell
        size = Vec2(Double(cols) * cell, Double(rows) * cell)
        tiles = Array(repeating: .wall, count: cols * rows)
        grid = ArenaGrid(cols: cols, rows: rows, cell: cell)
        var marks: [Character: [Vec2]] = [:]
        var order: [Character] = []
        var sconces: [Vec2] = []
        var hoards: [Vec2] = [], vaults: [Vec2] = []
        let levers = Set(plan.traps.compactMap(\.lever))

        for (line, text) in plan.rows.enumerated() {
            // The drawing has the vault at the top; the course counts up from the hoard.
            let r = rows - 1 - line
            let chars = Array(text)
            for c in 0..<cols {
                let ch: Character = c < chars.count ? chars[c] : "#"
                let centre = grid.centre(c, r)
                var tile = Tile.floor
                switch ch {
                case "#": tile = .wall
                case ".": tile = .floor
                case " ": tile = .void
                case "~": tile = .crumble
                case "H": tile = .hoard; hoards.append(centre)
                case "V": tile = .vault; vaults.append(centre)
                case "B": braziers.append(centre)
                case ",": tile = .alcove
                case "*": tile = .alcove; sconces.append(centre)
                default:
                    if marks[ch] == nil { order.append(ch) }
                    marks[ch, default: []].append(centre)
                    if levers.contains(ch) { tile = .alcove }
                }
                tiles[r * cols + c] = tile
                if tile == .wall { grid.wall(c, r) }
                if tile == .crumble { crumbles.append(r * cols + c) }
                if tile == .alcove { alcoves.append(centre) }
            }
        }
        braziers.sort { $0.y < $1.y }
        hoard = Course.middle(hoards)
        vault = Course.middle(vaults)
        let sill = (vaults.map(\.y).min() ?? 0) - cell
        vaultMouth = Vec2(vault.x, sill)

        for trap in plan.traps {
            guard let ends = marks[trap.mark], let first = ends.first, let last = ends.last else { continue }
            var a = first, b = last
            if trap.kind == .spikes || trap.kind == .gust {
                // A patch covers its tiles whole, less a little at the edges for spikes.
                let inset = trap.kind == .spikes ? 6.0 : 0
                let lo = Vec2(min(a.x, b.x) - cell / 2 + inset, min(a.y, b.y) - cell / 2 + inset)
                let hi = Vec2(max(a.x, b.x) + cell / 2 - inset, max(a.y, b.y) + cell / 2 - inset)
                a = lo
                b = hi
            }
            hazards.append(Hazard(trap.kind, from: a, to: b, period: trap.period, act: trap.act, offset: trap.offset,
                                  push: trap.push, plates: trap.plate.flatMap { marks[$0] } ?? []))
            if let ch = trap.lever, let at = marks[ch]?.first {
                mechanisms.append(Mechanism(kind: .lever(hazards.count - 1), pos: at))
            }
        }
        for (i, at) in sconces.sorted(by: { $0.y < $1.y }).enumerated() {
            let third = size.y / 3
            let lo = (at.y / third).rounded(.down) * third
            bands.append((lo, lo + third))
            mechanisms.append(Mechanism(kind: .sconce(i), pos: at))
        }
        mechanisms.append(Mechanism(kind: .vault, pos: vaultMouth))

        toVault = flow(to: .vault)
        toHoard = flow(to: .hoard)
        queue = tiles.indices.map { i in
            let p = grid.centre(i % cols, i / cols)
            return hazards.contains { h in
                switch h.kind {
                case .blade, .barrel, .flame, .darts: return segmentNear(h.a, h.b, p) < 70
                case .spikes, .gust:
                    let dx = max(h.a.x - p.x, 0, p.x - h.b.x), dy = max(h.a.y - p.y, 0, p.y - h.b.y)
                    return (dx * dx + dy * dy).squareRoot() < 70
                }
            }
        }
    }

    private static func middle(_ points: [Vec2]) -> Vec2 {
        guard !points.isEmpty else { return .zero }
        var sum = Vec2.zero
        for p in points { sum += p }
        return sum * (1 / Double(points.count))
    }

    // MARK: - Asking about the floor

    func index(at p: Vec2) -> Int? {
        let (c, r) = grid.cellOf(p)
        return grid.inside(c, r) ? r * Course.cols + c : nil
    }

    func tile(at p: Vec2) -> Tile {
        index(at: p).map { tiles[$0] } ?? .void
    }

    public func centre(of index: Int) -> Vec2 {
        grid.centre(index % Course.cols, index / Course.cols)
    }

    /// Whether the course itself has floor here. Crumbling floor counts: whether it is there right now is the game's to say.
    func hasFloor(_ p: Vec2) -> Bool {
        let t = tile(at: p)
        return t != .void && t != .wall
    }

    func zone(at p: Vec2) -> UInt8 {
        guard let i = index(at: p) else { return Zone.open }
        switch tiles[i] {
        case .hoard, .vault: return Zone.task
        case .alcove: return Zone.off
        default: return queue[i] ? Zone.task : Zone.open
        }
    }

    /// The last brazier a runner at this height has passed on the way to the vault.
    func brazier(below y: Double) -> Vec2? {
        braziers.last { $0.y <= y + Course.cell }
    }

    /// Whether a stretch of the course is one the sconce at this index lights.
    func band(_ i: Int, holds p: Vec2) -> Bool {
        i < bands.count && p.y >= bands[i].lo && p.y < bands[i].hi
    }

    // MARK: - The way through

    /// Floods out from every tile of one kind over whatever can be walked on.
    private func flow(to goal: Tile) -> [Int] {
        let cols = Course.cols
        var dist = Array(repeating: -1, count: tiles.count)
        var queue: [Int] = []
        for i in tiles.indices where tiles[i] == goal {
            dist[i] = 0
            queue.append(i)
        }
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            let c = i % cols, r = i / cols
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nc = c + dc, nr = r + dr
                guard grid.inside(nc, nr) else { continue }
                let j = nr * cols + nc
                guard dist[j] < 0, tiles[j] != .wall, tiles[j] != .void else { continue }
                dist[j] = dist[i] + 1
                queue.append(j)
            }
        }
        return dist
    }

    /// The middle of the neighbouring tile that is nearest the goal, without cutting a corner off a wall or a drop.
    func next(from p: Vec2, by field: [Int]) -> Vec2? {
        let cols = Course.cols
        let (c, r) = grid.cellOf(p)
        guard grid.inside(c, r) else { return nil }
        var here = field[r * cols + c]
        if here < 0 { here = Int.max }
        var best: Vec2?
        var bestD = here
        for dr in -1...1 {
            for dc in -1...1 where dc != 0 || dr != 0 {
                let nc = c + dc, nr = r + dr
                guard grid.inside(nc, nr) else { continue }
                let d = field[nr * cols + nc]
                guard d >= 0, d < bestD else { continue }
                if dc != 0, dr != 0, field[r * cols + nc] < 0 || field[nr * cols + c] < 0 { continue }
                bestD = d
                best = grid.centre(nc, nr)
            }
        }
        return best
    }
}
