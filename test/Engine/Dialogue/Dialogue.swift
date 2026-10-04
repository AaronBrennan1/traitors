import Foundation

/// Turns an intent plus a piece of evidence into a spoken line.
enum Dialogue {
    static func line(kind: StatementKind, target: PlayerID?, chip: Chip?, voice: Voice,
                     view: TableView, rng: inout SeededRNG, defence: Defence? = nil) -> String {
        let t = target.map { view.name($0) } ?? ""
        var body: String
        switch kind {
        case .selfDefend where defence != nil && defence != .denial && defence != .redirect:
            body = plea(defence!, chip: chip, view: view, rng: &rng)
        case .callout:
            body = charge(chip, rng: &rng)
        case .doubt where chip?.kind == .sighting:
            body = reason(chip, suspicious: true, view: view, rng: &rng) + " " + rng.pick([
                "Make of it what you will.", "It may be nothing.", "I'm only saying what I saw.",
            ])
        case .doubt:
            body = rng.pick([
                "I'm not a hundred per cent on {T}. That's all I'll say for now.",
                "Small thing, but {T} hasn't sat right with me today.",
                "I wouldn't write the name yet, but I'm keeping an eye on {T}.",
            ])
        case .vouch:
            body = reason(chip, suspicious: false, view: view, rng: &rng) + " " + rng.pick([
                "I'll stand over that.", "I'd stake my place here on it.", "If I'm wrong about {T}, send me home.",
            ])
        case .challenge:
            body = chip?.sight == .inView
                ? rng.pick([
                    "That's not true. {O} was in front of me the whole of {M} and did nothing of the kind. Why say it, {T}?",
                    "No. I never took my eyes off {O} in {M}. So what are you at, {T}?",
                ])
                : rng.pick([
                    "No, {T}. I saw {O} slip off in {M} myself. Why are you covering for them?",
                    "That's not what happened. I watched {O} in {M}, and it was not that. Explain yourself, {T}.",
                ])
        case .accuse:
            body = reason(chip, suspicious: true, view: view, rng: &rng)
        case .defend:
            body = reason(chip, suspicious: false, view: view, rng: &rng)
        case .selfDefend:
            if target != nil {
                body = rng.pick([
                    "I'm a faithful. If you want a traitor, look at {T}.",
                    "That's not me. Ask yourselves why {T} is happy to let this run.",
                    "You have the wrong person, and {T} is the one who gains from it.",
                    "I've nothing to hide. {T} is the one I'd be watching.",
                ])
            } else {
                body = rng.pick([
                    "I'm a faithful. Banish me and you'll see it written down.",
                    "You're wrong about me, and while you're wrong the traitors are laughing.",
                    "I've played this straight from the first day.",
                ])
            }
        case .answer:
            body = rng.pick(["Since you ask: {T}.", "{T}. That's where my vote is heading.", "If I had to write a name now, {T}."])
                + " " + reason(chip, suspicious: true, view: view, rng: &rng)
        case .declare:
            body = rng.pick(["I'm voting {T}.", "{T} for me tonight.", "My slate says {T}.", "It's {T} for me.", "I'm writing {T}."])
        case .question:
            body = rng.pick(["{T}, who are you voting for, and why?", "{T}, give us a name.", "I want to hear from {T}. Who do you suspect?"])
        case .claimShield:
            body = "I'll tell you all now: I hold the shield tonight."
        case .pass:
            body = "I'll keep my counsel for now."
        }
        // A defence that leans on evidence about somebody else names them, not the speaker.
        let subject = (kind == .selfDefend && defence == .evidence) ? chip.map { view.name($0.subject) } ?? t : t
        body = fill(body, t: subject, chip: chip, view: view)
        guard kind == .accuse || kind == .defend || kind == .callout else { return body }
        let lead = rng.pick(openers(voice))
        guard !lead.isEmpty else { return body }
        if lead.hasSuffix("but") || lead.hasSuffix(",") {
            return lead + " " + lowerFirst(body)
        }
        return lead + " " + body
    }

    /// Short label for an evidence chip, as shown on the human's notebook.
    static func label(_ chip: Chip, view: TableView) -> String {
        let o = chip.other.map { view.name($0) } ?? ""
        switch chip.kind {
        case .missionSlip: return "Under par in \(missionName(chip, view)) (day \(chip.day))"
        case .votedOutFaithful: return "Voted out \(o), a faithful"
        case .sparedTraitor: return "Didn't vote for the traitor \(o)"
        case .defendedTraitor: return "Defended the traitor \(o)"
        case .victimSuspected: return "\(o) suspected them, then was murdered"
        case .sayVote: return "Said one name, voted another (day \(chip.day))"
        case .votedTraitor: return "Voted for the traitor \(o)"
        case .accusedByTraitor: return "Was accused by the traitor \(o)"
        case .cleanMissions: return "Made par in every mission"
        case .gut: return "Just a feeling"
        case .sighting: return "Seen \(saw(chip.sight)) in \(missionName(chip, view)) (day \(chip.day))"
        case .inSight: return "In sight all through \(missionName(chip, view)) (day \(chip.day))"
        case .firstNamed: return "First to name \(o), a faithful"
        case .pushedHardest: return "Pushed hardest against \(o), a faithful"
        case .sworeBy: return "Swore by the traitor \(o)"
        case .caughtLie: return "Contradicted over what they said about \(o)"
        case .flaggedEarly: return "Had doubts about the traitor \(o) early"
        case .firstOnTraitor: return "First to name the traitor \(o)"
        case .tableAgreed: return "\(chip.unit ?? 0) voted for \(o)"
        }
    }

    /// Short label for a way of answering an accusation, as offered to the human.
    static func label(_ option: DefenceOption, view: TableView) -> String {
        let t = option.target.map { view.name($0) } ?? ""
        let o = option.chip?.other.map { view.name($0) } ?? ""
        switch option.defence {
        case .denial: return "Deny it flatly"
        case .redirect: return "Point at \(t) instead"
        case .diffusion: return "\(option.chip?.unit ?? 0) of us voted for \(o), not just me"
        case .evidence: return "Give your reason for \(o)"
        case .originRedirect: return "\(t) named \(o) first"
        case .trackRecord: return "Your record: " + (option.chip.map { label($0, view: view) } ?? "")
        case .badAtThis: return "I was just bad at the mission"
        case .ownAndPivot: return "Own the mistake, then point at \(t)"
        case .counterattack: return "Turn it on \(t): " + (option.chip.map { label($0, view: view) } ?? "")
        case .appeal: return "Ask them to trust you"
        }
    }

    /// What the human is told they noticed during a mission.
    static func noticed(_ s: Sighting, view: TableView) -> String {
        let name = view.name(s.subject)
        switch s.kind {
        case .inView: return "You had \(name) in sight the whole way through. Nothing odd."
        default: return "You noticed \(name) \(saw(s.kind))."
        }
    }

    private static func saw(_ kind: SightingKind?) -> String {
        switch kind {
        case .offTask: return "drifting off into the corners"
        case .loiter: return "standing about out of the way"
        case .brokeAway: return "slipping away from the group"
        case .startled: return "jump and look busy when watched"
        case .atQuestObject: return "at something that was no part of the mission"
        case .inView, .none: return "in plain sight throughout"
        }
    }

    /// Holding someone to account for how a banishment went.
    private static func charge(_ chip: Chip?, rng: inout SeededRNG) -> String {
        switch chip?.kind {
        case .firstNamed:
            return rng.pick([
                "{T}, you named {O} before anyone else, and {O} was a faithful. What made you so sure?",
                "{T}, it was you who put {O}'s name on the table first. {O} was one of us. Explain yourself.",
            ])
        case .pushedHardest:
            return rng.pick([
                "{T}, nobody pushed harder for {O} to go, and {O} was a faithful. Why?",
                "Who drove the vote on {O}? You did, {T}. And {O} was a faithful.",
            ])
        case .sworeBy:
            return rng.pick([
                "{T}, you swore by {O}. {O} was a traitor. Well?",
                "You staked your name on {O}, {T}, and {O} was a traitor. What have you to say?",
            ])
        default:
            return "{T}, you have some explaining to do."
        }
    }

    /// The accused answering for themselves.
    private static func plea(_ defence: Defence, chip: Chip?, view: TableView, rng: inout SeededRNG) -> String {
        switch defence {
        case .diffusion:
            return rng.pick([
                "\(chip?.unit ?? 0) of us wrote {O}'s name, not just me.",
                "I was one of \(chip?.unit ?? 0) who voted for {O}. Are we all traitors?",
            ])
        case .evidence:
            return "I had my reason and I'll give it again. " + reason(chip, suspicious: true, view: view, rng: &rng)
        case .originRedirect:
            return rng.pick([
                "{T} raised {O} before I did. I followed {T}.",
                "It was {T} who first said {O}'s name. Ask {T} what they knew.",
            ])
        case .trackRecord:
            switch chip?.kind {
            case .firstOnTraitor: return "I was the first to name {O}, and {O} was a traitor. Remember that."
            case .flaggedEarly: return "I had {O} marked on day \(chip?.day ?? 1), long before the rest of you. {O} was a traitor."
            case .accusedByTraitor: return "{O} came after me, and {O} was a traitor. What does that tell you?"
            default: return "I voted for {O}, and {O} was a traitor. Look at my record."
            }
        case .badAtThis:
            return rng.pick([
                "I was rubbish at {M}, that's all it was. Being bad at games isn't treachery.",
                "I had a bad day in {M}. If that makes a traitor, half this table is one.",
            ])
        case .ownAndPivot:
            return rng.pick([
                "I got {O} wrong, and I'll own that. But look at {T}.",
                "Yes, I was wrong about {O}. I'd sooner admit it than hide, which is more than {T} can say.",
            ])
        case .counterattack:
            return "And who is it pointing the finger? " + reason(chip, suspicious: true, view: view, rng: &rng)
        case .appeal:
            return rng.pick([
                "I've given this everything I have. On my family, I'm a faithful.",
                "You've nothing on me but a feeling. I'm asking you to trust me.",
            ])
        case .denial, .redirect:
            return "I'm a faithful."
        }
    }

    private static func reason(_ chip: Chip?, suspicious: Bool, view: TableView, rng: inout SeededRNG) -> String {
        switch chip?.kind {
        case .missionSlip:
            return rng.pick([
                "{T} came back from {M} well short. Something else had their attention out there.",
                "I watched the board after {M}. {T} was under par, and I don't think it was nerves.",
                "{T} made a poor fist of {M}. A traitor with a side quest to do would look just like that.",
                "Look at {M} again. {T} is down among the stragglers, and I want to know why.",
            ])
        case .votedOutFaithful:
            return rng.pick([
                "{T} was quick to put {O} out the door, and {O} was a faithful.",
                "Who steered us wrong on {O}? {T} had that name written down.",
            ])
        case .sparedTraitor:
            return rng.pick([
                "When we caught {O}, {T} was voting somewhere else. Why?",
                "{T} never wrote {O}'s name. That's a traitor being minded.",
            ])
        case .defendedTraitor:
            return rng.pick([
                "{T} stood up for {O}, and {O} turned out to be a traitor.",
                "Remember who spoke for {O}? {T} did.",
            ])
        case .victimSuspected:
            return rng.pick([
                "{O} had {T} in their sights, and {O} is the one who never came down to breakfast.",
                "{O} was onto {T}. Now {O} is gone. That's motive.",
            ])
        case .sayVote:
            return rng.pick([
                "{T} told us one name and wrote another. I don't trust that.",
                "{T} said one thing at this table and did another at the vote.",
            ])
        case .votedTraitor:
            return rng.pick([
                "{T} voted for {O} when it counted. Traitors don't do that lightly.",
                "{T} helped us catch {O}. I'd leave them be.",
            ])
        case .accusedByTraitor:
            return rng.pick([
                "{O} went after {T}, and {O} was a traitor. That counts in {T}'s favour.",
                "A traitor tried to pin it on {T}. I'd say that clears them.",
            ])
        case .sighting:
            switch chip?.sight {
            case .offTask:
                return rng.pick([
                    "{T} kept drifting off into the corners in {M}, nowhere near the work.",
                    "Forget the score. {T} was wandering the edges of {M} where there was nothing to do.",
                ])
            case .loiter:
                return rng.pick([
                    "Forget the score. {T} stood about at the edge of {M} for ages, doing nothing.",
                    "I watched {T} hang back in {M}, waiting on something. What?",
                ])
            case .brokeAway:
                return rng.pick([
                    "{T} peeled away from the rest of us in {M} and went where nobody could see.",
                    "Halfway through {M}, {T} was gone. Out of everyone's sight. Why?",
                ])
            case .startled:
                return rng.pick([
                    "The second I came round in {M}, {T} jumped and made a show of being busy.",
                    "{T} turned on their heel in {M} the moment they saw me looking.",
                ])
            default:
                return rng.pick([
                    "I saw {T} at something in {M} that had nothing to do with the mission.",
                    "{T} was busy in {M} with something that was no part of the game. I saw it.",
                ])
            }
        case .inSight:
            return rng.pick([
                "{T} was in front of me the whole of {M} and never put a foot wrong.",
                "I had {T} in my sight all through {M}. There was nothing to see.",
            ])
        case .firstNamed:
            return rng.pick([
                "{T} was the first to name {O}, and {O} was a faithful.",
                "It was {T} who started us on {O}. We lost a faithful for it.",
            ])
        case .pushedHardest:
            return "Nobody pushed harder than {T} to be rid of {O}, and {O} was a faithful."
        case .sworeBy:
            return "{T} swore by {O}, and {O} was a traitor."
        case .caughtLie:
            return rng.pick([
                "{T} told us something about {O} that was flatly contradicted. One of them is lying.",
                "{T} was caught out on what they said about {O}.",
            ])
        case .flaggedEarly:
            return "{T} had doubts about {O} before any of us did, and {O} was a traitor."
        case .firstOnTraitor:
            return "{T} named {O} first, and {O} was a traitor. That's a faithful at work."
        case .cleanMissions:
            return rng.pick([
                "{T} hasn't put a foot wrong in the missions. We're wasting a vote there.",
                "Nothing {T} has done in a mission points their way.",
            ])
        default:
            return suspicious
                ? rng.pick([
                    "I can't prove it, but something is off with {T}.",
                    "My gut says {T}, and it has been saying it a while.",
                    "{T} is too comfortable. That's all I have, but I have it.",
                ])
                : rng.pick([
                    "I don't see it with {T}. I think we'd be wasting a vote.",
                    "Leave {T} alone. I'd stake a lot on them being faithful.",
                ])
        }
    }

    private static func openers(_ voice: Voice) -> [String] {
        switch voice {
        case .blunt: return ["Right.", "I'll say it straight.", "No dressing it up.", ""]
        case .loud: return ["Ah here!", "Lads, come on.", "I'm not having it.", ""]
        case .wry: return ["Call me cynical.", "Forgive me, but", "How convenient.", ""]
        case .quiet: return ["I've been listening.", "I'll say this much.", "", ""]
        case .warm: return ["I hate saying this, but", "No offence meant.", "Don't take this badly.", ""]
        case .sly: return ["Interesting, isn't it.", "Here's a tell.", "Notice something?", ""]
        case .earnest: return ["I've thought hard about this.", "Honestly,", "Hand on heart,", ""]
        case .plain: return [""]
        }
    }

    private static func missionName(_ chip: Chip?, _ view: TableView) -> String {
        guard let chip, let r = view.index.reports.first(where: { $0.day == chip.day }) else { return "the mission" }
        return r.kind.title
    }

    private static func fill(_ s: String, t: String, chip: Chip?, view: TableView) -> String {
        s.replacingOccurrences(of: "{T}", with: t)
            .replacingOccurrences(of: "{O}", with: chip?.other.map { view.name($0) } ?? "them")
            .replacingOccurrences(of: "{M}", with: missionName(chip, view))
    }

    private static func lowerFirst(_ s: String) -> String {
        // Keep names and "I" capitalised; only soften sentence openers like "When" or "Look".
        let keep = ["I ", "I'"]
        guard let first = s.first, !keep.contains(where: { s.hasPrefix($0) }) else { return s }
        let word = s.prefix { $0 != " " && $0 != "," && $0 != "'" && $0 != "." }
        let common = ["When", "Look", "Who", "Remember", "My", "That", "You", "A", "Nothing", "Leave"]
        return common.contains(String(word)) ? first.lowercased() + s.dropFirst() : s
    }
}
