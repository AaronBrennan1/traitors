import SwiftUI
import TraitorsEngine

/// The vote, told the way it is at the table: slates turned one at a time with the count kept
/// beside them, then the banished player's walk, last words, and only then what they were.
struct VoteCeremony: View {
    @Environment(GameSession.self) private var session
    @Environment(Stage.self) private var stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var vote: PlayerID?

    typealias Moment = VoteTelling.Moment

    var body: some View {
        if let game = session.game {
            let telling = VoteTelling(game: game)
            let moments = telling.moments
            let banishAt = telling.banishAt
            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 0) {
                        tally(game, telling)
                        slates(game, moments, upTo: banishAt ?? moments.count)
                    }
                    if let banishAt, shown > banishAt {
                        banishment(game, Array(moments[banishAt...].prefix(shown - banishAt)))
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { shown = moments.count }
                .accessibilityAction(named: "Skip to the result") { shown = moments.count }
                BottomBar {
                    if case .vote(_, let candidates) = session.prompt {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Tie-break: vote again")
                            PlayerPicker(ids: candidates, selection: $vote)
                            Button(vote.map { "Vote to banish \(game.players[$0].name)" } ?? "Choose a player") {
                                if let vote { session.send(.vote(vote)) }
                                vote = nil
                            }
                            .buttonStyle(GoldButtonStyle())
                            .disabled(vote == nil)
                        }
                        .opacity(shown >= moments.count ? 1 : 0.4)
                        .allowsHitTesting(shown >= moments.count)
                    } else {
                        if session.spectating, game.winner == nil { SpectatorNote() }
                        Button(onward(session.prompt)) { session.send(.proceed) }
                            .buttonStyle(GoldButtonStyle())
                            .opacity(shown >= moments.count ? 1 : 0.45)
                    }
                }
            }
            .stepClock($shown, count: moments.count, key: "vote", hold: telling.hold, cue: { telling.cue($0)?.play() })
            .onChange(of: shown) { sync(telling) }
            .onAppear {
                // Coming back to a reveal whose first round was already watched: pick up at the revote.
                if shown == 0, game.phase == .voteReveal, let me = game.human, let at = telling.revoteStart,
                   moments.contains(where: { if case .slate(me, _, 2, _) = $0 { return true } else { return false } }) {
                    shown = at
                }
            }
        }
    }

    /// Once the declaration has been made, the rest of the screen may show it.
    private func sync(_ telling: VoteTelling) {
        let declared = telling.declared(shown: shown)
        guard declared.told else { return }
        session.tell()
        if let role = declared.role, stage.flood == nil {
            withAnimation(.easeInOut(duration: reduceMotion ? 1.6 : 0.6)) { stage.flood = Palette.role(role) }
        }
    }

    private func onward(_ prompt: Prompt?) -> String {
        switch prompt {
        case .proceed(.ending): return "See how it ended"
        case .proceed(.night): return "Nightfall"
        default: return "Continue"
        }
    }

    // MARK: - The slates

    @ViewBuilder
    private func tally(_ game: Game, _ telling: VoteTelling) -> some View {
        let rows = telling.tally(shown: shown)
        if !rows.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                ForEach(rows, id: \.player) { row in
                    VStack(spacing: 4) {
                        Avatar(player: game.players[row.player], size: 40, role: session.roleShown(row.player))
                        Text(game.players[row.player].isHuman ? "You" : game.players[row.player].name)
                            .font(.serif(.caption2)).foregroundStyle(Palette.parchment).lineLimit(1)
                        Text("\(row.votes)")
                            .font(.serif(.title2, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Palette.gold)
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(game.players[row.player].name), \(row.votes) \(row.votes == 1 ? "vote" : "votes")")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Palette.ink.opacity(0.6))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }

    private func slates(_ game: Game, _ moments: [Moment], upTo end: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(0..<min(shown, end), id: \.self) { i in
                        row(game, moments[i])
                            .id(i)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Color.clear.frame(height: 4).id(-1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: shown) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(-1, anchor: .bottom) } }
        }
    }

    @ViewBuilder
    private func row(_ game: Game, _ moment: Moment) -> some View {
        switch moment {
        case .line(let beat):
            BeatRow(beat: beat)
        case .call:
            HostLine(text: Host.slates)
        case .slate(let voter, let target, _, _):
            HStack(spacing: 10) {
                Avatar(player: game.players[voter].seated, size: 34)
                Text(game.players[voter].isHuman ? "You" : game.players[voter].name)
                    .font(.serif(.subheadline)).foregroundStyle(Palette.parchment)
                Spacer(minLength: 8)
                // The slate itself, with the name chalked on it.
                Text(game.players[target].isHuman ? "\(game.players[target].name) (you)" : game.players[target].name)
                    .font(.custom("Chalkduster", size: 17, relativeTo: .headline))
                    .foregroundStyle(Palette.parchment)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .frame(minWidth: 130)
                    .background(Color(red: 0.10, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.42, green: 0.30, blue: 0.18), lineWidth: 3))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Palette.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(game.players[voter].name) votes for \(game.players[target].name)")
        default:
            EmptyView()
        }
    }

    // MARK: - The banishment

    private func banishment(_ game: Game, _ told: [Moment]) -> some View {
        ZStack {
            Palette.ink.opacity(0.88)
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(told.indices, id: \.self) { i in
                        scene(game, told[i]).transition(.opacity)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center)
        }
    }

    @ViewBuilder
    private func scene(_ game: Game, _ moment: Moment) -> some View {
        switch moment {
        case .walk(let p):
            VStack(spacing: 12) {
                Avatar(player: game.players[p], size: 112, role: session.roleShown(p))
                HostLine(text: Host.banished(game.players[p].name))
            }
        case .words(_, let text):
            Text("“\(text)”")
                .font(.serif(.title3).italic())
                .foregroundStyle(Palette.parchment)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .ask:
            HostLine(text: Host.declare)
        case .declare(let p, let role):
            if let role {
                VStack(spacing: 6) {
                    Text(game.players[p].isHuman ? "You say it:" : "\(game.players[p].name):")
                        .font(.serif(.subheadline)).foregroundStyle(Palette.muted)
                    Text("“I am a")
                        .font(.serif(.title3).italic()).foregroundStyle(Palette.parchment)
                    Text(role == .traitor ? "TRAITOR" : "FAITHFUL")
                        .font(.serif(.largeTitle, weight: .heavy)).tracking(5)
                        .foregroundStyle(Palette.role(role))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .accessibilityLabel(role == .traitor ? "I am a traitor" : "I am a faithful")
                }
                .accessibilityElement(children: .combine)
            } else {
                VStack(spacing: 10) {
                    Text("\(game.players[p].name) leaves without a word.")
                        .font(.serif(.title3).italic()).foregroundStyle(Palette.parchment)
                        .multilineTextAlignment(.center)
                    HostLine(text: Host.finaleBanished)
                }
            }
        case .verdict(let beat):
            BeatRow(beat: beat)
        default:
            EmptyView()
        }
    }
}
