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
    /// The tiles a traitor has to be standing on when a beat lands.
    private(set) var cracks: [Int] = []
    private var makes: [PlayerID: Bool] = [:]
    private var freeSpot: [PlayerID: Vec2] = [:]
    private var fumbles: [PlayerID: Bool] = [:]

    override init(_ setup: ArenaSetup) {
        let total = setup.kind.spec.seconds(day: setup.day)
        interval = (total - 2) / Double(CeiliCore.scored + CeiliCore.free.count)
        nextBeat = interval
        super.init(setup)
        size = Vec2(Double(Self.side) * Self.tile, Double(Self.side) * Self.tile)
        vision = 92
        questGoal = setup.questSteps > 1 ? 4 : 3
        var dice = SeededRNG.derived(setup.seed, 7)
        // Just off every shape, so standing there on a called beat means breaking it.
        let off = dice.shuffled([(1, 2), (-1, 2), (2, -1), (-2, 1), (1, -2), (-1, -2)])
        cracks = off.prefix(setup.questSteps).map { index($0.0, $0.1) }
        cover = Self.free.sorted().map { CoverWindow(start: Double($0) * interval, end: Double($0 + 1) * interval, kind: .rhythm) }
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
        // Getting to the cracked tile on the beat without it looking like a dash does not always come off.
        for a in actors where isBot(a) && isQuester(a) { fumbles[a.id] = !rng.chance(0.62 + 0.3 * a.seat.skill) }
        if freeDance {
            shape = "FREE DANCE"
            log(.transitionStart, nil)
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
                let owed = Double(a.seat.target - count(of: a))
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
                let hit = on == place
                log(.beat, a, a: on, b: hit ? 1 : 0)
                if hit { addCount(1, for: a) } else { all = false }
            }
            if cracks.contains(on) {
                if isQuester(a), questOpen { questStep(a) } else { tell(.atQuestObject, a) }
            }
        }
        if freeDance { log(.transitionEnd, nil) }
        if all {
            log(.formationComplete, nil)
            addBonus(3, at: Vec2(size.x / 2, size.y / 2), "FULL \(shape) +3")
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
        if questDue(a), let crack = cracks.first {
            // The free dances are the time for it. With too few left, a called beat has to go instead.
            let freeLeft = Self.free.filter { $0 >= beat }.count
            let need = questGoal - questProgress
            if (freeDance || (freeLeft < need && a.seat.deceit > 0.5)) && fumbles[a.id] != true {
                noteTry(a)
                travel(a, to: centre(cracks.count > 1 && questProgress >= questGoal / 2 ? cracks[1] : crack), speed: speed, dt)
                return
            }
        }
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
        for (i, c) in cracks.enumerated() { out.append(Prop(id: 100 + i, kind: .crack, pos: centre(c), secret: true)) }
        return out
    }
}
