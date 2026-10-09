import SwiftUI
import TraitorsEngine

/// Breakfast: the table fills a few players at a time, and whoever was murdered is the chair
/// nobody comes to.
struct BreakfastCeremony: View {
    @Environment(GameSession.self) private var session
    @State private var shown = 0

    typealias Moment = BreakfastTelling.Moment

    var body: some View {
        if let game = session.game {
            let telling = BreakfastTelling(game: game)
            let moments = telling.moments
            let told = Array(moments.prefix(shown))
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            table(game, telling, told)
                            ForEach(told.indices, id: \.self) { i in
                                row(game, told[i]).transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            Color.clear.frame(height: 4).id(-1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: shown) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(-1, anchor: .bottom) } }
                }
                .contentShape(Rectangle())
                .onTapGesture { shown = moments.count }
                .accessibilityAction(named: "Skip ahead") { shown = moments.count }
                BottomBar {
                    if session.spectating, game.winner == nil { SpectatorNote() }
                    Button(onward(session.prompt)) {
                        session.send(.proceed)
                    }
                    .buttonStyle(GoldButtonStyle())
                    .opacity(shown >= moments.count ? 1 : 0.45)
                }
            }
            .stepClock($shown, count: moments.count, key: "breakfast", hold: telling.hold, cue: { telling.cue($0)?.play() })
            .onChange(of: shown, initial: true) {
                if telling.told(shown: shown) { session.tell() }
            }
        }
    }

    private func onward(_ prompt: Prompt?) -> String {
        switch prompt {
        case .proceed(.ending): return "See how it ended"
        case .proceed(.fireOfTruth): return "To the Fire of Truth"
        default: return "To the mission"
        }
    }

    // MARK: - The table

    private func table(_ game: Game, _ script: BreakfastTelling, _ told: [Moment]) -> some View {
        var here: Set<PlayerID> = []
        var noticed = false, named = false
        for moment in told {
            switch moment {
            case .arrive(let group): here.formUnion(group)
            case .empty: noticed = true
            case .victim: named = true
            default: break
            }
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
            ForEach(script.seats, id: \.self) { p in
                let player = game.players[p]
                VStack(spacing: 4) {
                    if here.contains(p) || (p == script.victim && named) {
                        Avatar(player: player, size: 54, role: session.roleShown(p))
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    } else {
                        // A chair with nobody in it yet.
                        Circle()
                            .strokeBorder(p == script.victim && noticed ? Palette.blood : Palette.line,
                                          style: StrokeStyle(lineWidth: p == script.victim && noticed ? 2 : 1, dash: [4, 4]))
                            .frame(width: 54, height: 54)
                    }
                    Text(here.contains(p) || (p == script.victim && named) ? (player.isHuman ? "You" : player.name) : " ")
                        .font(.serif(.caption)).foregroundStyle(Palette.parchment).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Palette.ink.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }

    @ViewBuilder
    private func row(_ game: Game, _ moment: Moment) -> some View {
        switch moment {
        case .letter:
            Letter(heading: Host.letter, name: nil, footnote: "You have been murdered.")
        case .arrive:
            EmptyView()
        case .empty:
            HostLine(text: Host.emptyChair)
        case .victim(let p):
            HostLine(text: game.players[p].isHuman ? Host.youWereMurdered : Host.murdered(game.players[p].name))
        case .react(let p, let text):
            BeatRow(beat: Beat(kind: .speech, speaker: p, text: text))
        case .line(let beat):
            BeatRow(beat: beat)
        }
    }
}

/// A letter from the turret.
struct Letter: View {
    let heading: String
    let name: String?
    let footnote: String

    var body: some View {
        VStack(spacing: 10) {
            Text(heading)
                .font(.serif(.subheadline).italic())
            if let name {
                Text(name)
                    .font(.custom("Snell Roundhand", size: 40, relativeTo: .largeTitle).weight(.bold))
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            Text(footnote)
                .font(.serif(.footnote))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "seal.fill").font(.title2).foregroundStyle(Palette.blood)
        }
        .foregroundStyle(Color(red: 0.20, green: 0.13, blue: 0.08))
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .frame(maxWidth: 320)
        .background(Color(red: 0.87, green: 0.81, blue: 0.68), in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
        .rotationEffect(.degrees(-1.5))
        .accessibilityElement(children: .combine)
    }
}
