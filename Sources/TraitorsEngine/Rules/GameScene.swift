import Foundation
import TraitorsCore
import TraitorsMinds

/// What the human seat is entitled to see right now.
///
/// The rules run ahead of the telling: by the time a banishment or a murder is being announced
/// the game has already sent that player out. Until the screen has said so (`told`), they are
/// shown in their seat and nothing about their going is given away.
public struct GameScene {
    public struct Seat {
        /// The player as they may be shown: still seated if their going has not been told.
        public let player: Player
        /// The role the human may see for them, if any.
        public let role: Role?
    }

    public let phase: Phase
    public let day: Int
    package let pot: Int
    package let finale: Bool
    public let seats: [Seat]
    /// The lines to present, in order.
    package let lines: [Beat]
    /// Whatever has just been resolved, as data.
    package let outcome: Outcome?
    /// Players the game has sent out whose going the screen has not told yet.
    public let concealed: Set<PlayerID>
    /// The human is out, and has been told so.
    public let spectating: Bool

    public func role(_ p: PlayerID) -> Role? { seats[p].role }
    public func shown(_ p: PlayerID) -> Player { seats[p].player }
}

extension Player {
    /// The player as they were while still at the table.
    public var seated: Player {
        var p = self
        p.alive = true
        return p
    }
}

extension Game {
    /// The scene as the human may see it. `told` is whether the screen has announced who has
    /// just left, which only matters at a banishment and at breakfast.
    public func scene(told: Bool) -> GameScene {
        var concealed: Set<PlayerID> = []
        if !told {
            if phase == .voteReveal, let out = outcome?.vote?.banished { concealed = [out] }
            if phase == .breakfast, let victim = outcome?.morning?.victim { concealed = [victim] }
        }
        // Out, and told so. With nobody in the human's seat there is nobody to keep anything from.
        let humanOut = !humanAlive && !(human.map(concealed.contains) ?? false)
        let open = phase == .gameOver || humanOut
        let seats = players.map { p -> GameScene.Seat in
            let role: Role?
            if open || p.id == human {
                role = p.role
            } else if humanIsTraitor, p.role == .traitor {
                role = .traitor
            } else {
                role = concealed.contains(p.id) ? nil : revealedRole(p.id)
            }
            return GameScene.Seat(player: concealed.contains(p.id) ? p.seated : p, role: role)
        }
        return GameScene(phase: phase, day: day, pot: pot, finale: finale, seats: seats, lines: feed, outcome: outcome,
                     concealed: concealed, spectating: human != nil && humanOut)
    }
}
