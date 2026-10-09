import Foundation
import TraitorsEngine

// A staged scene written out as the moments it is told in: what is shown, in what order, how
// long each is held and what is heard with it. Plain values, so a ceremony's script can be
// checked without a view, and the view is left with nothing to do but draw the moment it is on.

/// The first evening: meeting the others, the blindfold, and the hand on the shoulder or not.
struct RoleTelling: Equatable {
    enum Moment: Equatable {
        case welcome(String)
        case meet(PlayerID)
        case blindfold, circling, footstep(Int)
        /// A hand on the shoulder, or the steps going by.
        case touch
        case done, reveal
        /// Traitors only: hoods down in the turret.
        case turret
    }

    let role: Role
    let moments: [Moment]

    init(game: Game, role: Role) {
        self.role = role
        var out: [Moment] = Host.welcome.map { .welcome($0) }
        out += game.players.indices.filter { !game.players[$0].isHuman }.map { .meet($0) }
        out += [.blindfold, .circling, .footstep(1), .footstep(2), .footstep(3), .touch, .done, .reveal]
        if role == .traitor { out.append(.turret) }
        moments = out
    }

    /// Seconds to wait before a moment appears.
    func hold(_ i: Int) -> Double {
        if i == 0 { return 0.7 }
        switch moments[i] {
        case .welcome: return 2.8
        case .meet: return 2.4
        case .blindfold: return 2.6
        case .circling: return 2.6
        case .footstep: return 1.2
        case .touch: return 1.8
        case .done: return 2.6
        case .reveal: return 2.4
        case .turret: return 3.4
        }
    }

    func cue(_ i: Int) -> Cue? {
        switch moments[i] {
        case .meet: return .door
        case .blindfold: return .snuff
        case .footstep: return .footstep
        case .touch: return role == .traitor ? .shoulder : .footstep
        case .done: return .bell
        case .reveal: return .declare(role)
        case .turret: return .boom
        default: return nil
        }
    }

    /// Whether the blindfold is on once `shown` moments have played.
    func blindfolded(shown: Int) -> Bool {
        guard shown > 0 else { return false }
        switch moments[shown - 1] {
        case .blindfold, .circling, .footstep, .touch: return true
        default: return false
        }
    }
}

/// Breakfast: the table fills a few players at a time, and whoever was murdered is the chair
/// nobody comes to.
struct BreakfastTelling: Equatable {
    enum Moment: Equatable {
        /// What the human finds in their own room, when they are the one.
        case letter
        case arrive([PlayerID])
        case empty
        case victim(PlayerID)
        case react(PlayerID, String)
        case line(Beat)
    }

    let moments: [Moment]
    /// Whose chair is empty this morning.
    let victim: PlayerID?
    /// The table as it was last night: everyone here now, plus the chair nobody comes to.
    let seats: [PlayerID]

    init(game: Game) {
        let script = MorningScript(game: game)
        victim = script.victim
        seats = script.seats(game)
        var out: [Moment] = []
        if script.humanIsVictim { out.append(.letter) }
        out += script.arrivals.map { .arrive($0) }
        var lines = script.lines
        if let victim = script.victim {
            out.append(.empty)
            out.append(.victim(victim))
        } else if !lines.isEmpty {
            // The host speaks before anyone else does.
            out.append(.line(lines.removeFirst()))
        }
        for p in script.reactors {
            let voice = game.players[p].voice
            let text = script.victim.map { Flavour.murderReaction(voice, victim: game.players[$0].name, seat: p, seed: game.seed, day: game.day) }
                ?? Flavour.quietNightReaction(voice, seat: p, seed: game.seed, day: game.day)
            out.append(.react(p, text))
        }
        out += lines.map { .line($0) }
        moments = out
    }

    func hold(_ i: Int) -> Double {
        if i == 0 { return 0.6 }
        switch moments[i] {
        case .letter: return 0.6
        case .arrive: return 1.1
        case .empty: return 1.8
        case .victim: return 2.4
        case .react: return 1.6
        case .line: return 1.3
        }
    }

    func cue(_ i: Int) -> Cue? {
        switch moments[i] {
        case .letter: return .letter
        case .arrive: return .door
        case .empty: return .heartbeat
        case .victim: return .boom
        default: return nil
        }
    }

    /// Once the chair has a name, or there is no empty chair at all, nothing is being held back.
    func told(shown: Int) -> Bool {
        victim == nil || moments.prefix(shown).contains { if case .victim = $0 { return true } else { return false } }
    }
}

/// The vote as it is told at the table: slates turned one at a time with the count kept beside
/// them, then the banished player's walk, last words, and only then what they were.
struct VoteTelling: Equatable {
    enum Moment: Equatable {
        case line(Beat)
        /// The host calls for the slates.
        case call
        case slate(voter: PlayerID, target: PlayerID, round: Int, left: Int)
        case walk(PlayerID)
        case words(PlayerID, String)
        case ask
        case declare(PlayerID, Role?)
        case verdict(Beat)
    }

    private(set) var moments: [Moment] = []
    /// For each moment, how many of the script's steps have played once it has.
    private(set) var played: [Int] = []
    private let script: VoteScript

    static func == (a: VoteTelling, b: VoteTelling) -> Bool { a.moments == b.moments && a.played == b.played }

    /// The engine's script, with the host's calls, the last words and the question put to
    /// whoever is leaving worked in.
    init(game: Game) {
        script = VoteScript(game: game)
        var called = false
        for (i, step) in script.steps.enumerated() {
            var add: [Moment] = []
            switch step {
            case .line(let beat):
                add = [.line(beat)]
            case .slate(let voter, let target, let round):
                if !called, round == 1 {
                    // The call comes before the slate it is for.
                    moments.append(.call)
                    played.append(i)
                }
                called = true
                add = [.slate(voter: voter, target: target, round: round, left: script.slatesLeft(after: i))]
            case .banish(let target, let role):
                add = [.walk(target)]
                // In the finale they leave without a word, and nobody is told what they were.
                if role != nil {
                    let p = game.players[target]
                    if !p.isHuman { add.append(.words(target, Flavour.lastWords(p.voice, seat: target, seed: game.seed, day: game.day))) }
                    add.append(.ask)
                }
                add.append(.declare(target, role))
            case .verdict(let beat):
                add = [.verdict(beat)]
            }
            moments += add
            played += Array(repeating: i + 1, count: add.count)
        }
    }

    /// Seconds to wait before a moment appears: the last few slates are turned slowly.
    func hold(_ i: Int) -> Double {
        if i == 0 { return 0.5 }
        switch moments[i] {
        case .line: return 0.9
        case .call: return 0.9
        case .slate(_, _, _, let left): return left == 0 ? 2.4 : left <= 2 ? 1.7 : 1.1
        case .walk: return 2.0
        case .words: return 2.0
        case .ask: return 2.4
        case .declare(_, let role): return role == nil ? 2.2 : 3.0
        case .verdict: return 2.4
        }
    }

    func cue(_ i: Int) -> Cue? {
        switch moments[i] {
        case .call: return .bell
        case .slate(_, _, _, let left): return left <= 1 ? .lateSlate : .slate
        case .walk: return .boom
        case .ask: return .heartbeat
        case .declare(_, let role): return .declare(role)
        default: return nil
        }
    }

    /// The count for the round in progress once `shown` moments have played.
    func tally(shown: Int) -> [(player: PlayerID, votes: Int)] {
        script.tally(shown: shown > 0 ? played[min(shown, played.count) - 1] : 0)
    }

    /// The moment the second round begins at, for a viewer who has already watched the first.
    var revoteStart: Int? {
        script.revoteStart.flatMap { step in played.firstIndex { $0 > step } }
    }

    /// The moment the banishment begins at.
    var banishAt: Int? {
        moments.firstIndex { if case .walk = $0 { return true } else { return false } }
    }

    /// What the banished player declared, once `shown` moments have played. Until then the rest
    /// of the screen keeps them seated.
    func declared(shown: Int) -> (told: Bool, role: Role?) {
        for moment in moments.prefix(shown) {
            if case .declare(_, let role) = moment { return (true, role) }
        }
        return (false, nil)
    }
}
