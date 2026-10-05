import Foundation

enum Phase: String, Codable {
    case roleReveal, breakfast, missionBrief, mission, missionResult
    case roundTable, voting, voteReveal, night
    case finaleChoice, finaleReveal, gameOver
}

enum BeatKind: String, Codable {
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
struct Beat: Codable {
    var kind: BeatKind
    var speaker: PlayerID? = nil
    var target: PlayerID? = nil
    var text: String
    var role: Role? = nil
}

enum HumanSay: String, Codable {
    case accuse, defend, question, pass
}

enum HumanInput {
    case next
    case mission(MissionResult)
    case say(HumanSay, target: PlayerID?, chip: Chip?)
    /// Answer an accusation with one of `Game.defenceOptions()`.
    case rebut(Int)
    case vote(PlayerID)
    case murder(PlayerID)
    case recruit(PlayerID)
    case recruitAnswer(Bool)
    case finale(end: Bool)
}

/// What the human has to decide in the turret tonight.
enum NightChoice: String, Codable {
    case none, murder, recruit, offer
}

struct DaySnapshot: Codable {
    var day: Int
    /// What a neutral observer makes of each player (chance of being a traitor).
    var publicSuspicion: [Double]
    /// Each bot's private suspicion of the human; -1 where it does not apply.
    var ofHuman: [Double]
    /// The main thing each bot held against the human that day, where it had one.
    var whyHuman: [Chip?] = []
}

/// Sim-only switches for measuring how much the bots' reasoning is worth.
struct GameOptions: Codable {
    var randomFaithful = false
    var randomTraitors = false
    /// Play every mission out in its mini-game with bots, so what is seen comes from the game itself.
    var arena = false
}

/// Counters for the simulator and the end-of-game summary.
struct Tally: Codable {
    var roundTables = 0
    var nights = 0
    var murders = 0
    var unanimous = 0
    var firstTableSplit = false
    var firstBanishedTraitor: Bool? = nil
    var banishedTraitors = 0
    var banishedFaithful = 0
    var recruited = false
    /// Missions a traitor used the shadow's hand in, and missions it made the difference.
    var sabotageAttempts = 0
    var daysSunk = 0
    /// Days a traitor was banished with a partner still at the table, and how many partners voted for it.
    var partnerDown = 0
    var busVotes = 0
    var liesTold = 0
    var liesCaught = 0
    var callouts = 0
    var testimony = 0
    var challenges = 0
    var framings = 0
    /// Missions the company won, and nights the traitors were kept in by one.
    var groupWins = 0
    var quietNights = 0
    var defences: [String: Int] = [:]
}
