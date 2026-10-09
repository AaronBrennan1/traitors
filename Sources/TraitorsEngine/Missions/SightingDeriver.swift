import Foundation
import TraitorsCore
import TraitorsMinds

/// Turns the record of a mini-game into what each player saw of the others. Nothing here knows
/// who is a traitor: the same behaviour reads the same whoever it comes from.
package enum SightingDeriver {
    package struct Outcome {
        package var sightings: [Sighting] = []
        /// Players who were in somebody's sight nearly all game.
        var neverAlone: [PlayerID] = []
    }

    package static func derive(_ l: MissionLedger, day: Int, perception: [Double], human: PlayerID?, seed: UInt64,
                               tuning: SightingTuning = SightingTuning()) -> Outcome {
        let offTaskSeconds = tuning.offTaskSeconds, loiterSeconds = tuning.loiterSeconds
        let inViewShare = tuning.inViewShare, neverAloneShare = tuning.neverAloneShare, notice = tuning.notice, vouch = tuning.vouch
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
