import SwiftUI

/// The sound and haptics switches, wherever they are offered.
struct SettingsToggles: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Toggle(isOn: $store.settings.sound) {
                Label("Sound", systemImage: store.settings.sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .padding(.vertical, 10)
            Rectangle().fill(Palette.line).frame(height: 1)
            Toggle(isOn: $store.settings.haptics) {
                Label("Haptics", systemImage: "hand.tap.fill")
            }
            .padding(.vertical, 10)
        }
        .font(.serif(.subheadline, weight: .semibold))
        .foregroundStyle(Palette.parchment)
        .tint(Palette.gold)
        .onChange(of: store.settings.sound) { Feedback.play(.toggle) }
        .onChange(of: store.settings.haptics) { Feedback.play(.toggle) }
    }
}

/// The gauntlet stopped mid-round: how to play it, the switches, and the way out.
struct ArenaPauseView: View {
    let model: ArenaHUDModel
    /// The status bar's height, when the arena runs under it.
    var topInset: CGFloat = 0
    var onLeave: () -> Void

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

                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: "How to play")
                        ForEach(MissionKind.controls + [model.kind.twist], id: \.self) { line in
                            Text(line).font(.serif(.subheadline)).foregroundStyle(Palette.parchment)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .panel()

                    if let hand = model.handText { QuestBanner(text: hand) }

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
