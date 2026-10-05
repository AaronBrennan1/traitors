import Foundation

/// Turns the record of a mini-game into what each player saw of the others. Nothing here knows
/// who is a traitor: the same behaviour reads the same whoever it comes from.
enum SightingDeriver {
    /// Seconds in a place that does nothing for the mission before it reads as drifting off.
    static var offTaskSeconds = 3.0
    /// Seconds stood still away from any station before it reads as loitering.
    static var loiterSeconds = 4.0
    /// Share of the game a witness must have had someone in sight to vouch for them.
    static var inViewShare = 0.5
    /// Share of the game somebody must have been in anyone's sight to count as never alone.
    static var neverAloneShare = 0.9
    /// How much of what a bot is placed to see it actually takes in.
    static var notice = 0.32
    /// Chance somebody who had a player in view all game thinks to vouch for them.
    static var vouch = 0.2

    struct Outcome {
        var sightings: [Sighting] = []
        /// Players who were in somebody's sight nearly all game.
        var neverAlone: [PlayerID] = []
    }

    static func derive(_ l: MissionLedger, day: Int, perception: [Double], human: PlayerID?, seed: UInt64) -> Outcome {
        var out = Outcome()
        guard l.ticks > 0 else { return out }
        let n = l.seats.count
        let hz = Double(MissionLedger.hz)
        var rng = SeededRNG.derived(seed, 2)

        for (c, p) in l.seats.enumerated() {
            // What happened, by kind, and everyone placed to see it. An empty mask still counts as odd.
            var raw: [SightingKind: SeatMask] = [:]
            func note(_ kind: SightingKind, _ mask: SeatMask) { raw[kind, default: 0] |= mask }

            for e in l.events where e.actor == p {
                switch e.code {
                case .sprung:
                    note(.atTheWorks, e.seen)
                case .balked:
                    note(.startled, e.seen)
                case .tell:
                    if e.a >= 0, e.a < SightingKind.allCases.count { note(SightingKind.allCases[e.a], e.seen) }
                default:
                    break
                }
            }
            for span in l.spans(of: c, least: Int(offTaskSeconds * hz), where: { l.zone[$0] >= Zone.off }) {
                note(.offTask, l.watchers(of: c, span))
            }
            for span in l.idleSpans(of: c, least: Int(loiterSeconds * hz), where: { l.zone[$0] != Zone.task }) {
                note(.loiter, l.watchers(of: c, span))
            }

            if raw.isEmpty {
                // Nothing odd all game: whoever had them in view for most of it can say so.
                var mask: SeatMask = 0
                for (wc, w) in l.seats.enumerated() where wc != c {
                    var ticks = 0
                    for t in 0..<l.ticks where l.seen[t * n + c].has(w) { ticks += 1 }
                    if Double(ticks) >= inViewShare * Double(l.ticks), w == human || rng.chance(vouch) { mask |= SeatMask.seat(w) }
                }
                if mask != 0 { out.sightings.append(Sighting(day: day, subject: p, kind: .inView, witnesses: mask)) }
            } else {
                for kind in SightingKind.allCases {
                    guard var mask = raw[kind] else { continue }
                    mask &= ~SeatMask.seat(p)
                    // Being placed to see something is not the same as taking it in.
                    for w in mask.seats where w != human {
                        let sharp = w < perception.count ? perception[w] : 0.5
                        if !rng.chance(notice * (0.35 + 0.6 * sharp)) { mask &= ~SeatMask.seat(w) }
                    }
                    if mask != 0 { out.sightings.append(Sighting(day: day, subject: p, kind: kind, witnesses: mask)) }
                }
            }

            var watched = 0
            for t in 0..<l.ticks where l.seen[t * n + c] != 0 { watched += 1 }
            if Double(watched) >= neverAloneShare * Double(l.ticks) { out.neverAlone.append(p) }
        }
        return out
    }
}
