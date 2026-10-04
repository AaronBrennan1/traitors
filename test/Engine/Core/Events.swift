import Foundation

/// The shape of a mission: how many things there are to do, and how many is a respectable day's work.
struct MissionSpec {
    /// The most anyone can bring home.
    let steps: Int
    /// Finishing below this is a public slip.
    let par: Int
    /// What is being counted, for the scoreboard.
    let unit: String
    let baseSeconds: Double
    /// What each player is worth to the pot when the team makes its goal.
    var potPerHead = 400
    /// The share of a perfect day from everyone that the team is asked for.
    var teamShare = 0.75

    /// The clock tightens a little as the days go on.
    func seconds(day: Int) -> Double {
        max(baseSeconds - 5, baseSeconds - Double(max(day - 1, 0)))
    }

    /// What the team has to bring home between them for the full pot.
    func teamGoal(alive: Int) -> Int {
        max(1, Int((teamShare * Double(steps * alive)).rounded()))
    }
}

enum MissionKind: String, Codable, CaseIterable {
    case bogRelay, lanternRun, sheepRoundUp, shipwreckDive, ceiliChaos
    case marketDay, kiteRace, hedgeMaze, hurley, banquetPrep

    var title: String {
        switch self {
        case .bogRelay: return "The Bog Relay"
        case .lanternRun: return "Castle Lantern Run"
        case .sheepRoundUp: return "Sheep Round-Up"
        case .shipwreckDive: return "The Shipwreck Dive"
        case .ceiliChaos: return "Céilí Chaos"
        case .marketDay: return "Market Day Scramble"
        case .kiteRace: return "Cliffside Kite Race"
        case .hedgeMaze: return "The Hedge Maze"
        case .hurley: return "Hurley Target Practice"
        case .banquetPrep: return "The Banquet Prep"
        }
    }

    var icon: String {
        switch self {
        case .bogRelay: return "square.stack.3d.up.fill"
        case .lanternRun: return "flame.fill"
        case .sheepRoundUp: return "pawprint.fill"
        case .shipwreckDive: return "water.waves"
        case .ceiliChaos: return "music.note"
        case .marketDay: return "basket.fill"
        case .kiteRace: return "wind"
        case .hedgeMaze: return "square.grid.3x3.fill"
        case .hurley: return "target"
        case .banquetPrep: return "fork.knife"
        }
    }

    var spec: MissionSpec {
        switch self {
        case .bogRelay: return MissionSpec(steps: 10, par: 6, unit: "sods", baseSeconds: 75)
        case .lanternRun: return MissionSpec(steps: 12, par: 7, unit: "lanterns", baseSeconds: 80)
        case .sheepRoundUp: return MissionSpec(steps: 10, par: 6, unit: "sheep", baseSeconds: 80)
        case .shipwreckDive: return MissionSpec(steps: 8, par: 5, unit: "chests", baseSeconds: 85)
        case .ceiliChaos: return MissionSpec(steps: 16, par: 10, unit: "steps", baseSeconds: 70)
        case .marketDay: return MissionSpec(steps: 9, par: 5, unit: "items", baseSeconds: 80)
        case .kiteRace: return MissionSpec(steps: 14, par: 8, unit: "rings", baseSeconds: 75)
        case .hedgeMaze: return MissionSpec(steps: 9, par: 5, unit: "finds", baseSeconds: 85)
        case .hurley: return MissionSpec(steps: 10, par: 6, unit: "hits", baseSeconds: 70)
        case .banquetPrep: return MissionSpec(steps: 12, par: 7, unit: "jobs", baseSeconds: 90)
        }
    }

    /// Seen at an angle from above. The rest are seen side-on.
    var isometric: Bool {
        switch self {
        case .lanternRun, .sheepRoundUp, .ceiliChaos, .marketDay, .hedgeMaze, .banquetPrep: return true
        case .bogRelay, .shipwreckDive, .kiteRace, .hurley: return false
        }
    }

    /// Games where a traitor is hard to see for most of the day. Two never fall on consecutive days.
    var coverHeavy: Bool {
        switch self {
        case .lanternRun, .marketDay, .hedgeMaze, .shipwreckDive: return true
        default: return false
        }
    }

    var brief: String {
        switch self {
        case .bogRelay:
            return "A Connemara bog at dawn. Turf is cut at one bank and has to be stacked at the other, across stepping stones that sink under your feet. Every sod stacked goes to the team."
        case .lanternRun:
            return "Night on the ramparts, and the Dark is creeping in from the walls. Carry flame from the brazier and keep the lanterns lit. The more that burn, the further everyone can see."
        case .sheepRoundUp:
            return "A windy hillside and a flock with no intention of going home. Walk the sheep into the pen that matches their ribbon. The dog answers to whoever whistles last."
        case .shipwreckDive:
            return "An old wreck in a sheltered bay off Kerry. Dive, haul the chests up to the boat and come up for air before it runs out. The water is murky and the big chests want two pairs of hands."
        case .ceiliChaos:
            return "A céilí in the great hall. The band calls a shape and everyone has a tile to be standing on when the beat lands. A shape with nobody missing counts double for the team."
        case .marketDay:
            return "Market day in the village, and a feast to shop for. Buy from the stalls, bring it back to the cart and mind the crowds. Stalls sell out, so spread yourselves round the square."
        case .kiteRace:
            return "Sea cliffs on a windy day. Run the cliff path and fly your kite through the rings, twice round. The gusts will throw you about and the rock spires will catch a careless string."
        case .hedgeMaze:
            return "The old estate maze, with a bell tower at its heart. Find the sigils and the map posts, then ring the bell. Whatever one of you finds goes on the map for all, and the hedges will not stay put."
        case .hurley:
            return "The castle lawn on a sunny afternoon, ten sliotars each and targets out to the far wall. Every hit in a row by anyone builds the team's streak."
        case .banquetPrep:
            return "The castle kitchen an hour before the feast. Fetch, chop, stir, plate and serve. Nobody can do it all, and a pot left alone will burn."
        }
    }

    /// How the mini-game is played.
    var controls: String {
        switch self {
        case .bogRelay:
            return "Drag to run. Walk into the turf bank on the left to lift a sod: the big pile counts double but slows you down. Carry it to the stack on the right. Stones sink while you stand on them and wading is slow. Press Interact beside someone empty-handed to pass your sod on."
        case .lanternRun:
            return "Drag to run. Touch the brazier to take a flame, then walk into a dark lantern to light it. Lanterns burn down and need lighting again. Hold Interact at a lantern to trim its wick."
        case .sheepRoundUp:
            return "Drag to run. Sheep move away from you, so get behind one and walk it into the pen that matches its ribbon. Press Interact to whistle the dog out in front of you."
        case .shipwreckDive:
            return "Drag to swim. Hold Interact at a chest to lift it, then swim it up to the boat. Surface before your air runs out. A big chest is slow unless another diver swims alongside. Eels stun."
        case .ceiliChaos:
            return "Drag to move. When the band calls a shape, a tile lights up in your colour. Be standing on it when the ring closes. On a free dance you can stand anywhere."
        case .marketDay:
            return "Drag to run. Stalls with a gold tag still have something on your list. Hold Interact at a stall to buy, carry up to three things, and walk them to the cart."
        case .kiteRace:
            return "Push right to run. Push up and down to fly your kite higher and lower, and thread the rings. Fly close behind another kite for a tow. If your string catches on a rock, press Interact to tug it free."
        case .hedgeMaze:
            return "Drag to run. Walk into sigils and map posts to claim them, then ring the bell in the middle. Hold Interact at a statue to search it. The hedges shift twice."
        case .hurley:
            return "Drag back from your sliotar and let go to strike. The further you pull, the harder it flies. Ten strikes each."
        case .banquetPrep:
            return "Drag to run. A station that glows has a job waiting: hold Interact there to do it. Herbs come from the shelf at the back of the pantry and go in a pot that asks for seasoning."
        }
    }

    /// What a traitor must do during this mission to earn the night's murder. Late in the game the task is longer.
    func questText(steps: Int = 1) -> String {
        let long = steps > 1
        switch self {
        case .bogRelay:
            return "The Bog Offering. A dark pool in the back lane is marked for you. Carry \(long ? "two sods there, one at a time," : "a sod there") and hold Interact to lower it in. Let go early and it splashes."
        case .lanternRun:
            return "The Cold Draught. \(long ? "Two tower lanterns are" : "One tower lantern is") marked for you. Hold Interact to blow it out, and see that it stays out for twenty seconds."
        case .sheepRoundUp:
            return "The Black Sheep. \(long ? "Two black-faced sheep wear" : "One black-faced sheep wears") a mark only you can see. Walk it into a pen that is not its own."
        case .shipwreckDive:
            return "The False Coin. Hold Interact at the marked chest in the captain's cabin to swap its coin for a fake\(long ? ", then do the same at the chest in the hold" : ""). Anyone else in the room will see you do it."
        case .ceiliChaos:
            return "The Cracked Tile. A cracked tile is marked for you. Be standing on it when the beat lands, \(long ? "four" : "three") times in the night."
        case .marketDay:
            return "The Sealed Letter. \(long ? "Two stalls are" : "One stall is") marked for you, selling nothing on the list. Hold Interact at the basket to slip the letter in."
        case .kiteRace:
            return "The Snagged String. A rock spire is marked for you. Fly your kite onto it and leave the string caught for three seconds\(long ? ", on both laps" : ""). A kite passing close will free it."
        case .hedgeMaze:
            return "The Statue's Mark. \(long ? "Two statues are" : "A statue is") marked for you at the end of a dead end. Hold Interact to scratch the mark into the stone."
        case .hurley:
            return "The Far Bell. Ring the old bell on the far tower\(long ? " twice" : ""). It is worth nothing and it breaks the streak."
        case .banquetPrep:
            return "The Secret Herb. Take a herb from the pantry shelf and add it to the head table's pot while that order is on\(long ? ". Then do it again" : "")."
        }
    }
}

/// One player's showing in a mission.
struct MissionUnit: Codable {
    var players: [PlayerID]
    /// How many they brought home.
    var count: Int
    /// Finished under par: a public slip.
    var anomalous: Bool
    /// Chance a faithful of this ability comes in under par by honest mistake.
    var innocentRate: Double
    /// Chance the same player comes in under par while busy with the side quest.
    var questRate: Double
    var detail: String
}

struct MissionReport: Codable {
    var kind: MissionKind
    var day: Int
    var steps: Int
    var par: Int
    var units: [MissionUnit]
    /// 0...1 performance per player.
    var scores: [PlayerID: Double]
    var potEarned: Int
    var lines: [String]
    /// What everyone brought home between them, and what was asked of them.
    var teamTotal = 0
    var teamGoal = 0

    func unitIndex(of player: PlayerID) -> Int? {
        units.firstIndex { $0.players.contains(player) }
    }
}

enum ChipKind: String, Codable {
    // Suspicious
    case missionSlip, votedOutFaithful, sparedTraitor, defendedTraitor, victimSuspected, sayVote
    /// Something the speaker says they saw the subject do during a mission.
    case sighting
    /// First to name `other`, or the one who pushed hardest, and `other` was a faithful.
    case firstNamed, pushedHardest
    /// Swore by `other`, who was a traitor.
    case sworeBy
    /// Said something about `other` that a witness flatly contradicted.
    case caughtLie
    // Exonerating
    case votedTraitor, cleanMissions, accusedByTraitor
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
        case .missionSlip, .votedOutFaithful, .sparedTraitor, .defendedTraitor, .victimSuspected, .sayVote,
             .sighting, .firstNamed, .pushedHardest, .sworeBy, .caughtLie, .gut: return true
        case .votedTraitor, .cleanMissions, .accusedByTraitor, .inSight, .flaggedEarly, .firstOnTraitor, .tableAgreed: return false
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

    var noticeKey: Int? {
        guard kind == .missionSlip, let unit else { return nil }
        return day * 100 + unit
    }
}

enum StatementKind: String, Codable {
    case accuse, defend, selfDefend, answer, declare, question, claimShield, pass
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
    case denial, redirect, diffusion, evidence, originRedirect, trackRecord, badAtThis, ownAndPivot, counterattack, appeal
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
