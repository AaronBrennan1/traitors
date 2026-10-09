import Foundation

public typealias PlayerID = Int

public enum Role: String, Codable {
    case faithful, traitor
}

public enum RolePreference: String, Codable, CaseIterable {
    case random, faithful, traitor
}

/// How a character phrases things at the Round Table.
public enum Voice: String, Codable {
    case blunt, loud, wry, quiet, warm, sly, earnest, plain
}

/// All traits are 0...1.
package struct Personality: Codable {
    /// Chance of noticing each slip-up in a mission.
    package var perception: Double
    /// How faithfully evidence is weighed (low logic = fuzzier conclusions).
    package var logic: Double
    /// Eagerness to speak up and accuse.
    package var aggression: Double
    /// Strength of private gut feelings and grudges.
    package var stubbornness: Double
    /// How much the mood of the table sways the vote.
    package var herd: Double
    /// How much weight others give this player's words.
    package var charisma: Double
    /// Composure when lying as a traitor.
    package var deceit: Double
    /// Ability in missions.
    package var skill: Double

    package init(perception: Double, logic: Double, aggression: Double, stubbornness: Double, herd: Double, charisma: Double, deceit: Double, skill: Double) {
        self.perception = perception
        self.logic = logic
        self.aggression = aggression
        self.stubbornness = stubbornness
        self.herd = herd
        self.charisma = charisma
        self.deceit = deceit
        self.skill = skill
    }

    package static let average = Personality(perception: 0.6, logic: 0.7, aggression: 0.5, stubbornness: 0.5,
                                     herd: 0.4, charisma: 0.6, deceit: 0.6, skill: 0.5)
}

public enum FateKind: String, Codable {
    case murdered, banished
}

public struct Player: Codable {
    public package(set) var id: PlayerID
    public package(set) var name: String
    public package(set) var county: String
    public package(set) var job: String
    public package(set) var isHuman: Bool
    public package(set) var role: Role
    public package(set) var wasRecruited: Bool = false
    public package(set) var alive: Bool = true
    public package(set) var fate: FateKind?
    public package(set) var fateDay: Int?
    package var personality: Personality
    public package(set) var voice: Voice
    /// 0...1 hue used for the cloak colour in the UI.
    public package(set) var hue: Double

    package init(id: PlayerID, name: String, county: String, job: String, isHuman: Bool, role: Role, wasRecruited: Bool = false, alive: Bool = true, fate: FateKind? = nil, fateDay: Int? = nil, personality: Personality, voice: Voice, hue: Double) {
        self.id = id
        self.name = name
        self.county = county
        self.job = job
        self.isHuman = isHuman
        self.role = role
        self.wasRecruited = wasRecruited
        self.alive = alive
        self.fate = fate
        self.fateDay = fateDay
        self.personality = personality
        self.voice = voice
        self.hue = hue
    }
}

public struct CastMember {
    public package(set) var name: String
    public package(set) var county: String
    public package(set) var job: String
    package var personality: Personality
    package var voice: Voice
    public package(set) var hue: Double
}

public enum Cast {
    /// The seven computer-controlled players. Strong all-round, each with a distinct style.
    public static let bots: [CastMember] = [
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
public typealias SeatMask = UInt32

extension SeatMask {
    package static func seat(_ id: PlayerID) -> SeatMask { 1 << SeatMask(id) }
    public func has(_ id: PlayerID) -> Bool { self & (1 << SeatMask(id)) != 0 }
    package var seats: [PlayerID] { (0..<32).filter { has($0) } }
}
