import SwiftUI
import TraitorsEngine

enum Palette {
    static let ink = Tokens.Hue.ink.color
    static let panel = Tokens.Hue.panel.color
    static let panelHi = Tokens.Hue.panelHi.color
    static let line = Tokens.Hue.line.color
    static let gold = Tokens.Hue.gold.color
    static let parchment = Tokens.Hue.parchment.color
    static let muted = Tokens.Hue.parchment.color.opacity(0.62)
    static let blood = Tokens.Hue.blood.color
    static let faithful = Tokens.Hue.faithful.color

    static func role(_ role: Role) -> Color { role == .traitor ? blood : faithful }
    static func cloak(_ hue: Double) -> Color { Tokens.Hue.cloak(hue).color }
    static func cloak(for player: Player) -> Color { Tokens.Hue.cloak(for: player).color }
}

extension Font {
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

struct CastleBackground: View {
    var tint: Color = Palette.gold

    var body: some View {
        ZStack {
            // The great hall, standing still: the ground for the title, the sheets and the walkthrough.
            Canvas { ctx, size in PlacePainter(place: .hall, size: size).paint(&ctx) }
            LinearGradient(colors: [Palette.ink.opacity(0.35), Palette.ink.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [tint.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct Panel: ViewModifier {
    var stroke: Color = Palette.line
    var fill: Color = Palette.panel

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke, lineWidth: 1))
    }
}

extension View {
    func panel(stroke: Color = Palette.line, fill: Color = Palette.panel) -> some View {
        modifier(Panel(stroke: stroke, fill: fill))
    }
}

struct GoldButtonStyle: ButtonStyle {
    var tint: Color = Palette.gold
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.serif(.headline, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(tint.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Palette.parchment
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.serif(.subheadline, weight: .semibold))
            .foregroundStyle(tint.opacity(enabled ? 1 : 0.35))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(tint.opacity(configuration.isPressed ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(enabled ? 0.35 : 0.12), lineWidth: 1))
    }
}
