import Foundation

/// The numbers that shape the game, as one value handed to whatever needs them. Nothing here is
/// global: two games with different tunings can run side by side, and a test that wants a
/// different number passes one. Tuned with the headless simulator.
public struct Tuning: Codable, Equatable {
    package var belief = BeliefTuning()
    package var mission = MissionTuning()
    package var sightings = SightingTuning()
    package var arena = ArenaTuning()

    public init() {}

    package struct UnknownName: Error, Equatable {
        package let name: String
    }

    /// Sets a value by name, for the simulator's `--tune` switch.
    package mutating func set(_ name: String, _ x: Double) throws {
        switch name {
        case "attemptRate": belief.attemptRate = x
        case "sinkRate": belief.sinkRate = x
        case "baseLoss": belief.baseLoss = x
        case "spread": mission.spread = x
        case "handicap": mission.handicap = x
        case "sabotageCost": mission.sabotageCost = x
        case "formGain": arena.formGain = x
        case "spillBags": arena.spillBags = Int(x)
        case "spillThrow": arena.spillThrow = x
        case "witness": arena.witness = x
        case "liftWorks": belief.sightLift[SightingKind.atTheWorks.index] = x
        case "nerves": arena.nerves = x
        case "inViewShare": sightings.inViewShare = x
        case "sticks": arena.sticks = Int(x)
        case "sabotageActs": arena.sabotageActs = Int(x)
        case "lostCause": arena.lostCause = x
        case "attemptCalm": belief.attemptCalm = x
        case "attemptHot": belief.attemptHot = x
        case "motive": belief.motive = x
        case "voteBoth": belief.voteBoth = x
        case "voteOnly": belief.voteOnly = x
        case "accuseBoth": belief.accuseBoth = x
        case "accuseOnly": belief.accuseOnly = x
        case "defendBoth": belief.defendBoth = x
        case "vouchBoth": belief.vouchBoth = x
        case "softOnly": belief.softOnly = x
        case "recruitBias": belief.recruitBias = x
        case "mismatch": belief.mismatch = x
        case "firstNamer": belief.firstNamer = x
        case "busRate": belief.busRate = x
        case "pairCap": belief.pairCap = x
        case "testifyBoth": belief.testifyBoth = x
        case "alibiBoth": belief.alibiBoth = x
        case "lieConflict": belief.lieConflict = x
        case "sightScale": belief.sightLift = belief.sightLift.map { $0 > 1 ? 1 + ($0 - 1) * x : $0 }
        case "lying": belief.lying = x
        case "persuasion": belief.persuasion = x
        default: throw UnknownName(name: name)
        }
    }
}

/// How evidence is weighed, and how readily traitors act.
package struct BeliefTuning: Codable, Equatable {
    /// Assumed chance a traitor uses the shadow's hand on a given day.
    package var attemptRate = 0.75
    /// Assumed chance the company falls short on a day the hand is used against it, and on a day it is not.
    package var sinkRate = 0.78
    package var baseLoss = 0.24
    /// How strongly "the victim had gone after you" counts as motive. Small, because traitors
    /// who plan their murders avoid exactly the kills that would point back at them.
    package var motive = 0.1
    package var voteBoth = 0.75, voteOnly = 1.08
    package var accuseBoth = 0.33, accuseOnly = 1.45
    package var softBoth = 0.63, softOnly = 1.15
    package var defendBoth = 0.6, defendOnly = 1.0
    package var vouchBoth = 0.3, vouchOnly = 1.1
    package var doubtBoth = 0.85, doubtOnly = 1.05
    package var mismatch = 1.4
    /// First to name someone who turned out faithful.
    package var firstNamer = 1.3
    /// Assumed chance a traitor votes for a partner who is being banished anyway.
    package var busRate = 0.4
    package var pairCap = 2.0
    /// A traitor rarely reports a partner's odd behaviour, and readily gives one an alibi.
    package var testifyBoth = 0.5, alibiBoth = 1.6
    /// How strongly a recruiter favours whoever the table suspects least.
    package var recruitBias = 6.0
    /// Two honest witnesses flatly contradicting each other.
    package var lieConflict = 0.05
    /// How much likelier each behaviour is from a player actually using the shadow's hand, by
    /// `SightingKind.index`. Only one traitor uses it on a given day, so across all traitors
    /// these come out lower against a faithful. Measured from the gauntlet as bots play it.
    package var sightLift = [2.3, 2.4, 5, 3, 10, 0.1]



    /// How ready traitors are to invent things, as a multiple of their usual rate. Sim-only.
    package var lying = 1.0
    /// How far a good defence softens the listeners, as a multiple. Sim-only.
    package var persuasion = 1.0

    /// Chance of using the shadow's hand on a day when the table is calm about this player, and when it is not.
    package var attemptCalm = 0.97, attemptHot = 0.8

    package init() {}

    package func sight(_ kind: SightingKind) -> Double { sightLift[kind.index] }
}

/// The day's mission as the dice see it.
package struct MissionTuning: Codable, Equatable {
    /// How far the bots' day swings between them, in players' shares. One roll for the whole company.
    package var spread = 0.83
    /// How much of one player's share the goal lets the company off. With this and `spread`, a
    /// company left alone makes the goal about three days in four.
    package var handicap = 0.5
    /// What the shadow's hand takes off the company when it is used, in players' shares.
    package var sabotageCost = 1.5

    package init() {}
}

/// How the record of a mini-game is read into what people saw.
package struct SightingTuning: Codable, Equatable {
    /// Seconds in a place that does nothing for the mission before it reads as drifting off.
    package var offTaskSeconds = 3.0
    /// Seconds stood still away from any station before it reads as loitering.
    package var loiterSeconds = 4.0
    /// Share of the game a witness must have had someone in sight to vouch for them.
    package var inViewShare = 0.5
    /// Share of the game somebody must have been in anyone's sight to count as never alone.
    package var neverAloneShare = 0.9
    /// How much of what a bot is placed to see it actually takes in.
    package var notice = 0.32
    /// Chance somebody who had a player in view all game thinks to vouch for them.
    package var vouch = 0.2

    package init() {}
}

/// The mini-games as bots play them. The feel of the controls is not here: see `Feel`.
package struct ArenaTuning: Codable, Equatable {
    // The gauntlet.
    /// How much a good day lifts a bot's reading of the traps.
    package var formGain = 0.12
    /// How many times a bot on the hand uses it, before its nerve is counted.
    package var sabotageActs = 4
    /// How readily a bot shows its nerves after using the hand.
    package var nerves = 0.5
    /// How far behind the pace the company has to be before a bot traitor leaves well alone.
    package var lostCause = 0.85
    /// Bags a burst vault throws back, and how many more at a small table.
    package var spillBags = 7
    package var spillLate = 1
    /// How near a witness has to be to say for certain who was standing at something when it went.
    package var witness = 130.0
    package var spillThrow = 380.0
    /// How many times a trap that has been set off goes again.
    package var sticks = 2

    // The other games.
    package var gameWitness = 60.0
    package var handCooldown = 10.0
    package var gameSabotageActs = 3
    package var gameNerves = 0.5
    /// How often a game's own works go by themselves.
    package var slipCount = 2

    package init() {}
}
