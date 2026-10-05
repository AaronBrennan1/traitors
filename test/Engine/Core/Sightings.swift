import Foundation

/// How somebody was seen to carry themselves during a mission.
enum SightingKind: String, Codable, CaseIterable {
    /// Drifting to corners and dead ends that do nothing for the mission.
    case offTask
    /// Standing about somewhere out of the way.
    case loiter
    /// Up at the vault with nothing to put in it.
    case emptyHanded
    /// Stopping, turning back or looking busy the moment someone came into view.
    case startled
    /// Standing by a lever, a sconce or the vault door when it went.
    case atTheWorks
    /// Watched the whole way through and did nothing odd.
    case inView

    var index: Int { Self.allCases.firstIndex(of: self)! }
    var suspicious: Bool { self != .inView }
}

/// One thing that happened in a mission and who was looking. Private: it only becomes
/// public when a witness says it at the table, and then it is only their word.
struct Sighting: Codable, Equatable {
    var day: Int
    var subject: PlayerID
    var kind: SightingKind
    var witnesses: SeatMask

    func clashes(with claim: SightingKind) -> Bool {
        claim.suspicious ? kind == .inView : kind.suspicious
    }
}

/// How often people do odd things in a mission, with and without the shadow's hand to use.
enum SightingModel {
    /// Chance an ordinary player does this on an ordinary day.
    static func baseline(_ kind: SightingKind) -> Double {
        switch kind {
        case .offTask: return 0.15
        case .loiter: return 0.08
        case .emptyHanded: return 0.08
        case .startled: return 0.06
        case .atTheWorks: return 0.03
        case .inView: return 0
        }
    }

    /// A player's own habit, 0.5...1.5 times the baseline: some people always wander.
    /// It scales the innocent and the guilty rate alike, so the evidence is the same for everyone.
    static func quirk(seed: UInt64, player: PlayerID, kind: SightingKind) -> Double {
        var r = SeededRNG.derived(seed, UInt64(player), UInt64(kind.index))
        return r.range(0.5, 1.5)
    }

    /// How much likelier the behaviour is from this player while using the shadow's hand.
    /// A composed liar leaks less than the table assumes, a nervous one more.
    static func lift(_ kind: SightingKind, deceit: Double) -> Double {
        1 + (Tuning.sight(kind) - 1) * (1.42 - 0.7 * deceit)
    }

    /// Chance one onlooker catches a given piece of behaviour.
    static func watch(_ perception: Double) -> Double { 0.14 + 0.22 * perception }

    /// Chance one onlooker has eyes on a given player from start to finish.
    static func cover(_ perception: Double) -> Double { 0.03 + 0.05 * perception }
}
