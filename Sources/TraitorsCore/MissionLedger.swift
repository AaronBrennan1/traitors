import Foundation

/// Everything the gauntlet writes down as it is played.
package enum EventCode: String, Codable {
    /// Private: a traitor used the shadow's hand. `a` is the mechanism.
    case sabotage
    /// A mechanism went, and this player was standing by it. Written the same whoever or whatever worked it.
    case sprung
    /// Stood by a mechanism and left it the moment someone came into view.
    case balked
    /// Behaviour the game knows to be odd. `a` is the index of the `SightingKind`.
    case tell
    case downed, banked, spilled
    case darkStart, darkEnd
}

/// One thing that happened, and who could see or hear it at that moment.
package struct MissionEvent: Codable, Equatable {
    var tick: Int
    /// Seat of whoever did it, or -1 for the world.
    package var actor: Int
    package var code: EventCode
    package var a = 0
    var b = 0
    /// Who had the actor in sight.
    package var seen: SeatMask = 0
    /// Who was close enough to hear it, whether or not they could see.
    var heard: SeatMask = 0

    package init(tick: Int, actor: Int, code: EventCode, a: Int = 0, b: Int = 0, seen: SeatMask = 0, heard: SeatMask = 0) {
        self.tick = tick
        self.actor = actor
        self.code = code
        self.a = a
        self.b = b
        self.seen = seen
        self.heard = heard
    }
}

/// What part of the arena a player is standing in, as far as the day's work goes.
package enum Zone {
    package static let open: UInt8 = 0
    /// Somewhere it is normal to stand still: the hoard, the vault, the near side of a trap.
    package static let task: UInt8 = 1
    /// Somewhere that does nothing for the mission. Higher numbers are other such places.
    package static let off: UInt8 = 2
}

/// The record of one mini-game: where everyone was and who could see them, five times a
/// second, and the events along the way. It is read once to work out the sightings and then dropped.
public struct MissionLedger: Codable, Equatable {
    package static let hz = 5

    package var seats: [PlayerID]
    package var ticks = 0
    /// Position tracks, `ticks × seats.count`, in whole points.
    var x: [Int16] = []
    var y: [Int16] = []
    package var zone: [UInt8] = []
    /// Who had each player in sight at each tick.
    package var seen: [SeatMask] = []
    package var events: [MissionEvent] = []

    package init(seats: [PlayerID]) { self.seats = seats }

    func column(of seat: PlayerID) -> Int? { seats.firstIndex(of: seat) }

    package mutating func sample(x xs: [Double], y ys: [Double], zone zs: [UInt8], seen masks: [SeatMask]) {
        for i in seats.indices {
            x.append(Int16(clamp(xs[i], -32000, 32000)))
            y.append(Int16(clamp(ys[i], -32000, 32000)))
            zone.append(zs[i])
            seen.append(masks[i])
        }
        ticks += 1
    }

    /// Everyone who had this player in sight at any point in a span of ticks.
    package func watchers(of column: Int, _ range: Range<Int>) -> SeatMask {
        var mask: SeatMask = 0
        for t in range where t >= 0 && t < ticks { mask |= seen[t * seats.count + column] }
        return mask
    }

    /// Runs of ticks where something holds for a player, at least `least` ticks long.
    package func spans(of column: Int, least: Int, where holds: (Int) -> Bool) -> [Range<Int>] {
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
    package func idleSpans(of column: Int, least: Int, where allowed: (Int) -> Bool = { _ in true }) -> [Range<Int>] {
        let n = seats.count
        return spans(of: column, least: least) { i in
            guard i >= n, allowed(i) else { return false }
            return abs(Int(x[i]) - Int(x[i - n])) + abs(Int(y[i]) - Int(y[i - n])) <= 1
        }
    }
}
