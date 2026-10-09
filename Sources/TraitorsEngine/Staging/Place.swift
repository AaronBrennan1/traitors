import Foundation
import TraitorsCore
import TraitorsMinds

/// Where in the castle the current moment happens. Staging only: no rule reads it.
public enum Place: String, CaseIterable {
    case hall, breakfastRoom, grounds, roundTable, turret, bedchamber, fireOfTruth

    public static func of(_ game: Game) -> Place {
        switch game.phase {
        // The role is not known yet, so the room must not depend on it.
        case .roleReveal: return .hall
        case .breakfast: return .breakfastRoom
        case .missionBrief, .mission, .missionResult: return .grounds
        case .roundTable, .voting, .voteReveal: return game.finale ? .fireOfTruth : .roundTable
        case .finaleChoice, .finaleReveal, .gameOver: return .fireOfTruth
        case .night:
            // Someone being offered a place is still in their own room; a spectator sees the turret.
            if case .answerOffer = game.prompt { return .bedchamber }
            if game.human == nil || !game.humanAlive || game.humanIsTraitor { return .turret }
            return .bedchamber
        }
    }

    /// Changes whenever the player walks somewhere new, which is when the curtain falls.
    public static func sceneKey(_ game: Game) -> String {
        "\(of(game).rawValue)-\(game.day)"
    }

    /// The title card for arriving here, or nil where the scene introduces itself.
    public static func card(_ game: Game) -> (title: String, subtitle: String)? {
        switch of(game) {
        case .hall: return nil
        case .breakfastRoom: return ("Day \(game.day)", "Breakfast")
        case .grounds: return ("The Mission", game.mission?.kind.title ?? "In the grounds")
        case .roundTable: return ("The Round Table", "Day \(game.day)")
        case .turret: return ("Nightfall", "The turret")
        case .bedchamber: return ("Nightfall", "Your chamber")
        case .fireOfTruth: return game.phase == .gameOver ? nil : ("The Fire of Truth", "The finale")
        }
    }
}
