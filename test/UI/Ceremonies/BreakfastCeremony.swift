import SwiftUI

/// Breakfast: the table fills a few players at a time, and whoever was murdered is the chair
/// nobody comes to.
struct BreakfastCeremony: View {
    @Environment(GameStore.self) private var store
    @State private var shown = 0

    enum Moment {
        /// What the human finds in their own room, when they are the one.
        case letter
        case arrive([PlayerID])
        case empty
        case victim(PlayerID)
        case react(PlayerID, String)
        case line(Beat)
    }

    var body: some View {
        if let game = store.game {
            let script = MorningScript(game: game)
            let moments = Self.moments(game, script)
            let told = Array(moments.prefix(shown))
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            table(game, script, told)
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
                    if store.spectating, game.winner == nil { SpectatorNote() }
                    Button(game.winner != nil ? "See how it ended" : game.finale ? "To the Fire of Truth" : "To the mission") {
                        store.send(.next)
                    }
                    .buttonStyle(GoldButtonStyle())
                    .opacity(shown >= moments.count ? 1 : 0.45)
                }
            }
            .stepClock($shown, count: moments.count, key: "breakfast", hold: { hold(moments, $0) }, cue: { cue(moments[$0]) })
            .onChange(of: shown, initial: true) {
                // Once the chair has a name, or there is no empty chair at all, nothing is being held back.
                let named = told.contains { if case .victim = $0 { return true } else { return false } }
                if named || script.victim == nil { store.tell() }
            }
        }
    }

    static func moments(_ game: Game, _ script: MorningScript) -> [Moment] {
        var out: [Moment] = []
        if script.humanIsVictim { out.append(.letter) }
        out += script.arrivals.map { .arrive($0) }
        var lines = script.lines
        if let victim = script.victim {
            out.append(.empty)
            out.append(.victim(victim))
        } else if !lines.isEmpty {
            // The host speaks before anyone else does.
            out.append(.line(lines.removeFirst()))
        }
        for p in script.reactors {
            let voice = game.players[p].voice
            let text = script.victim.map { Flavour.murderReaction(voice, victim: game.players[$0].name, seat: p, seed: game.seed, day: game.day) }
                ?? Flavour.quietNightReaction(voice, seat: p, seed: game.seed, day: game.day)
            out.append(.react(p, text))
        }
        out += lines.map { .line($0) }
        return out
    }

    private func hold(_ moments: [Moment], _ i: Int) -> Double {
        if i == 0 { return 0.6 }
        switch moments[i] {
        case .letter: return 0.6
        case .arrive: return 1.1
        case .empty: return 1.8
        case .victim: return 2.4
        case .react: return 1.6
        case .line: return 1.3
        }
    }

    private func cue(_ moment: Moment) {
        switch moment {
        case .letter: Cue.letter.play()
        case .arrive: Cue.door.play()
        case .empty: Cue.heartbeat.play()
        case .victim: Cue.boom.play()
        default: break
        }
    }

    // MARK: - The table

    private func table(_ game: Game, _ script: MorningScript, _ told: [Moment]) -> some View {
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
            ForEach(script.seats(game), id: \.self) { p in
                let player = game.players[p]
                VStack(spacing: 4) {
                    if here.contains(p) || (p == script.victim && named) {
                        Avatar(player: player, size: 54, role: store.roleShown(p))
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
