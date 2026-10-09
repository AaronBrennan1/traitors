import SwiftUI
import TraitorsEngine

/// The Round Table: the discussion plays out above, and the human speaks, votes or
/// makes the finale choice below.
struct TableScreen: View {
    @Environment(GameSession.self) private var session
    @State private var settled = false
    @State private var vote: PlayerID?

    var body: some View {
        if let game = session.game {
            VStack(spacing: 0) {
                FeedList(beats: game.feed, pace: 0.9, settled: $settled)
                BottomBar {
                    switch session.prompt {
                    case .speak(let turn, let targets, let defences):
                        Composer(step: turn, targets: targets, defences: defences).id(turn)
                    case .vote(let round, let candidates):
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: round == 2 ? "Tie-break: vote again" : "Write a name on your slate")
                            PlayerPicker(ids: candidates, selection: $vote)
                            Button(vote.map { "Vote to banish \(game.players[$0].name)" } ?? "Choose a player") {
                                if let vote { session.send(.vote(vote)) }
                                vote = nil
                            }
                            .buttonStyle(GoldButtonStyle())
                            .disabled(vote == nil)
                        }
                    case .endOrBanish:
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "The Fire of Truth")
                            Text("End the game only if you believe every traitor is gone. It must be unanimous.")
                                .font(.serif(.footnote)).foregroundStyle(Palette.muted)
                            HStack(spacing: 10) {
                                Button("End the game") { session.send(.finale(end: true)) }
                                    .buttonStyle(GoldButtonStyle(tint: Palette.faithful))
                                Button("Banish again") { session.send(.finale(end: false)) }
                                    .buttonStyle(GoldButtonStyle(tint: Palette.blood))
                            }
                        }
                    default:
                        EmptyView()
                    }
                }
                .opacity(settled ? 1 : 0.4)
                .allowsHitTesting(settled)
                .animation(.easeOut(duration: 0.2), value: settled)
            }
        }
    }
}

/// The human's turn to speak: pick an action, a player, and a piece of evidence.
struct Composer: View {
    @Environment(GameSession.self) private var session
    let step: Int
    /// Who can be spoken about, and the ways there are to answer whoever last pointed at you.
    let targets: [PlayerID]
    let defences: [DefenceOption]
    @State private var action: HumanSay?
    @State private var target: PlayerID?
    @State private var chipIndex: Int?
    @State private var answering = false

    var body: some View {
        if let game = session.game {
            let view = game.view()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(text: "Your turn to speak (\(step) of 2)")
                    Spacer()
                    if action != nil || answering {
                        Button("Back") { action = nil; target = nil; chipIndex = nil; answering = false }
                            .font(.serif(.caption, weight: .bold))
                    }
                }
                if answering {
                    // Someone has pointed at you: answer them instead of taking an ordinary turn.
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(defences.indices, id: \.self) { i in
                                Button { session.send(.rebut(i)) } label: {
                                    HStack {
                                        Text(Dialogue.label(defences[i], view: view))
                                            .font(.serif(.footnote)).foregroundStyle(Palette.parchment)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 176)
                } else if let action {
                    PlayerPicker(ids: targets, selection: Binding(get: { target }, set: { target = $0; chipIndex = nil }))
                    if let target, action != .question {
                        let chips = game.notebook(about: target, suspicious: action == .accuse)
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(chips.indices, id: \.self) { i in
                                    Button { chipIndex = i } label: {
                                        HStack {
                                            Image(systemName: chipIndex == i ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(chipIndex == i ? Palette.gold : Palette.muted)
                                            Text(Dialogue.label(chips[i], view: view))
                                                .font(.serif(.footnote)).foregroundStyle(Palette.parchment)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 132)
                        Button(action == .accuse ? "Accuse \(game.players[target].name)" : "Speak up for \(game.players[target].name)") {
                            session.send(.say(action, target: target, chip: chipIndex.map { chips[$0] } ?? chips.last))
                        }
                        .buttonStyle(GoldButtonStyle(tint: action == .accuse ? Palette.blood : Palette.faithful))
                        .disabled(chipIndex == nil)
                    } else if let target, action == .question {
                        Button("Ask \(game.players[target].name) for a name") {
                            session.send(.say(.question, target: target, chip: nil))
                        }
                        .buttonStyle(GoldButtonStyle())
                    } else {
                        Text(prompt(action)).font(.serif(.footnote)).foregroundStyle(Palette.muted)
                    }
                } else {
                    if !defences.isEmpty {
                        Button("Answer the charge") { answering = true }.buttonStyle(GoldButtonStyle())
                    }
                    HStack(spacing: 8) {
                        Button("Accuse") { action = .accuse }.buttonStyle(GhostButtonStyle(tint: Palette.blood))
                        Button("Defend") { action = .defend }.buttonStyle(GhostButtonStyle(tint: Palette.faithful))
                        Button("Question") { action = .question }.buttonStyle(GhostButtonStyle(tint: Palette.gold))
                    }
                    Button("Stay quiet") { session.send(.say(.pass, target: nil, chip: nil)) }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private func prompt(_ action: HumanSay) -> String {
        switch action {
        case .accuse: return "Who are you accusing? Then pick the evidence you will cite."
        case .defend: return "Who are you standing up for? Then pick what you will point to."
        case .question: return "Who do you want to put on the spot? They must name a suspect, and the table will hold them to it."
        default: return ""
        }
    }
}
