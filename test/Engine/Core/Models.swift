import Foundation

typealias PlayerID = Int

enum Role: String, Codable {
    case faithful, traitor
}

enum RolePreference: String, Codable, CaseIterable {
    case random, faithful, traitor
}

/// How a character phrases things at the Round Table.
enum Voice: String, Codable {
    case blunt, loud, wry, quiet, warm, sly, earnest, plain
}

/// All traits are 0...1.
struct Personality: Codable {
    /// Chance of noticing each slip-up in a mission.
    var perception: Double
    /// How faithfully evidence is weighed (low logic = fuzzier conclusions).
    var logic: Double
    /// Eagerness to speak up and accuse.
    var aggression: Double
    /// Strength of private gut feelings and grudges.
    var stubbornness: Double
    /// How much the mood of the table sways the vote.
    var herd: Double
    /// How much weight others give this player's words.
    var charisma: Double
    /// Composure when lying as a traitor.
    var deceit: Double
    /// Ability in missions.
    var skill: Double

    static let average = Personality(perception: 0.6, logic: 0.7, aggression: 0.5, stubbornness: 0.5,
                                     herd: 0.4, charisma: 0.6, deceit: 0.6, skill: 0.5)
}

enum FateKind: String, Codable {
    case murdered, banished
}

struct Player: Codable {
    var id: PlayerID
    var name: String
    var county: String
    var job: String
    var isHuman: Bool
    var role: Role
    var wasRecruited: Bool = false
    var alive: Bool = true
    var fate: FateKind?
    var fateDay: Int?
    var personality: Personality
    var voice: Voice
    /// 0...1 hue used for the cloak colour in the UI.
    var hue: Double
}

struct CastMember {
    var name: String
    var county: String
    var job: String
    var personality: Personality
    var voice: Voice
    var hue: Double
}

enum Cast {
    /// The seven computer-controlled players. Strong all-round, each with a distinct style.
    static let bots: [CastMember] = [
        CastMember(name: "Siobhán", county: "Galway", job: "Retired Garda sergeant",
                   personality: Personality(perception: 0.92, logic: 0.85, aggression: 0.72, stubbornness: 0.70,
                                            herd: 0.20, charisma: 0.70, deceit: 0.55, skill: 0.60),
                   voice: .blunt, hue: 0.58),
        CastMember(name: "Declan", county: "Cork", job: "Publican",
                   personality: Personality(perception: 0.62, logic: 0.60, aggression: 0.82, stubbornness: 0.50,
                                            herd: 0.50, charisma: 0.88, deceit: 0.75, skill: 0.50),
                   voice: .loud, hue: 0.04),
        CastMember(name: "Aoife", county: "Dublin", job: "Barrister",
                   personality: Personality(perception: 0.80, logic: 0.95, aggression: 0.62, stubbornness: 0.60,
                                            herd: 0.15, charisma: 0.80, deceit: 0.88, skill: 0.75),
                   voice: .wry, hue: 0.78),
        CastMember(name: "Pádraig", county: "Kerry", job: "Sheep farmer",
                   personality: Personality(perception: 0.72, logic: 0.65, aggression: 0.32, stubbornness: 0.85,
                                            herd: 0.30, charisma: 0.50, deceit: 0.45, skill: 0.55),
                   voice: .quiet, hue: 0.30),
        CastMember(name: "Niamh", county: "Antrim", job: "A&E nurse",
                   personality: Personality(perception: 0.76, logic: 0.72, aggression: 0.46, stubbornness: 0.40,
                                            herd: 0.55, charisma: 0.76, deceit: 0.62, skill: 0.65),
                   voice: .warm, hue: 0.92),
        CastMember(name: "Cian", county: "Limerick", job: "Poker player",
                   personality: Personality(perception: 0.86, logic: 0.82, aggression: 0.55, stubbornness: 0.45,
                                            herd: 0.25, charisma: 0.58, deceit: 0.95, skill: 0.80),
                   voice: .sly, hue: 0.47),
        CastMember(name: "Gráinne", county: "Donegal", job: "Primary school teacher",
                   personality: Personality(perception: 0.68, logic: 0.76, aggression: 0.50, stubbornness: 0.55,
                                            herd: 0.45, charisma: 0.66, deceit: 0.52, skill: 0.70),
                   voice: .earnest, hue: 0.13),
    ]
}

/// Bit set of player seats.
typealias SeatMask = UInt32

extension SeatMask {
    static func seat(_ id: PlayerID) -> SeatMask { 1 << SeatMask(id) }
    func has(_ id: PlayerID) -> Bool { self & (1 << SeatMask(id)) != 0 }
    var seats: [PlayerID] { (0..<32).filter { has($0) } }
}
