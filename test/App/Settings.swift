import Foundation

/// What the player has switched on or off. Kept beside the stats, outside any one game.
struct Settings: Codable {
    var sound = true
    var haptics = true
}
