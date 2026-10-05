import Foundation

/// The woman who runs the castle. Everything ceremonial is said in her voice.
/// Her lines are fixed: none of them may draw from the game's random streams.
enum Host {
    static let name = "The Chatelaine"

    // MARK: Arrival and selection

    static let welcome = [
        "Welcome to my castle.",
        "You came as strangers. Most of you will leave as something worse.",
        "Play together and you will fill the pot. But among you I will choose traitors, and they mean to take it all.",
    ]
    static let blindfolds = "Blindfolds on. Nobody speaks. Nobody moves."
    static let circling = "If you feel my hand on your shoulder, you are a traitor."
    static let chosen = "It is done. Remove your blindfolds."
    static let turret = "Traitors. Lower your hoods, and see who shares your secret."

    // MARK: Breakfast

    static func firstBreakfast(players: Int, traitors: Int) -> String {
        "Good morning, players. \(number(players).capitalized) of you sit down to breakfast. \(number(traitors).capitalized) of you are lying to the rest."
    }
    static let emptyChair = "One chair is empty this morning."
    static func murdered(_ name: String) -> String { "\(name) was murdered in the night." }
    static let youWereMurdered = "The empty chair is yours. The others will not see you again."
    static let noMurder = "Everyone has come down to breakfast. Nobody was murdered in the night."
    static let quietNight = "Everyone has come down to breakfast. You won your day, and it bought you all a quiet night."

    // MARK: Round Table

    static func roundTable(day: Int) -> String {
        "Welcome to the Round Table. Day \(day). Somebody in this room is lying to you."
    }
    static let fireLit = "The fire is lit. Say what you have to say."
    static let declarations = "Before the slates. One by one, tell the table where you are leaning."
    static func tie(_ names: String) -> String {
        "We have a tie between \(names). They will sit out while the rest of you vote again."
    }
    static let fate = "Still tied. Then fate will decide."
    static let slates = "Players, it is time to vote. Reveal your slates."
    static func banished(_ name: String) -> String { "\(name), you have received the most votes. You are banished from the castle." }
    static let declare = "Before you go, tell them what you are."
    static let finaleBanished = "From here, nobody says what they were."

    // MARK: Finale

    static func noMission(left: Int) -> String {
        "No mission today. The last \(number(left)) of you gather at the Fire of Truth. From here, the banished leave without saying what they were."
    }
    static let finaleChoice = "You may end the game here, or banish again. Choose."
    static let notUnanimous = "It is not unanimous. There will be another banishment."
    static let endFaithful = "The game ends. Everyone left is faithful. The faithful win."
    static func endTraitors(_ names: String, count: Int) -> String {
        "The game ends. \(names) \(count == 1 ? "was a traitor" : "were traitors") all along. The traitors win."
    }
    static let allBanished = "Every traitor has been banished. The faithful win."
    static let outvoted = "The traitors can no longer be outvoted. The traitors win."
    static let finalReveal = "One last time. Step up to the fire, and tell us what you are."

    // MARK: Night

    static let nightfall = "Night falls on the castle. Doors are locked. One lamp still burns in the turret."
    static let letter = "By order of the traitors"

    static func missionIntro(day: Int) -> String {
        day == 1 ? "Your first mission. You win it together or not at all." : "Today's mission. Make the goal between you, and you all sleep safe."
    }
    static func missionRule(goal: Int, unit: String) -> String {
        "Bring home \(goal) \(unit) between you and nobody is murdered tonight. Fall short, and the traitors have their night."
    }
    static let missionWon = "You made your goal. Nobody dies tonight."
    static let missionLost = "You fell short. The traitors have their night."

    private static func number(_ n: Int) -> String {
        let words = ["none", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }
}
