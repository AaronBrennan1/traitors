import SwiftUI
import Charts
import TraitorsEngine

struct GameOverView: View {
    @Environment(GameSession.self) private var session
    var onExit: () -> Void
    /// The game whose last scene at the fire has already been watched.
    @AppStorage("endingSeenSeed") private var endingSeen = ""

    var body: some View {
        if let game = session.game {
            let winner = game.winner ?? .faithful
            let won = session.humanWon(game)
            if endingSeen != "\(game.seed)" {
                EndingCeremony { withAnimation(.easeInOut(duration: 0.4)) { endingSeen = "\(game.seed)" } }
            } else {
            ZStack {
                // The fire is still behind this; the summary needs a steadier ground to be read on.
                Palette.ink.opacity(0.6).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Image(systemName: winner == .traitor ? "theatermasks.fill" : "shield.lefthalf.filled")
                                .font(.system(size: 56)).foregroundStyle(Palette.role(winner))
                            Text(winner == .traitor ? "THE TRAITORS WIN" : "THE FAITHFUL WIN")
                                .font(.system(size: 28, weight: .heavy, design: .serif)).tracking(2)
                                .foregroundStyle(Palette.parchment)
                            if game.human != nil {
                                Text(won ? "You won. The pot of €\(game.pot.formatted()) is yours to share." : "You lost. The pot of €\(game.pot.formatted()) goes to the other side.")
                                    .font(.serif(.subheadline)).foregroundStyle(Palette.muted)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 28)


                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Who was who")
                            ForEach(game.players.indices, id: \.self) { i in
                                let p = game.players[i]
                                HStack(spacing: 10) {
                                    Avatar(player: p, size: 36, role: p.role)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.isHuman ? "\(p.name) (you)" : p.name)
                                            .font(.serif(.subheadline, weight: .semibold)).foregroundStyle(Palette.parchment)
                                        Text(fate(p)).font(.serif(.caption)).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    Text(p.role == .traitor ? (p.wasRecruited ? "Recruited traitor" : "Traitor") : "Faithful")
                                        .font(.serif(.caption, weight: .bold)).foregroundStyle(Palette.role(p.role))
                                }
                            }
                        }
                        .panel()

                        // Only the banishments the human was still present for say anything about them.
                        if let me = game.human {
                            let seen = game.history.filter { game.players[me].alive || $0.day < (game.players[me].fateDay ?? 0) || (game.players[me].fate == .murdered && $0.day == game.players[me].fateDay) }
                            if seen.count >= 2 { SuspicionChart(history: seen, me: me) }
                        }
                        if let me = game.human, let last = game.history.last(where: { $0.ofHuman.contains { $0 >= 0 } }) {
                            SuspectedBy(game: game, snapshot: last, me: me)
                        }

                        VStack(spacing: 10) {
                            Button("Back to the title") { session.leaveGame(); onExit() }.buttonStyle(GoldButtonStyle())
                        }
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16)
                }
            }
            }
        }
    }

    private func fate(_ p: Player) -> String {
        switch p.fate {
        case .murdered: return "Murdered on night \(p.fateDay ?? 0)"
        case .banished: return "Banished on day \(p.fateDay ?? 0)"
        case nil: return "Survived to the end"
        }
    }
}

/// One series: what a neutral observer made of the human after each banishment.
struct SuspicionChart: View {
    let history: [DaySnapshot]
    let me: PlayerID

    private var points: [(step: Int, value: Double)] {
        history.enumerated().map { ($0.offset + 1, $0.element.publicSuspicion[me] * 100) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "How suspicious you looked")
            Text("Chance a neutral observer gave of you being a traitor, after each banishment")
                .font(.serif(.caption)).foregroundStyle(Palette.muted)
            Chart {
                ForEach(points, id: \.step) { p in
                    LineMark(x: .value("Banishment", p.step), y: .value("Suspicion", p.value))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Palette.gold)
                    PointMark(x: .value("Banishment", p.step), y: .value("Suspicion", p.value))
                        .symbolSize(70)
                        .foregroundStyle(Palette.gold)
                        .annotation(position: .top, spacing: 4) {
                            if p.step == points.last?.step || p.step == points.first?.step {
                                Text("\(Int(p.value.rounded()))%")
                                    .font(.serif(.caption2, weight: .bold)).foregroundStyle(Palette.parchment)
                            }
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0.5...(Double(points.count) + 0.5))
            .chartXAxis {
                AxisMarks(values: points.map(\.step)) { value in
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)").font(.serif(.caption2)).foregroundStyle(Palette.muted) }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.serif(.caption2)).foregroundStyle(Palette.muted) }
                }
            }
            .frame(height: 170)
            .padding(.top, 8)
            .accessibilityLabel("Line chart of how suspicious you looked after each banishment")
        }
        .panel()
    }
}

/// Each faithful bot's private read of the human at the last point it was measured.
struct SuspectedBy: View {
    let game: Game
    let snapshot: DaySnapshot
    let me: PlayerID

    var body: some View {
        let rows = game.players.indices
            .filter { snapshot.ofHuman[$0] >= 0 }
            .sorted { snapshot.ofHuman[$0] > snapshot.ofHuman[$1] }
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "What they privately thought of you")
            Text("Each faithful's own suspicion of you on day \(snapshot.day)")
                .font(.serif(.caption)).foregroundStyle(Palette.muted)
            ForEach(rows, id: \.self) { i in
                let v = snapshot.ofHuman[i]
                HStack(spacing: 10) {
                    Text(game.players[i].name).font(.serif(.subheadline)).foregroundStyle(Palette.parchment)
                        .frame(width: 84, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.panelHi)
                            Capsule().fill(Palette.gold).frame(width: max(4, geo.size.width * v))
                        }
                    }
                    .frame(height: 10)
                    Text("\(Int((v * 100).rounded()))%").font(.serif(.caption, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Palette.parchment).frame(width: 40, alignment: .trailing)
                }
                // The main thing this player held against you, in their own terms.
                if snapshot.whyHuman.indices.contains(i), let chip = snapshot.whyHuman[i] {
                    Text(Dialogue.label(chip, view: game.view()))
                        .font(.serif(.caption2)).foregroundStyle(Palette.muted)
                }
            }
        }
        .panel()
    }
}
