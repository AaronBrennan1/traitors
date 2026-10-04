import SwiftUI

/// The vote, told the way it is at the table: slates turned one at a time with the count kept
/// beside them, then the banished player's walk, last words, and only then what they were.
struct VoteCeremony: View {
    @Environment(GameStore.self) private var store
    @Environment(Stage.self) private var stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var vote: PlayerID?

    enum Moment {
        case line(Beat)
        /// The host calls for the slates.
        case call
        case slate(voter: PlayerID, target: PlayerID, round: Int, left: Int)
        case walk(PlayerID)
        case words(PlayerID, String)
        case ask
        case declare(PlayerID, Role?)
        case verdict(Beat)
    }

    var body: some View {
        if let game = store.game {
            let moments = Self.moments(game)
            let banishAt = moments.firstIndex { if case .walk = $0 { return true } else { return false } }
            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 0) {
                        tally(game, moments)
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
                    if game.phase == .voting {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Tie-break: vote again")
                            PlayerPicker(ids: game.choices, selection: $vote)
                            Button(vote.map { "Vote to banish \(game.players[$0].name)" } ?? "Choose a player") {
                                if let vote { store.send(.vote(vote)) }
                                vote = nil
                            }
                            .buttonStyle(GoldButtonStyle())
                            .disabled(vote == nil)
                        }
                        .opacity(shown >= moments.count ? 1 : 0.4)
                        .allowsHitTesting(shown >= moments.count)
                    } else {
                        if store.spectating, game.winner == nil { SpectatorNote() }
                        Button(label(game)) { store.send(.next) }
                            .buttonStyle(GoldButtonStyle())
                            .opacity(shown >= moments.count ? 1 : 0.45)
                    }
                }
            }
            .stepClock($shown, count: moments.count, key: "vote", hold: { hold(moments, $0) }, cue: { cue(moments[$0]) })
            .onChange(of: shown) { sync(moments) }
            .onAppear {
                // Coming back to a reveal whose first round was already watched: pick up at the revote.
                if shown == 0, game.phase == .voteReveal, let me = game.human,
                   let at = moments.firstIndex(where: { if case .slate(_, _, 2, _) = $0 { return true } else { return false } }),
                   moments.contains(where: { if case .slate(me, _, 2, _) = $0 { return true } else { return false } }) {
                    shown = at
                }
            }
        }
    }

    // MARK: - The script

    static func moments(_ game: Game) -> [Moment] {
        let script = VoteScript(feed: game.feed)
        var out: [Moment] = []
        var called = false
        for (i, step) in script.steps.enumerated() {
            switch step {
            case .line(let beat):
                out.append(.line(beat))
            case .slate(let voter, let target, let round):
                if !called, round == 1 { out.append(.call) }
                called = true
                out.append(.slate(voter: voter, target: target, round: round, left: script.slatesLeft(after: i)))
            case .banish(let target, let role):
                out.append(.walk(target))
                // In the finale they leave without a word, and nobody is told what they were.
                if role != nil {
                    let p = game.players[target]
                    if !p.isHuman { out.append(.words(target, Flavour.lastWords(p.voice, seat: target, seed: game.seed, day: game.day))) }
                    out.append(.ask)
                }
                out.append(.declare(target, role))
            case .verdict(let beat):
                out.append(.verdict(beat))
            }
        }
        return out
    }

    /// Seconds to wait before a moment appears: the last few slates are turned slowly.
    private func hold(_ moments: [Moment], _ i: Int) -> Double {
        if i == 0 { return 0.5 }
        switch moments[i] {
        case .line: return 0.9
        case .call: return 0.9
        case .slate(_, _, _, let left): return left == 0 ? 2.4 : left <= 2 ? 1.7 : 1.1
        case .walk: return 2.0
        case .words: return 2.0
        case .ask: return 2.4
        case .declare(_, let role): return role == nil ? 2.2 : 3.0
        case .verdict: return 2.4
        }
    }

    private func cue(_ moment: Moment) {
        switch moment {
        case .call: Cue.bell.play()
        case .slate(_, _, _, let left): (left <= 1 ? Cue.lateSlate : Cue.slate).play()
        case .walk: Cue.boom.play()
        case .ask: Cue.heartbeat.play()
        case .declare(_, let role): Cue.declare(role).play()
        default: break
        }
    }

    /// Once the declaration has been made, the rest of the screen may show it.
    private func sync(_ moments: [Moment]) {
        for moment in moments.prefix(shown) {
            if case .declare(_, let role) = moment {
                store.tell()
                if let role, stage.flood == nil {
                    withAnimation(.easeInOut(duration: reduceMotion ? 1.6 : 0.6)) { stage.flood = Palette.role(role) }
                }
            }
        }
    }

    private func label(_ game: Game) -> String {
        if game.winner != nil || (game.finale && game.alive.count <= 2) { return "See how it ended" }
        return game.finale ? "Continue" : "Nightfall"
    }

    // MARK: - The slates

    /// The count for the round in progress, in the order names were first written.
    private func counts(_ moments: [Moment]) -> [(player: PlayerID, votes: Int)] {
        var round = 0
        var rows: [(player: PlayerID, votes: Int)] = []
        for moment in moments.prefix(shown) {
            guard case .slate(_, let target, let r, _) = moment else { continue }
            if r != round { round = r; rows = [] }
            if let i = rows.firstIndex(where: { $0.player == target }) { rows[i].votes += 1 } else { rows.append((target, 1)) }
        }
        return rows
    }

    @ViewBuilder
    private func tally(_ game: Game, _ moments: [Moment]) -> some View {
        let rows = counts(moments)
        if !rows.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                ForEach(rows, id: \.player) { row in
                    VStack(spacing: 4) {
                        Avatar(player: game.players[row.player], size: 40, role: store.roleShown(row.player))
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
                Avatar(player: seated(game.players[voter]), size: 34)
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
                Avatar(player: game.players[p], size: 112, role: store.roleShown(p))
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
