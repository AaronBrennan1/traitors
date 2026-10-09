import SwiftUI
import TraitorsEngine

/// Night. Traitors meet hooded in the turret and seal a letter; the faithful lock their door
/// and put the candle out.
struct NightView: View {
    @Environment(GameSession.self) private var session
    @Environment(Stage.self) private var stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pick: PlayerID?
    /// The name on the letter, once it is being sealed.
    @State private var sealing: PlayerID?
    @State private var asleep = false

    var body: some View {
        if let game = session.game {
            let inTurret = Place.of(game) == .turret
            let asked = session.prompt ?? .proceed(then: .morning)
            let night = NightChoice(asked)
            let murder = night == .murder
            ZStack {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 14) {
                            if inTurret, !game.aliveTraitors.isEmpty, game.humanIsTraitor || session.spectating {
                                conclave(game)
                            } else if case .answerOffer(let r) = asked {
                                Avatar(player: game.players[r], size: 110, hooded: true).padding(.top, 16)
                            } else {
                                Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(Palette.gold)
                                    .padding(.top, 20).accessibilityHidden(true)
                            }
                            ForEach(game.feed.indices, id: \.self) { BeatRow(beat: game.feed[$0]) }
                            if case .murder(_, let advice?) = asked, let partner = game.aliveTraitors.first(where: { $0 != game.human }) {
                                BeatRow(beat: Beat(kind: .speech, speaker: partner,
                                                   text: Flavour.turretAdvice(game.players[partner].voice, victim: game.players[advice].name)))
                            }
                            if night == .none, game.humanAlive, !game.humanIsTraitor {
                                Text("You lock your door and try to sleep. Somewhere above, the turret may be busy.")
                                    .font(.serif(.subheadline).italic()).foregroundStyle(Palette.muted)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    BottomBar {
                        switch asked {
                        case .murder(let candidates, _), .recruit(let candidates):
                            VStack(alignment: .leading, spacing: 10) {
                                SectionTitle(text: murder ? "Choose your victim" : "Choose your recruit")
                                PlayerPicker(ids: candidates, selection: $pick)
                                Button(pick.map { "\(murder ? "Murder" : "Recruit") \(game.players[$0].name)" } ?? "Choose a player") {
                                    if let pick { seal(pick, murder: murder) }
                                }
                                .buttonStyle(GoldButtonStyle(tint: Palette.blood))
                                .disabled(pick == nil)
                            }
                        case .answerOffer:
                            HStack(spacing: 10) {
                                Button("Join the traitors") { session.send(.offer(accept: true)) }
                                    .buttonStyle(GoldButtonStyle(tint: Palette.blood))
                                Button("Refuse") { session.send(.offer(accept: false)) }
                                    .buttonStyle(GhostButtonStyle())
                            }
                        default:
                            if session.spectating { SpectatorNote() }
                            if game.humanAlive, !game.humanIsTraitor {
                                Button("Blow out the candle") { snuff() }.buttonStyle(GoldButtonStyle()).disabled(asleep)
                            } else {
                                Button("Wait for morning") { session.send(.proceed) }.buttonStyle(GoldButtonStyle())
                            }
                        }
                    }
                }
                if let sealing {
                    ZStack {
                        Palette.ink.opacity(0.9).ignoresSafeArea()
                        Letter(heading: murder ? Host.letter : "An invitation from the turret",
                               name: game.players[sealing].name,
                               footnote: murder ? "Sealed, and left at the door. Whether it finds its mark, you will learn at breakfast."
                                                : "Slipped under the door. By morning you will know the answer.")
                    }
                    .transition(.opacity)
                    .onTapGesture { deliver(sealing, murder: murder) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Continues to the morning")
                }
            }
            .onAppear { if case .murder(_, let advice) = asked { pick = advice } }
        }
    }

    /// The traitors still in the game, hoods up.
    private func conclave(_ game: Game) -> some View {
        HStack(spacing: 18) {
            ForEach(game.aliveTraitors, id: \.self) { p in
                VStack(spacing: 6) {
                    Avatar(player: game.players[p], size: 76, hooded: true)
                    Text(game.players[p].isHuman ? "You" : game.players[p].name)
                        .font(.serif(.caption, weight: .semibold)).foregroundStyle(Palette.parchment)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 18)
    }

    private func seal(_ target: PlayerID, murder: Bool) {
        Cue.letter.play()
        withAnimation(.easeInOut(duration: 0.4)) { sealing = target }
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            deliver(target, murder: murder)
        }
    }

    private func deliver(_ target: PlayerID, murder: Bool) {
        // The tap and the timer can both get here; only the first one counts.
        guard sealing == target, session.game?.phase == .night else { return }
        sealing = nil
        session.send(murder ? .murder(target) : .recruit(target))
    }

    private func snuff() {
        asleep = true
        Cue.snuff.play()
        withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 1.1)) { stage.dim = 1 }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if session.game?.phase == .night { session.send(.proceed) }
        }
    }
}
