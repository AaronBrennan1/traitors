import Foundation
import TraitorsCore
import TraitorsMinds

/// A vote laid out for telling: what is said first, each slate in the order it should be
/// turned, and the banishment with its role held back. Built from the vote's outcome.
public struct VoteScript {
    public enum Step {
        /// Something said before or between the slates.
        case line(Beat)
        case slate(voter: PlayerID, target: PlayerID, round: Int)
        case banish(target: PlayerID, role: Role?)
        /// How the game stands after the banishment.
        case verdict(Beat)
    }

    public package(set) var steps: [Step] = []
    /// How many rounds of slates there are.
    package var rounds = 0

    /// The vote the game has just resolved, or the first round of one that tied and is waiting
    /// on the human. Whatever was said before the slates comes first.
    public init(game: Game) {
        self.init(game.outcome?.vote ?? VoteOutcome(), lead: Array(game.feed.prefix { $0.kind != .vote }), names: game.names)
    }

    package init(_ vote: VoteOutcome, lead: [Beat] = [], names: [String]) {
        steps = lead.map { .line($0) }
        for (i, ballots) in vote.rounds.enumerated() where !ballots.isEmpty {
            rounds += 1
            for (voter, target) in Self.suspenseOrder(ballots.map { ($0.voter, $0.target) }) {
                steps.append(.slate(voter: voter, target: target, round: rounds))
            }
            if i == 0, !vote.tied.isEmpty {
                steps.append(.line(Beat(kind: .host, text: Host.tie(vote.tied.map { names[$0] }.joined(separator: " and ")))))
            }
        }
        if vote.byFate { steps.append(.line(Beat(kind: .host, text: Host.fate))) }
        guard let out = vote.banished else { return }
        steps.append(.banish(target: out, role: vote.role))
        if let winner = vote.winner {
            steps.append(.verdict(Beat(kind: .host, text: winner == .faithful ? Host.allBanished : Host.outvoted)))
        }
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
    public func tally(shown: Int) -> [(player: PlayerID, votes: Int)] {
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
    public func slatesLeft(after index: Int) -> Int {
        guard steps.indices.contains(index), case .slate(_, _, let round) = steps[index] else { return 0 }
        return steps[(index + 1)...].filter { if case .slate(_, _, round) = $0 { return true } else { return false } }.count
    }

    /// Where the second round begins, for a viewer who has already watched the first.
    public var revoteStart: Int? {
        steps.firstIndex { if case .slate(_, _, 2) = $0 { return true } else { return false } }
    }

    /// Whoever the vote sends out.
    package var banished: PlayerID? {
        for step in steps { if case .banish(let target, _) = step { return target } }
        return nil
    }
}
