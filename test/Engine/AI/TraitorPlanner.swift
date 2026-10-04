import Foundation

/// Decision-making for a bot that is a traitor. It runs two models: the truth (its team), and
/// a faithful mask, which is the belief an honest player in its seat would hold from the same
/// record and the same sightings. By default it says what the mask would say. It strays from
/// the mask only where the team plan needs it to, and straying costs.
enum TraitorBrain {
    static func publicBelief(_ view: TableView) -> Belief {
        Inference.compute(view: view, observer: .publicView(count: view.count))
    }

    static func speak(view: TableView, me: PlayerID, team: [PlayerID], mind: inout BotMind, p: Personality,
                      replyTo: PlayerID?, plan: TeamPlan? = nil, phase: TablePhase = .openFloor,
                      known: [Sighting] = []) -> Intent? {
        let mask = Inference.compute(view: view, observer: FaithfulBrain.observer(mind, p))
        let partners = team.filter { $0 != me && view.seats[$0].alive }

        if let accuser = replyTo {
            let listeners = Listeners.build(view: view, team: team, known: known)
            // The mask supplies the defence, minus anything that would land on a partner.
            var options = Defences.candidates(me: me, accuser: accuser, view: view, belief: mask, mind: mind, p: p)
                .filter { o in o.target.map { !partners.contains($0) || plan?.stance($0) == .bus } ?? true }
            // With nothing solid to say, a good liar invents something about the accuser.
            if !team.contains(accuser), options.allSatisfy({ $0.credibility < 0.6 }), p.deceit > 0.6,
               view.index.reports.last?.day == view.day, mind.rng.chance(0.4 * p.deceit * Tuning.lying) {
                let chip = Chip(kind: .sighting, subject: accuser, day: view.day, sight: .loiter, strength: 0.8)
                options.append(DefenceOption(defence: .counterattack, target: accuser, chip: chip, credibility: 0.65, invented: true))
            }
            return Defences.choose(options, me: me, view: view, listeners: listeners, rng: &mind.rng, p: p).intent
        }

        let ix = view.index
        let base = FaithfulBrain.baseRate(view, mask)
        let today = ix.statements(day: view.day)
        let mine = today.filter { $0.speaker == me }
        let honest = FaithfulBrain.proposals(view: view, belief: mask, mind: mind, p: p, phase: phase)
        let best = honest.map(\.score).max() ?? 1
        // Straying from the mask is cheap for a practised liar and dear for a poor one.
        let stray = 1.3 - 0.9 * p.deceit
        // Too hot already: no adventures.
        let exposed = (plan?.danger[me] ?? 0) > 0.25
        var options: [Proposal] = []

        for h in honest {
            guard let t = h.intent.target, partners.contains(t) else {
                // What the mask would say anyway. Better still when it falls on the scapegoat.
                options.append(Proposal(intent: h.intent, score: h.score + (h.intent.target == plan?.scapegoat ? 0.4 : 0)))
                continue
            }
            // The mask points at a partner. Say it only when the plan is to cut them loose,
            // and never as the first to name them.
            let named = today.contains { $0.target == t && $0.kind.names && !team.contains($0.speaker) }
            if plan?.stance(t) == .bus, named, h.intent.kind == .accuse || h.intent.kind == .callout {
                options.append(Proposal(intent: h.intent, score: h.score + 0.8))
            }
        }

        // Pushing the scapegoat is a deviation, so only when it is needed: a partner (or this
        // traitor) is in real danger. At a quiet table the mask does all the talking.
        let pressed = team.contains { view.seats[$0].alive && plan?.stance($0) != .distance }
        if phase != .opening, pressed, let goat = plan?.scapegoat, view.seats[goat].alive,
           !mine.contains(where: { $0.target == goat && ($0.kind == .accuse || $0.kind == .callout) }) {
            let gap = max(0, best - mask.marginal(goat) / base)
            var chip = Chips.about(goat, view: view, noticed: nil, suspicious: true,
                                   sightings: mind.seen.filter { $0.day == view.day }).first { $0.kind != .gut }
            var score = 1.1 + (plan?.lead == me ? 0.4 : 0) - stray * gap - (exposed ? 0.5 : 0)
            // A push with nothing behind it needs something behind it.
            if chip == nil, plan?.lead == me, !exposed, p.deceit > 0.55, ix.reports.last?.day == view.day,
               !ix.told.contains(where: { $0.about == goat && $0.day == view.day }), mind.rng.chance(0.45 * p.deceit * Tuning.lying) {
                chip = Chip(kind: .sighting, subject: goat, day: view.day, sight: mind.rng.pick([.loiter, .offTask, .brokeAway]), strength: 0.8)
                score += 0.3
            }
            if chip != nil || view.heat[goat] >= 1 || mind.rng.chance(0.3) {
                options.append(Proposal(intent: Intent(kind: .accuse, target: goat,
                                                       chip: chip ?? Chip(kind: .gut, subject: goat, day: view.day, strength: 0.2)),
                                        score: score))
            }
        }

        for t in partners {
            guard let stance = plan?.stance(t) else { continue }
            switch stance {
            case .bus:
                break
            case .redirect:
                // One vouch a table, and only for a partner the table has actually turned on.
                guard phase == .rebuttals || phase == .openFloor, !exposed, view.heat[t] >= 0.8,
                      plan?.vouched.contains(me) == false,
                      !mine.contains(where: { ($0.kind == .defend || $0.kind == .vouch) && $0.target == t }) else { break }
                if let chip = Chips.about(t, view: view, noticed: nil, suspicious: false).first(where: { $0.kind != .gut }) {
                    options.append(Proposal(intent: Intent(kind: .defend, target: t, chip: chip), score: 0.7 + 0.6 * p.deceit))
                } else if p.deceit > 0.7, ix.reports.last?.day == view.day, mind.rng.chance(0.3 * p.deceit * Tuning.lying) {
                    let chip = Chip(kind: .inSight, subject: t, day: view.day, sight: .inView, strength: 1.1)
                    options.append(Proposal(intent: Intent(kind: .vouch, target: t, chip: chip), score: 0.6 + 0.6 * p.deceit))
                }
            case .distance:
                guard phase == .openFloor, mind.banked.isEmpty, mind.rng.chance(0.35),
                      !mine.contains(where: { $0.target == t }) else { break }
                options.append(Proposal(intent: Intent(kind: .doubt, target: t, chip: nil), score: 0.75 + 0.4 * p.deceit))
            }
        }

        guard let pick = options.max(by: { $0.score < $1.score }), pick.score > 0.6 else { return nil }
        if pick.intent.kind == .doubt, let t = pick.intent.target, partners.contains(t) { mind.banked.append(t) }
        return pick.intent
    }

    static func intent(view: TableView, me: PlayerID, team: [PlayerID], mind: inout BotMind, p: Personality,
                       candidates: [PlayerID], sticky: PlayerID?, plan: TeamPlan? = nil, known: [Sighting] = []) -> PlayerID {
        let pool = candidates.filter { $0 != me }
        guard !pool.isEmpty else { return candidates.first ?? me }
        let faithful = pool.filter { !team.contains($0) }
        let partners = team.filter { $0 != me && view.seats[$0].alive }
        guard !faithful.isEmpty else { return pool[0] }

        let listeners = Listeners.build(view: view, team: team, known: known)
        let salt = UInt64(view.log.count)
        // The ballots of partners who have already said a name are known; mine is what is being decided.
        let said = partners.compactMap { t in view.index.declared(day: view.day, by: t).map { (voter: t, target: $0) } }
        func banished(_ mine: PlayerID?, _ n: UInt64) -> [Double] {
            VoteSim.pBanish(view: view, listeners: listeners, fixed: said + (mine.map { [(voter: me, target: $0)] } ?? []),
                            pool: pool, rng: .derived(mind.rng.state, salt, n))
        }
        let free = banished(nil, 0)
        guard let goat = faithful.max(by: { free[$0] < free[$1] }) else { return pool[0] }

        // A partner who is going anyway: be on the right side of it. Decided once, when the
        // name is first given, and then kept to.
        if let sticky, partners.contains(sticky), pool.contains(sticky) { return sticky }
        if sticky == nil, let doomed = partners.filter({ pool.contains($0) }).max(by: { free[$0] < free[$1] }),
           free[doomed] >= TeamPlanner.busAt, free[me] < 0.5, mind.rng.chance(0.1 + 0.4 * p.deceit) {
            return doomed
        }

        // Risk to the team under each ballot I could cast.
        func risk(_ mine: PlayerID, _ n: UInt64) -> Double {
            let b = banished(mine, n)
            return team.reduce(0.0) { $0 + b[$1] }
        }
        let mask = Inference.compute(view: view, observer: FaithfulBrain.observer(mind, p))
        let own = faithful.max { mask.marginal($0) < mask.marginal($1) } ?? goat
        var pick = goat
        // Voting as a bloc is itself a tell. When my ballot is not the one that decides it,
        // vote the way my mask would and leave the push to my partner.
        if own != goat, said.contains(where: { $0.target == goat }), risk(own, 1) - risk(goat, 2) < 0.06 {
            pick = own
        }
        // Keep a declared name unless switching is what keeps a traitor at the table.
        if let sticky, sticky != pick, faithful.contains(sticky), risk(sticky, 3) - risk(pick, 4) < 0.1 {
            return sticky
        }
        return pick
    }

    static func murder(view: TableView, me: PlayerID, team: [PlayerID], mind: inout BotMind, p: Personality,
                       shieldClaims: [PlayerID], known: [Sighting] = []) -> PlayerID? {
        let pool = view.alive.filter { !team.contains($0) }
        guard !pool.isEmpty else { return nil }
        let pub = publicBelief(view)
        let living = team.filter { view.seats[$0].alive }
        let listeners = Listeners.build(view: view, team: team, known: known)
        let beliefs = listeners.beliefs
        var scores: [Double] = []
        for m in pool {
            // Look one step ahead: how exposed is the team if this is the body at breakfast?
            // This is what stops a run of kills that all point the same way.
            var after = view
            after.log.append(.night(day: view.day, victim: m, recruitNight: false))
            let next = Inference.compute(log: after.log, count: view.count, observer: .publicView(count: view.count))
            let exposure = living.reduce(0.0) { $0 + next.marginal($1) }
            var s = -6 * exposure
            // The ones who are onto us, and the ones who saw something and have not said it yet.
            if let i = listeners.ids.firstIndex(of: m) {
                s += 2.2 * view.voice(m) * living.reduce(0.0) { $0 + beliefs[i].marginal($1) }
            }
            let untold = known.contains { k in
                k.kind.suspicious && k.witnesses.has(m)
                    && !view.index.told.contains { $0.by == m && $0.about == k.subject && $0.day == k.day }
            }
            if untold { s += 1.0 }
            s += 0.6 * view.voice(m)
            s -= 2.5 * pub.marginal(m)
            // Framing: a death that leaves a faithful looking guiltier than anyone.
            let framed = pool.filter { $0 != m }.map { next.marginal($0) }.max() ?? 0
            s += 1.5 * p.deceit * framed
            if shieldClaims.contains(m) { s -= 1.5 }
            scores.append(s)
        }
        return pool[mind.rng.softmax(scores, temperature: 0.2 * (1.3 - p.deceit))]
    }

    static func recruit(view: TableView, me: PlayerID, mind: inout BotMind) -> PlayerID? {
        let pub = publicBelief(view)
        return view.alive.filter { $0 != me }.max {
            -pub.marginal($0) + 0.1 * view.seats[$0].charisma < -pub.marginal($1) + 0.1 * view.seats[$1].charisma
        }
    }

    /// Whether to go for the side quest today: less readily when the table already has its eye on this player.
    static func willAttempt(view: TableView, me: PlayerID, team: [PlayerID], mind: inout BotMind, p: Personality,
                            mustKill: Bool, known: [Sighting] = []) -> Bool {
        if mustKill { return true }
        let heat = Listeners.build(view: view, team: team, known: known).heat(of: me)
        let base = Double(Rules.traitors) / Double(max(view.alive.count - 1, 1))
        return mind.rng.chance(heat > 1.25 * base ? 0.6 : 0.92)
    }

    static func finaleEnd(view: TableView) -> Bool {
        // Only call for the end when a faithful could plausibly believe it is over.
        publicBelief(view).noneLeft(alive: view.aliveMask) > 0.45
    }
}
