import SwiftUI

/// What the table is shown after a mission: what the company brought home between them against
/// what was asked, and what that means for the night. It says nothing about anyone in particular.
struct MissionResultCard: View {
    let report: MissionReport
    @State private var filled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let unit = report.kind.spec.unit
        let made = report.groupWon
        let share = min(1, Double(report.teamTotal) / Double(max(report.teamGoal, 1)))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "The company's day")
                Spacer()
                Label(made ? "Goal made" : "Fell short", systemImage: made ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.serif(.caption, weight: .bold))
                    .foregroundStyle(made ? Palette.faithful : Palette.blood)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(report.teamTotal)")
                    .font(Tokens.TypeRole.numeral.font(.largeTitle))
                    .foregroundStyle(made ? Palette.faithful : Palette.parchment)
                Text("of \(report.teamGoal) \(unit)")
                    .font(.serif(.subheadline)).foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: "person.3.fill").font(.caption).foregroundStyle(Palette.gold.opacity(0.8))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.parchment.opacity(0.09))
                    Capsule().fill(made ? Palette.faithful : Palette.gold)
                        .frame(width: filled || reduceMotion ? max(8, geo.size.width * share) : 8)
                }
            }
            .frame(height: 10)
            Text(made ? "The goal is made. Nobody is murdered tonight."
                      : "The traitors have their night.")
                .font(.serif(.subheadline)).foregroundStyle(Palette.parchment)
                .fixedSize(horizontal: false, vertical: true)
            if report.potEarned > 0 {
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack {
                    Text("Added to the pot").font(.serif(.caption)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("€\(report.potEarned.formatted())").font(Tokens.TypeRole.numeral.font(.subheadline)).foregroundStyle(Palette.gold)
                }
            }
        }
        .panel()
        .accessibilityElement(children: .combine)
        .task {
            try? await Task.sleep(for: .seconds(0.25))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: Tokens.Motion.reveal * 2)) { filled = true }
            Feedback.play(.row)
        }
    }
}
