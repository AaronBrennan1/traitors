import Foundation

/// What the human's run of the gauntlet hands back to the engine.
public struct MissionResult: Codable, Equatable {
    /// How the human pulled their weight when the game was not played out: 0 did nothing, 1 an
    /// ordinary day's share. Ignored when `teamTotal` says what was actually brought home.
    package var effort = 1.0
    /// What a human traitor's hand took off the company when the game was not played out, in
    /// players' shares. Ignored from a faithful.
    package var sabotage = 0.0
    /// What the company brought home between them. Nil when the game was not played out.
    package var teamTotal: Int? = nil
    /// The traitor whose hand made the difference between the goal and falling short, if one did.
    package var sunkBy: PlayerID? = nil
    /// The record of the game as it was played. With one, what people saw is worked out from it
    /// and not from the dice.
    package var ledger: MissionLedger? = nil

    public init(effort: Double = 1.0, sabotage: Double = 0.0, teamTotal: Int? = nil, sunkBy: PlayerID? = nil, ledger: MissionLedger? = nil) {
        self.effort = effort
        self.sabotage = sabotage
        self.teamTotal = teamTotal
        self.sunkBy = sunkBy
        self.ledger = ledger
    }
}
