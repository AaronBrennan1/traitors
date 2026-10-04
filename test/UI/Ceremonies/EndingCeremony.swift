import SwiftUI

/// The last scene at the fire: whoever is left steps up and says what they are, and only then
/// is the winner named. Shown once per game, ahead of the summary.
struct EndingCeremony: View {
    @Environment(GameStore.self) private var store
    @Environment(Stage.self) private var stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDone: () -> Void
    @State private var shown = 0

    var body: some View {
        if let game = store.game {
            let survivors = game.alive
            // The host's call, one moment for each survivor, then the result.
            let count = survivors.count + 2
            let winner = game.winner ?? .faithful
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        if shown > 0 { HostLine(text: Host.finalReveal).transition(.opacity) }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: min(max(survivors.count, 1), 3)), spacing: 16) {
                            ForEach(Array(survivors.enumerated()), id: \.element) { i, p in
                                let said = shown > i + 1
                                let role = game.players[p].role
                                VStack(spacing: 6) {
                                    Avatar(player: game.players[p], size: 76, role: said ? role : nil)
                                    Text(game.players[p].isHuman ? "You" : game.players[p].name)
                                        .font(.serif(.subheadline, weight: .semibold)).foregroundStyle(Palette.parchment)
                                    Text(said ? (role == .traitor ? "TRAITOR" : "FAITHFUL") : " ")
                                        .font(.serif(.caption, weight: .heavy)).tracking(2)
                                        .foregroundStyle(Palette.role(role))
                                }
                                .opacity(shown > 0 ? 1 : 0)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        if shown >= count {
                            Text(winner == .traitor ? "THE TRAITORS WIN" : "THE FAITHFUL WIN")
                                .font(.serif(.title, weight: .heavy)).tracking(2)
                                .foregroundStyle(Palette.role(winner))
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center)
                .contentShape(Rectangle())
                .onTapGesture { shown = count }
                .accessibilityAction(named: "Skip to the result") { shown = count }
                Button("See how it unfolded", action: onDone)
                    .buttonStyle(GoldButtonStyle(tint: Palette.role(winner)))
                    .opacity(shown >= count ? 1 : 0.45)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .stepClock($shown, count: count, key: "ending", hold: { $0 == 0 ? 0.8 : $0 == count - 1 ? 2.6 : 2.2 }, cue: { i in
                if i == 0 { Cue.bell.play() }
                else if i == count - 1 { Cue.declare(winner).play() }
                else { Cue.heartbeat.play() }
            })
            .onChange(of: shown, initial: true) {
                if shown >= count, stage.flood == nil {
                    withAnimation(.easeInOut(duration: reduceMotion ? 1.6 : 0.8)) { stage.flood = Palette.role(winner) }
                }
            }
        }
    }
}
