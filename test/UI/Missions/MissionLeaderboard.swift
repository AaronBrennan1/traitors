import SwiftUI

/// The public scoreboard after a mission: everyone's count against par, best first, then what
/// the team made of it between them.
struct MissionLeaderboard: View {
    let report: MissionReport
    let players: [Player]
    var human: PlayerID? = nil
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [MissionUnit] {
        report.units.sorted { ($0.count, -($0.players.first ?? 0)) > ($1.count, -($1.players.first ?? 0)) }
    }

    var body: some View {
        let unit = report.kind.spec.unit
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "Scoreboard")
                Spacer()
                Label("Par \(report.par) of \(report.steps) \(unit)", systemImage: "flag.fill")
                    .font(.serif(.caption, weight: .bold)).foregroundStyle(Palette.gold.opacity(0.85))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, u in
                row(i, u)
                    .opacity(i < shown ? 1 : 0)
                    .offset(y: i < shown || reduceMotion ? 0 : 8)
            }
            if report.teamGoal > 0 { team(unit).opacity(shown >= rows.count ? 1 : 0) }
            Text("The gold line is par. Anyone short of it is flagged for the whole table to see.")
                .font(.serif(.caption)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panel()
        .task {
            while shown < rows.count {
                try? await Task.sleep(for: .seconds(0.22))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: Tokens.Motion.reveal)) { shown += 1 }
                Feedback.play(.row)
            }
        }
    }

    private func row(_ i: Int, _ u: MissionUnit) -> some View {
        let p = players[u.players[0]]
        let mine = p.id == human
        let ink = u.anomalous ? Palette.blood : Palette.parchment
        return HStack(spacing: 8) {
            Text("\(i + 1)")
                .font(Tokens.TypeRole.numeral.font(.caption)).foregroundStyle(i == 0 ? Palette.gold : Palette.muted)
                .frame(width: 14, alignment: .trailing)
            Avatar(player: seated(p), size: 28)
            Text(mine ? "You" : p.name)
                .font(.serif(.subheadline, weight: mine ? .bold : .regular))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(minWidth: 62, alignment: .leading)
                .layoutPriority(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.parchment.opacity(0.09))
                    Capsule()
                        .fill(LinearGradient(colors: u.anomalous ? [Palette.blood.opacity(0.7), Palette.blood]
                                                                 : [Palette.faithful.opacity(0.65), Palette.faithful],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: i < shown ? max(8, geo.size.width * Double(u.count) / Double(max(report.steps, 1))) : 0)
                    Rectangle().fill(Palette.gold)
                        .frame(width: 2, height: 18)
                        .offset(x: geo.size.width * Double(report.par) / Double(max(report.steps, 1)) - 1)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)
            Text("\(u.count)")
                .font(Tokens.TypeRole.numeral.font(.subheadline)).foregroundStyle(ink)
                .frame(width: 24, alignment: .trailing)
            Image(systemName: u.anomalous ? "flag.fill" : "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(u.anomalous ? Palette.blood : Palette.faithful.opacity(0.8))
                .frame(width: 14)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            if mine { RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(Palette.gold.opacity(0.10)) }
        }
        .overlay {
            if mine { RoundedRectangle(cornerRadius: Tokens.Radius.chip).stroke(Palette.gold.opacity(0.45), lineWidth: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(i + 1). \(mine ? "You" : p.name), \(u.count) of \(report.steps)\(u.anomalous ? ", under par, flagged" : "")")
    }

    private func team(_ unit: String) -> some View {
        let made = report.teamTotal >= report.teamGoal
        return VStack(spacing: 7) {
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack {
                Label("Team", systemImage: "person.3.fill").font(.serif(.subheadline, weight: .bold)).foregroundStyle(Palette.gold)
                Spacer()
                if made { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Palette.faithful) }
                Text("\(report.teamTotal) of \(report.teamGoal) \(unit)")
                    .font(Tokens.TypeRole.numeral.font(.subheadline))
                    .foregroundStyle(made ? Palette.faithful : Palette.parchment)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.parchment.opacity(0.09))
                    Capsule().fill(made ? Palette.faithful : Palette.gold)
                        .frame(width: max(6, geo.size.width * min(1, Double(report.teamTotal) / Double(max(report.teamGoal, 1)))))
                }
            }
            .frame(height: 6)
            if report.potEarned > 0 {
                HStack {
                    Text("Added to the pot").font(.serif(.caption)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("€\(report.potEarned.formatted())").font(Tokens.TypeRole.numeral.font(.subheadline)).foregroundStyle(Palette.gold)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
