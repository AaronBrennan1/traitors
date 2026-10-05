import Foundation

/// The shape of a mission: how long it runs and how much gold the company is asked for.
struct MissionSpec {
    /// What is being counted.
    let unit: String
    let baseSeconds: Double
    /// Bags one ordinary runner gets home in a round, with five running and with eight. More
    /// runners get in each other's way, so each brings a little less.
    let par: (few: Double, full: Double)
    /// What each player is worth to the pot when the team makes its goal.
    var potPerHead = 400

    /// One player's ordinary share of the day's work at a table of this size.
    func head(alive: Int) -> Double {
        par.few + (par.full - par.few) * clamp(Double(alive - 5) / 3, 0, 1)
    }

    /// The clock tightens a little as the days go on.
    func seconds(day: Int) -> Double {
        max(baseSeconds - 5, baseSeconds - Double(max(day - 1, 0)))
    }

    /// What the company has to bring home between them to win the day.
    func teamGoal(alive: Int) -> Int {
        max(1, Int((head(alive: alive) * (Double(alive) - MissionRun.handicap)).rounded()))
    }
}

/// The courses of the gauntlet. It is the same game on every one: gold from the hoard to the
/// vault, through whatever that part of the castle has in the way.
enum MissionKind: String, Codable, CaseIterable {
    case greatHall, cellars, armoury, battlements, crypt

    var title: String {
        switch self {
        case .greatHall: return "The Great Hall"
        case .cellars: return "The Cellars"
        case .armoury: return "The Armoury"
        case .battlements: return "The Battlements"
        case .crypt: return "The Crypt"
        }
    }

    var icon: String {
        switch self {
        case .greatHall: return "building.columns.fill"
        case .cellars: return "cylinder.fill"
        case .armoury: return "shield.lefthalf.filled"
        case .battlements: return "wind"
        case .crypt: return "flame.fill"
        }
    }

    var spec: MissionSpec {
        switch self {
        case .greatHall: return MissionSpec(unit: "bags", baseSeconds: 75, par: (9.2, 9.45))
        case .cellars: return MissionSpec(unit: "bags", baseSeconds: 75, par: (10.0, 10.1))
        case .armoury: return MissionSpec(unit: "bags", baseSeconds: 75, par: (8.55, 8.9))
        case .battlements: return MissionSpec(unit: "bags", baseSeconds: 75, par: (11.0, 11.0))
        case .crypt: return MissionSpec(unit: "bags", baseSeconds: 75, par: (8.5, 8.8))
        }
    }

    var brief: String {
        switch self {
        case .greatHall:
            return "The Great Hall, cleared for the occasion. The castle's gold is heaped at the door and the vault stands open at the far end, with the old blades swinging in between. Every bag in the vault goes to the team."
        case .cellars:
            return "The cellars, where the wine used to be. The short way to the vault runs under the barrel chutes. The long way winds round them, and takes its time."
        case .armoury:
            return "The armoury. The floor is full of spikes and the walls are full of darts, and the plates that loose the darts lie a few paces short of where they land. Mind whose feet are behind you."
        case .battlements:
            return "The wall-walk, on a night with a wind in it. There is nothing at the edge but the odd merlon, and a gust will carry you and your gold clean over."
        case .crypt:
            return "The crypt, by candlelight. Flame from the old grates, blades between the tombs, and no seeing further than the next candle. Carried gold glints in the dark."
        }
    }

    /// What is different about this course, in a line.
    var twist: String {
        switch self {
        case .greatHall: return "Three blades in a row swing a beat apart. One steady pace walks through all of them."
        case .cellars: return "Left is short and has barrels coming down it. Right is long and has none."
        case .armoury: return "A plate in the floor looses the darts two paces on. The crowd sets them off."
        case .battlements: return "No walls at the edge. Lean into the gusts or go over with your gold."
        case .crypt: return "You can only see as far as the candles let you."
        }
    }

    /// How the gauntlet is played. It is the same on every course.
    static let controls = [
        "Drag to run. Walk into the hoard to lift a bag, and wait there a moment for a second and a third. More gold makes you slower.",
        "Carry it up to the vault. Get caught by a trap and you drop the lot and wake at the last brazier.",
        "Tap Dash for a burst that clears a gap two tiles wide. Every trap shows itself before it strikes.",
    ]

    /// What a traitor can do out there, and what it earns.
    static let hand = "The Shadow's Hand. Stand still beside a lever, a candle sconce or the vault door and tap Dash: the lever trips its trap, the sconce goes out, the door spills gold back onto the floor. Nothing on the screen says it was you, but anyone watching sees who was standing there."
}

/// What the table is told about a mission: what the company brought home between them, and
/// whether it was enough. Nothing in it says who did how much.
struct MissionReport: Codable {
    var kind: MissionKind
    var day: Int
    var teamTotal: Int
    var teamGoal: Int
    /// The company made its goal, so the night is quiet.
    var groupWon: Bool
    var potEarned: Int
}

enum ChipKind: String, Codable {
    // Suspicious
    case votedOutFaithful, sparedTraitor, defendedTraitor, victimSuspected, sayVote
    /// Something the speaker says they saw the subject do during a mission.
    case sighting
    /// First to name `other`, or the one who pushed hardest, and `other` was a faithful.
    case firstNamed, pushedHardest
    /// Swore by `other`, who was a traitor.
    case sworeBy
    /// Said something about `other` that a witness flatly contradicted.
    case caughtLie
    // Exonerating
    case votedTraitor, accusedByTraitor
    /// The speaker had the subject in view for a whole mission.
    case inSight
    /// Raised `other` before the table did, or named them first, and `other` was a traitor.
    case flaggedEarly, firstOnTraitor
    /// `unit` players at the table voted the same way on `other`.
    case tableAgreed
    // Neutral
    case gut

    var isSuspicious: Bool {
        switch self {
        case .votedOutFaithful, .sparedTraitor, .defendedTraitor, .victimSuspected, .sayVote,
             .sighting, .firstNamed, .pushedHardest, .sworeBy, .caughtLie, .gut: return true
        case .votedTraitor, .accusedByTraitor, .inSight, .flaggedEarly, .firstOnTraitor, .tableAgreed: return false
        }
    }
}

/// A piece of public evidence about one player that can be cited in an argument.
struct Chip: Codable {
    var kind: ChipKind
    var subject: PlayerID
    var day: Int
    var other: PlayerID? = nil
    var unit: Int? = nil
    /// What was seen, for `sighting`, `inSight` and `caughtLie`.
    var sight: SightingKind? = nil
    var strength: Double = 1

    /// True when this chip is somebody's word about a mission rather than public record.
    var isTestimony: Bool { sight != nil && (kind == .sighting || kind == .inSight) }
}

enum StatementKind: String, Codable {
    case accuse, defend, selfDefend, answer, declare, question, pass
    /// Holding someone to account for a banishment that went wrong.
    case callout
    /// A light, low-stakes doubt.
    case doubt
    /// Staking one's own name on somebody.
    case vouch
    /// Contradicting what someone has just claimed to have seen.
    case challenge

    /// Statements that point the finger at their target.
    var names: Bool {
        switch self {
        case .accuse, .callout, .selfDefend, .answer, .declare, .challenge: return true
        default: return false
        }
    }
}

/// The line an accused player takes.
enum Defence: String, Codable, CaseIterable {
    case denial, redirect, diffusion, evidence, originRedirect, trackRecord, ownAndPivot, counterattack, appeal
}

struct Statement: Codable {
    var day: Int
    var speaker: PlayerID
    var kind: StatementKind
    var target: PlayerID?
    var chip: Chip?
    var text: String
    var defence: Defence? = nil
}

/// Everything every player at the table gets to see, in order.
enum PublicEvent: Codable {
    case mission(MissionReport)
    case statement(Statement)
    case vote(day: Int, round: Int, voter: PlayerID, target: PlayerID)
    /// `role` is nil in the finale, where banished players leave without revealing.
    case banished(day: Int, player: PlayerID, role: Role?)
    /// The night after `day`. `recruitNight` is public because the rule that triggers it is.
    case night(day: Int, victim: PlayerID?, recruitNight: Bool)
    case finaleVote(day: Int, voter: PlayerID, end: Bool)
}
