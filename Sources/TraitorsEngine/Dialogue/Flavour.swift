import Foundation
import TraitorsCore
import TraitorsMinds

/// Things the cast say that are colour, not evidence: nothing here is logged, so no line may
/// depend on a role or point at anyone still in the game. The signatures take no role for that reason.
public enum Flavour {
    /// How someone introduces themselves on the way in.
    public static func introduction(_ voice: Voice) -> String {
        switch voice {
        case .blunt: return "Thirty years reading liars for a living. I'll read this room too."
        case .loud: return "I run a pub. I've heard every tall tale going, and told half of them."
        case .wry: return "I argue for a living. Do try to keep up."
        case .quiet: return "I don't say much. I watch."
        case .warm: return "I look after people. I'd love to trust you all. I won't."
        case .sly: return "I play cards for money. Make of that what you will."
        case .earnest: return "I spend my days with seven-year-olds. You can't be harder to read."
        case .plain: return "I'm here to win it."
        }
    }

    /// Said standing in the circle, before the role is declared.
    public static func lastWords(_ voice: Voice, seat: PlayerID, seed: UInt64, day: Int) -> String {
        var rng = SeededRNG.derived(seed, UInt64(day), UInt64(seat), 0x1A57)
        switch voice {
        case .blunt: return rng.pick(["You've made your choice. Now live with it.", "I've nothing to add. You'll know soon enough."])
        case .loud: return rng.pick(["Well, that's me told! Mind yourselves, the lot of you.", "Ye'll be talking about this one at breakfast, I promise you."])
        case .wry: return rng.pick(["I'd say no hard feelings. I'd possibly be lying.", "So many names on so many slates. How flattering."])
        case .quiet: return rng.pick(["I said what I had to say.", "It's been a long few days. Look after each other."])
        case .warm: return rng.pick(["I've loved every one of you. Truly. Mind each other.", "No hard feelings. I'd have done the same, maybe."])
        case .sly: return rng.pick(["Well played. Somebody at this table, anyway.", "I'd have bet against this. I'd have lost."])
        case .earnest: return rng.pick(["I did my best. I really did.", "I hope you're right about me. For your sake."])
        case .plain: return rng.pick(["I said what I had to say.", "Good luck to you all."])
        }
    }

    /// Said at breakfast over the empty chair.
    public static func murderReaction(_ voice: Voice, victim: String, seat: PlayerID, seed: UInt64, day: Int) -> String {
        var rng = SeededRNG.derived(seed, UInt64(day), UInt64(seat), 0xC4A1)
        let line: String
        switch voice {
        case .blunt: line = rng.pick(["{V}. Somebody in this room did that.", "So it's {V}. Right."])
        case .loud: line = rng.pick(["Ah no. Not {V}!", "{V}? Ah, for God's sake."])
        case .wry: line = rng.pick(["And then there were fewer.", "Poor {V}. Nobody even said goodnight."])
        case .quiet: line = rng.pick(["{V}.", "I had a feeling it would be {V}'s chair."])
        case .warm: line = rng.pick(["Oh, {V}. I only spoke to them last night.", "Not {V}. They didn't deserve that."])
        case .sly: line = rng.pick(["One chair short. Somebody slept well.", "{V}. That was not the obvious choice."])
        case .earnest: line = rng.pick(["That's not fair. {V} did nothing wrong.", "I really thought {V} would walk through that door."])
        case .plain: line = rng.pick(["{V}. I didn't see that coming.", "Not {V}."])
        }
        return line.replacingOccurrences(of: "{V}", with: victim)
    }

    /// Said at breakfast when every chair is filled.
    public static func quietNightReaction(_ voice: Voice, seat: PlayerID, seed: UInt64, day: Int) -> String {
        var rng = SeededRNG.derived(seed, UInt64(day), UInt64(seat), 0x9E7)
        switch voice {
        case .blunt: return rng.pick(["Everyone. Count again.", "No murder. Somebody will have to explain that."])
        case .loud: return rng.pick(["We're all here? We're all here!", "Well, would you look at that. A full table."])
        case .wry: return rng.pick(["A full house. How suspicious.", "Nobody dead. I hardly know what to do with myself."])
        case .quiet: return rng.pick(["All of us.", "I counted twice."])
        case .warm: return rng.pick(["Oh, thank God. Everyone.", "I've never been so glad to see you all."])
        case .sly: return rng.pick(["No murder. Now that is interesting.", "Somebody had a quiet night."])
        case .earnest: return rng.pick(["Everyone's here. Everyone's really here.", "I didn't sleep. I was sure it would be one of us."])
        case .plain: return rng.pick(["Everyone made it.", "A full table."])
        }
    }

    /// What a partner says in the turret when putting a name forward. Only traitors hear it.
    public static func turretAdvice(_ voice: Voice, victim: String) -> String {
        let line: String
        switch voice {
        case .blunt: line = "{V}. Sees too much. Tonight."
        case .loud: line = "It has to be {V}. Tell me I'm wrong."
        case .wry: line = "I'd hate for anything to happen to {V}. Tonight, ideally."
        case .quiet: line = "{V}."
        case .warm: line = "I'm fond of {V}. That's why it should be now."
        case .sly: line = "{V}. Nobody will see it coming, least of all {V}."
        case .earnest: line = "I've thought about it all day. {V}."
        case .plain: line = "I say {V}."
        }
        return line.replacingOccurrences(of: "{V}", with: victim)
    }
}
