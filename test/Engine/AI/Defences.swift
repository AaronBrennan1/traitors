import Foundation

/// One way of answering an accusation. Everything it rests on is a chip, which the rest of
/// the table can check against the record or, for something seen, against their own eyes.
struct DefenceOption {
    var defence: Defence
    var target: PlayerID? = nil
    var chip: Chip? = nil
    /// How well it stands up, 0...1.
    var credibility: Double
    /// True when the chip is something the speaker made up.
    var invented = false

    var intent: Intent {
        Intent(kind: .selfDefend, target: target, chip: chip, defence: defence, credibility: credibility)
    }
}

enum Defences {
    /// How much a defence of this credibility takes the heat off, and how far it softens
    /// each listener's private view of the speaker.
    static func relief(_ credibility: Double) -> Double { 0.9 * credibility }
    static func soothe(_ credibility: Double) -> Double { 0.3 * credibility * Tuning.persuasion }

    /// Every defence open to `me` that the record actually supports.
    static func candidates(me: PlayerID, accuser: PlayerID, view: TableView, belief: Belief, mind: BotMind,
                           p: Personality) -> [DefenceOption] {
        let ix = view.index
        let charge = ix.statements.last { $0.day == view.day && $0.speaker == accuser && $0.target == me }?.chip
        let others = view.alive.filter { $0 != me }
        var out = [DefenceOption(defence: .denial, credibility: 0.15)]

        // The banishment being held against this player, if that is what the charge is about.
        let held = charge?.other.flatMap { o in ix.blame.last { $0.player == o && $0.role == .faithful } }
        let wrong = held ?? ix.blame.last { b in b.role == .faithful && ix.firstVote(day: b.day, voter: me) == b.player }

        if let b = wrong, ix.firstVote(day: b.day, voter: me) == b.player, b.votes >= 3 {
            let chip = Chip(kind: .tableAgreed, subject: me, day: b.day, other: b.player, unit: b.votes, strength: 0.8)
            out.append(DefenceOption(defence: .diffusion, chip: chip,
                                     credibility: 0.25 + 0.6 * Double(b.votes) / Double(max(b.voters, 1))))
        }
        if let b = wrong {
            // The reason this player had at the time.
            let then = mind.seen.filter { $0.day <= b.day }
            if let chip = Chips.about(b.player, view: view, noticed: mind.noticed, suspicious: true, sightings: then)
                .first(where: { $0.kind == .sighting || $0.kind == .missionSlip }) {
                out.append(DefenceOption(defence: .evidence, chip: chip, credibility: 0.35 + 0.3 * chip.strength))
            }
            if let first = b.firstNamer, first != me, view.seats[first].alive {
                let chip = Chip(kind: .firstNamed, subject: first, day: b.day, other: b.player, strength: 0.9)
                out.append(DefenceOption(defence: .originRedirect, target: first, chip: chip, credibility: 0.7))
            }
            if b.firstNamer == me || b.pusher == me {
                // No denying it: own the mistake and point at someone who has more to answer for.
                let pivot = others.filter { $0 != accuser }.max { belief.marginal($0) < belief.marginal($1) }
                if let pivot {
                    // The chip is the admission itself, so the line can name who was wronged.
                    let chip = Chip(kind: b.firstNamer == me ? .firstNamed : .pushedHardest, subject: me, day: b.day,
                                    other: b.player, strength: 0.5)
                    out.append(DefenceOption(defence: .ownAndPivot, target: pivot, chip: chip, credibility: 0.5))
                }
            }
        }

        let record = Chips.about(me, view: view, noticed: nil, suspicious: false)
            .filter { [.votedTraitor, .firstOnTraitor, .flaggedEarly, .accusedByTraitor].contains($0.kind) }
        if let chip = record.first {
            out.append(DefenceOption(defence: .trackRecord, chip: chip,
                                     credibility: min(1, 0.45 + 0.25 * record.reduce(0) { $0 + $1.strength })))
        }

        if charge?.kind == .missionSlip {
            // Accused on the score alone. It carries if someone has said they had eyes on this player.
            let alibi = ix.told.contains { $0.about == me && $0.day == view.day && $0.kind == .inView }
            out.append(DefenceOption(defence: .badAtThis, credibility: alibi ? 0.85 : 0.5))
        }

        let base = FaithfulBrain.baseRate(view, belief)
        if let chip = Chips.about(accuser, view: view, noticed: mind.noticed, suspicious: true,
                                  sightings: mind.seen.filter({ $0.day == view.day })).first(where: { $0.kind != .gut }) {
            let lift = belief.marginal(accuser) / base
            out.append(DefenceOption(defence: .counterattack, target: accuser, chip: chip,
                                     credibility: 0.25 * chip.strength + (lift > 1.15 ? 0.3 : 0) + 0.1 * p.stubbornness))
        }

        if let top = FaithfulBrain.topSuspect(view, belief, me: me, among: others.filter({ $0 != accuser })),
           belief.marginal(top) / base > 1.15 {
            let chip = FaithfulBrain.bestChip(top, view, mind.noticed, suspicious: true,
                                              sightings: mind.seen.filter { $0.day == view.day }, belief: belief)
            out.append(DefenceOption(defence: .redirect, target: top, chip: chip,
                                     credibility: 0.2 + 0.3 * min(chip?.strength ?? 0, 1)))
        }

        if charge == nil || charge?.kind == .gut {
            // Nothing concrete to answer, so answer the person.
            out.append(DefenceOption(defence: .appeal, credibility: 0.15 + 0.4 * p.charisma))
        }
        return out
    }

    /// Picks the defence that leaves the table least suspicious of `me`, by trying each one
    /// on a model of every listener. A made-up claim is marked down by the chance of being caught.
    static func choose(_ options: [DefenceOption], me: PlayerID, view: TableView, listeners: Listeners,
                       rng: inout SeededRNG, p: Personality) -> DefenceOption {
        let before = listeners.heat(of: me)
        let scores = options.map { o -> Double in
            let said = Statement(day: view.day, speaker: me, kind: .selfDefend, target: o.target, chip: o.chip,
                                 text: "", defence: o.defence)
            let after = listeners.after(said, soothe: soothe(o.credibility)).heat(of: me)
            var s = (before - after) + 0.05 * relief(o.credibility)
            if o.invented { s -= 0.2 * 0.25 * (1.2 - p.deceit) }
            return s
        }
        return options[rng.softmax(scores, temperature: 0.01 * (1.3 - p.logic))]
    }
}
