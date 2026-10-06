import Foundation

/// Céilí Chaos. The band calls a shape, everyone has a tile in it, and what counts is being on
/// that tile when the beat lands. Every so often there is a free dance and nobody has a tile.
final class CeiliCore: ArenaCore {
    static let side = 7
    static let tile = 44.0
    static let scored = 16
    static let free: Set<Int> = [4, 9, 14]
    /// Tiles for eight dancers, as steps from the middle of the floor.
    static let shapes: [(name: String, tiles: [(Int, Int)])] = [
        ("RING", [(2, 0), (2, 2), (0, 2), (-2, 2), (-2, 0), (-2, -2), (0, -2), (2, -2)]),
        ("STAR", [(1, 0), (3, 0), (0, 1), (0, 3), (-1, 0), (-3, 0), (0, -1), (0, -3)]),
        ("LINES", [(-3, 1), (-1, 1), (1, 1), (3, 1), (-3, -1), (-1, -1), (1, -1), (3, -1)]),
    ]

    private(set) var beat = 0
    let beats = CeiliCore.scored + CeiliCore.free.count
    let interval: Double
    private(set) var nextBeat: Double
    /// Each dancer's tile for the coming beat, by seat. Empty on a free dance.
    private(set) var places: [PlayerID: Int] = [:]
    private(set) var shape = ""
    /// Two boards that are not sound. They are just off every shape, so nobody has cause to be on one.
    private(set) var cracks: [Int] = []
    private var makes: [PlayerID: Bool] = [:]
    private var freeSpot: [PlayerID: Vec2] = [:]

    override class var pace: Double { 11 }
    override class var handCost: Int { 4 }
    override class var swing: Double { 0.55 }

    override init(_ setup: ArenaSetup) {
        let total = setup.kind.spec.seconds(day: setup.day)
        interval = (total - 2) / Double(CeiliCore.scored + CeiliCore.free.count)
        nextBeat = interval
        super.init(setup)
        size = Vec2(Double(Self.side) * Self.tile, Double(Self.side) * Self.tile)
        vision = 92
        var dice = SeededRNG.derived(setup.seed, 7)
        // Just off every shape, so standing there on a called beat means breaking it.
        let off = dice.shuffled([(1, 2), (-1, 2), (2, -1), (-2, 1), (1, -2), (-1, -2)])
        cracks = off.prefix(2).map { index($0.0, $0.1) }
        for (i, c) in cracks.enumerated() { works.append(Works(id: i, pos: centre(c), reach: 20, text: "A BOARD GIVES WAY")) }
        for (i, a) in actors.enumerated() {
            let t = Self.shapes[0].tiles[i % 8]
            a.pos = centre(index(t.0, t.1))
        }
        call()
        ready()
    }

    func index(_ dx: Int, _ dy: Int) -> Int { (dy + 3) * Self.side + dx + 3 }
    func centre(_ tile: Int) -> Vec2 { Vec2((Double(tile % Self.side) + 0.5) * Self.tile, (Double(tile / Self.side) + 0.5) * Self.tile) }
    func tile(at p: Vec2) -> Int {
        let c = Int(clamp(p.x / Self.tile, 0, Double(Self.side) - 0.01)), r = Int(clamp(p.y / Self.tile, 0, Double(Self.side) - 0.01))
        return r * Self.side + c
    }

    var freeDance: Bool { Self.free.contains(beat) }
    /// 0 just after a beat, 1 as the next one lands.
    var beatProgress: Double { clamp(1 - (nextBeat - time) / interval, 0, 1) }

    override func zone(of a: ArenaActor) -> UInt8 { Zone.task }

    /// Hands out the tiles for the coming beat.
    private func call() {
        places = [:]
        makes = [:]
        freeSpot = [:]
        guard beat < beats else { return }
        if freeDance {
            shape = "FREE DANCE"
            for a in actors {
                let t = tile(at: a.pos)
                let near = [t, t + 1, t - 1, t + Self.side, t - Self.side].filter { $0 >= 0 && $0 < Self.side * Self.side }
                freeSpot[a.id] = centre(rng.pick(near))
            }
        } else {
            let s = Self.shapes[(beat / 2) % Self.shapes.count]
            shape = s.name
            let turn = beat / 2
            for (i, a) in actors.enumerated() {
                let t = s.tiles[(i + turn) % 8]
                places[a.id] = index(t.0, t.1)
            }
            // Each bot settles now whether it makes this beat, so its night adds up to what it is headed for.
            let left = (beat..<beats).filter { !Self.free.contains($0) }.count
            for a in actors where isBot(a) {
                let owed = Double(a.target - count(of: a))
                makes[a.id] = rng.chance(clamp(owed / Double(max(left, 1)), 0, 1))
            }
        }
        cues.append(.banner(shape))
    }

    private func land() {
        var all = !freeDance
        for a in actors {
            let on = tile(at: a.pos)
            if let place = places[a.id] {
                if on == place { addCount(1, for: a) } else { all = false }
            }
        }
        // With no button to press, a traitor standing still on a bad board as the beat lands is the hand.
        if let me = human, let w = canSabotage(me) { sabotage(me, w) }
        if all {
            addBonus(2, at: Vec2(size.x / 2, size.y / 2), "FULL \(shape) +2")
        }
        beat += 1
        nextBeat += interval
        call()
    }

    override func tick(_ dt: Double) {
        for a in actors {
            if isBot(a) { think(a, dt) } else { slide(a, input.move * 128, dt) }
        }
        if time >= nextBeat, beat < beats { land() }
    }

    private func think(_ a: ArenaActor, _ dt: Double) {
        let speed = 120.0
        if runHand(a, speed: speed, dt) { return }
        if runHabit(a, speed: speed, dt) { return }
        if let place = places[a.id] {
            var to = centre(place)
            // Missing a beat is arriving a tile short, not wandering off.
            if makes[a.id] == false { to = to + (Vec2(size.x / 2, size.y / 2) - to).unit * Self.tile }
            travel(a, to: to, speed: speed, dt)
        } else if let to = freeSpot[a.id] {
            travel(a, to: to, speed: speed * 0.7, dt)
        }
    }

    override func props() -> [Prop] {
        var out: [Prop] = []
        for (seat, place) in places {
            out.append(Prop(id: seat, kind: .tile, pos: centre(place), value: beatProgress, tint: seat))
        }
        for (i, c) in cracks.enumerated() { out.append(Prop(id: 100 + i, kind: .crack, pos: centre(c))) }
        return out
    }
}
