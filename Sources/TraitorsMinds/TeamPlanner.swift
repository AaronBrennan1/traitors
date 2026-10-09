import Foundation
import TraitorsCore

/// How the rest of the team treats one of its own at today's table.
enum Stance: String, Codable {
    /// They are going anyway: vote them out and bank the trust.
    case bus
    /// In real danger but saveable: push a faithful instead, without moving as a bloc.
    case redirect
    /// Safe: a little cheap doubt now is an alibi later.
    case distance
}

/// What the traitors have agreed for a Round Table. Kept on the game so that every traitor
/// (and a human traitor's whisper) works from the same plan, and a saved game resumes with it.
public struct TeamPlan: Codable {
    package var day: Int
    /// Length of the public log the plan was made from.
    package var asOf: Int
    /// Chance each seat is banished tonight if the team votes for the scapegoat.
    var danger: [Double]
    /// Stance towards each living traitor, by seat. Nil for everyone else.
    var stances: [Stance?]
    /// The faithful the table is readiest to banish.
    var scapegoat: PlayerID?
    /// The traitor best placed to lead a push; the others keep their distance from it.
    var lead: PlayerID?
    /// Traitors who have used their one vouch at this table.
    package var vouched: [PlayerID] = []

    func stance(_ p: PlayerID) -> Stance? { stances[p] }
}

package enum TeamPlanner {
    static let busAt = 0.6
    static let redirectAt = 0.3

    package static func plan(view: TableView, team: [PlayerID], known: [Sighting], seed: UInt64) -> TeamPlan {
        var fresh = Recall()
        return plan(view: view, team: team, known: known, seed: seed, recall: &fresh)
    }

    static func plan(view: TableView, team: [PlayerID], known: [Sighting], seed: UInt64, recall: inout Recall) -> TeamPlan {
        let living = team.filter { view.seats[$0].alive }
        let listeners = Listeners.build(view: view, team: team, known: known, recall: &recall)
        let salt = UInt64(view.log.count)
        let free = VoteSim.pBanish(view: view, listeners: listeners, fixed: [],
                                   rng: .derived(seed, UInt64(view.day), salt, 1))
        let goat = view.alive.filter { !team.contains($0) }.max {
            free[$0] + 0.02 * view.heat[$0] < free[$1] + 0.02 * view.heat[$1]
        }
        let fixed = goat.map { g in living.map { (voter: $0, target: g) } } ?? []
        let danger = VoteSim.pBanish(view: view, listeners: listeners, fixed: fixed,
                                     rng: .derived(seed, UInt64(view.day), salt, 2))
        var stances: [Stance?] = Array(repeating: nil, count: view.count)
        for t in living {
            stances[t] = danger[t] >= busAt ? .bus : danger[t] >= redirectAt ? .redirect : .distance
        }
        let lead = living.min { danger[$0] < danger[$1] }
        return TeamPlan(day: view.day, asOf: view.log.count, danger: danger, stances: stances, scapegoat: goat, lead: lead)
    }

    /// What a bot traitor tells a human partner about the plan.
    package static func whisper(_ plan: TeamPlan, from bot: PlayerID, to human: PlayerID, view: TableView) -> String? {
        let name = view.name(bot)
        if plan.stance(bot) == .bus {
            return "\(name) whispers: \"They have me. Don't go down with me: write my name and bank the trust.\""
        }
        if plan.stance(human) == .bus {
            return "\(name) whispers: \"The table has turned on you. I can't pull you out of this without sinking us both.\""
        }
        guard let goat = plan.scapegoat else { return nil }
        if plan.stance(bot) == .redirect || plan.stance(human) == .redirect {
            let who = plan.lead == human ? "You lead it" : "I'll lead it"
            return "\(name) whispers: \"We need them looking at \(view.name(goat)). \(who), and we don't vote as a pair unless we must.\""
        }
        return "\(name) whispers: \"Quiet table for us. \(view.name(goat)) is where it's heading. I may put a small doubt on you for cover.\""
    }
}
