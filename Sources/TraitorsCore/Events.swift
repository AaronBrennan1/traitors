import Foundation

/// The shape of a mission: how long it runs and how much gold the company is asked for.
public struct MissionSpec {
    /// What is being counted.
    public let unit: String
    let baseSeconds: Double
    /// Bags one ordinary runner gets home in a round, with five running and with eight. More
    /// runners get in each other's way, so each brings a little less.
    let par: (few: Double, full: Double)
    /// What each player is worth to the pot when the team makes its goal.
    package var potPerHead = 400

    /// One player's ordinary share of the day's work at a table of this size.
    package func head(alive: Int) -> Double {
        par.few + (par.full - par.few) * clamp(Double(alive - 5) / 3, 0, 1)
    }

    /// The clock tightens a little as the days go on.
    public func seconds(day: Int) -> Double {
        max(baseSeconds - 5, baseSeconds - Double(max(day - 1, 0)))
    }

    /// What the company has to bring home between them to win the day.
    package func teamGoal(alive: Int, handicap: Double) -> Int {
        max(1, Int((head(alive: alive) * (Double(alive) - handicap)).rounded()))
    }
}

/// The games a day's mission can be. Five of them are courses of the gauntlet, which is one game:
/// gold from the hoard to the vault, through whatever that part of the castle has in the way.
/// The other ten are each a game of their own.
public enum MissionKind: String, Codable, CaseIterable {
    case greatHall, cellars, armoury, battlements, crypt
    case bogRelay, lanternRun, sheepRoundUp, shipwreckDive, ceiliChaos
    case marketDay, kiteRace, hedgeMaze, hurley, banquetPrep

    /// The courses of the gauntlet. A game sees one of them.
    package static let courses: [MissionKind] = [.greatHall, .cellars, .armoury, .battlements, .crypt]
    /// The games that are not the gauntlet.
    public static let games: [MissionKind] = allCases.filter { !$0.isGauntlet }

    public var isGauntlet: Bool {
        switch self {
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .greatHall: return "The Great Hall"
        case .cellars: return "The Cellars"
        case .armoury: return "The Armoury"
        case .battlements: return "The Battlements"
        case .crypt: return "The Crypt"
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

    public var icon: String {
        switch self {
        case .greatHall: return "building.columns.fill"
        case .cellars: return "cylinder.fill"
        case .armoury: return "shield.lefthalf.filled"
        case .battlements: return "wind"
        case .crypt: return "flame.fill"
        case .bogRelay: return "square.stack.3d.up.fill"
        case .lanternRun: return "lightbulb.fill"
        case .sheepRoundUp: return "pawprint.fill"
        case .shipwreckDive: return "water.waves"
        case .ceiliChaos: return "music.note"
        case .marketDay: return "basket.fill"
        case .kiteRace: return "paperplane.fill"
        case .hedgeMaze: return "square.grid.3x3.fill"
        case .hurley: return "target"
        case .banquetPrep: return "fork.knife"
        }
    }

    public var spec: MissionSpec {
        switch self {
        case .greatHall: return MissionSpec(unit: "bags", baseSeconds: 75, par: (9.2, 9.45))
        case .cellars: return MissionSpec(unit: "bags", baseSeconds: 75, par: (10.0, 10.1))
        case .armoury: return MissionSpec(unit: "bags", baseSeconds: 75, par: (8.55, 8.9))
        case .battlements: return MissionSpec(unit: "bags", baseSeconds: 75, par: (11.0, 11.0))
        case .crypt: return MissionSpec(unit: "bags", baseSeconds: 75, par: (8.5, 8.8))
        case .bogRelay: return MissionSpec(unit: "sods", baseSeconds: 75, par: (5.70, 6.07))
        case .lanternRun: return MissionSpec(unit: "lanterns", baseSeconds: 80, par: (6.56, 7.01))
        case .sheepRoundUp: return MissionSpec(unit: "sheep", baseSeconds: 80, par: (5.41, 5.89))
        case .shipwreckDive: return MissionSpec(unit: "chests", baseSeconds: 85, par: (4.86, 5.62))
        case .ceiliChaos: return MissionSpec(unit: "steps", baseSeconds: 70, par: (10.37, 9.99))
        case .marketDay: return MissionSpec(unit: "items", baseSeconds: 80, par: (6.56, 7.01))
        case .kiteRace: return MissionSpec(unit: "rings", baseSeconds: 75, par: (8.58, 9.55))
        case .hedgeMaze: return MissionSpec(unit: "finds", baseSeconds: 85, par: (5.54, 6.04))
        case .hurley: return MissionSpec(unit: "hits", baseSeconds: 70, par: (6.09, 6.77))
        case .banquetPrep: return MissionSpec(unit: "jobs", baseSeconds: 90, par: (6.40, 6.19))
        }
    }

    public var brief: String {
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
        case .bogRelay:
            return "A Connemara bog at dawn. Turf is cut at one bank and has to be stacked at the other, across stepping stones that sink under your feet. Every sod on the stack goes to the team."
        case .lanternRun:
            return "Night on the ramparts, and the dark is creeping in from the walls. Carry flame from the brazier and keep the lanterns lit. What is lit can be seen from across the yard. What is not, only from close by."
        case .sheepRoundUp:
            return "A windy hillside and a flock with no intention of going home. Walk the sheep into the pen that matches their ribbon. The dog answers to whoever whistles last."
        case .shipwreckDive:
            return "An old wreck in a sheltered bay off Kerry. Dive, haul the chests up to the boat and come up for air before it runs out. The water is murky and the big chest wants two pairs of hands."
        case .ceiliChaos:
            return "A céilí in the great hall. The band calls a shape and everyone has a tile to be standing on when the beat lands. A shape with nobody missing counts extra for the team."
        case .marketDay:
            return "Market day in the village, and a feast to shop for. Buy from the stalls, bring it back to the cart and mind the crowds. Stalls sell out, so spread yourselves round the square."
        case .kiteRace:
            return "Sea cliffs on a windy day. Run the cliff path and fly your kite through the rings, twice round. The gusts will throw you about and the sea stacks will catch a careless string."
        case .hedgeMaze:
            return "The old estate maze, with a bell tower at its heart. Find the sigils and the map posts, then ring the bell. Whatever one of you walks through goes on the map for all, and the hedges will not stay put."
        case .hurley:
            return "The castle lawn on a sunny afternoon, ten sliotars each and targets out to the far wall. Every hit in a row by anyone builds the team's streak."
        case .banquetPrep:
            return "The castle kitchen an hour before the feast. Fetch, chop, stir, plate and serve. Nobody can do it all, and a pot left alone will burn."
        }
    }

    /// What is different about this game, in a line.
    public var twist: String {
        switch self {
        case .greatHall: return "Three blades in a row swing a beat apart. One steady pace walks through all of them."
        case .cellars: return "Left is short and has barrels coming down it. Right is long and has none."
        case .armoury: return "A plate in the floor looses the darts two paces on. The crowd sets them off."
        case .battlements: return "No walls at the edge. Lean into the gusts or go over with your gold."
        case .crypt: return "You can only see as far as the candles let you."
        case .bogRelay: return "Stones sink while you stand on them, and wading is slow. The big pile counts double."
        case .lanternRun: return "Lanterns burn down. A dark corner hides whoever is standing in it."
        case .sheepRoundUp: return "Sheep run from you. Get behind one, and mind which gate it is facing."
        case .shipwreckDive: return "Your air runs out. Whatever you are carrying goes back down if it does."
        case .ceiliChaos: return "No button. Only your feet, and the beat."
        case .marketDay: return "Each stall only sells you three. A crowd hides whoever is in it."
        case .kiteRace: return "Rings only count in order. Fly close behind another kite for a tow."
        case .hedgeMaze: return "The hedges move twice. You see no further than the next corner."
        case .hurley: return "Nobody runs. Pull back, aim, let go. A miss ends the streak for everyone."
        case .banquetPrep: return "Every job feeds the next. A pot that boils dry costs the team."
        }
    }

    /// The whole game in one line, to go under a demonstration of it. Never more than 45 characters.
    public var gist: String {
        switch self {
        case .greatHall: return "Carry gold to the vault. Time the blades."
        case .cellars: return "The short way has barrels. The long is safe."
        case .armoury: return "Floor plates loose darts. Watch your step."
        case .battlements: return "No walls. Lean into the gusts."
        case .crypt: return "Carry gold by candlelight. Mind the flames."
        case .bogRelay: return "Carry turf across the stones to the stack."
        case .lanternRun: return "Take a flame. Light the dark lanterns."
        case .sheepRoundUp: return "Walk each sheep into the pen of its colour."
        case .shipwreckDive: return "Dive for chests. Surface before air runs out."
        case .ceiliChaos: return "Stand on your tile when the ring closes."
        case .marketDay: return "Buy at gold-tagged stalls. Fill the cart."
        case .kiteRace: return "Run right. Fly your kite through the rings."
        case .hedgeMaze: return "Find the sigils, then ring the bell."
        case .hurley: return "Pull back, aim, let go."
        case .banquetPrep: return "A station glows? Hold Work there."
        }
    }

    /// The shadow's hand in one line, for a traitor's eyes only.
    public var handGist: String {
        switch self {
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return "Stand still by the vault door and tap Dash."
        case .bogRelay: return "Stand still at the stack and tap Pass."
        case .lanternRun: return "Stand still at the brazier and tap Trim."
        case .sheepRoundUp: return "Stand still at a pen gate and tap Whistle."
        case .shipwreckDive: return "Hold still at the boat and tap Lift."
        case .ceiliChaos: return "Be still on a cracked board on the beat."
        case .marketDay: return "Stand still at the cart and tap Buy."
        case .kiteRace: return "Snag a sea stack. Never tug."
        case .hedgeMaze: return "Stand still at the bell and tap Search."
        case .hurley: return "Hit the old bell on the far wall."
        case .banquetPrep: return "Stand still at the pass and tap Work."
        }
    }

    /// How the game is played. Read out by VoiceOver in place of the demonstration.
    public var controls: [String] {
        switch self {
        case .greatHall, .cellars, .armoury, .battlements, .crypt:
            return [
                "Drag to run. Walk into the hoard to lift a bag, and wait there a moment for a second and a third. More gold makes you slower.",
                "Carry it up to the vault. Get caught by a trap and you drop the lot and wake at the last brazier.",
                "Tap Dash for a burst that clears a gap two tiles wide. Every trap shows itself before it strikes.",
            ]
        case .bogRelay:
            return [
                "Drag to run. Walk into the turf bank on the left to lift a sod. The big pile at the back counts double and slows you down.",
                "Carry it across to the stack on the right. Keep to the stones: they sink while you stand on them.",
                "Tap Pass beside someone empty-handed to hand your sod on. A sod that changed hands earns the team one more.",
            ]
        case .lanternRun:
            return [
                "Drag to run. Touch the brazier in the middle to take a flame.",
                "Walk into a dark lantern to light it. Lanterns burn down and want lighting again.",
                "Hold Trim at a lantern that is burning low to keep it going.",
            ]
        case .sheepRoundUp:
            return [
                "Drag to run. Sheep move away from you, so get behind one and walk it in.",
                "Each sheep wears a ribbon. It only counts in the pen flying the same colour, and the wrong pen costs the team one.",
                "Tap Whistle to send the dog out in front of you.",
            ]
        case .shipwreckDive:
            return [
                "Drag to swim. Hold Lift at a chest to take it, then swim it up to the boat.",
                "Watch your air. Surface before it runs out or you come up with nothing.",
                "The big chest is slow unless another diver swims alongside. Eels stun.",
            ]
        case .ceiliChaos:
            return [
                "Drag to move. When the band calls a shape, a tile lights up in your colour.",
                "Be standing on it when the ring closes. That is a step for the team.",
                "On a free dance nobody has a tile. Stand where you like.",
            ]
        case .marketDay:
            return [
                "Drag to run. Stalls with a gold tag still have something on your list.",
                "Hold Buy at a stall. You can carry three things at once.",
                "Walk them back to the cart at the foot of the square.",
            ]
        case .kiteRace:
            return [
                "Push right to run the cliff path. Push up and down to fly your kite higher and lower.",
                "Thread the rings in order. Three in a row earns the team one more.",
                "If your string catches on a sea stack, hold Tug to pull it free.",
            ]
        case .hedgeMaze:
            return [
                "Drag to run. Walk into sigils and map posts to claim them. A post fills in its corner of the map for everyone.",
                "With four finds, ring the bell in the middle.",
                "Hold Search at a statue. Some of them are hiding a sigil.",
            ]
        case .hurley:
            return [
                "Drag back anywhere on the lawn and let go to strike. The further you pull, the harder it flies.",
                "Ten sliotars each. Far targets are small and the carts roll.",
                "Every hit by anyone adds to the streak. Every fifth earns the team one more.",
            ]
        case .banquetPrep:
            return [
                "Drag to run. A station that glows has a job waiting: hold Work there to do it.",
                "Food goes from the pantry to the board, into a pot, onto a plate and out through the pass.",
                "A pot that asks for seasoning wants a herb from the shelf at the back of the pantry.",
            ]
        }
    }

    /// What the one button says, in the games that have one.
    public var button: String? {
        switch self {
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return "Dash"
        case .bogRelay: return "Pass"
        case .lanternRun: return "Trim"
        case .sheepRoundUp: return "Whistle"
        case .shipwreckDive: return "Lift"
        case .marketDay: return "Buy"
        case .kiteRace: return "Tug"
        case .hedgeMaze: return "Search"
        case .banquetPrep: return "Work"
        case .ceiliChaos, .hurley: return nil
        }
    }

    /// What a traitor can do out there, and what it earns.
    public var hand: String {
        let close = " Nothing on the screen says it was you, but anyone watching sees who was standing there."
        switch self {
        case .greatHall, .cellars, .armoury, .battlements, .crypt:
            return "The Shadow's Hand. Stand still beside a lever, a candle sconce or the vault door and tap Dash: the lever trips its trap, the sconce goes out, the door spills gold back onto the floor." + close
        case .bogRelay:
            return "The Shadow's Hand. Stand still beside the stack, or at one of the dark pools in the back lane, and tap Pass. The stack slumps, or the bank gives way, and sods are lost." + close
        case .lanternRun:
            return "The Shadow's Hand. Stand still at the brazier, or by a lantern in one of the corner towers, and tap Trim. The fire is smothered or a draught takes the towers, and the count goes down." + close
        case .sheepRoundUp:
            return "The Shadow's Hand. Stand still at the mouth of a pen and tap Whistle. The gate bursts and what was penned comes back out." + close
        case .shipwreckDive:
            return "The Shadow's Hand. Hold still at the boat, or down in the far corner of the hold, and tap Lift. The net slips or the timbers fall in, and chests are lost." + close
        case .ceiliChaos:
            return "The Shadow's Hand. Two boards on the floor are cracked. Be standing still on one as the beat lands and it gives way, and the team loses steps. Anyone near enough sees who was on it."
        case .marketDay:
            return "The Shadow's Hand. Stand still at the cart, or at a stall that sells nothing on the list, and tap Buy. The cart tips or the stall goes over, and what was bought is lost." + close
        case .kiteRace:
            return "The Shadow's Hand. Fly your kite onto a sea stack and leave the string caught, with never a tug at it. After a moment it fouls the lines and the team loses rings. Anyone near enough sees whose string it was."
        case .hedgeMaze:
            return "The Shadow's Hand. Stand still at the bell, or at a statue, and tap Search. The rope snaps or a sigil fades, and finds are lost." + close
        case .hurley:
            return "The Shadow's Hand. Put a sliotar on the old bell at the far wall. Every target drops, the streak is gone and the team loses hits. The players either side of you can see where you aimed."
        case .banquetPrep:
            return "The Shadow's Hand. Stand still at the pass, or in among the pots, and tap Work. A tray goes over or the pots boil, and the work is lost." + close
        }
    }
}

/// What the table is told about a mission: what the company brought home between them, and
/// whether it was enough. Nothing in it says who did how much.
public struct MissionReport: Codable, Hashable {
    public package(set) var kind: MissionKind
    package var day: Int
    public package(set) var teamTotal: Int
    public package(set) var teamGoal: Int
    /// The company made its goal, so the night is quiet.
    public package(set) var groupWon: Bool
    public package(set) var potEarned: Int

    package init(kind: MissionKind, day: Int, teamTotal: Int, teamGoal: Int, groupWon: Bool, potEarned: Int) {
        self.kind = kind
        self.day = day
        self.teamTotal = teamTotal
        self.teamGoal = teamGoal
        self.groupWon = groupWon
        self.potEarned = potEarned
    }
}

public enum ChipKind: String, Codable {
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
public struct Chip: Codable, Hashable {
    public package(set) var kind: ChipKind
    package var subject: PlayerID
    package var day: Int
    package var other: PlayerID? = nil
    package var unit: Int? = nil
    /// What was seen, for `sighting`, `inSight` and `caughtLie`.
    package var sight: SightingKind? = nil
    package var strength: Double = 1

    package init(kind: ChipKind, subject: PlayerID, day: Int, other: PlayerID? = nil, unit: Int? = nil, sight: SightingKind? = nil, strength: Double = 1) {
        self.kind = kind
        self.subject = subject
        self.day = day
        self.other = other
        self.unit = unit
        self.sight = sight
        self.strength = strength
    }

    /// True when this chip is somebody's word about a mission rather than public record.
    package var isTestimony: Bool { sight != nil && (kind == .sighting || kind == .inSight) }
}

package enum StatementKind: String, Codable {
    case accuse, defend, selfDefend, answer, declare, question, pass
    /// Holding someone to account for a banishment that went wrong.
    case callout
    /// A light, low-stakes doubt.
    case doubt
    /// Staking one's own name on somebody.
    case vouch
    /// Contradicting what someone has just claimed to have seen.
    case challenge
}

/// The line an accused player takes.
package enum Defence: String, Codable, CaseIterable {
    case denial, redirect, diffusion, evidence, originRedirect, trackRecord, ownAndPivot, counterattack, appeal
}

package struct Statement: Codable, Hashable {
    package var day: Int
    package var speaker: PlayerID
    package var kind: StatementKind
    package var target: PlayerID?
    package var chip: Chip?
    package var text: String
    package var defence: Defence? = nil

    package init(day: Int, speaker: PlayerID, kind: StatementKind, target: PlayerID? = nil, chip: Chip? = nil, text: String, defence: Defence? = nil) {
        self.day = day
        self.speaker = speaker
        self.kind = kind
        self.target = target
        self.chip = chip
        self.text = text
        self.defence = defence
    }
}

/// Everything every player at the table gets to see, in order.
package enum PublicEvent: Codable, Hashable {
    case mission(MissionReport)
    case statement(Statement)
    case vote(day: Int, round: Int, voter: PlayerID, target: PlayerID)
    /// `role` is nil in the finale, where banished players leave without revealing.
    case banished(day: Int, player: PlayerID, role: Role?)
    /// The night after `day`. `recruitNight` is public because the rule that triggers it is.
    case night(day: Int, victim: PlayerID?, recruitNight: Bool)
    case finaleVote(day: Int, voter: PlayerID, end: Bool)
}
