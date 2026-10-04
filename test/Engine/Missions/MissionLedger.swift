import Foundation

/// Everything a mini-game writes down as it is played.
enum EventCode: String, Codable {
    // Every game.
    case interactStart, interactDone, interactAbort
    /// A traitor set off for the side quest, one piece of it was done, all of it was done.
    case questTry, questStep, questDone
    case enteredZone, coverStart, coverEnd, scored
    /// Behaviour a game knows to be odd for it. `a` is the index of the `SightingKind`.
    case tell
    // The Bog Relay.
    case sodPickedUp, sodDelivered, sodLost, splash
    // Castle Lantern Run.
    case lanternLit, lanternOut, flameCarried, darkPosition
    // Sheep Round-Up.
    case sheepPenned, dogCommand, gust
    // The Shipwreck Dive.
    case dive, surface, chestOpened, chestRaised, roomEntered
    // Céilí Chaos.
    case beat, formationComplete, transitionStart, transitionEnd
    // Market Day Scramble.
    case stallVisited, itemBought, crowdCover
    // Cliffside Kite Race.
    case ringPassed, snag
    // The Hedge Maze.
    case mapRevealed, deadEndEntered, statueInteract, hedgeShift
    // Hurley Target Practice.
    case shot, streakBroken, bellRung
    // The Banquet Prep.
    case ingredientTaken, potInteraction, orderServed, stationClaimed
}

/// One thing that happened, and who could see or hear it at that moment.
struct MissionEvent: Codable, Equatable {
    var tick: Int
    /// Seat of whoever did it, or -1 for the world.
    var actor: Int
    var code: EventCode
    var a = 0
    var b = 0
    /// Who had the actor in sight.
    var seen: SeatMask = 0
    /// Who was close enough to hear it, whether or not they could see.
    var heard: SeatMask = 0
}

enum CoverKind: String, Codable {
    case fog, dark, chaos, crowd, structure, rhythm, volley, depth
}

/// A stretch of the game when it is hard to see what anyone is doing.
struct CoverWindow: Codable, Equatable {
    var start: Double
    var end: Double
    var kind: CoverKind
}

/// What part of the arena a player is standing in, as far as the day's work goes.
enum Zone {
    static let open: UInt8 = 0
    /// Somewhere it is normal to stand still: a station, a firing line, the surface.
    static let task: UInt8 = 1
    /// Somewhere that does nothing for the mission. Higher numbers are other such places.
    static let off: UInt8 = 2
}

/// The record of one mini-game: where everyone was and who could see them, five times a
/// second, and the events along the way. It is read once to work out the sightings and then dropped.
struct MissionLedger: Codable, Equatable {
    static let hz = 5

    var seats: [PlayerID]
    var ticks = 0
    /// Position tracks, `ticks × seats.count`, in whole points.
    var x: [Int16] = []
    var y: [Int16] = []
    var zone: [UInt8] = []
    /// Who had each player in sight at each tick.
    var seen: [SeatMask] = []
    var events: [MissionEvent] = []
    var cover: [CoverWindow] = []
    /// How far from the middle of the others counts as having left the pack. 0 when a game has no pack.
    var spread = 0.0

    init(seats: [PlayerID]) { self.seats = seats }

    func column(of seat: PlayerID) -> Int? { seats.firstIndex(of: seat) }

    mutating func sample(x xs: [Double], y ys: [Double], zone zs: [UInt8], seen masks: [SeatMask]) {
        for i in seats.indices {
            x.append(Int16(clamp(xs[i], -32000, 32000)))
            y.append(Int16(clamp(ys[i], -32000, 32000)))
            zone.append(zs[i])
            seen.append(masks[i])
        }
        ticks += 1
    }

    /// Everyone who had this player in sight at any point in a span of ticks.
    func watchers(of column: Int, _ range: Range<Int>) -> SeatMask {
        var mask: SeatMask = 0
        for t in range where t >= 0 && t < ticks { mask |= seen[t * seats.count + column] }
        return mask
    }

    /// Runs of ticks where something holds for a player, at least `least` ticks long.
    func spans(of column: Int, least: Int, where holds: (Int) -> Bool) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for t in 0...ticks {
            let on = t < ticks && holds(t * seats.count + column)
            if on, start == nil { start = t }
            if !on, let s = start {
                if t - s >= least { out.append(s..<t) }
                start = nil
            }
        }
        return out
    }

    /// Stretches where the player did not move from the spot.
    func idleSpans(of column: Int, least: Int, where allowed: (Int) -> Bool = { _ in true }) -> [Range<Int>] {
        let n = seats.count
        return spans(of: column, least: least) { i in
            guard i >= n, allowed(i) else { return false }
            return abs(Int(x[i]) - Int(x[i - n])) + abs(Int(y[i]) - Int(y[i - n])) <= 1
        }
    }

    /// How far a player is from the middle of everybody else.
    func groupDistance(of column: Int, tick: Int) -> Double {
        let n = seats.count
        guard n > 1 else { return 0 }
        var sx = 0.0, sy = 0.0
        for c in 0..<n where c != column {
            sx += Double(x[tick * n + c])
            sy += Double(y[tick * n + c])
        }
        let dx = Double(x[tick * n + column]) - sx / Double(n - 1)
        let dy = Double(y[tick * n + column]) - sy / Double(n - 1)
        return (dx * dx + dy * dy).squareRoot()
    }
}
