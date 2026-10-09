import Foundation
import TraitorsCore

/// A model of what everyone else at the table makes of things: one mind per listener, each
/// given the public record plus whatever the modeller knows that listener saw. It answers
/// "how guilty do I look to each of them", and "what if this were said next".
struct Listeners {
    var ids: [PlayerID]
    var replays: [Replay]
    /// What each listener currently believes, in the order of `ids`.
    var beliefs: [Belief]

    /// One mind for every living player outside `team`. `known` is the sightings the
    /// modeller knows about, which each listener is credited with if they were a witness.
    static func build(view: TableView, team: [PlayerID], known: [Sighting]) -> Listeners {
        var fresh = Recall()
        return build(view: view, team: team, known: known, recall: &fresh)
    }

    /// The same, carrying on from whatever of it `recall` has already worked through.
    static func build(view: TableView, team: [PlayerID], known: [Sighting], recall: inout Recall) -> Listeners {
        let ids = view.alive.filter { !team.contains($0) }
        var replays: [Replay] = []
        for l in ids {
            let observer = Observer(id: l, gut: Array(repeating: 0, count: view.count), temper: 1,
                                    sightings: known.filter { $0.witnesses.has(l) })
            replays.append(recall.replay(.listener(l), of: view.record, seats: view.count, observer: observer, tuning: view.tuning))
        }
        return Listeners(ids: ids, replays: replays, beliefs: replays.map { $0.belief() })
    }

    /// Each listener's suspicion of `p`, in the order of `ids`.
    func suspicion(of p: PlayerID) -> [Double] {
        beliefs.map { $0.marginal(p) }
    }

    /// How hot `p` is across the table: every listener has one vote, so each counts the same.
    func heat(of p: PlayerID) -> Double {
        let s = zip(ids, suspicion(of: p)).filter { $0.0 != p }.map(\.1)
        return s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count)
    }

    /// The table after hearing `statement`, with each listener warming to the speaker by `soothe`.
    func after(_ statement: Statement, soothe: Double = 0) -> Listeners {
        var next = self
        for i in next.replays.indices {
            next.replays[i].feed(.statement(statement))
            if soothe != 0 { next.replays[i].nudge(statement.speaker, by: -soothe) }
            next.beliefs[i] = next.replays[i].belief()
        }
        return next
    }
}

/// Plays the coming vote many times over from a model of the table.
enum VoteSim {
    /// Chance each seat is the one banished. `fixed` are ballots already decided (the
    /// modeller's own side); listeners vote from their modelled beliefs, mostly keeping to
    /// any name they have declared. `rng` should be a derived stream.
    static func pBanish(view: TableView, listeners: Listeners, fixed: [(voter: PlayerID, target: PlayerID)],
                        pool: [PlayerID]? = nil, samples: Int = 96, rng: SeededRNG) -> [Double] {
        var rng = rng
        let pool = pool ?? view.alive
        var out = Array(repeating: 0.0, count: view.count)
        guard !pool.isEmpty else { return out }
        let beliefs = listeners.beliefs
        var odds: [[Double]] = []
        for (i, l) in listeners.ids.enumerated() {
            let scores = pool.map { $0 == l ? -Double.infinity : (log(beliefs[i].marginal($0) + 0.03) + 0.12 * view.heat[$0]) / 0.2 }
            let top = scores.max() ?? 0
            var w = scores.map { $0 == -Double.infinity ? 0 : exp($0 - top) }
            let z = w.reduce(0, +)
            if z > 0 { w = w.map { $0 / z } }
            if let said = view.index.declared(day: view.day, by: l), let j = pool.firstIndex(of: said) {
                w = w.map { $0 * 0.3 }
                w[j] += 0.7
            }
            odds.append(w)
        }
        for _ in 0..<samples {
            var counts = Array(repeating: 0, count: pool.count)
            for f in fixed { if let j = pool.firstIndex(of: f.target) { counts[j] += 1 } }
            for w in odds where w.contains(where: { $0 > 0 }) { counts[rng.weighted(w)] += 1 }
            let most = counts.max() ?? 0
            let tied = pool.indices.filter { counts[$0] == most }
            for j in tied { out[pool[j]] += 1 / Double(tied.count) }
        }
        return out.map { $0 / Double(samples) }
    }
}
