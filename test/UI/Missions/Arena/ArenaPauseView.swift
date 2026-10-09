import SwiftUI
import TraitorsEngine
import TraitorsGauntlet

/// The sound and haptics switches, wherever they are offered.
struct SettingsToggles: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            Toggle(isOn: $session.settings.sound) {
                Label("Sound", systemImage: session.settings.sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .padding(.vertical, 10)
            Rectangle().fill(Palette.line).frame(height: 1)
            Toggle(isOn: $session.settings.haptics) {
                Label("Haptics", systemImage: "hand.tap.fill")
            }
            .padding(.vertical, 10)
        }
        .font(.serif(.subheadline, weight: .semibold))
        .foregroundStyle(Palette.parchment)
        .tint(Palette.gold)
        .onChange(of: session.settings.sound) { Feedback.play(.toggle) }
        .onChange(of: session.settings.haptics) { Feedback.play(.toggle) }
    }
}

/// A mini-game stopped mid-round: the game demonstrating itself, the switches, and the way out.
struct ArenaPauseView: View {
    let model: ArenaHUDModel
    /// The status bar's height, when the arena runs under it.
    var topInset: CGFloat = 0
    var onLeave: () -> Void
    @State private var reel = ArenaDemo.Reel.play

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.86).ignoresSafeArea()
            ScrollView {
                VStack(spacing: Tokens.Space.l) {
                    VStack(spacing: 6) {
                        Image(systemName: model.kind.icon).font(.title).foregroundStyle(Palette.gold)
                        Text("Paused").font(.serif(.caption, weight: .heavy)).tracking(3).foregroundStyle(Palette.muted)
                        Text(model.title).font(.serif(.title2, weight: .bold)).foregroundStyle(Palette.parchment)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Tokens.Space.xl + topInset)

                    // How it is played, shown and not told. A traitor can turn it over to see the hand.
                    VStack(spacing: Tokens.Space.m) {
                        DemoReel(kind: model.kind, reel: reel, compact: true)
                            .frame(width: 210)
                        Text(reel == .hand ? model.kind.handGist : model.kind.gist)
                            .font(.serif(.subheadline, weight: .semibold)).foregroundStyle(Palette.parchment)
                            .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.6)
                        if model.handText != nil {
                            Button {
                                Feedback.play(.tap)
                                reel = reel == .hand ? .play : .hand
                            } label: {
                                Label(reel == .hand ? "The game" : "The shadow's hand", systemImage: reel == .hand ? "gamecontroller.fill" : "eye.slash.fill")
                                    .font(.serif(.caption, weight: .heavy)).tracking(1)
                                    .foregroundStyle(reel == .hand ? Palette.gold : Palette.blood)
                                    .padding(.horizontal, 12).frame(minHeight: 30)
                                    .overlay(Capsule().strokeBorder((reel == .hand ? Palette.gold : Palette.blood).opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SettingsToggles().panel()

                    VStack(spacing: 10) {
                        Button("Resume") { model.paused = false }.buttonStyle(GoldButtonStyle())
                        Button("Save and leave") { onLeave() }.buttonStyle(GhostButtonStyle())
                        Text("The mission starts again from the top when you come back.")
                            .font(.serif(.caption)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, Tokens.Space.xl)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}
