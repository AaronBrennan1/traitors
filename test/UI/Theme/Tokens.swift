import SwiftUI
import UIKit
import TraitorsEngine

/// One colour, defined once and handed to SwiftUI, SpriteKit and SceneKit alike.
struct Swatch {
    let ui: UIColor

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
        ui = UIColor(red: r, green: g, blue: b, alpha: a)
    }

    init(_ ui: UIColor) { self.ui = ui }

    var color: Color { Color(uiColor: ui) }
    var cg: CGColor { ui.cgColor }
}

/// The look of the whole app: the castle by candlelight. `Palette` and `Toon` are views of this.
enum Tokens {
    enum Hue {
        // The shell.
        static let ink = Swatch(0.030, 0.047, 0.043)
        static let panel = Swatch(0.082, 0.118, 0.108)
        static let panelHi = Swatch(0.125, 0.170, 0.155)
        static let line = Swatch(1, 1, 1, 0.10)
        static let gold = Swatch(0.84, 0.70, 0.36)
        static let goldDeep = Swatch(0.56, 0.42, 0.17)
        static let parchment = Swatch(0.93, 0.90, 0.82)
        static let blood = Swatch(0.78, 0.20, 0.20)
        static let faithful = Swatch(0.33, 0.74, 0.58)
        /// Dark edges and deep shadow: ink with a little green in it.
        static let outline = Swatch(0.035, 0.055, 0.050)
        /// Only for things that give off light.
        static let ember = Swatch(1.00, 0.74, 0.36)
        static let mist = Swatch(0.70, 0.78, 0.76)

        // The gauntlet: stone that reads at a glance, a drop that is plainly a drop, and one
        // colour kept for whatever is about to hurt.
        static let flagstone = Swatch(0.34, 0.37, 0.38)
        static let flagstoneHi = Swatch(0.43, 0.46, 0.46)
        static let wallStone = Swatch(0.15, 0.17, 0.19)
        static let pit = Swatch(0.02, 0.03, 0.035)
        static let danger = Swatch(0.98, 0.30, 0.22)

        // Scenery, all a step darker and greyer than daylight.
        static let grass = Swatch(0.27, 0.42, 0.26)
        static let mossGreen = Swatch(0.30, 0.44, 0.28)
        static let hedge = Swatch(0.13, 0.29, 0.19)
        static let bog = Swatch(0.22, 0.18, 0.14)
        static let bogWater = Swatch(0.08, 0.12, 0.14)
        static let turf = Swatch(0.30, 0.20, 0.13)
        static let heather = Swatch(0.44, 0.34, 0.48)
        static let limestone = Swatch(0.58, 0.60, 0.57)
        static let slate = Swatch(0.25, 0.29, 0.32)
        static let wood = Swatch(0.52, 0.35, 0.21)
        static let woodDark = Swatch(0.33, 0.21, 0.13)
        static let steel = Swatch(0.62, 0.67, 0.72)
        static let straw = Swatch(0.80, 0.67, 0.36)
        static let sea = Swatch(0.11, 0.27, 0.35)
        /// The three pens of the round-up.
        static let ribbons = [Swatch(0.80, 0.27, 0.25), Swatch(0.28, 0.48, 0.80), Swatch(0.88, 0.73, 0.26)]

        /// The human's cloak, so no bot's colour can be mistaken for it.
        static let youCloak = Swatch(0.95, 0.93, 0.86)

        /// A cloak in a player's hue, the same on a token as on the figure in the arena.
        static func cloak(_ hue: Double) -> Swatch {
            Swatch(UIColor(hue: CGFloat(hue), saturation: 0.60, brightness: 0.74, alpha: 1))
        }

        static func cloak(for player: Player) -> Swatch { player.isHuman ? youCloak : cloak(player.hue) }
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let card: CGFloat = 14
        static let sheet: CGFloat = 22
    }

    enum Motion {
        static let quick = 0.12
        static let standard = 0.22
        static let reveal = 0.3
        static let slow = 0.45
        /// The player has asked for less movement: no shake, no confetti, no drifting.
        static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
    }

    /// Lettering. Everything is the system serif; these only differ in weight.
    enum TypeRole {
        case display, title, label, numeral, caption

        private var weight: UIFont.Weight {
            switch self {
            case .display: return .heavy
            case .title, .numeral: return .bold
            case .label: return .semibold
            case .caption: return .medium
            }
        }

        /// For SpriteKit and SceneKit, which draw their lettering into textures.
        func ui(_ size: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.serif) { return UIFont(descriptor: d, size: size) }
            return base
        }

        func font(_ style: Font.TextStyle) -> Font {
            let w: Font.Weight
            switch self {
            case .display: w = .heavy
            case .title, .numeral: w = .bold
            case .label: w = .semibold
            case .caption: w = .medium
            }
            let f = Font.system(style, design: .serif).weight(w)
            return self == .numeral ? f.monospacedDigit() : f
        }
    }
}
