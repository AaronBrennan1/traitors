import Foundation

/// A bot's private notes. Combined with the public `TableView`, this is all it ever reasons from.
struct BotMind: Codable {
    var id: PlayerID
    /// Log-odds hunch about each player; grows into a grudge when they come after this bot.
    var gut: [Double]
    /// What this bot saw other people do in missions.
    var seen: [Sighting] = []
    /// What this bot did in missions that somebody else saw, and who.
    var exposed: [Sighting] = []
    /// Partners this bot has already put a small doubt on record about.
    var banked: [PlayerID] = []
    var rng: SeededRNG
}

/// What a bot wants to say: turned into a `Statement` with wording by the engine.
struct Intent {
    var kind: StatementKind
    var target: PlayerID?
    var chip: Chip?
    var defence: Defence? = nil
    /// How well a defence stands up, 0...1.
    var credibility = 0.0
}

/// Something a bot could say, and how much it wants to.
struct Proposal {
    var intent: Intent
    var score: Double
}

/// The beats of a Round Table. Each gives the floor to a different kind of remark.
enum TablePhase {
    case opening, accusations, rebuttals, openFloor

    /// How keen a bot is to take the floor: the threatened want their say, the sure
    /// want to be heard, and some people simply talk.
    func urgency(heat: Double, spoken: Int, p: Personality, jitter: Double) -> Double {
        switch self {
        case .opening, .accusations: return p.aggression + 0.2 * heat + jitter
        case .rebuttals: return 0.5 * heat + 0.4 * p.aggression + jitter
        case .openFloor: return 0.6 * p.aggression + 0.2 * heat - 0.25 * Double(spoken) + jitter
        }
    }
}

/// Decision-making for a bot that is faithful.
enum FaithfulBrain {
    static func observer(_ mind: BotMind, _ p: Personality) -> Observer {
        Observer(id: mind.id, gut: mind.gut, temper: 0.55 + 0.45 * p.logic, sightings: mind.seen, decay: 0.9 + 0.1 * p.logic)
    }

    /// Chance a random other living player is a traitor, as a yardstick for "more suspicious than average".
    static func baseRate(_ view: TableView, _ belief: Belief) -> Double {
        let others = view.alive.count - 1
        guard others > 0 else { return 1 }
        let expected = view.alive.reduce(0.0) { $0 + belief.marginal($1) }
        return max(expected / Double(others), 0.05)
    }

    static func topSuspect(_ view: TableView, _ belief: Belief, me: PlayerID, among: [PlayerID]? = nil) -> PlayerID? {
        (among ?? view.alive).filter { $0 != me }.max { belief.marginal($0) < belief.marginal($1) }
    }

    /// Everything this mind would be willing to say unprompted right now. Pure: a traitor
    /// asks the same question of its faithful mask without anything being rolled.
    static func proposals(view: TableView, belief: Belief, mind: BotMind, p: Personality, phase: TablePhase) -> [Proposal] {
        let me = mind.id
        let ix = view.index
        let base = baseRate(view, belief)
        let others = view.alive.filter { $0 != me }
        let today = ix.statements(day: view.day).filter { $0.speaker == me }
        let fresh = mind.seen.filter { $0.day == view.day }
        func lift(_ x: PlayerID) -> Double { belief.marginal(x) / base }
        func raised(_ x: PlayerID) -> Bool {
            today.contains { $0.target == x && ($0.kind == .accuse || $0.kind == .callout || $0.kind == .doubt) }
        }
        var out: [Proposal] = []

        switch phase {
        case .opening:
            // Hold people to what happened at the last table.
            guard let last = ix.blame.last, last.role == .faithful, last.day >= view.day - 1 else { break }
            for (who, kind, weight) in [(last.firstNamer, ChipKind.firstNamed, 0.9), (last.pusher, ChipKind.pushedHardest, 0.7)] {
                guard let x = who, x != me, view.seats[x].alive, !raised(x), lift(x) > 0.9 else { continue }
                let chip = Chip(kind: kind, subject: x, day: last.day, other: last.player, strength: weight)
                out.append(Proposal(intent: Intent(kind: .callout, target: x, chip: chip), score: lift(x) + weight))
            }
            for b in ix.banishments where b.role == .traitor && b.day >= view.day - 1 {
                for v in ix.vouches where v.about == b.player && v.by != me && view.seats[v.by].alive && !raised(v.by) {
                    let chip = Chip(kind: .sworeBy, subject: v.by, day: v.day, other: b.player, strength: 1.4)
                    out.append(Proposal(intent: Intent(kind: .callout, target: v.by, chip: chip), score: lift(v.by) + 1.4))
                }
            }

        case .accusations, .openFloor:
            let bar = 1.3 - 0.35 * p.aggression
            for x in others where !raised(x) {
                let l = lift(x)
                if l > bar {
                    let chip = bestChip(x, view, suspicious: true, sightings: fresh, belief: belief)
                    out.append(Proposal(intent: Intent(kind: .accuse, target: x, chip: chip), score: l))
                } else if phase == .openFloor, l > 1.05, !today.contains(where: { $0.kind == .doubt }) {
                    out.append(Proposal(intent: Intent(kind: .doubt, target: x, chip: nil), score: l - 0.45))
                }
            }
            // Say what was seen, whoever it was, unless the table has already heard it. Reporting
            // only what fits an existing suspicion would just feed the table its own bias back.
            for s in fresh where s.kind.suspicious && s.subject != me && view.seats[s.subject].alive {
                guard !ix.told.contains(where: { $0.day == s.day && $0.about == s.subject && ($0.kind == s.kind || $0.by == me) })
                else { continue }
                let chip = Chip(kind: .sighting, subject: s.subject, day: s.day, sight: s.kind, strength: Tuning.sight(s.kind) / 5)
                let l = lift(s.subject)
                out.append(Proposal(intent: Intent(kind: l > bar ? .accuse : .doubt, target: s.subject, chip: chip),
                                    score: 0.9 + 0.5 * chip.strength + 0.3 * l))
            }
            if phase == .openFloor { out += support(view: view, belief: belief, mind: mind, base: base, today: today, fresh: fresh) }

        case .rebuttals:
            out += support(view: view, belief: belief, mind: mind, base: base, today: today, fresh: fresh)
        }
        return out
    }

    /// Speaking up for someone the table is turning on, if this mind reads them as faithful.
    private static func support(view: TableView, belief: Belief, mind: BotMind, base: Double,
                                today: [Statement], fresh: [Sighting]) -> [Proposal] {
        var out: [Proposal] = []
        for x in view.alive where x != mind.id && belief.marginal(x) < base * 0.7 {
            guard !today.contains(where: { ($0.kind == .defend || $0.kind == .vouch) && $0.target == x }) else { continue }
            let watched = fresh.contains { $0.subject == x && $0.kind == .inView }
            if watched, view.heat[x] >= 0.6 {
                let chip = Chip(kind: .inSight, subject: x, day: view.day, sight: .inView, strength: 1.1)
                out.append(Proposal(intent: Intent(kind: .vouch, target: x, chip: chip), score: 1.6 + 0.2 * view.heat[x]))
            } else if view.heat[x] >= 1.0 {
                let chip = bestChip(x, view, suspicious: false, belief: belief)
                out.append(Proposal(intent: Intent(kind: .defend, target: x, chip: chip), score: 1.0 + 0.2 * view.heat[x]))
            }
        }
        return out
    }

    static func speak(view: TableView, mind: inout BotMind, p: Personality, replyTo: PlayerID?,
                      phase: TablePhase = .openFloor) -> Intent? {
        let belief = Inference.compute(view: view, observer: observer(mind, p))
        if let accuser = replyTo {
            let options = Defences.candidates(me: mind.id, accuser: accuser, view: view, belief: belief, mind: mind, p: p)
            let listeners = Listeners.build(view: view, team: [mind.id], known: mind.exposed)
            return Defences.choose(options, me: mind.id, view: view, listeners: listeners, rng: &mind.rng, p: p).intent
        }
        return proposals(view: view, belief: belief, mind: mind, p: p, phase: phase).max { $0.score < $1.score }?.intent
    }

    /// Who this bot means to vote for. `sticky` is a name it has already given the table.
    static func intent(view: TableView, mind: inout BotMind, p: Personality, candidates: [PlayerID], sticky: PlayerID?) -> PlayerID {
        let me = mind.id
        let pool = candidates.filter { $0 != me }
        guard !pool.isEmpty else { return candidates.first ?? me }
        let belief = Inference.compute(view: view, observer: observer(mind, p))
        let scores = pool.map { log(belief.marginal($0) + 0.03) + 0.3 * p.herd * view.heat[$0] }
        let pick = pool[mind.rng.softmax(scores, temperature: 0.3 * (1.25 - p.logic))]
        if let sticky, let si = pool.firstIndex(of: sticky), let pi = pool.firstIndex(of: pick), scores[pi] - scores[si] < 0.45 {
            return sticky
        }
        return pick
    }

    static func finaleEnd(view: TableView, mind: BotMind, p: Personality) -> Bool {
        let belief = Inference.compute(view: view, observer: observer(mind, p))
        return belief.noneLeft(alive: view.aliveMask) > 0.7
    }

    /// The chip to cite about `x`. Given the belief, it is the one that best matches why this
    /// mind actually thinks what it thinks, so what a bot says is what moved it.
    static func bestChip(_ x: PlayerID, _ view: TableView, suspicious: Bool,
                         sightings: [Sighting] = [], belief: Belief? = nil) -> Chip? {
        let chips = Chips.about(x, view: view, suspicious: suspicious, sightings: sightings)
        if suspicious, let belief {
            for reason in belief.reasons(for: x) {
                guard let kind = reason.kind else { break }
                if let c = chips.first(where: { cites(kind).contains($0.kind) }) { return c }
            }
        }
        return chips.first
    }

    private static func cites(_ kind: EvidenceKind) -> [ChipKind] {
        switch kind {
        case .mission: return [.sighting]
        case .vote: return [.sparedTraitor, .votedOutFaithful]
        case .defend: return [.sworeBy, .defendedTraitor]
        case .firstNamer: return [.firstNamed, .pushedHardest]
        case .pair: return [.sparedTraitor]
        case .mismatch: return [.sayVote]
        case .lie: return [.caughtLie]
        case .motive: return [.victimSuspected]
        case .testimony, .accuse: return []
        }
    }
}
