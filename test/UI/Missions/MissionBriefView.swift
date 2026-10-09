import SwiftUI
import TraitorsEngine
import TraitorsGauntlet

/// Before each mission: the game playing itself for a few seconds, one line to say what it is,
/// and for a traitor a second reel that shows the shadow's hand. Nothing here has to be read to
/// be understood. The long form of it is still there for VoiceOver, on the reel.
struct MissionBriefView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which reel is showing: the game, or the hand.
    @State private var reel = ArenaDemo.Reel.play
    /// The hand has been shown once without being asked for. After that it is left to the traitor.
    @State private var turned = false
    @State private var arrived = false

    var body: some View {
        if let game = session.game, let run = game.mission {
            let kind = run.kind
            let secrets = game.feed.filter { $0.kind == .secret }
            let traitor = !secrets.isEmpty
            let hand = reel == .hand
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if traitor { reelSwitch }

                    DemoReel(kind: kind, reel: reel) {
                        // A traitor is shown the hand once the game itself has played through.
                        guard traitor, !turned, reel == .play else { return }
                        turned = true
                        turn(to: .hand)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(arrived || reduceMotion ? 1 : 0.96)
                    .opacity(arrived ? 1 : 0)
                    .gesture(DragGesture(minimumDistance: 24).onEnded { drag in
                        guard traitor, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                        turned = true
                        turn(to: drag.translation.width < 0 ? .hand : .play)
                    })

                    // The one line.
                    Text(hand ? kind.handGist : kind.gist)
                        .font(Tokens.TypeRole.title.font(.title3))
                        .foregroundStyle(Palette.parchment)
                        .multilineTextAlignment(.center)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity)
                        .opacity(arrived ? 1 : 0)
                        .offset(y: arrived || reduceMotion ? 0 : 8)

                    HStack(spacing: 8) {
                        chip("flag.checkered", "\(run.teamGoal) \(kind.spec.unit)", says: "The goal is \(run.teamGoal) \(kind.spec.unit) between you")
                        chip("hourglass", "\(Int(kind.spec.seconds(day: game.day)))s", says: "\(Int(kind.spec.seconds(day: game.day))) seconds")
                        if hand {
                            chip("moon.fill", "Your night", tint: Palette.blood, says: "Keep the company short of its goal and the night is the traitors'")
                        } else {
                            chip("checkmark.shield.fill", "Safe night", tint: Palette.faithful, says: "Make the goal and nobody is murdered tonight")
                        }
                    }
                    .opacity(arrived ? 1 : 0)

                    // What a traitor is told about tonight is the state of the game, not how to play it.
                    if hand, secrets.count > 1 {
                        Label(secrets[1].text, systemImage: "moon.stars.fill")
                            .font(.serif(.caption)).foregroundStyle(Palette.muted)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomBar {
                    if !game.humanAlive, game.human != nil { SpectatorNote() }
                    Button(game.humanAlive ? "Begin the mission" : "Watch the mission") {
                        Feedback.play(.tap)
                        session.send(.proceed)
                    }
                    .buttonStyle(GoldButtonStyle())
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: Tokens.Motion.standard) : .spring(response: 0.45, dampingFraction: 0.82)) { arrived = true }
            }
        }
    }

    private func turn(to next: ArenaDemo.Reel) {
        guard next != reel else { return }
        Feedback.play(.tap)
        withAnimation(.easeInOut(duration: Tokens.Motion.reveal)) { reel = next }
    }

    /// Two reels for a traitor: the game everyone plays, and what only they can do in it.
    private var reelSwitch: some View {
        HStack(spacing: 6) {
            tab(.play, "gamecontroller.fill", "The game", Palette.gold)
            tab(.hand, "eye.slash.fill", "The shadow's hand", Palette.blood)
        }
    }

    private func tab(_ which: ArenaDemo.Reel, _ icon: String, _ name: String, _ tint: Color) -> some View {
        let on = reel == which
        return Button {
            turned = true
            turn(to: which)
        } label: {
            Label(name, systemImage: icon)
                .font(.serif(.caption, weight: .heavy)).tracking(1)
                .foregroundStyle(on ? Palette.ink : tint)
                .padding(.horizontal, 12).frame(minHeight: 30)
                .background(on ? tint : tint.opacity(0.1), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(on ? 0 : 0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A number worth knowing, with a glyph for what it is the number of.
    private func chip(_ icon: String, _ value: String, tint: Color = Palette.gold, says: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            Text(value).font(Tokens.TypeRole.numeral.font(.footnote)).foregroundStyle(Palette.parchment).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Palette.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(says)
    }
}

extension MissionKind {
    /// The colour of each game's light, for the card that introduces it.
    var tint: Color {
        switch self {
        case .greatHall: return Color(red: 0.50, green: 0.30, blue: 0.16)
        case .cellars: return Color(red: 0.34, green: 0.22, blue: 0.16)
        case .armoury: return Color(red: 0.28, green: 0.32, blue: 0.40)
        case .battlements: return Color(red: 0.16, green: 0.22, blue: 0.40)
        case .crypt: return Color(red: 0.12, green: 0.30, blue: 0.26)
        case .bogRelay: return Color(red: 0.42, green: 0.27, blue: 0.20)
        case .lanternRun: return Color(red: 0.12, green: 0.16, blue: 0.36)
        case .sheepRoundUp: return Color(red: 0.22, green: 0.38, blue: 0.20)
        case .shipwreckDive: return Color(red: 0.10, green: 0.30, blue: 0.38)
        case .ceiliChaos: return Color(red: 0.52, green: 0.34, blue: 0.12)
        case .marketDay: return Color(red: 0.50, green: 0.24, blue: 0.18)
        case .kiteRace: return Color(red: 0.24, green: 0.36, blue: 0.48)
        case .hedgeMaze: return Color(red: 0.12, green: 0.30, blue: 0.18)
        case .hurley: return Color(red: 0.46, green: 0.26, blue: 0.30)
        case .banquetPrep: return Color(red: 0.48, green: 0.30, blue: 0.14)
        }
    }
}

extension MissionKind {
    /// What plays under the game.
    var bed: Bed {
        switch self {
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return .gauntlet
        case .ceiliChaos, .marketDay, .banquetPrep: return .reel
        case .bogRelay, .shipwreckDive, .kiteRace: return .shore
        case .lanternRun, .hedgeMaze: return .dusk
        case .sheepRoundUp, .hurley: return .green
        }
    }
}
