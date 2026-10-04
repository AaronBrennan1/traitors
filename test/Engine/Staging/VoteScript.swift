import Foundation

/// A vote feed laid out for telling: what is said first, each slate in the order it should be
/// turned, and the banishment with its role held back. Built from beat kinds, never from text.
struct VoteScript {
    enum Step {
        /// Something said before or between the slates.
        case line(Beat)
        case slate(voter: PlayerID, target: PlayerID, round: Int)
        case banish(target: PlayerID, role: Role?)
        /// How the game stands after the banishment.
        case verdict(Beat)
    }

    var steps: [Step] = []
    /// How many rounds of slates there are.
    var rounds = 0

    init(feed: [Beat]) {
        var pending: [(PlayerID, PlayerID)] = []
        var banished = false

        func flush(_ steps: inout [Step], _ rounds: inout Int) {
            guard !pending.isEmpty else { return }
            rounds += 1
            for (voter, target) in Self.suspenseOrder(pending) {
                steps.append(.slate(voter: voter, target: target, round: rounds))
            }
            pending = []
        }

        for beat in feed {
            if beat.kind == .vote, let voter = beat.speaker, let target = beat.target, !banished {
                pending.append((voter, target))
                continue
            }
            flush(&steps, &rounds)
            if beat.kind == .banish, let target = beat.target {
                steps.append(.banish(target: target, role: beat.role))
                banished = true
            } else {
                steps.append(banished ? .verdict(beat) : .line(beat))
            }
        }
        flush(&steps, &rounds)
    }

    /// The slates of one round, reordered so the count stays level for as long as it can:
    /// stray votes first, then the front-runners trading the lead.
    static func suspenseOrder(_ slates: [(PlayerID, PlayerID)]) -> [(PlayerID, PlayerID)] {
        var total: [PlayerID: Int] = [:]
        for (_, target) in slates { total[target, default: 0] += 1 }
        var running: [PlayerID: Int] = [:]
        var left = slates
        var out: [(PlayerID, PlayerID)] = []
        while !left.isEmpty {
            var best = 0
            for i in left.indices.dropFirst() {
                let a = left[i].1, b = left[best].1
                let ka = (running[a, default: 0], total[a, default: 0])
                let kb = (running[b, default: 0], total[b, default: 0])
                if ka < kb { best = i }
            }
            let pick = left.remove(at: best)
            running[pick.1, default: 0] += 1
            out.append(pick)
        }
        return out
    }

    /// The count as it stands once `shown` steps have played, for the round then in progress.
    /// Names appear in the order they were first written.
    func tally(shown: Int) -> [(player: PlayerID, votes: Int)] {
        var current = 0
        var rows: [(player: PlayerID, votes: Int)] = []
        for step in steps.prefix(shown) {
            guard case .slate(_, let target, let round) = step else { continue }
            if round != current { current = round; rows = [] }
            if let i = rows.firstIndex(where: { $0.player == target }) {
                rows[i].votes += 1
            } else {
                rows.append((target, 1))
            }
        }
        return rows
    }

    /// Slates still to turn in the round of the step at `index`, not counting that step.
    func slatesLeft(after index: Int) -> Int {
        guard steps.indices.contains(index), case .slate(_, _, let round) = steps[index] else { return 0 }
        return steps[(index + 1)...].filter { if case .slate(_, _, round) = $0 { return true } else { return false } }.count
    }

    /// Where the second round begins, for a viewer who has already watched the first.
    var revoteStart: Int? {
        steps.firstIndex { if case .slate(_, _, 2) = $0 { return true } else { return false } }
    }

    /// Whoever the feed sends out, so the rest of the screen can keep them seated until it is told.
    var banished: PlayerID? {
        for step in steps { if case .banish(let target, _) = step { return target } }
        return nil
    }
}
