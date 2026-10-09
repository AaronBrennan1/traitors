import Foundation
import TraitorsCore

/// A mini-game as whoever draws it may look at it. A stage reads the game it is given and
/// changes nothing: time, the thumbs and the result all go through the `ArenaSession`.
public protocol ArenaGame: AnyObject {
    var setup: ArenaSetup { get }
}

/// A mini-game as the session drives it, whichever game it is. The gauntlet is one; each of the
/// others is an `ArenaCore`.
package protocol ArenaPlay: ArenaGame {
    /// Seconds in one step. The game only ever moves in whole steps.
    var stepSeconds: Double { get }
    var input: ArenaInput { get set }
    func step()
    /// The human pressed their button.
    func press()
    /// The human let a strike go: which way and how hard, length 0...1.
    func shoot(_ shot: Vec2)

    var finished: Bool { get }
    var time: Double { get }
    var timeLeft: Double { get }
    var totalTime: Double { get }
    var teamTotal: Int { get }
    /// What the company has to bring home between them.
    var goal: Int { get }
    var won: Bool { get }
    /// Private: the traitor whose hand made the difference between making the goal and not.
    var sunkBy: PlayerID? { get }
    var ledger: MissionLedger { get }
    var cues: [ArenaCue] { get set }
    /// The seat of the human, while they are the one playing it.
    var humanSeat: PlayerID? { get }

    // For the player's own screen and for measuring. None of it goes into the result.
    /// What each seat has brought home, in the order of `setup.cast`.
    var tally: [Int] { get }
    /// What each seat's hand has cost the company.
    var loss: [Double] { get }
    /// How often each seat used the hand.
    var acts: [Int] { get }

    // What the session asks on behalf of whoever is at the controls.
    /// The button, the edge of sight and what is in hand this frame, `alpha` of the way between
    /// steps. Nil when nobody is at the controls.
    func panel(alpha: Double, pressed: Bool, playing: Bool) -> PlayerPanel?
    /// How the round went for the player themselves, beyond the count.
    func ownExtras(place: Int) -> [PlayerResult.Extra]
    /// Whether the player at the controls can see a seat. True where nothing is ever hidden.
    func playerSees(_ seat: PlayerID) -> Bool
    /// Where a numbered trap is, for a sound that comes from it.
    func trap(_ index: Int) -> Vec2?
    /// Where a strike pulled back this far would come down, and whether there is one to let go.
    func aim(_ pull: Vec2) -> (from: Vec2, to: Vec2, ready: Bool)?
}

/// What the player at the controls is shown about their own hands and eyes, this frame.
public struct PlayerPanel {
    /// 0...1 round the button while something is filling: a dash coming back, a job being done.
    public package(set) var ring: Double?
    /// Whether a press would do anything.
    public package(set) var lit: Bool
    /// A traitor is standing where a press would be the shadow's hand. The game's own answer.
    public package(set) var handInReach: Bool
    /// How far the player can see, where that is not the whole floor.
    public package(set) var sight: Double?
    /// Where they are looking from.
    public package(set) var eye: Vec2
    /// What is in their arms, and their run of deliveries.
    public package(set) var bags: (have: Int, of: Int, streak: Int)?
    /// Something of their own that runs down: air, sliotars.
    public package(set) var meter: (label: String, value: Double)?
}

/// How a round came out for whoever played it. Only they are shown it.
public struct PlayerResult {
    public struct Extra {
        public let value: Int
        public let what: What
        public enum What { case inARow, nearMisses, place(of: Int), mostByAnyone }
    }
    public let count: Int
    public let extras: [Extra]
}

/// What a traitor's hand did in a round. Only ever the human's own.
public struct HandSummary {
    public let uses: Int
    public let cost: Int
    /// It made the difference between the goal and falling short.
    public let sank: Bool
}

extension ArenaPlay {
    public func shoot(_ shot: Vec2) {}
}

extension ArenaPlay {
    public func playerSees(_ seat: PlayerID) -> Bool { true }
    public func trap(_ index: Int) -> Vec2? { nil }
    public func aim(_ pull: Vec2) -> (from: Vec2, to: Vec2, ready: Bool)? { nil }
}

extension Gauntlet: ArenaPlay {
    public var stepSeconds: Double { Feel.tick }
    public var totalTime: Double { Double(totalTicks) * Feel.tick }
    public var humanSeat: PlayerID? { human.map { runners[$0].id } }
    public var tally: [Int] { runners.map(\.banked) }

    public func panel(alpha: Double, pressed: Bool, playing: Bool) -> PlayerPanel? {
        guard let i = human else { return nil }
        let r = runners[i]
        let ready = playing ? r.dashReady : 1
        let far = vision(r.pos, r.pos)
        return PlayerPanel(ring: ready < 1 ? ready : nil, lit: ready >= 1, handInReach: canSabotage(r),
                           sight: far < 250 ? far : nil, eye: r.last + (r.pos - r.last) * alpha,
                           bags: (r.carry, Feel.maxCarry, r.streak), meter: nil)
    }

    public func ownExtras(place: Int) -> [PlayerResult.Extra] {
        guard let r = human.map({ runners[$0] }) else { return [] }
        return [.init(value: r.bestStreak, what: .inARow), .init(value: r.nearMisses, what: .nearMisses)]
    }

    public func trap(_ index: Int) -> Vec2? { hazards.indices.contains(index) ? hazards[index].a : nil }
}

enum ArenaGames {
    static func make(_ setup: ArenaSetup) -> any ArenaPlay {
        switch setup.kind {
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return Gauntlet(setup)
        case .bogRelay: return BogCore(setup)
        case .lanternRun: return LanternCore(setup)
        case .sheepRoundUp: return SheepCore(setup)
        case .shipwreckDive: return ShipCore(setup)
        case .ceiliChaos: return CeiliCore(setup)
        case .marketDay: return MarketCore(setup)
        case .kiteRace: return KiteCore(setup)
        case .hedgeMaze: return MazeCore(setup)
        case .hurley: return HurleyCore(setup)
        case .banquetPrep: return BanquetCore(setup)
        }
    }
}
