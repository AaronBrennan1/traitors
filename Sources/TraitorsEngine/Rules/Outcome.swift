import Foundation
import TraitorsCore
import TraitorsMinds

/// What has just been resolved, as data. The feed says the same thing in words; anything that
/// needs to know who voted for whom or who died reads it here and never from a line of text.
public enum Outcome: Codable {
    /// The day's mission, and what the human saw during it.
    case mission(MissionReport, noticed: [Sighting])
    case vote(VoteOutcome)
    case morning(MorningOutcome)

    public var vote: VoteOutcome? { if case .vote(let v) = self { return v } else { return nil } }
    public var morning: MorningOutcome? { if case .morning(let m) = self { return m } else { return nil } }
}

public struct Ballot: Codable, Equatable {
    package var voter: PlayerID
    public package(set) var target: PlayerID

    package init(voter: PlayerID, target: PlayerID) {
        self.voter = voter
        self.target = target
    }
}

/// A vote at the table. While a tie is waiting on the human's second slate it holds the first
/// round only, and nobody has been banished yet.
public struct VoteOutcome: Codable, Equatable {
    /// The slates of each round, in the order they were written down.
    public package(set) var rounds: [[Ballot]] = []
    /// Who was level after the first round, when it tied.
    package var tied: [PlayerID] = []
    /// The second round tied as well, and the lot decided.
    package var byFate = false
    public package(set) var banished: PlayerID?
    /// What the banished player declared. Nil in the finale, where nobody says.
    public package(set) var role: Role?
    /// Who has won, when this banishment settled it.
    package var winner: Role?

    package init(rounds: [[Ballot]] = [], tied: [PlayerID] = [], byFate: Bool = false, banished: PlayerID? = nil,
                role: Role? = nil, winner: Role? = nil) {
        self.rounds = rounds
        self.tied = tied
        self.byFate = byFate
        self.banished = banished
        self.role = role
        self.winner = winner
    }
}

/// What the house wakes up to.
public struct MorningOutcome: Codable, Equatable {
    /// Whoever was murdered in the night.
    public package(set) var victim: PlayerID?
    /// Whether the night was the traitors' to use. False after a day the company won.
    package var traitorsHadTheNight: Bool
    /// A recruitment was offered in place of a murder.
    package var recruitNight: Bool
    /// Those the house can say were never out of sight during yesterday's mission.
    package var neverOutOfSight: [PlayerID] = []
}
