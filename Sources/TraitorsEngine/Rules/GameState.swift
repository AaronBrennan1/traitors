import Foundation
import TraitorsCore
import TraitorsMinds

public enum Phase: String, Codable {
    case roleReveal, breakfast, missionBrief, mission, missionResult
    case roundTable, voting, voteReveal, night
    case finaleChoice, finaleReveal, gameOver
}

public enum BeatKind: String, Codable {
    /// Scene-setting text.
    case narration
    /// Something the host says to the room.
    case host
    /// Something a player says at the table.
    case speech
    case vote, banish, murder
    /// Shown only to the human: traitor business, whispers.
    case secret
    case result
}

/// One line of what is happening, for the UI to present in order.
public struct Beat: Codable, Equatable {
    public package(set) var kind: BeatKind
    public package(set) var speaker: PlayerID? = nil
    public package(set) var target: PlayerID? = nil
    public package(set) var text: String
    public package(set) var role: Role? = nil

    public init(kind: BeatKind, speaker: PlayerID? = nil, target: PlayerID? = nil, text: String, role: Role? = nil) {
        self.kind = kind
        self.speaker = speaker
        self.target = target
        self.text = text
        self.role = role
    }
}

public enum HumanSay: String, Codable {
    case accuse, defend, question, pass
}

/// What the human has to decide in the turret tonight.
public enum NightChoice: String, Codable {
    case none, murder, recruit, offer
}

public struct DaySnapshot: Codable {
    public package(set) var day: Int
    /// What a neutral observer makes of each player (chance of being a traitor).
    public package(set) var publicSuspicion: [Double]
    /// Each bot's private suspicion of the human; -1 where it does not apply.
    public package(set) var ofHuman: [Double]
    /// The main thing each bot held against the human that day, where it had one.
    public package(set) var whyHuman: [Chip?] = []
}

/// Sim-only switches for measuring how much the bots' reasoning is worth.
public struct GameOptions: Codable {
    var randomFaithful = false
    var randomTraitors = false
    /// Play every mission out in its mini-game with bots, so what is seen comes from the game itself.
    var arena = false
    /// The numbers the game is played by. The defaults are the game as shipped.
    package var tuning = Tuning()

    public init(randomFaithful: Bool = false, randomTraitors: Bool = false, arena: Bool = false, tuning: Tuning = Tuning()) {
        self.randomFaithful = randomFaithful
        self.randomTraitors = randomTraitors
        self.arena = arena
        self.tuning = tuning
    }
}

/// Counters for the simulator and the end-of-game summary.
public struct Tally: Codable {
    public package(set) var roundTables = 0
    package var nights = 0
    package var murders = 0
    package var unanimous = 0
    package var firstTableSplit = false
    package var firstBanishedTraitor: Bool? = nil
    package var banishedTraitors = 0
    package var banishedFaithful = 0
    package var recruited = false
    /// Missions a traitor used the shadow's hand in, and missions it made the difference.
    package var sabotageAttempts = 0
    package var daysSunk = 0
    /// Days a traitor was banished with a partner still at the table, and how many partners voted for it.
    package var partnerDown = 0
    package var busVotes = 0
    package var liesTold = 0
    package var liesCaught = 0
    package var callouts = 0
    package var testimony = 0
    package var challenges = 0
    var framings = 0
    /// Missions the company won, and nights the traitors were kept in by one.
    package var groupWins = 0
    package var quietNights = 0
    package var defences: [String: Int] = [:]
}
