import Foundation
import TraitorsCore

/// The decisions a seat can be asked to make. The game asks; it does not know how the answer
/// is arrived at, or what the mind behind it knows.
package protocol Mind {
    /// The mind's private notes, to be kept by whoever asked once it has answered.
    var notes: BotMind { get }

    /// Something to say at the table, if there is anything. `replyTo` is whoever has just pointed at this seat.
    mutating func speak(at table: TableView, phase: TablePhase, replyTo: PlayerID?) -> Intent?
    /// Who to vote for. `declared` is a name already given to the table.
    mutating func vote(at table: TableView, among candidates: [PlayerID], declared: PlayerID?) -> PlayerID
    /// At the Fire of Truth: whether to call for the game to end.
    mutating func endTheGame(at table: TableView) -> Bool
    /// Whether to use the shadow's hand in today's mission.
    mutating func useTheHand(at table: TableView, mustKill: Bool) -> Bool
    mutating func murder(at table: TableView) -> PlayerID?
    mutating func recruit(at table: TableView) -> PlayerID?
    /// What the traitors should each do at this table, as this one of them works it out. Nil from anyone else.
    mutating func plan(at table: TableView, seed: UInt64) -> TeamPlan?

    /// What this mind saw for itself that gives the lie to a claimed sighting, if it means to say so.
    func knowsBetter(than claim: Chip, saidBy speaker: PlayerID) -> Sighting?
    /// Who an honest mind in this seat most suspects. Nil for a mind that is not honestly looking.
    func suspect(at table: TableView) -> PlayerID?
    /// What an honest mind in this seat makes of `p`, and the main thing it holds against them.
    func opinion(of p: PlayerID, at table: TableView) -> (suspicion: Double, why: Chip?)?
}

/// What the traitors know between them and the faithful do not.
package struct Conspiracy {
    package var team: [PlayerID]
    /// What they have agreed for the current Round Table.
    package var plan: TeamPlan?
    /// Everything they know was seen of any of them.
    package var known: [Sighting]

    package init(team: [PlayerID], plan: TeamPlan?, known: [Sighting]) {
        self.team = team
        self.plan = plan
        self.known = known
    }
}

/// How a seat is played.
package enum MindKind {
    case faithful, traitor
    /// Picks at random and says nothing. For measuring what reasoning is worth.
    case random
}

package enum Minds {
    /// The mind for a seat. A traitor is given what the team knows; nobody else is.
    package static func make(_ kind: MindKind, notes: BotMind, traits: Personality, conspiracy: Conspiracy?) -> any Mind {
        switch kind {
        case .faithful: return FaithfulMind(notes: notes, traits: traits)
        case .traitor: return TraitorMind(notes: notes, traits: traits, among: conspiracy ?? Conspiracy(team: [notes.id], plan: nil, known: []))
        case .random: return RandomMind(notes: notes, traits: traits, team: conspiracy?.team)
        }
    }

    /// What a neutral onlooker makes of each player: the chance each is a traitor.
    package static func publicSuspicion(at table: TableView) -> [Double] {
        TraitorBrain.publicBelief(table).marginals(count: table.count)
    }

    /// The bot traitor the table is least wary of, who is the one to use the hand if anyone does.
    package static func leastSuspected(of seats: [PlayerID], at table: TableView) -> (seat: PlayerID, suspicion: (PlayerID) -> Double)? {
        let pub = TraitorBrain.publicBelief(table)
        guard let seat = seats.min(by: { pub.marginal($0) < pub.marginal($1) }) else { return nil }
        return (seat, { pub.marginal($0) })
    }

    /// The ways the player in a seat could answer whoever last pointed at them. Empty when nobody has.
    package static func defences(for notes: BotMind, traits: Personality, at table: TableView) -> [DefenceOption] {
        guard let accuser = table.index.accuser(of: notes.id, day: table.day) else { return [] }
        var notes = notes
        let belief = FaithfulBrain.honest(view: table, mind: &notes, p: traits)
        return Defences.candidates(me: notes.id, accuser: accuser, view: table, belief: belief, mind: notes, p: traits)
    }

    /// The strongest thing on the record to cite about a player.
    package static func bestChip(about p: PlayerID, at table: TableView, suspicious: Bool) -> Chip? {
        FaithfulBrain.bestChip(p, table, suspicious: suspicious)
    }
}

private func honestOpinion(of p: PlayerID, at table: TableView, notes: BotMind, traits: Personality) -> (suspicion: Double, why: Chip?) {
    var notes = notes
    let belief = FaithfulBrain.honest(view: table, mind: &notes, p: traits)
    let chip = FaithfulBrain.bestChip(p, table, suspicious: true, sightings: notes.seen.filter { $0.day == table.day }, belief: belief)
    return (belief.marginal(p), chip?.kind == .gut ? nil : chip)
}

private func clash(_ claim: Chip, in seen: [Sighting]) -> Sighting? {
    guard let said = claim.sight else { return nil }
    return seen.first { $0.subject == claim.subject && $0.day == claim.day && $0.clashes(with: said) }
}

struct FaithfulMind: Mind {
    private(set) var notes: BotMind
    let traits: Personality

    mutating func speak(at table: TableView, phase: TablePhase, replyTo: PlayerID?) -> Intent? {
        FaithfulBrain.speak(view: table, mind: &notes, p: traits, replyTo: replyTo, phase: phase)
    }

    mutating func vote(at table: TableView, among candidates: [PlayerID], declared: PlayerID?) -> PlayerID {
        FaithfulBrain.intent(view: table, mind: &notes, p: traits, candidates: candidates, sticky: declared)
    }

    mutating func endTheGame(at table: TableView) -> Bool {
        FaithfulBrain.finaleEnd(view: table, mind: &notes, p: traits)
    }

    mutating func useTheHand(at table: TableView, mustKill: Bool) -> Bool { false }
    mutating func murder(at table: TableView) -> PlayerID? { nil }
    mutating func recruit(at table: TableView) -> PlayerID? { nil }
    mutating func plan(at table: TableView, seed: UInt64) -> TeamPlan? { nil }

    func knowsBetter(than claim: Chip, saidBy speaker: PlayerID) -> Sighting? { clash(claim, in: notes.seen) }

    func suspect(at table: TableView) -> PlayerID? {
        var notes = notes
        let belief = FaithfulBrain.honest(view: table, mind: &notes, p: traits)
        return FaithfulBrain.topSuspect(table, belief, me: notes.id)
    }

    func opinion(of p: PlayerID, at table: TableView) -> (suspicion: Double, why: Chip?)? {
        honestOpinion(of: p, at: table, notes: notes, traits: traits)
    }
}

struct TraitorMind: Mind {
    private(set) var notes: BotMind
    let traits: Personality
    let among: Conspiracy

    mutating func speak(at table: TableView, phase: TablePhase, replyTo: PlayerID?) -> Intent? {
        TraitorBrain.speak(view: table, me: notes.id, team: among.team, mind: &notes, p: traits, replyTo: replyTo,
                           plan: among.plan, phase: phase, known: among.known)
    }

    mutating func vote(at table: TableView, among candidates: [PlayerID], declared: PlayerID?) -> PlayerID {
        TraitorBrain.intent(view: table, me: notes.id, team: among.team, mind: &notes, p: traits, candidates: candidates,
                            sticky: declared, plan: among.plan, known: among.known)
    }

    mutating func endTheGame(at table: TableView) -> Bool { TraitorBrain.finaleEnd(view: table, mind: &notes) }

    mutating func plan(at table: TableView, seed: UInt64) -> TeamPlan? {
        TeamPlanner.plan(view: table, team: among.team, known: among.known, seed: seed, recall: &notes.recall)
    }

    mutating func useTheHand(at table: TableView, mustKill: Bool) -> Bool {
        TraitorBrain.willAttempt(view: table, me: notes.id, team: among.team, mind: &notes, p: traits, mustKill: mustKill, known: among.known)
    }

    mutating func murder(at table: TableView) -> PlayerID? {
        TraitorBrain.murder(view: table, me: notes.id, team: among.team, mind: &notes, p: traits, known: among.known)
    }

    mutating func recruit(at table: TableView) -> PlayerID? {
        // Someone to fall back on is drawn first, whether or not it comes to that.
        let fallback = notes.rng.pick(table.alive.filter { $0 != notes.id })
        return TraitorBrain.recruit(view: table, me: notes.id, mind: &notes) ?? fallback
    }

    func knowsBetter(than claim: Chip, saidBy speaker: PlayerID) -> Sighting? {
        // A traitor does not expose a partner's lie.
        among.team.contains(speaker) ? nil : clash(claim, in: notes.seen)
    }

    func suspect(at table: TableView) -> PlayerID? { nil }
    func opinion(of p: PlayerID, at table: TableView) -> (suspicion: Double, why: Chip?)? { nil }
}

struct RandomMind: Mind {
    private(set) var notes: BotMind
    let traits: Personality
    /// The team, when this seat is on it.
    let team: [PlayerID]?

    mutating func speak(at table: TableView, phase: TablePhase, replyTo: PlayerID?) -> Intent? { nil }

    mutating func vote(at table: TableView, among candidates: [PlayerID], declared: PlayerID?) -> PlayerID {
        let others = candidates.filter { $0 != notes.id }
        return others.isEmpty ? notes.id : notes.rng.pick(others)
    }

    mutating func endTheGame(at table: TableView) -> Bool { notes.rng.chance(0.5) }

    /// A team playing at random draws lots for the hand between them; no one of them is asked.
    mutating func useTheHand(at table: TableView, mustKill: Bool) -> Bool { false }

    mutating func murder(at table: TableView) -> PlayerID? {
        guard let team else { return nil }
        return notes.rng.pick(table.alive.filter { !team.contains($0) })
    }

    mutating func recruit(at table: TableView) -> PlayerID? {
        notes.rng.pick(table.alive.filter { $0 != notes.id })
    }

    mutating func plan(at table: TableView, seed: UInt64) -> TeamPlan? { nil }

    func knowsBetter(than claim: Chip, saidBy speaker: PlayerID) -> Sighting? { nil }
    func suspect(at table: TableView) -> PlayerID? { nil }

    func opinion(of p: PlayerID, at table: TableView) -> (suspicion: Double, why: Chip?)? {
        team == nil ? honestOpinion(of: p, at: table, notes: notes, traits: traits) : nil
    }
}
