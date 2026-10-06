import Foundation

/// One mini-game as the runner and the screen need to know it, whichever game it is. The
/// gauntlet is one; each of the others is an `ArenaCore`.
protocol ArenaGame: AnyObject {
    var setup: ArenaSetup { get }
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
}

extension ArenaGame {
    func shoot(_ shot: Vec2) {}
}

extension Gauntlet: ArenaGame {
    var stepSeconds: Double { Feel.tick }
    var totalTime: Double { Double(totalTicks) * Feel.tick }
    var humanSeat: PlayerID? { human.map { runners[$0].id } }
    var tally: [Int] { runners.map(\.banked) }
}

enum ArenaGames {
    static func make(_ setup: ArenaSetup) -> any ArenaGame {
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
